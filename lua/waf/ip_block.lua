-- IP 封控模块
-- 路径：项目目录下的 lua/waf/ip_block.lua（保持在项目目录，不复制到系统目录）

local ip_utils = require "waf.ip_utils"
local mysql_pool = require "waf.mysql_pool"
local geo_block = require "waf.geo_block"
local auto_block = require "waf.auto_block"
local frequency_stats = require "waf.frequency_stats"
local fallback = require "waf.fallback"
local metrics = require "waf.metrics"
local cache_protection = require "waf.cache_protection"
local ip_trie = require "waf.ip_trie"
local lru_cache = require "waf.lru_cache"
local redis_cache = require "waf.redis_cache"
local serializer = require "waf.serializer"
local feature_switches = require "waf.feature_switches"
local config = require "config"
local cjson = require "cjson"

local _M = {}
local cache = ngx.shared.waf_cache
local CACHE_KEY_PREFIX = "block_rules:"
local CACHE_TTL = config.cache.ttl
local RULE_LIST_TTL = config.cache.rule_list_ttl or 300  -- 规则列表缓存时间（默认5分钟）
local RULE_LIST_KEY_BLOCK = "rule_list:ip_range:block"  -- IP 段封控规则列表缓存键
local RULE_LIST_KEY_WHITELIST = "rule_list:ip_range:whitelist"  -- IP 段白名单规则列表缓存键

-- 检查白名单
local function check_whitelist(client_ip)
    -- 检查白名单功能是否启用（优先从数据库读取）
    local whitelist_enabled = feature_switches.is_enabled("whitelist")
    if not whitelist_enabled or not config.whitelist.enable then
        return false
    end

    -- 从缓存获取白名单
    local cache_key = "whitelist:" .. client_ip
    local cached = cache:get(cache_key)
    if cached ~= nil then
        metrics.record_cache_hit()
        return cached == "1"
    end

    -- 降级模式：如果数据库不可用，仅使用缓存
    if fallback.should_fallback() then
        metrics.record_cache_miss()
        return fallback.get_whitelist_from_cache(client_ip)
    end

    -- 查询数据库（先查询单个 IP）
    local sql = [[
        SELECT id, ip_type, ip_value FROM waf_whitelist 
        WHERE status = 1 
        AND ip_type = 'single_ip'
        AND ip_value = ?
        LIMIT 1
    ]]

    local res, err = mysql_pool.query(sql, client_ip)
    if err then
        ngx.log(ngx.ERR, "whitelist query error: ", err)
        metrics.record_cache_miss()
        -- 降级模式：尝试从缓存获取
        if fallback.should_fallback() then
            return fallback.get_whitelist_from_cache(client_ip)
        end
        return false
    end

    if res and #res > 0 then
        cache:set(cache_key, "1", CACHE_TTL)
        return true
    end

    -- 查询 IP 段（使用缓存的规则列表）
    local rule_list_data = cache:get(RULE_LIST_KEY_WHITELIST)
    local rules = nil
    
    if rule_list_data then
        -- 从缓存获取规则列表（优化：减少字符串操作）
        local ok, decoded = pcall(cjson.decode, rule_list_data)
        if ok and decoded then
            rules = decoded
        end
    end
    
    -- 如果缓存不存在或已过期，从数据库查询
    if not rules then
        local sql = [[
            SELECT id, ip_type, ip_value FROM waf_whitelist 
            WHERE status = 1 
            AND ip_type = 'ip_range'
        ]]

        local res, err = mysql_pool.query(sql)
        if err then
            ngx.log(ngx.ERR, "whitelist ip_range query error: ", err)
            return false
        end

        rules = res or {}
        -- 缓存规则列表（使用较长的 TTL）
        cache:set(RULE_LIST_KEY_WHITELIST, cjson.encode(rules), RULE_LIST_TTL)
    end

    if rules and #rules > 0 then
        -- 遍历 IP 段规则进行匹配
        for _, rule in ipairs(rules) do
            local ip_value = rule.ip_value
            
            -- 检查 CIDR 格式
            if ip_utils.match_cidr(client_ip, ip_value) then
                cache:set(cache_key, "1", CACHE_TTL)
                return true
            end
            
            -- 检查 IP 范围格式
            local start_ip, end_ip = ip_utils.parse_ip_range(ip_value)
            if start_ip and end_ip then
                if ip_utils.match_ip_range(client_ip, start_ip, end_ip) then
                    cache:set(cache_key, "1", CACHE_TTL)
                    return true
                end
            end
        end
    end

    -- 未匹配到白名单
    cache:set(cache_key, "0", CACHE_TTL)
    return false
end

-- 检查单个 IP 封控
local function check_single_ip(client_ip)
    local cache_key = CACHE_KEY_PREFIX .. "single:" .. client_ip
    local cached = cache:get(cache_key)
    if cached ~= nil then
        metrics.record_cache_hit()
        if cached == "1" then
            -- 从另一个缓存获取规则信息
            local rule_cache_key = cache_key .. ":rule"
            local rule_data = cache:get(rule_cache_key)
            if rule_data then
                return true, cjson.decode(rule_data)
            end
            -- 如果规则数据不存在，重新查询数据库获取规则信息
            -- 这种情况可能发生在缓存过期或规则数据未正确缓存时
            -- 继续执行下面的数据库查询逻辑
        else
            return false, nil
        end
    else
        metrics.record_cache_miss()
    end

    -- 降级模式：如果数据库不可用，仅使用缓存
    if fallback.should_fallback() then
        return fallback.get_block_rule_from_cache(client_ip, "single_ip")
    end

    -- 先检查白名单（优先级高）
    local whitelist_sql = [[
        SELECT id, rule_name, rule_type FROM waf_block_rules 
        WHERE status = 1 
        AND rule_type = 'ip_whitelist'
        AND (rule_value = ? OR rule_value LIKE ? OR rule_value LIKE ? OR rule_value LIKE ?)
        AND (start_time IS NULL OR start_time <= NOW())
        AND (end_time IS NULL OR end_time >= NOW())
        ORDER BY priority DESC
        LIMIT 1
    ]]
    -- 匹配单个IP、CIDR格式、IP范围格式（支持多选，用逗号分隔）
    local ip_pattern = client_ip .. ",%"
    local ip_pattern2 = "%," .. client_ip .. ",%"
    local ip_pattern3 = "%," .. client_ip

    local whitelist_res, err = mysql_pool.query(whitelist_sql, client_ip, ip_pattern, ip_pattern2, ip_pattern3)
    if err then
        ngx.log(ngx.ERR, "ip whitelist query error: ", err)
    end
    
    -- 如果在白名单中，直接允许通过
    if whitelist_res and #whitelist_res > 0 then
        return false, nil  -- 不在黑名单中，允许通过
    end
    
    -- 检查黑名单
    local blacklist_sql = [[
        SELECT id, rule_name, rule_type FROM waf_block_rules 
        WHERE status = 1 
        AND rule_type = 'ip_blacklist'
        AND (rule_value = ? OR rule_value LIKE ? OR rule_value LIKE ? OR rule_value LIKE ?)
        AND (start_time IS NULL OR start_time <= NOW())
        AND (end_time IS NULL OR end_time >= NOW())
        ORDER BY priority DESC
        LIMIT 1
    ]]
    
    local res, err = mysql_pool.query(blacklist_sql, client_ip, ip_pattern, ip_pattern2, ip_pattern3)
    if err then
        ngx.log(ngx.ERR, "single ip query error: ", err)
        -- 降级模式：尝试从缓存获取
        if fallback.should_fallback() then
            return fallback.get_block_rule_from_cache(client_ip, "ip_blacklist")
        end
        return false, nil
    end

    local is_blocked = res and #res > 0
    cache:set(cache_key, is_blocked and "1" or "0", CACHE_TTL)
    
    if is_blocked then
        local rule = res[1]
        -- 缓存规则信息
        local rule_data = {id = rule.id, rule_name = rule.rule_name}
        cache:set(cache_key .. ":rule", cjson.encode(rule_data), CACHE_TTL)
        return true, rule
    end
    
    return false, nil
end

-- 检查 IP 段封控
local function check_ip_range(client_ip)
    local cache_key = CACHE_KEY_PREFIX .. "range:" .. client_ip
    local cached = cache:get(cache_key)
    if cached ~= nil then
        if cached == "1" then
            -- 需要从另一个缓存获取规则信息
            local rule_cache_key = cache_key .. ":rule"
            local rule_data = cache:get(rule_cache_key)
            if rule_data then
                return true, cjson.decode(rule_data)
            end
            -- 如果规则数据不存在，继续查询数据库获取规则信息
            -- 继续执行下面的数据库查询逻辑
        else
            return false, nil
        end
    end

    -- 查询所有 IP 段规则（使用缓存的规则列表）
    -- 先尝试从Redis二级缓存获取
    local rules = nil
    if redis_cache.is_available() then
        rules = redis_cache.get(RULE_LIST_KEY_BLOCK)
    end
    
    -- 如果Redis中没有，从本地缓存获取
    if not rules then
        local rule_list_data = cache:get(RULE_LIST_KEY_BLOCK)
        if rule_list_data then
            -- 从缓存获取规则列表（支持JSON和MessagePack）
            local ok, decoded = pcall(function()
                return serializer.decode(rule_list_data)
            end)
            if ok and decoded then
                rules = decoded
                -- 同步到Redis
                if redis_cache.is_available() then
                    redis_cache.set(RULE_LIST_KEY_BLOCK, rules, RULE_LIST_TTL)
                end
            end
        end
    end
    
    -- 如果缓存不存在或已过期，从数据库查询
    if not rules then
        -- 检查缓存穿透防护
        local allow_query, reason = cache_protection.should_allow_query(
            RULE_LIST_KEY_BLOCK, client_ip, client_ip, "ip_range_query"
        )
        if not allow_query then
            -- 被防护机制拦截，返回空结果
            if reason == "empty_result_cached" then
                cache:set(cache_key, "0", CACHE_TTL)
                return false, nil
            end
        end
        
        local sql = [[
            SELECT id, rule_name, rule_value, priority FROM waf_block_rules 
            WHERE status = 1 
            AND rule_type = 'ip_range'
            AND (start_time IS NULL OR start_time <= NOW())
            AND (end_time IS NULL OR end_time >= NOW())
            ORDER BY priority DESC
        ]]

        local res, err = mysql_pool.query(sql)
        if err then
            ngx.log(ngx.ERR, "ip range query error: ", err)
            -- 记录查询失败
            cache_protection.record_query_result(RULE_LIST_KEY_BLOCK, client_ip, false)
            return false, nil
        end

        rules = res or {}
        
        -- 记录查询结果
        cache_protection.record_query_result(RULE_LIST_KEY_BLOCK, client_ip, #rules > 0)
        
        -- 缓存规则列表（使用序列化器，支持JSON和MessagePack）
        local serialized, format = serializer.encode(rules)
        if serialized then
            cache:set(RULE_LIST_KEY_BLOCK, serialized, RULE_LIST_TTL)
            -- 同步到Redis
            if redis_cache.is_available() then
                redis_cache.set(RULE_LIST_KEY_BLOCK, rules, RULE_LIST_TTL)
            end
        end
        
        -- 构建并缓存Trie树
        if #rules > 0 then
            local trie_manager = ip_trie.build_trie(rules)
            local trie_data = ip_trie.serialize_trie(trie_manager)
            local trie_serialized, _ = serializer.encode(trie_data)
            if trie_serialized then
                cache:set(RULE_LIST_KEY_BLOCK .. ":trie", trie_serialized, RULE_LIST_TTL)
            end
        end
    end

    if not rules or #rules == 0 then
        lru_cache.set(cache_key, "0", CACHE_TTL)
        return false, nil
    end

    -- 尝试使用Trie树匹配（优先）
    local trie_data = cache:get(RULE_LIST_KEY_BLOCK .. ":trie")
    if trie_data then
        local ok, trie_serialized = pcall(cjson.decode, trie_data)
        if ok and trie_serialized then
            -- 重建Trie树并匹配
            local trie_manager = ip_trie.deserialize_trie(trie_serialized, rules)
            local matched_rule = trie_manager:match(client_ip)
            
            if matched_rule then
                lru_cache.set(cache_key, "1", CACHE_TTL)
                local rule_data = {id = matched_rule.id, rule_name = matched_rule.rule_name}
                lru_cache.set(cache_key .. ":rule", cjson.encode(rule_data), CACHE_TTL)
                return true, matched_rule
            end
        end
    end

    -- 回退到传统遍历匹配（用于IP范围规则）
    for _, rule in ipairs(rules) do
        local rule_value = rule.rule_value
        
        -- 检查 CIDR 格式（如果Trie树未匹配到）
        if ip_utils.match_cidr(client_ip, rule_value) then
            lru_cache.set(cache_key, "1", CACHE_TTL)
            local rule_data = {id = rule.id, rule_name = rule.rule_name}
            lru_cache.set(cache_key .. ":rule", cjson.encode(rule_data), CACHE_TTL)
            return true, rule
        end
        
        -- 检查 IP 范围格式（192.168.1.1-192.168.1.100）
        local start_ip, end_ip = ip_utils.parse_ip_range(rule_value)
        if start_ip and end_ip then
            if ip_utils.match_ip_range(client_ip, start_ip, end_ip) then
                lru_cache.set(cache_key, "1", CACHE_TTL)
                local rule_data = {id = rule.id, rule_name = rule.rule_name}
                lru_cache.set(cache_key .. ":rule", cjson.encode(rule_data), CACHE_TTL)
                return true, rule
            end
        end
    end

    lru_cache.set(cache_key, "0", CACHE_TTL)
    return false, nil
end

-- 检查地域封控（使用 GeoIP2 数据库）
local function check_geo_block(client_ip)
    return geo_block.check(client_ip)
end

-- 记录封控日志
local function log_block(client_ip, rule, block_reason)
    if not rule then
        return
    end

    local request_path = ngx.var.request_uri or ""
    local user_agent = ngx.var.http_user_agent or ""
    block_reason = block_reason or "manual"
    
    local sql = [[
        INSERT INTO waf_block_logs (client_ip, rule_id, rule_name, block_time, request_path, user_agent, block_reason)
        VALUES (?, ?, ?, NOW(), ?, ?, ?)
    ]]

    local ok, err = mysql_pool.insert(sql, client_ip, rule.id, rule.rule_name, request_path, user_agent, block_reason)
    if err then
        ngx.log(ngx.ERR, "block log insert error: ", err)
    end
end

-- 检查规则版本号（用于缓存失效）
local function check_rule_version()
    if not config.cache_invalidation.enable_version_check then
        return
    end

    local cache_key = "rule_version:current"
    local cached_version = cache:get(cache_key)
    
    local sql = [[
        SELECT config_value FROM waf_system_config
        WHERE config_key = 'rule_version'
        LIMIT 1
    ]]

    local res, err = mysql_pool.query(sql)
    if err then
        ngx.log(ngx.ERR, "rule version query error: ", err)
        return
    end

    if res and #res > 0 then
        local current_version = tonumber(res[1].config_value) or 1
        if cached_version and tonumber(cached_version) ~= current_version then
            -- 版本号变化，清除所有规则缓存
            ngx.log(ngx.INFO, "rule version changed, clearing caches")
            cache:delete(RULE_LIST_KEY_BLOCK)
            cache:delete(RULE_LIST_KEY_WHITELIST)
        end
        cache:set(cache_key, current_version, config.cache_invalidation.version_check_interval or 30)
    end
end

-- 主检查函数
function _M.check()
    -- 检查IP封控功能是否启用（优先从数据库读取）
    local ip_block_enabled = feature_switches.is_enabled("ip_block")
    if not ip_block_enabled or not config.block.enable then
        return
    end

    -- 检查规则版本号（用于缓存失效）
    check_rule_version()

    -- 获取客户端真实 IP
    local client_ip = ip_utils.get_real_ip()
    if not client_ip then
        return
    end

    -- 检查白名单（优先级最高）
    if check_whitelist(client_ip) then
        return
    end

    -- 检查封控规则（按优先级顺序）
    local is_blocked = false
    local matched_rule = nil
    local block_reason = "manual"

    -- 1. 检查自动封控（优先级最高）
    local auto_blocked, auto_block_info = auto_block.check_auto_block(client_ip)
    if auto_blocked then
        is_blocked = true
        matched_rule = {
            id = auto_block_info.id,
            rule_name = "自动封控-" .. client_ip,
            block_reason = auto_block_info.reason
        }
        block_reason = auto_block_info.reason or "auto_frequency"
        goto block
    end

    -- 2. 检查单个 IP
    is_blocked, matched_rule = check_single_ip(client_ip)
    if is_blocked then
        goto block
    end

    -- 3. 检查 IP 段
    is_blocked, matched_rule = check_ip_range(client_ip)
    if is_blocked then
        goto block
    end

    -- 4. 检查地域封控
    is_blocked, matched_rule = check_geo_block(client_ip)
    if is_blocked then
        goto block
    end

    -- 5. 检查是否需要自动封控（基于频率统计）
    if config.auto_block.enable then
        local should_block, block_info = frequency_stats.should_auto_block(client_ip)
        if should_block then
            -- 创建自动封控规则
            local ok, auto_rule = auto_block.create_auto_block_rule(client_ip, block_info)
            if ok then
                is_blocked = true
                matched_rule = {
                    id = auto_rule.id,
                    rule_name = "自动封控-" .. client_ip,
                    block_reason = block_info.reason
                }
                block_reason = block_info.reason or "auto_frequency"
                goto block
            end
        end
    end

    -- 未匹配任何规则，允许通过
    return

    ::block::
    -- 记录封控日志
    log_block(client_ip, matched_rule, block_reason)
    
    -- 记录监控指标
    if config.metrics and config.metrics.enable then
        metrics.record_block(block_reason)
    end
    
    -- 返回 403
    ngx.status = 403
    ngx.header.content_type = "text/html; charset=utf-8"
    ngx.say(config.block.block_page)
    ngx.exit(403)
end

return _M

