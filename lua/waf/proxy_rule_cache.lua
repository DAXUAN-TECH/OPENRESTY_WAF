-- 代理规则缓存模块
-- 路径：项目目录下的 lua/waf/proxy_rule_cache.lua
-- 功能：缓存proxy_id和ip_rule_ids的映射关系，减少数据库查询

local mysql_pool = require "waf.mysql_pool"
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
local CACHE_KEY_PREFIX = "proxy_rule_ids:"
local CACHE_TTL = 300  -- 缓存时间（5分钟）

-- 通过server_name和listen_port获取proxy_id和ip_rule_ids
-- @param server_name string 服务器名称（可选）
-- @param listen_port number 监听端口（可选）
-- @return table|nil ip_rule_ids数组，如果不存在则返回nil
function _M.get_rule_ids(server_name, listen_port)
    if not cache then
        ngx.log(ngx.WARN, "proxy_rule_cache: 共享内存不可用，无法使用缓存")
        return nil
    end
    
    -- 构建缓存键
    local cache_key = nil
    if server_name and server_name ~= "" and server_name ~= "_" then
        -- 优先使用server_name（可能包含多个域名，使用第一个）
        local first_domain = server_name:match("^%s*([^%s]+)")
        if first_domain then
            cache_key = CACHE_KEY_PREFIX .. "server_name:" .. first_domain
        end
    end
    
    if not cache_key and listen_port then
        -- 如果没有server_name，使用listen_port
        cache_key = CACHE_KEY_PREFIX .. "port:" .. tostring(listen_port)
    end
    
    if not cache_key then
        ngx.log(ngx.WARN, "proxy_rule_cache: 无法构建缓存键，server_name和listen_port都为空")
        return nil
    end
    
    -- 从缓存获取
    local cached_data = cache:get(cache_key)
    if cached_data then
        local ok, decoded = pcall(cjson.decode, cached_data)
        if ok and decoded and type(decoded) == "table" then
            ngx.log(ngx.INFO, "proxy_rule_cache: 缓存命中，cache_key: ", cache_key, ", rule_ids: ", cjson.encode(decoded))
            return decoded
        else
            ngx.log(ngx.WARN, "proxy_rule_cache: 缓存数据解析失败，cache_key: ", cache_key)
        end
    end
    
    -- 缓存未命中，查询数据库
    ngx.log(ngx.INFO, "proxy_rule_cache: 缓存未命中，查询数据库，cache_key: ", cache_key)
    
    local sql = nil
    local query_params = {}
    
    if server_name and server_name ~= "" and server_name ~= "_" then
        -- 使用server_name查询
        local first_domain = server_name:match("^%s*([^%s]+)")
        if first_domain then
            sql = [[
                SELECT id, ip_rule_ids 
                FROM waf_proxy_configs 
                WHERE status = 1 
                AND server_name LIKE ?
                LIMIT 1
            ]]
            -- 使用LIKE匹配，因为server_name可能包含多个域名（空格分隔）
            table.insert(query_params, "%" .. first_domain .. "%")
        end
    end
    
    if not sql and listen_port then
        -- 使用listen_port查询
        sql = [[
            SELECT id, ip_rule_ids 
            FROM waf_proxy_configs 
            WHERE status = 1 
            AND listen_port = ?
            LIMIT 1
        ]]
        table.insert(query_params, listen_port)
    end
    
    if not sql then
        ngx.log(ngx.WARN, "proxy_rule_cache: 无法构建SQL查询，server_name和listen_port都为空")
        return nil
    end
    
    local res, err = mysql_pool.query(sql, unpack(query_params))
    if err then
        ngx.log(ngx.ERR, "proxy_rule_cache: 查询数据库失败，error: ", err)
        return nil
    end
    
    if not res or #res == 0 then
        ngx.log(ngx.INFO, "proxy_rule_cache: 未找到匹配的代理配置")
        -- 缓存空结果，避免重复查询（缓存时间较短）
        cache:set(cache_key, cjson.encode({}), CACHE_TTL)
        return nil
    end
    
    local proxy = res[1]
    local ip_rule_ids = nil
    
    -- 解析ip_rule_ids JSON字段
    if proxy.ip_rule_ids then
        local ok, decoded_rule_ids = pcall(cjson.decode, proxy.ip_rule_ids)
        if ok and decoded_rule_ids and type(decoded_rule_ids) == "table" and #decoded_rule_ids > 0 then
            ip_rule_ids = decoded_rule_ids
        end
    end
    
    -- 更新缓存
    if ip_rule_ids then
        cache:set(cache_key, cjson.encode(ip_rule_ids), CACHE_TTL)
        ngx.log(ngx.INFO, "proxy_rule_cache: 缓存已更新，cache_key: ", cache_key, ", rule_ids: ", cjson.encode(ip_rule_ids))
    else
        -- 缓存空结果
        cache:set(cache_key, cjson.encode({}), CACHE_TTL)
    end
    
    return ip_rule_ids
end

-- 清除指定代理的缓存
-- @param proxy_id number 代理ID
function _M.clear_cache(proxy_id)
    if not cache or not proxy_id then
        return
    end
    
    -- 查询代理配置，获取server_name和listen_port
    local sql = [[
        SELECT server_name, listen_port 
        FROM waf_proxy_configs 
        WHERE id = ?
        LIMIT 1
    ]]
    
    local res, err = mysql_pool.query(sql, proxy_id)
    if err then
        ngx.log(ngx.ERR, "proxy_rule_cache: 查询代理配置失败，proxy_id: ", proxy_id, ", error: ", err)
        return
    end
    
    if not res or #res == 0 then
        return
    end
    
    local proxy = res[1]
    
    -- 清除server_name缓存
    if proxy.server_name and proxy.server_name ~= "" and proxy.server_name ~= "_" then
        local first_domain = proxy.server_name:match("^%s*([^%s]+)")
        if first_domain then
            local cache_key = CACHE_KEY_PREFIX .. "server_name:" .. first_domain
            cache:delete(cache_key)
            ngx.log(ngx.INFO, "proxy_rule_cache: 已清除server_name缓存，cache_key: ", cache_key)
        end
    end
    
    -- 清除listen_port缓存
    if proxy.listen_port then
        local cache_key = CACHE_KEY_PREFIX .. "port:" .. tostring(proxy.listen_port)
        cache:delete(cache_key)
        ngx.log(ngx.INFO, "proxy_rule_cache: 已清除listen_port缓存，cache_key: ", cache_key)
    end
end

-- 清除所有代理规则缓存
function _M.clear_all_cache()
    if not cache then
        return
    end
    
    -- 注意：ngx.shared不支持遍历，这里只能清除已知的缓存键
    -- 实际应用中，可以通过设置较短的TTL让缓存自动过期
    ngx.log(ngx.INFO, "proxy_rule_cache: 清除所有缓存（通过TTL自动过期）")
end

return _M

