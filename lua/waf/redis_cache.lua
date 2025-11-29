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
    
    -- 如果连接不存在，重新初始化
    if not redis_client then
        if not init_redis() then
            return nil
        end
    end
    
    -- 注意：不在这里检查连接有效性，因为ping()本身可能会在已关闭的socket上发送数据
    -- 连接有效性检查将在实际Redis操作时通过pcall捕获错误来处理
    return redis_client
end

-- 构建Redis键
local function build_key(key)
    return REDIS_PREFIX .. key
end

-- 检查是否是socket关闭相关的错误（统一错误检测函数）
local function is_closed_socket_error(error_msg)
    if not error_msg then
        return false
    end
    local msg = tostring(error_msg):lower()
    return (
        msg == "closed" or
        string.find(msg, "closed") or
        string.find(msg, "closed socket") or
        string.find(msg, "attempt to send data") or
        string.find(msg, "broken pipe") or
        string.find(msg, "connection reset") or
        string.find(msg, "connection refused") or
        string.find(msg, "connection timed out")
    ) or false
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
    
    -- 存储到Redis（使用pcall包装，捕获可能的socket错误）
    local redis_key = build_key(key)
    local pcall_ok, redis_ok, redis_err = pcall(function()
        return red:setex(redis_key, ttl, serialized)
    end)
    
    -- 如果pcall失败，说明发生了Lua错误（如socket关闭）
    if not pcall_ok then
        ngx.log(ngx.WARN, "Redis set pcall failed: ", tostring(redis_ok))
        -- 立即清除连接，避免后续操作使用已关闭的连接
        if redis_client then
            local close_ok, close_err = pcall(function()
                redis_client:close()
            end)
            redis_client = nil
        end
        -- 尝试重新连接并重试一次
        red = get_redis()
        if red then
            local retry_pcall_ok, retry_redis_ok, retry_redis_err = pcall(function()
                return red:setex(redis_key, ttl, serialized)
            end)
            if retry_pcall_ok and retry_redis_ok then
                return true, nil
            else
                ngx.log(ngx.WARN, "Redis set error after reconnect: ", tostring(retry_redis_ok or retry_redis_err))
                redis_client = nil
                return false, tostring(retry_redis_ok or retry_redis_err)
            end
        else
            ngx.log(ngx.WARN, "Redis reconnect failed, set operation skipped")
            return false, "redis reconnect failed"
        end
    end
    
    -- 检查是否是socket关闭相关的错误（包括pcall失败和Redis返回错误两种情况）
    local is_closed = false
    local error_msg = ""
    
    if not pcall_ok then
        error_msg = tostring(redis_ok)
        is_closed = is_closed_socket_error(error_msg)
    elseif not redis_ok then
        error_msg = tostring(redis_err)
        is_closed = is_closed_socket_error(error_msg)
    end
    
    -- 如果是socket关闭错误，清除连接并重试
    if is_closed then
        ngx.log(ngx.WARN, "Redis connection closed, attempting to reconnect. Error: ", error_msg)
        -- 立即清除连接，避免后续操作使用已关闭的连接
        if redis_client then
            local close_ok, close_err = pcall(function()
                redis_client:close()
            end)
            redis_client = nil
        end
        -- 尝试重新连接并重试一次
        red = get_redis()
        if red then
            local retry_pcall_ok, retry_redis_ok, retry_redis_err = pcall(function()
                return red:setex(redis_key, ttl, serialized)
            end)
            if retry_pcall_ok and retry_redis_ok then
                return true, nil
            else
                ngx.log(ngx.WARN, "Redis set error after reconnect: ", tostring(retry_redis_ok or retry_redis_err))
                redis_client = nil
                return false, tostring(retry_redis_ok or retry_redis_err)
            end
        else
            ngx.log(ngx.WARN, "Redis reconnect failed, set operation skipped")
            return false, "redis reconnect failed"
        end
    end
    
    -- 如果pcall失败但不是socket关闭错误
    if not pcall_ok then
        ngx.log(ngx.ERR, "Redis set pcall failed: ", error_msg)
        redis_client = nil
        return false, error_msg
    end
    
    -- 如果Redis返回错误但不是socket关闭错误
    if not redis_ok then
        ngx.log(ngx.ERR, "Redis set error: ", error_msg)
        redis_client = nil
        return false, error_msg
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
    
    -- 使用pcall包装Redis操作，捕获可能的socket错误
    local pcall_ok, redis_res, redis_err = pcall(function()
        return red:get(redis_key)
    end)
    
    -- 检查是否是socket关闭相关的错误（包括pcall失败和Redis返回错误两种情况）
    local is_closed = false
    local error_msg = ""
    
    if not pcall_ok then
        error_msg = tostring(redis_res)
        is_closed = is_closed_socket_error(error_msg)
    elseif redis_err then
        error_msg = tostring(redis_err)
        is_closed = is_closed_socket_error(error_msg)
    end
    
    -- 如果是socket关闭错误，清除连接并重试
    if is_closed then
        ngx.log(ngx.WARN, "Redis connection closed, attempting to reconnect. Error: ", error_msg)
        -- 立即清除连接，避免后续操作使用已关闭的连接
        if redis_client then
            local close_ok, close_err = pcall(function()
                redis_client:close()
            end)
            redis_client = nil
        end
        -- 尝试重新连接并重试一次
        red = get_redis()
        if red then
            local retry_pcall_ok, retry_redis_res, retry_redis_err = pcall(function()
                return red:get(redis_key)
            end)
            if retry_pcall_ok and not retry_redis_err then
                if not retry_redis_res or retry_redis_res == ngx.null then
                    return nil
                end
                -- 反序列化
                local data, format = serializer.decode(retry_redis_res)
                return data
            else
                ngx.log(ngx.WARN, "Redis get retry failed: ", tostring(retry_redis_res or retry_redis_err))
                redis_client = nil
                return nil
            end
        else
            ngx.log(ngx.WARN, "Redis reconnect failed, get operation skipped")
            return nil
        end
    end
    
    -- 如果pcall失败但不是socket关闭错误
    if not pcall_ok then
        ngx.log(ngx.ERR, "Redis get pcall failed: ", error_msg)
        redis_client = nil
        return nil
    end
    
    -- 如果Redis返回错误但不是socket关闭错误
    if redis_err then
        ngx.log(ngx.ERR, "Redis get error: ", error_msg)
        redis_client = nil
        return nil
    end
    
    local res = redis_res
    
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
    
    -- 使用pcall包装整个函数，确保所有错误都被捕获
    local success, result = pcall(function()
        local red = get_redis()
        if not red then
            return false
        end
        
        local redis_key = build_key(key)
        
        -- 使用pcall包装Redis操作，捕获可能的socket错误
        local pcall_ok, redis_ok, redis_err = pcall(function()
            return red:del(redis_key)
        end)
        
        -- 检查是否是socket关闭相关的错误（包括pcall失败和Redis返回错误两种情况）
        local is_closed_error = false
        local error_msg = ""
        
        if not pcall_ok then
            -- pcall失败，说明发生了Lua错误（如socket关闭）
            error_msg = tostring(redis_ok)
            is_closed_error = (error_msg and (
                string.find(error_msg, "closed") or
                string.find(error_msg, "closed socket") or
                string.find(error_msg, "attempt to send data") or
                string.find(error_msg, "broken pipe") or
                string.find(error_msg, "Connection reset")
            )) or false
        elseif not redis_ok then
            -- Redis返回错误
            error_msg = tostring(redis_err)
            is_closed_error = (error_msg and (
                error_msg == "closed" or
                string.find(error_msg, "closed") or
                string.find(error_msg, "closed socket") or
                string.find(error_msg, "attempt to send data") or
                string.find(error_msg, "broken pipe") or
                string.find(error_msg, "Connection reset")
            )) or false
        end
        
        -- 如果是socket关闭错误，清除连接并重试
        if is_closed_error then
            ngx.log(ngx.WARN, "Redis connection closed, attempting to reconnect. Error: ", error_msg)
            -- 立即清除连接，避免后续操作使用已关闭的连接
            if redis_client then
                local close_ok, close_err = pcall(function()
                    redis_client:close()
                end)
                redis_client = nil
            end
            -- 尝试重新连接并重试一次
            red = get_redis()
            if red then
                local retry_pcall_ok, retry_redis_ok, retry_redis_err = pcall(function()
                    return red:del(redis_key)
                end)
                if retry_pcall_ok and retry_redis_ok then
                    return true
                else
                    ngx.log(ngx.WARN, "Redis delete retry failed: ", tostring(retry_redis_ok or retry_redis_err))
                    redis_client = nil
                    return false
                end
            else
                ngx.log(ngx.WARN, "Redis reconnect failed, delete operation skipped")
                return false
            end
        end
        
        -- 如果pcall失败但不是socket关闭错误
        if not pcall_ok then
            ngx.log(ngx.WARN, "Redis delete pcall failed: ", error_msg)
            redis_client = nil
            return false
        end
        
        -- 如果Redis返回错误但不是socket关闭错误
        if not redis_ok then
            ngx.log(ngx.WARN, "Redis delete error: ", error_msg)
            redis_client = nil
            return false
        end
        
        return true
    end)
    
    -- 如果外层pcall失败，说明发生了严重错误
    if not success then
        ngx.log(ngx.ERR, "Redis delete outer pcall failed: ", tostring(result))
        redis_client = nil
        return false
    end
    
    return result or false
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
    
    -- 使用pcall包装Redis操作，捕获可能的socket错误
    local pcall_ok, redis_keys, redis_err = pcall(function()
        return red:keys(redis_pattern)
    end)
    
    -- 检查是否是socket关闭相关的错误（包括pcall失败和Redis返回错误两种情况）
    local is_closed = false
    local error_msg = ""
    
    if not pcall_ok then
        error_msg = tostring(redis_keys)
        is_closed = is_closed_socket_error(error_msg)
    elseif redis_err then
        error_msg = tostring(redis_err)
        is_closed = is_closed_socket_error(error_msg)
    end
    
    -- 如果是socket关闭错误，清除连接并重试
    if is_closed then
        ngx.log(ngx.WARN, "Redis connection closed, attempting to reconnect. Error: ", error_msg)
        -- 立即清除连接，避免后续操作使用已关闭的连接
        if redis_client then
            local close_ok, close_err = pcall(function()
                redis_client:close()
            end)
            redis_client = nil
        end
        -- 尝试重新连接并重试一次
        red = get_redis()
        if red then
            local retry_pcall_ok, retry_redis_keys, retry_redis_err = pcall(function()
                return red:keys(redis_pattern)
            end)
            if retry_pcall_ok and not retry_redis_err then
                if retry_redis_keys and #retry_redis_keys > 0 then
                    local del_pcall_ok, del_redis_ok, del_redis_err = pcall(function()
                        return red:del(unpack(retry_redis_keys))
                    end)
                    if not del_pcall_ok or not del_redis_ok then
                        ngx.log(ngx.WARN, "Redis delete pattern failed: ", tostring(del_redis_ok or del_redis_err))
                    end
                end
                return true
            else
                ngx.log(ngx.WARN, "Redis keys retry failed: ", tostring(retry_redis_keys or retry_redis_err))
                redis_client = nil
                return false
            end
        else
            ngx.log(ngx.WARN, "Redis reconnect failed, delete_pattern operation skipped")
            return false
        end
    end
    
    -- 如果pcall失败但不是socket关闭错误
    if not pcall_ok then
        ngx.log(ngx.ERR, "Redis keys pcall failed: ", error_msg)
        redis_client = nil
        return false
    end
    
    -- 如果Redis返回错误但不是socket关闭错误
    if redis_err then
        ngx.log(ngx.ERR, "Redis keys error: ", error_msg)
        redis_client = nil
        return false
    end
    
    local keys = redis_keys
    
    if keys and #keys > 0 then
        local del_pcall_ok, del_redis_ok, del_redis_err = pcall(function()
            return red:del(unpack(keys))
        end)
        if not del_pcall_ok or not del_redis_ok then
            ngx.log(ngx.WARN, "Redis delete pattern failed: ", tostring(del_redis_ok or del_redis_err))
            -- 即使删除失败，也返回true，因为keys操作成功了
        end
    end
    
    return true
end

-- 发布消息到Redis频道（用于Pub/Sub）
function _M.publish(channel, message)
    if not REDIS_ENABLED then
        return false, "redis cache disabled"
    end
    
    local red = get_redis()
    if not red then
        return false, "redis not available"
    end
    
    -- 使用pcall包装Redis操作，捕获可能的socket错误
    local pcall_ok, redis_result, redis_err = pcall(function()
        return red:publish(channel, message)
    end)
    
    -- 检查是否是socket关闭相关的错误（包括pcall失败和Redis返回错误两种情况）
    local is_closed = false
    local error_msg = ""
    
    if not pcall_ok then
        error_msg = tostring(redis_result)
        is_closed = is_closed_socket_error(error_msg)
    elseif redis_err then
        error_msg = tostring(redis_err)
        is_closed = is_closed_socket_error(error_msg)
    end
    
    -- 如果是socket关闭错误，清除连接并重试
    if is_closed then
        ngx.log(ngx.WARN, "Redis connection closed during publish, attempting to reconnect. Error: ", error_msg)
        -- 立即清除连接，避免后续操作使用已关闭的连接
        if redis_client then
            local close_ok, close_err = pcall(function()
                redis_client:close()
            end)
            redis_client = nil
        end
        -- 尝试重新连接并重试一次
        red = get_redis()
        if red then
            local retry_pcall_ok, retry_redis_result, retry_redis_err = pcall(function()
                return red:publish(channel, message)
            end)
            if retry_pcall_ok and retry_redis_result then
                return retry_redis_result, nil
            else
                ngx.log(ngx.WARN, "Redis publish error after reconnect: ", tostring(retry_redis_result or retry_redis_err))
                redis_client = nil
                return false, tostring(retry_redis_result or retry_redis_err)
            end
        else
            ngx.log(ngx.WARN, "Redis reconnect failed, publish operation skipped")
            return false, "redis reconnect failed"
        end
    end
    
    -- 如果pcall失败但不是socket关闭错误
    if not pcall_ok then
        ngx.log(ngx.ERR, "Redis publish pcall failed: ", error_msg)
        redis_client = nil
        return false, error_msg
    end
    
    -- 如果Redis返回错误但不是socket关闭错误
    if redis_err then
        ngx.log(ngx.ERR, "Redis publish error: ", error_msg)
        redis_client = nil
        return false, error_msg
    end
    
    return redis_result, nil
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

