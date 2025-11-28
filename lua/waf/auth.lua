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
            rshift = function(x, n) 
                return math.floor(x / (2^n)) 
            end,
            band = function(x, y) 
                -- 位与操作：使用数学运算实现（只处理32位）
                -- 对于 byte & 0xF 这种简单情况，直接使用取模即可
                -- 0xF = 15，byte % 16 等价于 byte & 0xF（对于小于256的值）
                if x < 256 and y < 256 then
                    -- 简单情况：直接使用取模
                    return x % (y + 1)
                else
                    -- 复杂情况：使用逐位计算
                    local result = 0
                    local power = 1
                    local x_val = x
                    local y_val = y
                    for i = 1, 32 do
                        local x_bit = x_val % 2
                        local y_bit = y_val % 2
                        if x_bit == 1 and y_bit == 1 then
                            result = result + power
                        end
                        x_val = math.floor(x_val / 2)
                        y_val = math.floor(y_val / 2)
                        power = power * 2
                        if x_val == 0 and y_val == 0 then
                            break
                        end
                    end
                    return result
                end
            end,
            bxor = function(x, y)
                -- 异或操作：使用数学运算实现
                local result = 0
                local power = 1
                local x_val = x
                local y_val = y
                for i = 1, 32 do
                    local x_bit = x_val % 2
                    local y_bit = y_val % 2
                    if (x_bit == 1 and y_bit == 0) or (x_bit == 0 and y_bit == 1) then
                        result = result + power
                    end
                    x_val = math.floor(x_val / 2)
                    y_val = math.floor(y_val / 2)
                    power = power * 2
                    if x_val == 0 and y_val == 0 then
                        break
                    end
                end
                return result
            end
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
        local byte = string.byte(raw_string, i)
        -- 使用 bit 库进行异或操作（如果可用），否则使用数学运算
        if bit and bit.bxor then
            hash = bit.bxor(hash, byte)
            hash = hash * 16777619
            -- 使用 bit 库进行位与操作（如果可用），否则使用取模
            if bit and bit.band then
                hash = bit.band(hash, 0xFFFFFFFF)
            else
                -- 0xFFFFFFFF = 4294967295，对于32位整数，使用取模
                hash = hash % 4294967296  -- 2^32
            end
        else
            -- 如果 bit 库不可用，使用简化的哈希算法（避免复杂的异或实现）
            hash = hash + byte
            hash = hash * 16777619
            hash = hash % 4294967296  -- 2^32，限制为32位
        end
    end
    
    local hex_chars = "0123456789abcdef"
    local hex_string = ""
    local temp_hash = hash
    for i = 1, 8 do
        -- 使用 bit 库进行位与操作（如果可用），否则使用取模
        local idx
        if bit and bit.band then
            idx = bit.band(temp_hash, 0xF) + 1
        else
            idx = (temp_hash % 16) + 1
        end
        hex_string = hex_chars:sub(idx, idx) .. hex_string
        -- 使用 bit 库进行右移操作（如果可用），否则使用数学运算
        if bit and bit.rshift then
            temp_hash = bit.rshift(temp_hash, 4)
        else
            temp_hash = math.floor(temp_hash / 16)
        end
    end
    
    return hex_string .. string.format("%x%x", timestamp, random_num1)
end

-- 验证用户名和密码（优先从数据库读取，回退到配置文件）
function _M.verify_credentials(username, password)
    if not username or not password then
        ngx.log(ngx.WARN, "verify_credentials: username or password is empty")
        return false, nil
    end
    
    ngx.log(ngx.INFO, "verify_credentials: attempting to verify user: ", username)
    
    -- 优先从数据库查询用户
    local mysql_pool = require "waf.mysql_pool"
    local ok, res, query_err = pcall(function()
        local sql = [[
            SELECT id, username, password_hash, role, totp_secret, status
            FROM waf_users
            WHERE username = ?
            AND status = 1
            LIMIT 1
        ]]
        -- mysql_pool.query 返回 (res, err)，pcall 会传递所有返回值
        return mysql_pool.query(sql, username)
    end)
    
    -- 记录数据库查询结果
    if not ok then
        -- pcall 失败，res 是错误信息
        ngx.log(ngx.ERR, "verify_credentials: database query failed (pcall error): ", tostring(res))
        return false, nil
    end
    
    -- pcall 成功，res 是查询结果，query_err 是错误信息（如果有）
    if query_err then
        ngx.log(ngx.ERR, "verify_credentials: database query error: ", tostring(query_err))
        return false, nil
    end
    
    -- 如果查询返回 nil（可能是连接失败）
    if not res then
        ngx.log(ngx.ERR, "verify_credentials: database query returned nil (connection failed?)")
        return false, nil
    end
    
    -- 记录查询结果详情
    if res then
        ngx.log(ngx.WARN, "verify_credentials: query result count: ", tostring(#res))
    else
        ngx.log(ngx.WARN, "verify_credentials: query result is nil")
    end
    
    if res and #res > 0 then
        local user = res[1]
        ngx.log(ngx.WARN, "verify_credentials: user found in database: ", username, ", role: ", user.role or "unknown", ", user_id: ", tostring(user.id))
        
        -- 使用密码工具模块验证密码（支持BCrypt和简单哈希）
        local verify_ok, verify_err = password_utils.verify_password(password, user.password_hash)
        if verify_ok then
            ngx.log(ngx.WARN, "verify_credentials: password verification successful for user: ", username)
            return true, {
                id = user.id,
                username = user.username,
                role = user.role,
                totp_secret = user.totp_secret
            }
        else
            -- 验证失败，记录日志（但不泄露具体原因）
            ngx.log(ngx.WARN, "verify_credentials: password verification failed for user: ", username, ", error: ", tostring(verify_err))
            return false, nil
        end
    else
        ngx.log(ngx.WARN, "verify_credentials: user not found in database: ", username, ", res is nil: ", tostring(res == nil), ", res count: ", res and tostring(#res) or "N/A")
    end
    
    -- 如果数据库中没有用户，且尝试登录的是默认管理员账号，自动创建初始管理员用户
    if ok and (not res or #res == 0) then
        ngx.log(ngx.WARN, "verify_credentials: user not found, checking if database is empty...")
        -- 检查数据库中是否有任何用户
        local check_ok, check_res, check_err = pcall(function()
            local check_sql = "SELECT COUNT(*) as user_count FROM waf_users LIMIT 1"
            local result, err = mysql_pool.query(check_sql)
            if err then
                return nil, err
            end
            return result
        end)
        
        if not check_ok then
            ngx.log(ngx.ERR, "verify_credentials: failed to check user count (pcall error): ", tostring(check_res))
            return false, nil
        end
        
        if check_err then
            ngx.log(ngx.ERR, "verify_credentials: failed to check user count (query error): ", tostring(check_err))
            return false, nil
        end
        
        -- 记录检查结果
        if check_res then
            ngx.log(ngx.WARN, "verify_credentials: user count check result: ", tostring(check_res), ", count: ", check_res and #check_res > 0 and tostring(check_res[1].user_count) or "N/A")
        else
            ngx.log(ngx.WARN, "verify_credentials: user count check result is nil")
        end
        
        -- 如果数据库中没有用户，且尝试登录的是 admin/admin123，自动创建默认管理员用户
        -- 注意：MySQL COUNT(*) 返回的是数字，但可能被转换为字符串，需要转换为数字比较
        local user_count = check_res and #check_res > 0 and (tonumber(check_res[1].user_count) or 0) or 0
        ngx.log(ngx.WARN, "verify_credentials: user_count (converted): ", tostring(user_count), ", type: ", type(user_count))
        
        if check_ok and check_res and #check_res > 0 and user_count == 0 then
            ngx.log(ngx.WARN, "verify_credentials: database is empty (user_count: 0), username: ", username, ", password match: ", tostring(password == "admin123"))
            if username == "admin" and password == "admin123" then
                ngx.log(ngx.WARN, "verify_credentials: database is empty, creating default admin user (username: admin, password: admin123)")
                
                -- 生成密码哈希
                local password_hash, hash_err = password_utils.hash_password(password, 10)
                if not password_hash then
                    ngx.log(ngx.ERR, "verify_credentials: failed to hash password for default admin user: ", tostring(hash_err))
                    return false, nil
                end
                
                ngx.log(ngx.INFO, "verify_credentials: password hash generated successfully")
                
                -- 创建默认管理员用户
                local create_ok, create_result, create_err = pcall(function()
                    local create_sql = [[
                        INSERT INTO waf_users (username, password_hash, role, status, password_must_change)
                        VALUES (?, ?, 'admin', 1, 1)
                    ]]
                    local insert_id, err = mysql_pool.insert(create_sql, username, password_hash)
                    if err then
                        return nil, err
                    end
                    return insert_id
                end)
                
                if not create_ok then
                    ngx.log(ngx.ERR, "verify_credentials: failed to create default admin user (pcall error): ", tostring(create_result))
                    return false, nil
                end
                
                if create_err then
                    ngx.log(ngx.ERR, "verify_credentials: failed to create default admin user (insert error): ", tostring(create_err))
                    return false, nil
                end
                
                if create_ok and create_result then
                    ngx.log(ngx.WARN, "verify_credentials: default admin user created successfully, insert_id: ", tostring(create_result))
                    -- 重新查询用户信息
                    local user_ok, user_res, user_err = pcall(function()
                        local user_sql = [[
                            SELECT id, username, password_hash, role, totp_secret, status
                            FROM waf_users
                            WHERE username = ?
                            AND status = 1
                            LIMIT 1
                        ]]
                        return mysql_pool.query(user_sql, username)
                    end)
                    
                    if not user_ok then
                        ngx.log(ngx.ERR, "verify_credentials: failed to query created user (pcall error): ", tostring(user_res))
                        return false, nil
                    end
                    
                    if user_err then
                        ngx.log(ngx.ERR, "verify_credentials: failed to query created user (query error): ", tostring(user_err))
                        return false, nil
                    end
                    
                    if not user_res then
                        ngx.log(ngx.ERR, "verify_credentials: failed to query created user (returned nil)")
                        return false, nil
                    end
                    
                    if user_ok and user_res and #user_res > 0 then
                        local user = user_res[1]
                        ngx.log(ngx.INFO, "verify_credentials: created user verified successfully, user_id: ", tostring(user.id))
                        return true, {
                            id = user.id,
                            username = user.username,
                            role = user.role,
                            totp_secret = user.totp_secret
                        }
                    else
                        ngx.log(ngx.ERR, "verify_credentials: created user not found after creation")
                    end
                else
                    ngx.log(ngx.ERR, "verify_credentials: failed to create default admin user: create_ok=", tostring(create_ok), ", create_result=", tostring(create_result))
                end
            else
                ngx.log(ngx.WARN, "verify_credentials: database is empty but credentials are not admin/admin123, username: ", username, ", password length: ", tostring(password and #password or 0))
            end
        else
            if check_res and #check_res > 0 then
                ngx.log(ngx.WARN, "verify_credentials: database is not empty (user_count: ", tostring(check_res[1].user_count), "), but user '", username, "' not found")
            else
                ngx.log(ngx.WARN, "verify_credentials: failed to get user count from database, check_res: ", tostring(check_res))
            end
        end
    else
        ngx.log(ngx.WARN, "verify_credentials: skipping empty database check, ok: ", tostring(ok), ", res: ", tostring(res), ", res count: ", res and tostring(#res) or "N/A")
    end
    
    -- 不再使用硬编码的默认用户，所有用户必须从数据库读取
    -- 如果数据库中没有用户，需要通过安装脚本或API创建初始管理员用户
    ngx.log(ngx.WARN, "verify_credentials: authentication failed for user: ", username)
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
        local cjson = require "cjson"
        
        -- 将 cjson.null 转换为 nil（MySQL NULL值可能被转换为cjson.null）
        local totp_secret = user.totp_secret
        if totp_secret == cjson.null or totp_secret == nil then
            totp_secret = nil
        elseif type(totp_secret) == "string" and totp_secret == "" then
            -- 空字符串也视为未启用
            totp_secret = nil
        end
        
        return {
            id = user.id,
            username = user.username,
            role = user.role,
            totp_secret = totp_secret,
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
    if not user then
        return false
    end
    
    -- 检查 totp_secret 是否存在且非空
    -- get_user() 已经将 cjson.null 和空字符串转换为 nil，所以这里只需要检查是否为 nil
    if user.totp_secret and type(user.totp_secret) == "string" and user.totp_secret ~= "" then
        return true
    end
    
    return false
end

-- 修改用户密码
-- 参数：username - 用户名
--      old_password - 旧密码（用于验证）
--      new_password - 新密码
-- 返回：ok - 是否成功，err - 错误信息
function _M.change_password(username, old_password, new_password)
    if not username or not old_password or not new_password then
        return false, "用户名、旧密码和新密码不能为空"
    end
    
    -- 去除密码前后空格（防止用户误输入空格）
    if type(old_password) == "string" then
        old_password = old_password:match("^%s*(.-)%s*$") or old_password
    end
    if type(new_password) == "string" then
        new_password = new_password:match("^%s*(.-)%s*$") or new_password
    end
    
    -- 再次检查去除空格后的密码是否为空
    if old_password == "" or new_password == "" then
        return false, "密码不能为空"
    end
    
    -- 验证旧密码
    ngx.log(ngx.INFO, "change_password: verifying old password for user: ", username, ", password length: ", tostring(old_password and #old_password or 0))
    local verify_ok, user = _M.verify_credentials(username, old_password)
    if not verify_ok then
        ngx.log(ngx.WARN, "change_password: old password verification failed for user: ", username)
        return false, "旧密码错误，请检查输入的密码是否正确"
    end
    
    -- 检查新密码强度
    local strength = password_utils.check_password_strength(new_password)
    if not strength.valid then
        return false, strength.message or "新密码不符合要求"
    end
    
    -- 生成新密码哈希
    local password_hash, hash_err = password_utils.hash_password(new_password, 10)
    if not password_hash then
        ngx.log(ngx.ERR, "change_password: failed to hash new password: ", tostring(hash_err))
        return false, "生成密码哈希失败"
    end
    
    -- 更新数据库中的密码
    local mysql_pool = require "waf.mysql_pool"
    local res, err = mysql_pool.query([[
        UPDATE waf_users
        SET password_hash = ?,
            password_changed_at = NOW(),
            password_must_change = 0
        WHERE username = ?
    ]], password_hash, username)
    
    if err then
        ngx.log(ngx.ERR, "change_password: database error: ", tostring(err))
        return false, "更新密码失败"
    end
    
    if not res then
        ngx.log(ngx.ERR, "change_password: database query returned nil")
        return false, "更新密码失败"
    end
    
    ngx.log(ngx.INFO, "change_password: password changed successfully for user: ", username)
    return true, nil
end

-- 创建会话
function _M.create_session(username, user_info)
    local session_id = generate_session_id()
    local session_key = SESSION_PREFIX .. session_id
    
    local session_data = {
        username = username,
        user_id = user_info.id,  -- 添加 user_id 到 session 数据
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

