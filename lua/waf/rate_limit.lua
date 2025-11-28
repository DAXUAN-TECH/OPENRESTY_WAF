-- 速率限制模块
-- 路径：项目目录下的 lua/waf/rate_limit.lua（保持在项目目录，不复制到系统目录）
-- 功能：实现API层面的速率限制，防止暴力破解和滥用

local config_manager = require "waf.config_manager"
local cache = ngx.shared.waf_cache

local _M = {}

-- 速率限制配置（从数据库读取）
local RATE_LIMIT_LOGIN_ENABLED = config_manager.get_config("rate_limit_login_enable", true, "boolean")
local RATE_LIMIT_LOGIN_RATE = tonumber(config_manager.get_config("rate_limit_login_rate", 5, "number")) or 5  -- 每分钟请求数
local RATE_LIMIT_API_ENABLED = config_manager.get_config("rate_limit_api_enable", true, "boolean")
local RATE_LIMIT_API_RATE = tonumber(config_manager.get_config("rate_limit_api_rate", 100, "number")) or 100  -- 每分钟请求数

-- 速率限制键前缀
local RATE_LIMIT_PREFIX = "rate_limit:"
local RATE_LIMIT_WINDOW = 60  -- 时间窗口（秒）

-- 检查速率限制
function _M.check_rate_limit(key, max_requests, window)
    window = window or RATE_LIMIT_WINDOW
    max_requests = max_requests or RATE_LIMIT_API_RATE
    
    local cache_key = RATE_LIMIT_PREFIX .. key
    local current_time = ngx.time()
    local window_start = current_time - (current_time % window)
    local window_key = cache_key .. ":" .. window_start
    
    -- 获取当前窗口的请求数
    local count = cache:get(window_key) or 0
    
    if count >= max_requests then
        -- 计算重置时间
        local reset_time = window_start + window
        local remaining = reset_time - current_time
        return false, remaining, max_requests
    end
    
    -- 增加计数
    cache:incr(window_key, 1)
    cache:expire(window_key, window + 1)  -- 多1秒确保不会提前过期
    
    return true, window - (current_time % window), max_requests - count - 1
end

-- 登录接口速率限制
function _M.check_login_rate_limit(username, ip_address)
    if not RATE_LIMIT_LOGIN_ENABLED then
        return true
    end
    
    -- 使用用户名和IP地址作为限制键
    local key = "login:" .. (username or "unknown") .. ":" .. (ip_address or ngx.var.remote_addr)
    return _M.check_rate_limit(key, RATE_LIMIT_LOGIN_RATE, RATE_LIMIT_WINDOW)
end

-- API接口速率限制
function _M.check_api_rate_limit(user_id, ip_address, endpoint)
    if not RATE_LIMIT_API_ENABLED then
        return true
    end
    
    -- 使用用户ID、IP地址和端点作为限制键
    local key = "api:" .. (user_id or "anonymous") .. ":" .. (ip_address or ngx.var.remote_addr) .. ":" .. (endpoint or "default")
    return _M.check_rate_limit(key, RATE_LIMIT_API_RATE, RATE_LIMIT_WINDOW)
end

-- 通用速率限制（自定义）
function _M.check_custom_rate_limit(key, max_requests, window)
    return _M.check_rate_limit(key, max_requests, window)
end

-- 获取速率限制信息（用于返回给客户端）
function _M.get_rate_limit_info(key, max_requests, window)
    window = window or RATE_LIMIT_WINDOW
    max_requests = max_requests or RATE_LIMIT_API_RATE
    
    local cache_key = RATE_LIMIT_PREFIX .. key
    local current_time = ngx.time()
    local window_start = current_time - (current_time % window)
    local window_key = cache_key .. ":" .. window_start
    
    local count = cache:get(window_key) or 0
    local reset_time = window_start + window
    local remaining = math.max(0, reset_time - current_time)
    local remaining_requests = math.max(0, max_requests - count)
    
    return {
        limit = max_requests,
        remaining = remaining_requests,
        reset = reset_time
    }
end

return _M

