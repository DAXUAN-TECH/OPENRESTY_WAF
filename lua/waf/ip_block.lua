-- IP 封控模块
-- 路径：/usr/local/openresty/nginx/lua/waf/ip_block.lua

local ip_utils = require "waf.ip_utils"
local mysql_pool = require "waf.mysql_pool"
local geo_block = require "waf.geo_block"
local config = require "config"

local _M = {}
local cache = ngx.shared.waf_cache
local CACHE_KEY_PREFIX = "block_rules:"
local CACHE_TTL = config.cache.ttl

-- 检查白名单
local function check_whitelist(client_ip)
    if not config.whitelist.enable then
        return false
    end

    -- 从缓存获取白名单
    local cache_key = "whitelist:" .. client_ip
    local cached = cache:get(cache_key)
    if cached ~= nil then
        return cached == "1"
    end

    -- 查询数据库
    local sql = [[
        SELECT id FROM whitelist 
        WHERE status = 1 
        AND (
            (ip_type = 'single_ip' AND ip_value = ?)
            OR (ip_type = 'ip_range' AND ? LIKE CONCAT(ip_value, '%'))
        )
        LIMIT 1
    ]]

    local res, err = mysql_pool.query(sql, client_ip, client_ip)
    if err then
        ngx.log(ngx.ERR, "whitelist query error: ", err)
        return false
    end

    local is_whitelisted = res and #res > 0
    cache:set(cache_key, is_whitelisted and "1" or "0", CACHE_TTL)
    
    return is_whitelisted
end

-- 检查单个 IP 封控
local function check_single_ip(client_ip)
    local cache_key = CACHE_KEY_PREFIX .. "single:" .. client_ip
    local cached = cache:get(cache_key)
    if cached ~= nil then
        return cached == "1"
    end

    local sql = [[
        SELECT id, rule_name FROM block_rules 
        WHERE status = 1 
        AND rule_type = 'single_ip' 
        AND rule_value = ?
        AND (start_time IS NULL OR start_time <= NOW())
        AND (end_time IS NULL OR end_time >= NOW())
        ORDER BY priority DESC
        LIMIT 1
    ]]

    local res, err = mysql_pool.query(sql, client_ip)
    if err then
        ngx.log(ngx.ERR, "single ip query error: ", err)
        return false, nil
    end

    local is_blocked = res and #res > 0
    cache:set(cache_key, is_blocked and "1" or "0", CACHE_TTL)
    
    if is_blocked then
        return true, res[1]
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
        else
            return false, nil
        end
    end

    -- 查询所有 IP 段规则
    local sql = [[
        SELECT id, rule_name, rule_value, priority FROM block_rules 
        WHERE status = 1 
        AND rule_type = 'ip_range'
        AND (start_time IS NULL OR start_time <= NOW())
        AND (end_time IS NULL OR end_time >= NOW())
        ORDER BY priority DESC
    ]]

    local res, err = mysql_pool.query(sql)
    if err then
        ngx.log(ngx.ERR, "ip range query error: ", err)
        return false, nil
    end

    if not res or #res == 0 then
        cache:set(cache_key, "0", CACHE_TTL)
        return false, nil
    end

    -- 遍历规则进行匹配
    for _, rule in ipairs(res) do
        local rule_value = rule.rule_value
        
        -- 检查 CIDR 格式
        if ip_utils.match_cidr(client_ip, rule_value) then
            cache:set(cache_key, "1", CACHE_TTL)
            local rule_data = {id = rule.id, rule_name = rule.rule_name}
            cache:set(cache_key .. ":rule", cjson.encode(rule_data), CACHE_TTL)
            return true, rule
        end
        
        -- 检查 IP 范围格式（192.168.1.1-192.168.1.100）
        local start_ip, end_ip = ip_utils.parse_ip_range(rule_value)
        if start_ip and end_ip then
            if ip_utils.match_ip_range(client_ip, start_ip, end_ip) then
                cache:set(cache_key, "1", CACHE_TTL)
                local rule_data = {id = rule.id, rule_name = rule.rule_name}
                cache:set(cache_key .. ":rule", cjson.encode(rule_data), CACHE_TTL)
                return true, rule
            end
        end
    end

    cache:set(cache_key, "0", CACHE_TTL)
    return false, nil
end

-- 检查地域封控（使用 GeoIP2 数据库）
local function check_geo_block(client_ip)
    return geo_block.check(client_ip)
end

-- 记录封控日志
local function log_block(client_ip, rule)
    if not rule then
        return
    end

    local request_path = ngx.var.request_uri or ""
    local user_agent = ngx.var.http_user_agent or ""
    
    local sql = [[
        INSERT INTO block_logs (client_ip, rule_id, rule_name, block_time, request_path, user_agent)
        VALUES (?, ?, ?, NOW(), ?, ?)
    ]]

    local ok, err = mysql_pool.insert(sql, client_ip, rule.id, rule.rule_name, request_path, user_agent)
    if err then
        ngx.log(ngx.ERR, "block log insert error: ", err)
    end
end

-- 主检查函数
function _M.check()
    if not config.block.enable then
        return
    end

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

    -- 1. 检查单个 IP
    is_blocked, matched_rule = check_single_ip(client_ip)
    if is_blocked then
        goto block
    end

    -- 2. 检查 IP 段
    is_blocked, matched_rule = check_ip_range(client_ip)
    if is_blocked then
        goto block
    end

    -- 3. 检查地域封控
    is_blocked, matched_rule = check_geo_block(client_ip)
    if is_blocked then
        goto block
    end

    -- 未匹配任何规则，允许通过
    return

    ::block::
    -- 记录封控日志
    log_block(client_ip, matched_rule)
    
    -- 返回 403
    ngx.status = 403
    ngx.header.content_type = "text/html; charset=utf-8"
    ngx.say(config.block.block_page)
    ngx.exit(403)
end

return _M

