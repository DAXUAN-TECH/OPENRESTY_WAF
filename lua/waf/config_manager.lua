-- 配置管理模块
-- 路径：项目目录下的 lua/waf/config_manager.lua（保持在项目目录，不复制到系统目录）
-- 功能：从数据库读取配置，支持配置热更新和缓存

local cjson = require "cjson"
local mysql_pool = require "waf.mysql_pool"
local config = require "config"

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
local CONFIG_CACHE_PREFIX = "config:"
local CONFIG_CACHE_TTL = 300  -- 配置缓存时间（秒，5分钟）

-- 从数据库读取配置值
local function get_config_from_db(config_key, default_value)
    local cache_key = CONFIG_CACHE_PREFIX .. config_key
    local cached = nil
    if cache then
        cached = cache:get(cache_key)
    end
    if cached ~= nil then
        return cached
    end
    
    local ok, res = pcall(function()
        local sql = [[
            SELECT config_value FROM waf_system_config
            WHERE config_key = ?
            LIMIT 1
        ]]
        return mysql_pool.query(sql, config_key)
    end)
    
    if ok and res and #res > 0 then
        local value = res[1].config_value
        if cache then
            cache:set(cache_key, value, CONFIG_CACHE_TTL)
        end
        return value
    end
    
    -- 如果数据库中没有，返回默认值
    if default_value ~= nil then
        if cache then
            cache:set(cache_key, tostring(default_value), CONFIG_CACHE_TTL)
        end
        return tostring(default_value)
    end
    
    return nil
end

-- 获取配置值（支持类型转换）
function _M.get_config(config_key, default_value, value_type)
    local value = get_config_from_db(config_key, default_value)
    if value == nil then
        return default_value
    end
    
    -- 类型转换
    if value_type == "number" then
        return tonumber(value) or default_value
    elseif value_type == "boolean" then
        return value == "1" or value == "true" or value == "yes"
    elseif value_type == "json" then
        local ok, decoded = pcall(cjson.decode, value)
        if ok then
            return decoded
        end
        return default_value
    else
        return value
    end
end

-- 设置配置值（更新数据库和缓存）
function _M.set_config(config_key, config_value, description)
    local value_str = tostring(config_value)
    if type(config_value) == "table" then
        value_str = cjson.encode(config_value)
    elseif type(config_value) == "boolean" then
        value_str = config_value and "1" or "0"
    end
    
    local ok, err = pcall(function()
        local sql = [[
            INSERT INTO waf_system_config (config_key, config_value, description)
            VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE
                config_value = VALUES(config_value),
                description = COALESCE(VALUES(description), description),
                updated_at = CURRENT_TIMESTAMP
        ]]
        return mysql_pool.query(sql, config_key, value_str, description)
    end)
    
    if ok and not err then
        -- 更新缓存
        if cache then
            local cache_key = CONFIG_CACHE_PREFIX .. config_key
            cache:set(cache_key, value_str, CONFIG_CACHE_TTL)
        end
        return true
    end
    
    return false, err
end

-- 批量获取配置
function _M.get_configs(config_keys, defaults)
    local results = {}
    for i, key in ipairs(config_keys) do
        local default_value = defaults and defaults[key] or nil
        results[key] = _M.get_config(key, default_value)
    end
    return results
end

-- 清除配置缓存
function _M.clear_cache(config_key)
    if not cache then
        return
    end
    if config_key then
        local cache_key = CONFIG_CACHE_PREFIX .. config_key
        cache:delete(cache_key)
    else
        -- 清除所有配置缓存（通过设置过期时间）
        -- 注意：ngx.shared 不支持批量删除，这里只清除常用的配置
        local common_keys = {
            "cache_ttl", "log_batch_size", "block_enable", "whitelist_enable",
            "geo_enable", "auto_block_enable", "session_ttl", "csrf_enable"
        }
        for _, key in ipairs(common_keys) do
            local cache_key = CONFIG_CACHE_PREFIX .. key
            cache:delete(cache_key)
        end
    end
end

-- 获取所有配置（用于配置管理界面）
function _M.get_all_configs()
    local ok, res = pcall(function()
        local sql = [[
            SELECT config_key, config_value, description, updated_at
            FROM waf_system_config
            ORDER BY config_key
        ]]
        return mysql_pool.query(sql)
    end)
    
    if ok and res then
        return res
    end
    
    return {}
end

return _M

