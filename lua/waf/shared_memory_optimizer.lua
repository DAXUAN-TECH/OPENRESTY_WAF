-- 共享内存优化模块
-- 路径：项目目录下的 lua/waf/shared_memory_optimizer.lua（保持在项目目录，不复制到系统目录）
-- 功能：使用 Redis 替代部分共享内存，实现跨进程共享和分布式缓存
-- 优化说明：
-- 1. ngx.shared 无法跨进程共享，使用 Redis 实现分布式缓存
-- 2. 将非关键数据迁移到 Redis，减少共享内存压力
-- 3. 提供统一的缓存接口，自动选择使用共享内存或 Redis

local config_manager = require "waf.config_manager"
local redis_cache = require "waf.redis_cache"
local cjson = require "cjson"

local _M = {}
local cache = ngx.shared.waf_cache

-- 配置键（从数据库读取）
local SHARED_MEMORY_OPTIMIZER_ENABLE = "shared_memory_optimizer_enable"
local REDIS_FALLBACK_ENABLE = "shared_memory_redis_fallback_enable"

-- 缓存键分类（决定使用共享内存还是 Redis）
local SHARED_MEMORY_KEYS = {
    -- 关键数据使用共享内存（低延迟）
    ["ip_block:"] = true,
    ["whitelist:"] = true,
    ["rule_list:"] = true,
    ["session:"] = true,
    ["csrf:"] = true,
}

local REDIS_KEYS = {
    -- 非关键数据使用 Redis（可跨进程）
    ["cache_access_count:"] = true,
    ["cache_access_time:"] = true,
    ["cache_hotspot:"] = true,
    ["frequency_stats:"] = true,
    ["log_queue:"] = true,
}

-- 检查功能是否启用
local function is_enabled()
    return config_manager.get_config(SHARED_MEMORY_OPTIMIZER_ENABLE, false, "boolean")
end

local function is_redis_fallback_enabled()
    return is_enabled() and config_manager.get_config(REDIS_FALLBACK_ENABLE, true, "boolean")
end

-- 判断键应该使用哪种存储
local function get_storage_type(key)
    if not is_enabled() then
        return "shared"  -- 默认使用共享内存
    end
    
    -- 检查是否为关键数据
    for prefix, _ in pairs(SHARED_MEMORY_KEYS) do
        if key:match("^" .. prefix) then
            return "shared"
        end
    end
    
    -- 检查是否为非关键数据
    for prefix, _ in pairs(REDIS_KEYS) do
        if key:match("^" .. prefix) then
            return "redis"
        end
    end
    
    -- 默认使用共享内存
    return "shared"
end

-- 统一的 get 接口
function _M.get(key, default_value)
    local storage_type = get_storage_type(key)
    
    if storage_type == "redis" and is_redis_fallback_enabled() and redis_cache.enable then
        -- 使用 Redis
        local ok, value = redis_cache.get(key)
        if ok and value then
            return value
        end
        -- Redis 失败时回退到共享内存
        if not ok then
            ngx.log(ngx.WARN, "Redis get failed for key: ", key, ", falling back to shared memory")
        end
    end
    
    -- 使用共享内存
    local value = cache:get(key)
    if value == nil then
        return default_value
    end
    return value
end

-- 统一的 set 接口
function _M.set(key, value, ttl)
    local storage_type = get_storage_type(key)
    
    if storage_type == "redis" and is_redis_fallback_enabled() and redis_cache.enable then
        -- 使用 Redis
        local ok, err = redis_cache.set(key, value, ttl)
        if ok then
            return true
        end
        -- Redis 失败时回退到共享内存
        if not ok then
            ngx.log(ngx.WARN, "Redis set failed for key: ", key, ", falling back to shared memory: ", err or "unknown")
        end
    end
    
    -- 使用共享内存
    ttl = ttl or 0
    return cache:set(key, value, ttl)
end

-- 统一的 delete 接口
function _M.delete(key)
    local storage_type = get_storage_type(key)
    
    -- 同时删除 Redis 和共享内存中的键（确保一致性）
    if storage_type == "redis" and is_redis_fallback_enabled() and redis_cache.enable then
        redis_cache.delete(key)
    end
    
    cache:delete(key)
end

-- 统一的 incr 接口
function _M.incr(key, value)
    local storage_type = get_storage_type(key)
    
    if storage_type == "redis" and is_redis_fallback_enabled() and redis_cache.enable then
        -- Redis 不支持 incr，需要先 get 再 set
        local ok, current = redis_cache.get(key)
        if ok then
            local new_value = (tonumber(current) or 0) + (value or 1)
            redis_cache.set(key, tostring(new_value))
            return new_value
        end
    end
    
    -- 使用共享内存
    return cache:incr(key, value or 1)
end

-- 获取统计信息
function _M.get_stats()
    if not is_enabled() then
        return {
            enabled = false
        }
    end
    
    return {
        enabled = true,
        redis_fallback_enabled = is_redis_fallback_enabled(),
        redis_available = redis_cache.enable or false,
        shared_memory_keys_count = #SHARED_MEMORY_KEYS,
        redis_keys_count = #REDIS_KEYS
    }
end

return _M

