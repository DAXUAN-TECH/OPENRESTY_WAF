-- 自动封控模块
-- 路径：项目目录下的 lua/waf/auto_block.lua（保持在项目目录，不复制到系统目录）

local mysql_pool = require "waf.mysql_pool"
local config = require "config"
local frequency_stats = require "waf.frequency_stats"
local feature_switches = require "waf.feature_switches"
local cjson = require "cjson"

local _M = {}
-- 安全获取共享内存（兼容Stream块）
local function get_cache()
    local ok, cache = pcall(function()
        return ngx.shared.waf_cache
    end)
    if ok and cache then
        return cache
    end
    return nil
end
local cache = get_cache()
local CACHE_KEY_PREFIX = "auto_block:"
local CACHE_TTL = config.cache.ttl

-- 创建自动封控规则
function _M.create_auto_block_rule(client_ip, block_info)
    -- 检查自动封控功能是否启用（优先从数据库读取）
    local auto_block_enabled = feature_switches.is_enabled("auto_block")
    if not auto_block_enabled or not config.auto_block.enable then
        return false, nil
    end

    -- 检查是否已经存在自动封控记录
    local sql_check = [[
        SELECT id, status FROM waf_auto_block_logs
        WHERE client_ip = ?
        AND status = 1
        LIMIT 1
    ]]

    local res_check, err = mysql_pool.query(sql_check, client_ip)
    if err then
        ngx.log(ngx.ERR, "auto block check error: ", err)
        return false, err
    end

    if res_check and #res_check > 0 then
        -- 已经存在自动封控记录，不需要重复创建
        return true, res_check[1]
    end

    -- 计算自动解封时间
    local block_duration = config.auto_block.block_duration or 3600
    local unblock_time = ngx.time() + block_duration
    local unblock_time_str = os.date("!%Y-%m-%d %H:%M:%S", unblock_time)

    -- 创建自动封控记录
    local sql_insert = [[
        INSERT INTO waf_auto_block_logs
        (client_ip, block_reason, block_threshold, auto_unblock_time, status)
        VALUES (?, ?, ?, ?, 1)
    ]]

    local threshold_json = cjson.encode(block_info.threshold)
    local insert_id, err = mysql_pool.insert(sql_insert, 
        client_ip, 
        block_info.reason, 
        threshold_json,
        unblock_time_str
    )

    if err then
        ngx.log(ngx.ERR, "auto block insert error: ", err)
        return false, err
    end

    -- 创建封控规则（如果不存在）
    local rule_name = "自动封控-" .. client_ip .. "-" .. block_info.reason
    local rule_value = client_ip
    local rule_type = "single_ip"
    
    -- 检查规则是否已存在
    local sql_rule_check = [[
        SELECT id FROM waf_block_rules
        WHERE rule_type = 'single_ip'
        AND rule_value = ?
        AND rule_name LIKE '自动封控-%'
        LIMIT 1
    ]]

    local res_rule_check, err = mysql_pool.query(sql_rule_check, rule_value)
    if err then
        ngx.log(ngx.ERR, "auto block rule check error: ", err)
    end

    if not res_rule_check or #res_rule_check == 0 then
        -- 创建封控规则
        local sql_rule_insert = [[
            INSERT INTO waf_block_rules
            (rule_type, rule_value, rule_name, description, status, priority, end_time, rule_version)
            VALUES (?, ?, ?, ?, 1, 50, ?, 1)
        ]]

        local description = string.format("自动封控：%s，原因：%s，阈值：%s", 
            client_ip, block_info.reason, threshold_json)
        
        local rule_id, err = mysql_pool.insert(sql_rule_insert,
            rule_type,
            rule_value,
            rule_name,
            description,
            unblock_time_str
        )

        if err then
            ngx.log(ngx.ERR, "auto block rule insert error: ", err)
        else
            -- 清除相关缓存
            _M.invalidate_cache(client_ip)
            ngx.log(ngx.INFO, "auto block rule created: ", rule_id, " for IP: ", client_ip)
        end
    end

    return true, {id = insert_id}
end

-- 检查IP是否被自动封控
function _M.check_auto_block(client_ip)
    -- 检查自动封控功能是否启用（优先从数据库读取）
    local auto_block_enabled = feature_switches.is_enabled("auto_block")
    if not auto_block_enabled or not config.auto_block.enable then
        return false, nil
    end

    local cache_key = CACHE_KEY_PREFIX .. client_ip
    local cached = cache:get(cache_key)
    if cached ~= nil then
        if cached == "1" then
            -- 从另一个缓存获取封控信息
            local info_cache_key = cache_key .. ":info"
            local info_data = cache:get(info_cache_key)
            if info_data then
                local ok, info = pcall(function()
                    return cjson.decode(info_data)
                end)
                if ok and info then
                    return true, info
                end
            end
        else
            return false, nil
        end
    end

    -- 查询数据库
    local sql = [[
        SELECT id, block_reason, block_threshold, auto_unblock_time
        FROM waf_auto_block_logs
        WHERE client_ip = ?
        AND status = 1
        AND (auto_unblock_time IS NULL OR auto_unblock_time > NOW())
        LIMIT 1
    ]]

    local res, err = mysql_pool.query(sql, client_ip)
    if err then
        ngx.log(ngx.ERR, "auto block query error: ", err)
        return false, nil
    end

    if res and #res > 0 then
        local block_info = {
            id = res[1].id,
            reason = res[1].block_reason,
            threshold = res[1].block_threshold,
            auto_unblock_time = res[1].auto_unblock_time
        }
        
        -- 解析阈值JSON
        if block_info.threshold then
            local ok, threshold = pcall(function()
                return cjson.decode(block_info.threshold)
            end)
            if ok then
                block_info.threshold = threshold
            end
        end

        cache:set(cache_key, "1", CACHE_TTL)
        cache:set(cache_key .. ":info", cjson.encode(block_info), CACHE_TTL)
        return true, block_info
    end

    cache:set(cache_key, "0", CACHE_TTL)
    return false, nil
end

-- 清除缓存
function _M.invalidate_cache(client_ip)
    if client_ip then
        cache:delete(CACHE_KEY_PREFIX .. client_ip)
        cache:delete(CACHE_KEY_PREFIX .. client_ip .. ":info")
        -- 同时清除封控规则缓存
        cache:delete("block_rules:single:" .. client_ip)
        cache:delete("block_rules:single:" .. client_ip .. ":rule")
    else
        -- 清除所有自动封控缓存（谨慎使用）
        ngx.log(ngx.WARN, "invalidate_cache called without IP, skipping")
    end
end

return _M

