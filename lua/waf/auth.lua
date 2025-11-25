-- 用户认证模块
-- 路径：项目目录下的 lua/waf/auth.lua（保持在项目目录，不复制到系统目录）
-- 功能：处理用户登录、登出、会话验证

local cjson = require "cjson"
local password_utils = require "waf.password_utils"

-- 加载 bit 库（用于位运算）
local bit = bit
if not bit then
    local ok, bit_module = pcall(require, "bit")
    if ok and bit_module then
        bit = bit_module
    else
        -- 如果 bit 库不可用，使用数学运算替代
        bit = {
            rshift = function(x, n) return math.floor(x / (2^n)) end,
            band = function(x, y) return x % (2^32) & y % (2^32) end
        }
    end
end

local _M = {}
local cache = ngx.shared.waf_cache

-- 配置（从数据库读取，支持动态配置）
local config_manager = require "waf.config_manager"
local SESSION_PREFIX = "session:"
local SESSION_TTL = tonumber(config_manager.get_config("session_ttl", 86400, "number")) or 86400  -- 会话过期时间（秒，默认24小时）
local SESSION_COOKIE_NAME = config_manager.get_config("session_cookie_name", "waf_session", "string") or "waf_session"
local SESSION_ENABLE_SECURE = config_manager.get_config("session_enable_secure", true, "boolean")
local SESSION_ENABLE_HTTPONLY = config_manager.get_config("session_enable_httponly", true, "boolean")

-- 注意：不再使用硬编码的默认用户，所有用户必须从数据库读取
-- 首次安装时，需要通过安装脚本或API创建初始管理员用户

-- 生成加密安全的随机会话ID（使用OpenSSL随机数生成器）
local function generate_session_id()
    -- 使用OpenSSL生成32字节随机数（如果可用）
    local ok, random_bytes = pcall(function()
        local resty_random = require "resty.random"
        if resty_random then
            return resty_random.bytes(32)
        end
        return nil
    end)
    
    if ok and random_bytes then
        -- 转换为16进制字符串
        local hex_chars = "0123456789abcdef"
        local hex_string = ""
        for i = 1, #random_bytes do
            local byte = string.byte(random_bytes, i)
            -- 使用 bit 库进行位运算（如果可用），否则使用数学运算
            local high_nibble, low_nibble
            if bit and bit.rshift and bit.band then
                high_nibble = bit.rshift(byte, 4)
                low_nibble = bit.band(byte, 0xF)
            else
                -- 回退到数学运算
                high_nibble = math.floor(byte / 16)
                low_nibble = byte % 16
            end
            hex_string = hex_string .. hex_chars:sub(high_nibble + 1, high_nibble + 1)
            hex_string = hex_string .. hex_chars:sub(low_nibble + 1, low_nibble + 1)
        end
        return hex_string
    end
    
    -- 回退方案：使用时间戳 + 随机数 + IP地址 + 工作进程ID + 更强的哈希
    local timestamp = ngx.time()
    local random_num1 = math.random(1000000, 9999999)
    local random_num2 = math.random(1000000, 9999999)
    local remote_addr = ngx.var.remote_addr or "0.0.0.0"
    local worker_pid = ngx.worker.pid()
    
    -- 组合生成唯一字符串
    local raw_string = timestamp .. ":" .. random_num1 .. ":" .. random_num2 .. ":" .. remote_addr .. ":" .. worker_pid
    
    -- 使用MD5哈希（如果可用）
    local ok, md5_hash = pcall(function()
        return ngx.md5(raw_string)
    end)
    
    if ok and md5_hash then
        return md5_hash .. string.format("%x%x", timestamp, random_num1)
    end
    
    -- 最终回退：使用FNV-1a哈希
    local hash = 2166136261
    for i = 1, #raw_string do
        hash = hash ~ string.byte(raw_string, i)
        hash = hash * 16777619
        hash = hash & 0xFFFFFFFF
    end
    
    local hex_chars = "0123456789abcdef"
    local hex_string = ""
    local temp_hash = hash
    for i = 1, 8 do
        local idx = (temp_hash & 0xF) + 1
        hex_string = hex_chars:sub(idx, idx) .. hex_string
        temp_hash = temp_hash >> 4
    end
    
    return hex_string .. string.format("%x%x", timestamp, random_num1)
end

-- 验证用户名和密码（优先从数据库读取，回退到配置文件）
function _M.verify_credentials(username, password)
    if not username or not password then
        return false, nil
    end
    
    -- 优先从数据库查询用户
    local mysql_pool = require "waf.mysql_pool"
    local ok, res = pcall(function()
        local sql = [[
            SELECT id, username, password_hash, role, totp_secret, status
            FROM waf_users
            WHERE username = ?
            AND status = 1
            LIMIT 1
        ]]
        return mysql_pool.query(sql, username)
    end)
    
    if ok and res and #res > 0 then
        local user = res[1]
        
        -- 使用密码工具模块验证密码（支持BCrypt和简单哈希）
        local verify_ok, err = password_utils.verify_password(password, user.password_hash)
        if verify_ok then
            return true, {
                id = user.id,
                username = user.username,
                role = user.role,
                totp_secret = user.totp_secret
            }
        else
            -- 验证失败，记录日志（但不泄露具体原因）
            ngx.log(ngx.INFO, "Password verification failed for user: ", username)
            return false, nil
        end
    end
    
    -- 不再使用硬编码的默认用户，所有用户必须从数据库读取
    -- 如果数据库中没有用户，需要通过安装脚本或API创建初始管理员用户
    return false, nil
end

-- 获取用户信息（包括 TOTP 配置，优先从数据库读取）
function _M.get_user(username)
    if not username then
        return nil
    end
    
    -- 优先从数据库查询
    local mysql_pool = require "waf.mysql_pool"
    local ok, res = pcall(function()
        local sql = [[
            SELECT id, username, role, totp_secret, status
            FROM waf_users
            WHERE username = ?
            LIMIT 1
        ]]
        return mysql_pool.query(sql, username)
    end)
    
    if ok and res and #res > 0 then
        local user = res[1]
        return {
            id = user.id,
            username = user.username,
            role = user.role,
            totp_secret = user.totp_secret,
            status = user.status
        }
    end
    
    -- 不再使用硬编码的默认用户
    return nil
end

-- 设置用户的 TOTP 密钥（优先保存到数据库）
function _M.set_user_totp_secret(username, secret)
    if not username then
        return false
    end
    
    -- 优先保存到数据库
    local mysql_pool = require "waf.mysql_pool"
    local ok, err = pcall(function()
        local sql = [[
            UPDATE waf_users
            SET totp_secret = ?
            WHERE username = ?
        ]]
        return mysql_pool.query(sql, secret or nil, username)
    end)
    
    if ok and not err then
        return true
    end
    
    -- 不再使用硬编码的默认用户
    return false
end

-- 检查用户是否启用了 TOTP
function _M.user_has_totp(username)
    local user = _M.get_user(username)
    if user and user.totp_secret and user.totp_secret ~= "" then
        return true
    end
    return false
end

-- 创建会话
function _M.create_session(username, user_info)
    local session_id = generate_session_id()
    local session_key = SESSION_PREFIX .. session_id
    
    local session_data = {
        username = username,
        role = user_info.role or "user",
        created_at = ngx.time(),
        last_access = ngx.time()
    }
    
    -- 存储会话数据到共享内存
    local ok, err = cache:set(session_key, cjson.encode(session_data), SESSION_TTL)
    if not ok then
        ngx.log(ngx.ERR, "Failed to create session: ", err)
        return nil, "Failed to create session"
    end
    
    return session_id, nil
end

-- 获取会话
function _M.get_session(session_id)
    if not session_id then
        return nil
    end
    
    local session_key = SESSION_PREFIX .. session_id
    local session_data = cache:get(session_key)
    
    if not session_data then
        return nil
    end
    
    local ok, data = pcall(cjson.decode, session_data)
    if not ok then
        ngx.log(ngx.ERR, "Failed to decode session data: ", data)
        return nil
    end
    
    -- 更新最后访问时间
    data.last_access = ngx.time()
    cache:set(session_key, cjson.encode(data), SESSION_TTL)
    
    return data
end

-- 删除会话
function _M.delete_session(session_id)
    if not session_id then
        return
    end
    
    local session_key = SESSION_PREFIX .. session_id
    cache:delete(session_key)
end

-- 从Cookie获取会话ID
function _M.get_session_from_cookie()
    local cookie = ngx.var.cookie_waf_session
    if not cookie then
        return nil
    end
    
    return cookie
end

-- 设置会话Cookie（支持动态配置）
function _M.set_session_cookie(session_id)
    local cookie_value = SESSION_COOKIE_NAME .. "=" .. session_id
    cookie_value = cookie_value .. "; Path=/; Max-Age=" .. SESSION_TTL
    
    -- 根据配置添加HttpOnly标志
    if SESSION_ENABLE_HTTPONLY then
        cookie_value = cookie_value .. "; HttpOnly"
    end
    
    -- 根据配置和HTTPS状态添加Secure标志
    if SESSION_ENABLE_SECURE and ngx.var.scheme == "https" then
        cookie_value = cookie_value .. "; Secure"
    end
    
    ngx.header["Set-Cookie"] = cookie_value
end

-- 清除会话Cookie
function _M.clear_session_cookie()
    local cookie_value = SESSION_COOKIE_NAME .. "=; Path=/; Max-Age=0"
    if SESSION_ENABLE_HTTPONLY then
        cookie_value = cookie_value .. "; HttpOnly"
    end
    if SESSION_ENABLE_SECURE and ngx.var.scheme == "https" then
        cookie_value = cookie_value .. "; Secure"
    end
    ngx.header["Set-Cookie"] = cookie_value
end

-- 检查用户是否已登录
function _M.is_authenticated()
    local session_id = _M.get_session_from_cookie()
    if not session_id then
        return false, nil
    end
    
    local session = _M.get_session(session_id)
    if not session then
        return false, nil
    end
    
    return true, session
end

-- 要求认证（如果未登录则返回401）
function _M.require_auth()
    local authenticated, session = _M.is_authenticated()
    if not authenticated then
        ngx.status = 401
        ngx.header.content_type = "application/json; charset=utf-8"
        ngx.say(cjson.encode({
            error = "Unauthorized",
            message = "请先登录"
        }))
        ngx.exit(401)
    end
    
    return session
end

return _M

