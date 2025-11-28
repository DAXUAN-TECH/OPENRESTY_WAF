-- 自动解封模块
-- 路径：项目目录下的 lua/waf/auto_unblock.lua（保持在项目目录，不复制到系统目录）

local mysql_pool = require "waf.mysql_pool"
local auto_block = require "waf.auto_block"
local feature_switches = require "waf.feature_switches"
local config = require "config"
local cjson = require "cjson"

local _M = {}
local cache = ngx.shared.waf_cache

-- 检查并执行自动解封（包括规则过期解封）
function _M.check_and_unblock()
    local unblocked_count = 0
    
    -- 1. 检查自动封控记录过期
    local sql_auto = [[
        SELECT id, client_ip, block_reason
        FROM waf_auto_block_logs
        WHERE status = 1
        AND auto_unblock_time IS NOT NULL
        AND auto_unblock_time <= NOW()
        LIMIT 100
    ]]

    local res, err = mysql_pool.query(sql_auto)
    if err then
        ngx.log(ngx.ERR, "auto unblock query error: ", err)
    elseif res and #res > 0 then
        for _, record in ipairs(res) do
            local ok, unblock_err = _M.unblock_ip(record.client_ip, record.id)
            if ok then
                unblocked_count = unblocked_count + 1
                ngx.log(ngx.INFO, "auto unblocked IP: ", record.client_ip, 
                        ", reason: ", record.block_reason)
            else
                ngx.log(ngx.ERR, "auto unblock failed for IP: ", record.client_ip, 
                        ", error: ", unblock_err)
            end
        end
    end
    
    -- 2. 检查规则过期（end_time < NOW()）
    local sql_rules = [[
        SELECT id, rule_name, rule_value, rule_type
        FROM waf_block_rules
        WHERE status = 1
        AND end_time IS NOT NULL
        AND end_time <= NOW()
        LIMIT 100
    ]]
    
    local res_rules, err_rules = mysql_pool.query(sql_rules)
    if err_rules then
        ngx.log(ngx.ERR, "rule expiration check error: ", err_rules)
    elseif res_rules and #res_rules > 0 then
        for _, rule in ipairs(res_rules) do
            local ok, unblock_err = _M.unblock_expired_rule(rule.id, rule.rule_value, rule.rule_type)
            if ok then
                unblocked_count = unblocked_count + 1
                ngx.log(ngx.INFO, "auto unblocked expired rule: ", rule.rule_name, 
                        " (ID: ", rule.id, ")")
            else
                ngx.log(ngx.ERR, "auto unblock expired rule failed: ", rule.rule_name, 
                        ", error: ", unblock_err)
            end
        end
    end

    return unblocked_count
end

-- 解封过期规则
function _M.unblock_expired_rule(rule_id, rule_value, rule_type)
    if not rule_id then
        return false, "rule_id is required"
    end
    
    -- 禁用规则
    local sql_update = [[
        UPDATE waf_block_rules
        SET status = 0
        WHERE id = ?
        AND status = 1
    ]]
    
    local ok, err = mysql_pool.query(sql_update, rule_id)
    if err then
        ngx.log(ngx.ERR, "unblock expired rule update error: ", err)
        return false, err
    end
    
    -- 清除相关缓存
    _M.invalidate_rule_cache(rule_id, rule_value, rule_type)
    
    -- 记录解封日志
    local sql_log = [[
        INSERT INTO waf_block_logs
        (client_ip, rule_id, rule_name, block_time, request_path, user_agent, block_reason)
        VALUES (?, ?, '规则过期自动解封', NOW(), '', '', 'rule_expired')
    ]]
    
    mysql_pool.insert(sql_log, rule_value or '', rule_id)
    
    return true, nil
end

-- 解封指定IP
function _M.unblock_ip(client_ip, auto_block_log_id)
    if not client_ip then
        return false, "client_ip is required"
    end

    -- 更新自动封控记录状态
    local sql_update_log = [[
        UPDATE waf_auto_block_logs
        SET status = 0
        WHERE client_ip = ?
        AND (id = ? OR ? IS NULL)
        AND status = 1
    ]]

    local ok, err = mysql_pool.query(sql_update_log, client_ip, auto_block_log_id, auto_block_log_id)
    if err then
        ngx.log(ngx.ERR, "auto unblock log update error: ", err)
        return false, err
    end

    -- 删除或禁用对应的封控规则
    local sql_update_rule = [[
        UPDATE waf_block_rules
        SET status = 0
        WHERE rule_type = 'single_ip'
        AND rule_value = ?
        AND rule_name LIKE '自动封控-%'
        AND status = 1
    ]]

    ok, err = mysql_pool.query(sql_update_rule, client_ip)
    if err then
        ngx.log(ngx.ERR, "auto unblock rule update error: ", err)
        -- 继续执行，不返回错误
    end

    -- 清除相关缓存
    _M.invalidate_ip_cache(client_ip)

    -- 记录解封日志
    local sql_log = [[
        INSERT INTO waf_block_logs
        (client_ip, rule_id, rule_name, block_time, request_path, user_agent, block_reason)
        VALUES (?, NULL, '自动解封', NOW(), '', '', 'auto_unblock')
    ]]

    mysql_pool.insert(sql_log, client_ip)

    return true, nil
end

-- 清除IP相关缓存
function _M.invalidate_ip_cache(client_ip)
    if not client_ip then
        return
    end
    
    local cache_invalidation = require "waf.cache_invalidation"
    if cache_invalidation and cache_invalidation.invalidate_ip_cache then
        cache_invalidation.invalidate_ip_cache(client_ip)
    else
        -- 直接清除缓存
        local cache = ngx.shared.waf_cache
        cache:delete("auto_block:" .. client_ip)
        cache:delete("freq_stats:" .. client_ip)
    end
end

-- 清除规则相关缓存
function _M.invalidate_rule_cache(rule_id, rule_value, rule_type)
    if not rule_id then
        return
    end
    
    local cache_invalidation = require "waf.cache_invalidation"
    if cache_invalidation and cache_invalidation.invalidate_rule_cache then
        cache_invalidation.invalidate_rule_cache(rule_id)
    else
        -- 直接清除缓存
        local cache = ngx.shared.waf_cache
        cache:delete("rule:" .. rule_id)
        if rule_value then
            cache:delete("block:" .. rule_value)
        end
    end
    
    -- 更新规则版本号以触发缓存失效
    local cache_invalidation = require "waf.cache_invalidation"
    if cache_invalidation and cache_invalidation.increment_rule_version then
        cache_invalidation.increment_rule_version()
    end
end

-- 初始化工作进程定时器（在init_worker阶段调用）
function _M.init_worker()
    -- 在init_worker阶段不能使用TCP连接，只检查配置文件
    -- 数据库检查将在定时器回调中进行
    if not config.auto_block or not config.auto_block.enable then
        ngx.log(ngx.INFO, "auto unblock disabled in config, skipping timer initialization")
        return
    end
    
    local check_interval = config.auto_block.check_interval or 10

    local function periodic_check(premature)
        if premature then
            return
        end
        
        -- 在定时器回调中，可以安全地检查数据库
        -- 先检查配置文件
        if not config.auto_block or not config.auto_block.enable then
            ngx.log(ngx.INFO, "auto unblock disabled in config, stopping timer")
            return
        end
        
        -- 再检查数据库中的功能开关（使用pcall避免错误传播）
        local auto_block_enabled = true
        local ok, result = pcall(function()
            return feature_switches.is_enabled("auto_block")
        end)
        
        if ok then
            auto_block_enabled = result
        else
            -- 如果检查失败（可能是数据库不可用），使用配置文件的值
            -- 使用错误缓存，避免重复记录错误日志
            local error_cache_key = "auto_unblock_db_error"
            local last_error_time = cache:get(error_cache_key)
            local current_time = ngx.time()
            
            if not last_error_time or (current_time - last_error_time) > 300 then
                ngx.log(ngx.WARN, "failed to check feature switch from database, using config value")
                cache:set(error_cache_key, current_time, 600)  -- 缓存10分钟
            end
            auto_block_enabled = config.auto_block.enable
        end
        
        if not auto_block_enabled then
            ngx.log(ngx.INFO, "auto unblock disabled in database, stopping timer")
            return
        end

        local unblocked_count = _M.check_and_unblock()
        if unblocked_count > 0 then
            ngx.log(ngx.INFO, "auto unblock completed, unblocked ", unblocked_count, " IPs")
        end

        -- 设置下一次定时器
        local ok, err = ngx.timer.at(check_interval, periodic_check)
        if not ok then
            ngx.log(ngx.ERR, "failed to create auto unblock timer: ", err)
        end
    end

    -- 启动定时器
    local ok, err = ngx.timer.at(check_interval, periodic_check)
    if not ok then
        ngx.log(ngx.ERR, "failed to create initial auto unblock timer: ", err)
    end
end

return _M

