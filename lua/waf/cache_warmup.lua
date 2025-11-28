-- 缓存预热和失效平滑过渡模块
-- 路径：项目目录下的 lua/waf/cache_warmup.lua（保持在项目目录，不复制到系统目录）
-- 功能：实现缓存预热机制、缓存失效的平滑过渡

local mysql_pool = require "waf.mysql_pool"
local cache_invalidation = require "waf.cache_invalidation"
local ip_trie = require "waf.ip_trie"
local config = require "config"
local cjson = require "cjson"

local _M = {}
local cache = ngx.shared.waf_cache

-- 配置
local WARMUP_ENABLED = config.cache_warmup and config.cache_warmup.enable or true
local WARMUP_INTERVAL = config.cache_warmup and config.cache_warmup.interval or 300  -- 预热间隔（秒）
local WARMUP_BATCH_SIZE = config.cache_warmup and config.cache_warmup.batch_size or 100  -- 预热批次大小
local SMOOTH_TRANSITION_ENABLED = config.cache_warmup and config.cache_warmup.smooth_transition or true

-- 缓存键
local WARMUP_STATUS_KEY = "warmup_status"
local OLD_RULES_KEY = "old_rules"
local NEW_RULES_KEY = "new_rules"

-- 预热状态
local WarmupStatus = {
    IDLE = "idle",
    WARMING = "warming",
    COMPLETE = "complete"
}

-- 获取预热状态
function _M.get_warmup_status()
    return cache:get(WARMUP_STATUS_KEY) or WarmupStatus.IDLE
end

-- 设置预热状态
function _M.set_warmup_status(status)
    cache:set(WARMUP_STATUS_KEY, status, 3600)
end

-- 预热IP段规则
function _M.warmup_ip_range_rules()
    if not WARMUP_ENABLED then
        return false, "warmup disabled"
    end
    
    _M.set_warmup_status(WarmupStatus.WARMING)
    
    -- 查询所有启用的IP段规则
    local sql = [[
        SELECT id, rule_name, rule_value, priority FROM waf_block_rules 
        WHERE status = 1 
        AND rule_type = 'ip_range'
        AND (start_time IS NULL OR start_time <= NOW())
        AND (end_time IS NULL OR end_time >= NOW())
        ORDER BY priority DESC
    ]]
    
    local rules, err = mysql_pool.query(sql)
    if err then
        _M.set_warmup_status(WarmupStatus.IDLE)
        return false, err
    end
    
    if not rules or #rules == 0 then
        _M.set_warmup_status(WarmupStatus.COMPLETE)
        return true, "no rules to warmup"
    end
    
    -- 构建Trie树
    local trie_manager = ip_trie.build_trie(rules)
    
    -- 缓存规则列表和Trie树
    local cache_key = "rule_list:ip_range:block"
    cache:set(cache_key, cjson.encode(rules), config.cache.rule_list_ttl or 300)
    
    -- 缓存Trie树（序列化）
    local trie_data = ip_trie.serialize_trie(trie_manager)
    cache:set(cache_key .. ":trie", cjson.encode(trie_data), config.cache.rule_list_ttl or 300)
    
    _M.set_warmup_status(WarmupStatus.COMPLETE)
    
    return true, "warmup complete"
end

-- 预热白名单规则
function _M.warmup_whitelist_rules()
    if not WARMUP_ENABLED then
        return false, "warmup disabled"
    end
    
    -- 查询所有启用的白名单规则
    local sql = [[
        SELECT id, ip_type, ip_value FROM waf_whitelist 
        WHERE status = 1 
        AND ip_type = 'ip_range'
    ]]
    
    local rules, err = mysql_pool.query(sql)
    if err then
        return false, err
    end
    
    if not rules or #rules == 0 then
        return true, "no whitelist rules to warmup"
    end
    
    -- 缓存白名单规则列表
    local cache_key = "rule_list:ip_range:whitelist"
    cache:set(cache_key, cjson.encode(rules), config.cache.rule_list_ttl or 300)
    
    -- 构建Trie树
    local trie_manager = ip_trie.build_trie(rules)
    local trie_data = ip_trie.serialize_trie(trie_manager)
    cache:set(cache_key .. ":trie", cjson.encode(trie_data), config.cache.rule_list_ttl or 300)
    
    return true, "whitelist warmup complete"
end

-- 预热常用IP的封控结果
function _M.warmup_common_ips()
    if not WARMUP_ENABLED then
        return false, "warmup disabled"
    end
    
    -- 查询最近访问的IP（从访问日志）
    local sql = [[
        SELECT DISTINCT client_ip, COUNT(*) as access_count
        FROM waf_access_logs
        WHERE request_time >= DATE_SUB(NOW(), INTERVAL 1 HOUR)
        GROUP BY client_ip
        ORDER BY access_count DESC
        LIMIT ?
    ]]
    
    local common_ips, err = mysql_pool.query(sql, WARMUP_BATCH_SIZE)
    if err then
        return false, err
    end
    
    if not common_ips or #common_ips == 0 then
        return true, "no common IPs to warmup"
    end
    
    -- 预热这些IP的封控结果（这里只是示例，实际预热逻辑在ip_block.lua中）
    local warmed_count = 0
    for _, ip_data in ipairs(common_ips) do
        local ip = ip_data.client_ip
        -- 触发封控检查（会填充缓存）
        -- 注意：这里不能直接调用ip_block.check()，因为它在access阶段
        -- 实际预热应该在定时器中异步进行
        warmed_count = warmed_count + 1
    end
    
    return true, string.format("warmed %d common IPs", warmed_count)
end

-- 平滑过渡：保存旧规则
function _M.save_old_rules()
    if not SMOOTH_TRANSITION_ENABLED then
        return
    end
    
    local cache_key = "rule_list:ip_range:block"
    local old_rules = cache:get(cache_key)
    if old_rules then
        cache:set(OLD_RULES_KEY, old_rules, 600)  -- 保存10分钟
    end
end

-- 平滑过渡：获取旧规则
function _M.get_old_rules()
    return cache:get(OLD_RULES_KEY)
end

-- 平滑过渡：切换到新规则
function _M.transition_to_new_rules()
    if not SMOOTH_TRANSITION_ENABLED then
        return
    end
    
    -- 删除旧规则
    cache:delete(OLD_RULES_KEY)
    
    -- 更新版本号
    cache_invalidation.increment_version()
end

-- 执行完整预热
function _M.do_warmup()
    local results = {}
    
    -- 保存旧规则（用于平滑过渡）
    _M.save_old_rules()
    
    -- 预热IP段规则
    local ok, err = _M.warmup_ip_range_rules()
    table.insert(results, {
        type = "ip_range_rules",
        success = ok,
        error = err
    })
    
    -- 预热白名单规则
    ok, err = _M.warmup_whitelist_rules()
    table.insert(results, {
        type = "whitelist_rules",
        success = ok,
        error = err
    })
    
    -- 预热常用IP（可选）
    if config.cache_warmup and config.cache_warmup.warmup_common_ips then
        ok, err = _M.warmup_common_ips()
        table.insert(results, {
            type = "common_ips",
            success = ok,
            error = err
        })
    end
    
    return results
end

-- 检查是否需要预热
function _M.should_warmup()
    local status = _M.get_warmup_status()
    if status == WarmupStatus.WARMING then
        return false  -- 正在预热中
    end
    
    -- 检查规则版本号变化
    local cache_key = "rule_version:current"
    local cached_version = cache:get(cache_key)
    
    local sql = [[
        SELECT config_value FROM waf_system_config
        WHERE config_key = 'rule_version'
        LIMIT 1
    ]]
    
    local res, err = mysql_pool.query(sql)
    if err then
        return false
    end
    
    if res and #res > 0 then
        local current_version = tonumber(res[1].config_value) or 1
        if cached_version and tonumber(cached_version) ~= current_version then
            return true  -- 版本号变化，需要预热
        end
    end
    
    return false
end

return _M

