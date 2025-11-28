-- Redis二级缓存模块
-- 路径：项目目录下的 lua/waf/redis_cache.lua（保持在项目目录，不复制到系统目录）
-- 功能：使用Redis作为二级缓存，提升分布式环境下的缓存性能

local config = require "config"
local serializer = require "waf.serializer"

local _M = {}
local redis_client = nil

-- 配置
local REDIS_ENABLED = config.redis_cache and config.redis_cache.enable or false
local REDIS_PREFIX = config.redis_cache and config.redis_cache.key_prefix or "waf:"
local REDIS_TTL = config.redis_cache and config.redis_cache.ttl or 300  -- 默认5分钟

-- 初始化Redis连接
local function init_redis()
    if not REDIS_ENABLED then
        return false
    end
    
    if redis_client then
        return true
    end
    
    local ok, redis = pcall(require, "resty.redis")
    if not ok then
        ngx.log(ngx.WARN, "Redis module not available, install: opm get openresty/lua-resty-redis")
        return false
    end
    
    local red = redis:new()
    red:set_timeout(config.redis.timeout or 1000)
    
    local ok, err = red:connect(config.redis.host, config.redis.port)
    if not ok then
        ngx.log(ngx.ERR, "failed to connect to Redis: ", err)
        return false
    end
    
    -- 如果有密码，进行认证
    if config.redis.password then
        local ok, err = red:auth(config.redis.password)
        if not ok then
            ngx.log(ngx.ERR, "failed to authenticate Redis: ", err)
            red:close()
            return false
        end
    end
    
    -- 选择数据库
    if config.redis.db then
        red:select(config.redis.db)
    end
    
    redis_client = red
    return true
end

-- 检查Redis连接是否有效
local function is_connection_valid(red)
    if not red then
        return false
    end
    
    -- 尝试执行一个简单的命令来检查连接
    local ok, err = pcall(function()
        red:ping()
    end)
    
    if not ok then
        return false
    end
    
    return true
end

-- 获取Redis连接
local function get_redis()
    if not REDIS_ENABLED then
        return nil
    end
    
    -- 如果连接存在，检查是否有效
    if redis_client then
        -- 检查连接是否有效（简单检查，避免每次都ping）
        -- 如果连接无效，会在实际操作时发现并重新连接
    else
        if not init_redis() then
            return nil
        end
    end
    
    return redis_client
end

-- 构建Redis键
local function build_key(key)
    return REDIS_PREFIX .. key
end

-- 设置缓存值
function _M.set(key, value, ttl)
    if not REDIS_ENABLED then
        return false, "redis cache disabled"
    end
    
    local red = get_redis()
    if not red then
        return false, "redis not available"
    end
    
    ttl = ttl or REDIS_TTL
    
    -- 序列化值
    local serialized, format = serializer.encode(value)
    if not serialized then
        return false, "serialization failed"
    end
    
    -- 存储到Redis
    local redis_key = build_key(key)
    local ok, err = red:setex(redis_key, ttl, serialized)
    
    -- 如果连接关闭，尝试重新连接并重试一次
    if not ok then
        if err == "closed" or string.find(err, "closed") then
            ngx.log(ngx.WARN, "Redis connection closed, attempting to reconnect")
            redis_client = nil
            red = get_redis()
            if red then
                -- 重试一次
                ok, err = red:setex(redis_key, ttl, serialized)
                if not ok then
                    ngx.log(ngx.ERR, "Redis set error after reconnect: ", err)
                    redis_client = nil
                    return false, err
                end
                return true, nil
            else
                ngx.log(ngx.WARN, "Redis reconnect failed, set operation skipped")
                return false, "redis reconnect failed"
            end
        else
            ngx.log(ngx.ERR, "Redis set error: ", err)
            redis_client = nil
            return false, err
        end
    end
    
    return true, nil
end

-- 获取缓存值
function _M.get(key)
    if not REDIS_ENABLED then
        return nil
    end
    
    local red = get_redis()
    if not red then
        return nil
    end
    
    local redis_key = build_key(key)
    local res, err = red:get(redis_key)
    
    -- 如果连接关闭，尝试重新连接并重试一次
    if err then
        if err == "closed" or string.find(err, "closed") then
            ngx.log(ngx.WARN, "Redis connection closed, attempting to reconnect")
            redis_client = nil
            red = get_redis()
            if red then
                -- 重试一次
                res, err = red:get(redis_key)
                if err then
                    ngx.log(ngx.ERR, "Redis get error after reconnect: ", err)
                    redis_client = nil
                    return nil
                end
            else
                ngx.log(ngx.WARN, "Redis reconnect failed, get operation skipped")
                return nil
            end
        else
            ngx.log(ngx.ERR, "Redis get error: ", err)
            redis_client = nil
            return nil
        end
    end
    
    if not res or res == ngx.null then
        return nil
    end
    
    -- 反序列化
    local data, format = serializer.decode(res)
    return data
end

-- 删除缓存值
function _M.delete(key)
    if not REDIS_ENABLED then
        return false
    end
    
    local red = get_redis()
    if not red then
        return false
    end
    
    local redis_key = build_key(key)
    local ok, err = red:del(redis_key)
    
    -- 如果连接关闭，尝试重新连接并重试一次
    if err then
        if err == "closed" or string.find(err, "closed") then
            ngx.log(ngx.WARN, "Redis connection closed, attempting to reconnect")
            redis_client = nil
            red = get_redis()
            if red then
                -- 重试一次
                ok, err = red:del(redis_key)
                if err then
                    ngx.log(ngx.ERR, "Redis delete error after reconnect: ", err)
                    redis_client = nil
                    return false
                end
                return true
            else
                ngx.log(ngx.WARN, "Redis reconnect failed, delete operation skipped")
                return false
            end
        else
            ngx.log(ngx.ERR, "Redis delete error: ", err)
            redis_client = nil
            return false
        end
    end
    
    return true
end

-- 批量删除（使用模式匹配）
function _M.delete_pattern(pattern)
    if not REDIS_ENABLED then
        return false
    end
    
    local red = get_redis()
    if not red then
        return false
    end
    
    local redis_pattern = build_key(pattern)
    local keys, err = red:keys(redis_pattern)
    
    if err then
        ngx.log(ngx.ERR, "Redis keys error: ", err)
        redis_client = nil
        return false
    end
    
    if keys and #keys > 0 then
        red:del(unpack(keys))
    end
    
    return true
end

-- 检查Redis是否可用
function _M.is_available()
    if not REDIS_ENABLED then
        return false
    end
    
    local red = get_redis()
    return red ~= nil
end

-- 关闭Redis连接
function _M.close()
    if redis_client then
        redis_client:set_keepalive(10000, config.redis.pool_size or 100)
        redis_client = nil
    end
end

return _M

