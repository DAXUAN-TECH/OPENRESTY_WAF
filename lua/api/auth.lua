-- 认证API模块
-- 路径：项目目录下的 lua/api/auth.lua（保持在项目目录，不复制到系统目录）
-- 功能：处理登录、登出、会话检查等认证相关的API请求

local auth = require "waf.auth"
local totp = require "waf.totp"
local password_utils = require "waf.password_utils"
local api_utils = require "api.utils"
local cjson = require "cjson"
local audit_log = require "waf.audit_log"
local csrf = require "waf.csrf"

local _M = {}

-- 登录接口（支持两步验证）
function _M.login()
    local args = api_utils.get_args()
    
    -- 检查请求方法
    if ngx.req.get_method() ~= "POST" then
        api_utils.json_response({error = "Method not allowed"}, 405)
        return
    end
    
    -- 获取用户名和密码
    local username = args.username
    local password = args.password
    local totp_code = args.totp_code  -- TOTP 验证码（可选）
    
    ngx.log(ngx.INFO, "auth.login: login attempt for user: ", username or "nil")
    
    if not username or not password then
        ngx.log(ngx.WARN, "auth.login: username or password is empty")
        api_utils.json_response({
            error = "Bad Request",
            message = "用户名和密码不能为空"
        }, 400)
        return
    end
    
    -- 验证用户名和密码
    local ok, user, verify_err = auth.verify_credentials(username, password)
    if not ok then
        ngx.log(ngx.WARN, "auth.login: authentication failed for user: ", username, ", error: ", tostring(verify_err))
        -- 记录登录失败审计日志
        audit_log.log_login(username, false, "用户名或密码错误")
        api_utils.json_response({
            error = "Unauthorized",
            message = "用户名或密码错误"
        }, 401)
        return
    end
    
    ngx.log(ngx.INFO, "auth.login: authentication successful for user: ", username, ", role: ", user.role or "unknown")
    
    -- 检查用户是否启用了 TOTP
    -- 注意：只有用户明确启用后（通过 enable_totp），登录时才要求验证码
    -- 如果只是生成了 secret 但没有验证启用，允许登录
    local has_totp = auth.user_has_totp(username)
    
    if has_totp then
        local user_info = auth.get_user(username)
        if user_info and user_info.totp_secret and user_info.totp_secret ~= "" then
            -- 验证 TOTP secret 是否有效（能够生成有效的 TOTP 代码）
            -- 如果 secret 无效，说明可能是未完成的设置或损坏的数据，清除它并允许登录
            local secret_valid = false
            local test_code, test_err = pcall(function()
                local code = totp.generate_totp(user_info.totp_secret)
                return code ~= nil and code ~= ""
            end)
            
            if test_code and test_err then
                secret_valid = true
            end
            
            if not secret_valid then
                -- secret 无效，清除它并允许登录（可能是未完成的设置或损坏的数据）
                ngx.log(ngx.WARN, "auth.login: user has invalid TOTP secret, clearing it and allowing login")
                auth.set_user_totp_secret(username, nil)
            else
                -- secret 有效，要求验证码
                if not totp_code or totp_code == "" then
                    api_utils.json_response({
                        error = "TOTP Required",
                        message = "请输入双因素认证代码",
                        requires_totp = true
                    }, 200)  -- 返回 200，但要求提供 TOTP
                    return
                end
                
                -- 验证 TOTP 代码（使用较大的时间窗口以支持时间偏差）
                -- 允许前后10个时间窗口（±5分钟），支持跨时区或时间同步不准确的情况
                local totp_ok, err = totp.verify_totp(user_info.totp_secret, totp_code, 30, 10)
                if not totp_ok then
                    -- 记录登录失败审计日志
                    audit_log.log_login(username, false, "双因素认证代码错误")
                    api_utils.json_response({
                        error = "Unauthorized",
                        message = "双因素认证代码错误，请确保时间同步正确，验证码在5分钟内有效"
                    }, 401)
                    return
                end
            end
        end
    end
    
    -- 创建会话
    local session_id, err = auth.create_session(username, user)
    if not session_id then
        audit_log.log_login(username, false, "创建会话失败: " .. (err or "unknown error"))
        api_utils.json_response({
            error = "Internal Server Error",
            message = err or "创建会话失败"
        }, 500)
        return
    end
    
    -- 生成CSRF Token
    local csrf_token = csrf.generate_token(user.id or username)
    
    -- 设置Cookie
    auth.set_session_cookie(session_id)
    
    -- 记录登录成功审计日志
    audit_log.log_login(username, true, nil)
    
    -- 返回成功响应（包含CSRF Token）
    api_utils.json_response({
        success = true,
        message = "登录成功",
        username = username,
        role = user.role,
        csrf_token = csrf_token
    }, 200)
end

-- 登出接口
function _M.logout()
    local authenticated, session = auth.is_authenticated()
    local username = nil
    if authenticated and session then
        username = session.username
    end
    
    -- 先记录登出审计日志（在删除 session 之前）
    -- 即使 username 为 nil，也尝试记录（log_logout 会处理）
    audit_log.log_logout(username)
    
    local session_id = auth.get_session_from_cookie()
    if session_id then
        auth.delete_session(session_id)
    end
    
    -- 清除Cookie
    auth.clear_session_cookie()
    
    -- 检查请求方法：GET请求直接重定向，POST请求返回JSON
    local method = ngx.req.get_method()
    if method == "GET" then
        -- GET请求：直接重定向到登录页面
        ngx.redirect("/login")
        return
    else
        -- POST请求：返回JSON响应（供AJAX调用）
        api_utils.json_response({
            success = true,
            message = "登出成功"
        }, 200)
    end
end

-- 检查登录状态接口（返回CSRF Token）
function _M.check()
    local authenticated, session = auth.is_authenticated()
    if authenticated then
        -- 生成新的CSRF Token（优先使用 user_id，如果没有则使用 username）
        local csrf_token = csrf.generate_token(session.user_id or session.username)
        api_utils.json_response({
            authenticated = true,
            username = session.username,
            role = session.role,
            csrf_token = csrf_token
        }, 200)
    else
        api_utils.json_response({
            authenticated = false
        }, 200)
    end
end

-- 获取当前用户信息
function _M.me()
    local session = auth.require_auth()
    if session then
        local user_info = auth.get_user(session.username)
        api_utils.json_response({
            username = session.username,
            role = session.role,
            has_totp = auth.user_has_totp(session.username),
            created_at = session.created_at,
            last_access = session.last_access
        }, 200)
    end
end

-- 获取当前用户的 TOTP 状态
function _M.get_totp_status()
    local session = auth.require_auth()
    if not session then
        return
    end
    
    local has_totp = auth.user_has_totp(session.username)
    
    api_utils.json_response({
        enabled = has_totp,
        username = session.username
    }, 200)
end

-- 生成 TOTP 密钥和 QR 码
function _M.setup_totp()
    local session = auth.require_auth()
    if not session then
        return
    end
    
    local config = require "config"
    local username = session.username
    
    -- 生成新的 TOTP 密钥
    local secret = totp.generate_secret(16)
    
    -- 将 secret 临时保存到共享内存（5分钟有效期）
    -- 这样即使用户多次打开设置弹窗，也能使用最近生成的 secret 进行验证
    local cache = ngx.shared.waf_cache
    local totp_setup_key = "totp_setup:" .. username
    local totp_setup_ttl = 300  -- 5分钟
    local ok, err = cache:set(totp_setup_key, secret, totp_setup_ttl)
    if not ok then
        ngx.log(ngx.WARN, "auth.setup_totp: failed to cache secret for user: ", username, ", error: ", tostring(err))
    else
        ngx.log(ngx.INFO, "auth.setup_totp: cached secret for user: ", username, ", will expire in ", totp_setup_ttl, " seconds")
    end
    
    -- 生成 QR 码数据
    local qr_data = totp.generate_qr_data(secret, username, "WAF Management")
    
    -- 根据配置决定是否生成外部 QR 码 URL
    local qr_generator = config.totp and config.totp.qr_generator or "local"
    local qr_url = nil
    
    if qr_generator == "external" then
        qr_url, _ = totp.generate_qr_url(secret, username, "WAF Management")
    end
    
    -- 确保返回的secret与qr_data中的secret一致（都是清理后的）
    local response = {
        secret = qr_data.secret,  -- 使用qr_data中的secret（已清理），确保前后端一致
        qr_data = qr_data,
        qr_generator = qr_generator,
        allow_manual_entry = config.totp and config.totp.allow_manual_entry ~= false,
        message = "请使用 Google Authenticator 扫描二维码或手动输入密钥，然后验证代码以启用双因素认证"
    }
    
    -- 记录调试信息
    ngx.log(ngx.DEBUG, "auth.setup_totp: original secret: ", string.sub(secret, 1, 20), "...", ", response secret: ", string.sub(response.secret, 1, 20), "...", ", qr_data.secret: ", string.sub(qr_data.secret, 1, 20), "...")
    
    if qr_url then
        response.qr_url = qr_url
    end
    
    -- 记录审计日志（设置TOTP）
    audit_log.log_totp_action("setup", session.username, true, nil)
    
    -- 记录调试信息：记录返回的secret和otpauth_url
    ngx.log(ngx.DEBUG, "auth.setup_totp: returning secret: ", string.sub(response.secret, 1, 20), "...", ", otpauth_url: ", string.sub(qr_data.otpauth_url, 1, 100), "...")
    
    api_utils.json_response(response, 200)
end

-- 验证并启用 TOTP
function _M.enable_totp()
    local session = auth.require_auth()
    if not session then
        return
    end
    
    local args = api_utils.get_args()
    local secret = args.secret
    local code = args.code
    
    if not secret or not code then
        api_utils.json_response({
            error = "Bad Request",
            message = "密钥和验证码不能为空"
        }, 400)
        return
    end
    
    -- 清理验证码：只保留数字，并确保是字符串类型
    if type(code) == "number" then
        code = tostring(code)
    end
    code = string.gsub(tostring(code), "%D", "")
    
    -- 验证验证码格式
    if not code or #code ~= 6 then
        ngx.log(ngx.WARN, "auth.enable_totp: invalid code format, code length: ", code and #code or 0, ", code type: ", type(code))
        api_utils.json_response({
            error = "Bad Request",
            message = "验证码必须是6位数字"
        }, 400)
        return
    end
    
    -- 清理和验证 secret 格式（Base32）
    if type(secret) == "number" then
        secret = tostring(secret)
    end
    secret = tostring(secret)
    -- 移除空格和换行符（Base32 编码可能包含空格用于格式化）
    secret = string.gsub(secret, "%s", "")
    -- 转换为大写（Base32 标准使用大写字母）
    secret = string.upper(secret)
    
    -- 验证 secret 格式（Base32）
    if not secret or #secret < 16 then
        ngx.log(ngx.WARN, "auth.enable_totp: invalid secret format, secret length: ", secret and #secret or 0, ", secret type: ", type(secret))
        api_utils.json_response({
            error = "Bad Request",
            message = "密钥格式无效"
        }, 400)
        return
    end
    
    -- 验证 Base32 字符集（只允许 A-Z 和 2-7）
    local base32_pattern = "^[A-Z2-7]+$"
    if not string.match(secret, base32_pattern) then
        ngx.log(ngx.WARN, "auth.enable_totp: secret contains invalid Base32 characters, secret: ", string.sub(secret, 1, 20), "...")
        api_utils.json_response({
            error = "Bad Request",
            message = "密钥包含无效字符，必须是Base32格式（A-Z, 2-7）"
        }, 400)
        return
    end
    
    -- 记录详细的secret信息用于调试
    ngx.log(ngx.INFO, "auth.enable_totp: verifying TOTP for user: ", session.username)
    ngx.log(ngx.INFO, "auth.enable_totp: provided secret length: ", #secret, ", secret (first 20 chars): ", string.sub(secret, 1, 20), ", secret (last 10 chars): ", string.sub(secret, -10), ", code: ", code)
    
    -- 检查缓存的 secret
    local cache = ngx.shared.waf_cache
    local totp_setup_key = "totp_setup:" .. session.username
    local cached_secret = cache:get(totp_setup_key)
    
    -- 清理secret（移除空格，转换为大写），确保格式一致
    local cleaned_secret = string.upper(string.gsub(secret, "%s", ""))
    
    if cached_secret then
        -- 清理缓存的secret（移除空格，转换为大写）
        local cleaned_cached_secret = string.upper(string.gsub(cached_secret, "%s", ""))
        local secrets_match = cleaned_cached_secret == cleaned_secret
        
        ngx.log(ngx.DEBUG, "auth.enable_totp: found cached secret for user: ", session.username)
        ngx.log(ngx.DEBUG, "auth.enable_totp: cached_secret length: ", #cached_secret, ", cached_secret (first 20 chars): ", string.sub(cached_secret, 1, 20), ", cached_secret (last 10 chars): ", string.sub(cached_secret, -10))
        ngx.log(ngx.DEBUG, "auth.enable_totp: provided_secret length: ", #secret, ", provided_secret (first 20 chars): ", string.sub(secret, 1, 20), ", provided_secret (last 10 chars): ", string.sub(secret, -10))
        ngx.log(ngx.DEBUG, "auth.enable_totp: cleaned_cached_secret (first 20 chars): ", string.sub(cleaned_cached_secret, 1, 20), ", cleaned_provided_secret (first 20 chars): ", string.sub(cleaned_secret, 1, 20))
        ngx.log(ngx.DEBUG, "auth.enable_totp: secrets match: ", secrets_match, ", exact match: ", cached_secret == secret)
        
        -- 记录服务器当前时间信息用于调试
        local server_time = ngx.time()
        local server_time_str = os.date("!%Y-%m-%d %H:%M:%S", server_time)
        local time_step = 30
        local current_counter = math.floor(server_time / time_step)
        ngx.log(ngx.DEBUG, "auth.enable_totp: server_time: ", server_time, " (", server_time_str, " UTC), time_step: ", time_step, ", current_counter: ", current_counter)
        
        -- 使用清理后的缓存的secret生成当前时间的验证码用于对比
        local test_code_cached, test_err_cached = totp.generate_totp(cleaned_cached_secret, 30, 6)
        if test_code_cached then
            ngx.log(ngx.DEBUG, "auth.enable_totp: generated code from cleaned_cached_secret: ", test_code_cached, ", user input: ", code, ", match: ", test_code_cached == code)
        else
            ngx.log(ngx.WARN, "auth.enable_totp: failed to generate code from cleaned_cached_secret: ", tostring(test_err_cached))
        end
        
        -- 使用清理后的提供的secret生成当前时间的验证码用于对比
        local test_code_provided, test_err_provided = totp.generate_totp(cleaned_secret, 30, 6)
        if test_code_provided then
            ngx.log(ngx.DEBUG, "auth.enable_totp: generated code from cleaned_provided_secret: ", test_code_provided, ", user input: ", code, ", match: ", test_code_provided == code)
        else
            ngx.log(ngx.WARN, "auth.enable_totp: failed to generate code from cleaned_provided_secret: ", tostring(test_err_provided))
        end
        
        -- 提示用户检查时间同步（只有在不匹配时才记录WARN）
        if test_code_cached and test_code_cached ~= code then
            ngx.log(ngx.WARN, "auth.enable_totp: WARNING: Generated code (", test_code_cached, ") does not match user input (", code, "). This may indicate a time synchronization issue between server and mobile device.")
        end
    else
        ngx.log(ngx.DEBUG, "auth.enable_totp: no cached secret found for user: ", session.username)
        
        -- 记录服务器当前时间信息用于调试
        local server_time = ngx.time()
        local server_time_str = os.date("!%Y-%m-%d %H:%M:%S", server_time)
        local time_step = 30
        local current_counter = math.floor(server_time / time_step)
        ngx.log(ngx.DEBUG, "auth.enable_totp: server_time: ", server_time, " (", server_time_str, " UTC), time_step: ", time_step, ", current_counter: ", current_counter)
        
        -- 使用清理后的提供的secret生成当前时间的验证码用于对比
        local test_code_provided, test_err_provided = totp.generate_totp(cleaned_secret, 30, 6)
        if test_code_provided then
            ngx.log(ngx.DEBUG, "auth.enable_totp: generated code from cleaned_provided_secret: ", test_code_provided, ", user input: ", code, ", match: ", test_code_provided == code)
        else
            ngx.log(ngx.WARN, "auth.enable_totp: failed to generate code from cleaned_provided_secret: ", tostring(test_err_provided))
        end
        
        -- 提示用户检查时间同步（只有在不匹配时才记录WARN）
        if test_code_provided and test_code_provided ~= code then
            ngx.log(ngx.WARN, "auth.enable_totp: WARNING: Generated code (", test_code_provided, ") does not match user input (", code, "). This may indicate a time synchronization issue between server and mobile device.")
        end
    end
    
    -- 优先使用缓存的 secret 验证（如果存在），因为缓存的 secret 是服务器生成的，更可靠
    local totp_ok, err = false, "Not verified yet"
    local secret_source = "provided"
    
    -- 增加时间窗口以支持更大的时间偏差（±5分钟，共10个时间窗口）
    -- 这对于跨时区或时间同步不准确的情况很有帮助
    local time_window = 10  -- 允许前后10个时间窗口（±5分钟）
    
    if cached_secret then
        -- 清理缓存的secret（已经在上面清理过了，这里直接使用）
        local cleaned_cached_secret = string.upper(string.gsub(cached_secret, "%s", ""))
        
        -- 先尝试使用缓存的 secret（服务器生成的，更可靠）
        ngx.log(ngx.INFO, "auth.enable_totp: trying cached secret first for user: ", session.username, ", time_window: ", time_window)
        totp_ok, err = totp.verify_totp(cleaned_cached_secret, code, 30, time_window)
        if totp_ok then
            secret = cleaned_cached_secret
            secret_source = "cached"
            ngx.log(ngx.INFO, "auth.enable_totp: cached secret verification successful for user: ", session.username)
        else
            ngx.log(ngx.INFO, "auth.enable_totp: cached secret verification failed, trying provided secret for user: ", session.username)
            -- 如果缓存的 secret 验证失败，尝试提供的 secret
            totp_ok, err = totp.verify_totp(cleaned_secret, code, 30, time_window)
            if totp_ok then
                secret = cleaned_secret
                secret_source = "provided"
                ngx.log(ngx.INFO, "auth.enable_totp: provided secret verification successful for user: ", session.username)
            else
                ngx.log(ngx.WARN, "auth.enable_totp: both cached and provided secret verification failed for user: ", session.username)
            end
        end
    else
        -- 没有缓存的 secret，直接使用提供的 secret
        ngx.log(ngx.INFO, "auth.enable_totp: no cached secret, using provided secret for user: ", session.username, ", time_window: ", time_window)
        totp_ok, err = totp.verify_totp(cleaned_secret, code, 30, time_window)
        if totp_ok then
            secret = cleaned_secret
        end
        secret_source = "provided"
    end
    
    if not totp_ok then
        ngx.log(ngx.WARN, "auth.enable_totp: TOTP verification failed for user: ", session.username, ", secret_source: ", secret_source, ", error: ", tostring(err))
        
        -- 获取服务器时间信息用于错误消息
        local server_time = ngx.time()
        local server_time_str = os.date("!%Y-%m-%d %H:%M:%S", server_time)
        local time_step = 30
        local current_counter = math.floor(server_time / time_step)
        
        api_utils.json_response({
            error = "Unauthorized",
            message = "验证码错误，请重试。\n\n可能的原因：\n1. 时间不同步：请确保手机和服务器时间同步（服务器时间：" .. server_time_str .. " UTC）\n2. 验证码过期：验证码每30秒更新一次，请在90秒内输入\n3. 密钥不匹配：请确保扫描的二维码或输入的密钥正确\n\n如果问题持续，请检查：\n- 手机时间是否准确（建议开启自动同步）\n- 服务器时间是否准确（建议使用NTP同步）\n- 时区设置是否正确"
        }, 401)
        return
    end
    
    -- 验证成功，清除缓存的 secret
    if secret_source == "cached" then
        local cache = ngx.shared.waf_cache
        local totp_setup_key = "totp_setup:" .. session.username
        cache:delete(totp_setup_key)
        ngx.log(ngx.INFO, "auth.enable_totp: cleared cached secret for user: ", session.username)
    end
    
    ngx.log(ngx.INFO, "auth.enable_totp: TOTP verification successful for user: ", session.username)
    
    -- 保存 TOTP 密钥
    local ok = auth.set_user_totp_secret(session.username, secret)
    if not ok then
        -- 记录审计日志（失败）
        audit_log.log_totp_action("enable", session.username, false, "保存密钥失败")
        api_utils.json_response({
            error = "Internal Server Error",
            message = "保存密钥失败"
        }, 500)
        return
    end
    
    -- 记录审计日志（成功）
    audit_log.log_totp_action("enable", session.username, true, nil)
    
    api_utils.json_response({
        success = true,
        message = "双因素认证已启用"
    }, 200)
end

-- 禁用 TOTP
function _M.disable_totp()
    local session = auth.require_auth()
    if not session then
        return
    end
    
    local args = api_utils.get_args()
    local code = args.code
    
    -- 获取用户信息
    local user_info = auth.get_user(session.username)
    if not user_info or not user_info.totp_secret then
        api_utils.json_response({
            error = "Bad Request",
            message = "未启用双因素认证"
        }, 400)
        return
    end
    
    -- 验证 TOTP 代码（需要验证后才能禁用）
    if not code then
        api_utils.json_response({
            error = "Bad Request",
            message = "请输入验证码以禁用双因素认证"
        }, 400)
        return
    end
    
    local totp_ok, err = totp.verify_totp(user_info.totp_secret, code)
    if not totp_ok then
        api_utils.json_response({
            error = "Unauthorized",
            message = "验证码错误"
        }, 401)
        return
    end
    
    -- 清除 TOTP 密钥
    local ok = auth.set_user_totp_secret(session.username, nil)
    if not ok then
        -- 记录审计日志（失败）
        audit_log.log_totp_action("disable", session.username, false, "清除密钥失败")
        api_utils.json_response({
            error = "Internal Server Error",
            message = "清除密钥失败"
        }, 500)
        return
    end
    
    -- 记录审计日志（成功）
    audit_log.log_totp_action("disable", session.username, true, nil)
    
    api_utils.json_response({
        success = true,
        message = "双因素认证已禁用"
    }, 200)
end

-- 重置 TOTP（验证旧验证码 -> 生成新密钥 -> 验证新验证码）
function _M.reset_totp()
    local session = auth.require_auth()
    if not session then
        return
    end
    
    local args = api_utils.get_args()
    local old_code = args.old_code  -- 旧验证码
    local new_code = args.new_code   -- 新验证码（可选，用于立即启用）
    local secret = args.secret        -- 新密钥（可选，如果前端已经生成）
    
    -- 获取用户信息
    local user_info = auth.get_user(session.username)
    if not user_info or not user_info.totp_secret then
        api_utils.json_response({
            error = "Bad Request",
            message = "未启用双因素认证，无法重置"
        }, 400)
        return
    end
    
    -- 第一步：验证旧验证码
    if not old_code then
        api_utils.json_response({
            error = "Bad Request",
            message = "请输入当前验证码以确认重置"
        }, 400)
        return
    end
    
    local totp_ok, err = totp.verify_totp(user_info.totp_secret, old_code)
    if not totp_ok then
        -- 记录审计日志（失败）
        audit_log.log_totp_action("reset", session.username, false, "旧验证码错误")
        api_utils.json_response({
            error = "Unauthorized",
            message = "当前验证码错误"
        }, 401)
        return
    end
    
    -- 第二步：生成新密钥和QR码
    local config = require "config"
    local new_secret = secret or totp.generate_secret(16)
    local qr_data = totp.generate_qr_data(new_secret, session.username, "WAF Management")
    
    -- 根据配置决定是否生成外部 QR 码 URL
    local qr_generator = config.totp and config.totp.qr_generator or "local"
    local qr_url = nil
    
    if qr_generator == "external" then
        qr_url, _ = totp.generate_qr_url(new_secret, session.username, "WAF Management")
    end
    
    local response = {
        success = true,
        secret = new_secret,
        qr_data = qr_data,
        qr_generator = qr_generator,
        allow_manual_entry = config.totp and config.totp.allow_manual_entry ~= false,
        message = "旧验证码验证成功，请使用 Google Authenticator 扫描新二维码或手动输入新密钥，然后输入新的6位验证码完成重置"
    }
    
    if qr_url then
        response.qr_url = qr_url
    end
    
    -- 如果提供了新验证码，直接验证并启用
    if new_code and new_code ~= "" then
        local new_totp_ok, new_err = totp.verify_totp(new_secret, new_code)
        if not new_totp_ok then
            -- 记录审计日志（失败）
            audit_log.log_totp_action("reset", session.username, false, "新验证码错误")
            api_utils.json_response({
                error = "Unauthorized",
                message = "新验证码错误，请重试"
            }, 401)
            return
        end
        
        -- 保存新密钥
        local ok = auth.set_user_totp_secret(session.username, new_secret)
        if not ok then
            -- 记录审计日志（失败）
            audit_log.log_totp_action("reset", session.username, false, "保存新密钥失败")
            api_utils.json_response({
                error = "Internal Server Error",
                message = "保存新密钥失败"
            }, 500)
            return
        end
        
        -- 记录审计日志（成功）
        audit_log.log_totp_action("reset", session.username, true, nil)
        
        response.success = true
        response.message = "双因素认证已重置并启用"
        response.enabled = true
    else
        -- 只返回新密钥和QR码，等待前端验证新验证码
        -- 注意：此时旧密钥仍然有效，需要用户验证新验证码后才能替换
        -- 这里我们暂时不清除旧密钥，等待用户验证新验证码后再清除
        response.requires_new_code = true
    end
    
    api_utils.json_response(response, 200)
end

-- 完成重置 TOTP（验证新验证码并保存新密钥）
function _M.complete_reset_totp()
    local session = auth.require_auth()
    if not session then
        return
    end
    
    local args = api_utils.get_args()
    local secret = args.secret  -- 新密钥
    local code = args.code      -- 新验证码
    
    if not secret or not code then
        api_utils.json_response({
            error = "Bad Request",
            message = "密钥和验证码不能为空"
        }, 400)
        return
    end
    
    -- 验证新验证码
    local totp_ok, err = totp.verify_totp(secret, code)
    if not totp_ok then
        -- 记录审计日志（失败）
        audit_log.log_totp_action("reset", session.username, false, "新验证码错误")
        api_utils.json_response({
            error = "Unauthorized",
            message = "新验证码错误，请重试"
        }, 401)
        return
    end
    
    -- 保存新密钥（替换旧密钥）
    local ok = auth.set_user_totp_secret(session.username, secret)
    if not ok then
        -- 记录审计日志（失败）
        audit_log.log_totp_action("reset", session.username, false, "保存新密钥失败")
        api_utils.json_response({
            error = "Internal Server Error",
            message = "保存新密钥失败"
        }, 500)
        return
    end
    
    -- 记录审计日志（成功）
    audit_log.log_totp_action("reset", session.username, true, nil)
    
    api_utils.json_response({
        success = true,
        message = "双因素认证已重置并启用"
    }, 200)
end

-- 生成密码哈希（管理员工具）
function _M.hash_password()
    local session = auth.require_auth()
    if not session then
        return
    end
    
    -- 只有管理员可以使用此功能
    if session.role ~= "admin" then
        api_utils.json_response({
            error = "Forbidden",
            message = "只有管理员可以使用此功能"
        }, 403)
        return
    end
    
    local args = api_utils.get_args()
    local password = args.password
    local cost = tonumber(args.cost) or 10
    
    if not password then
        api_utils.json_response({
            error = "Bad Request",
            message = "密码不能为空"
        }, 400)
        return
    end
    
    -- 检查密码强度
    local strength = password_utils.check_password_strength(password)
    if not strength.valid then
        api_utils.json_response({
            error = "Bad Request",
            message = "密码长度至少8位",
            strength = strength
        }, 400)
        return
    end
    
    -- 生成密码哈希
    local hash, err = password_utils.hash_password(password, cost)
    if not hash then
        api_utils.json_response({
            error = "Internal Server Error",
            message = err or "生成密码哈希失败"
        }, 500)
        return
    end
    
    api_utils.json_response({
        success = true,
        hash = hash,
        strength = strength,
        message = "密码哈希生成成功"
    }, 200)
end

-- 检查密码强度
function _M.check_password_strength()
    local args = api_utils.get_args()
    local password = args.password
    
    if not password then
        api_utils.json_response({
            error = "Bad Request",
            message = "密码不能为空"
        }, 400)
        return
    end
    
    local strength = password_utils.check_password_strength(password)
    api_utils.json_response({
        valid = strength.valid,
        strength = strength.strength,
        score = strength.score,
        checks = strength.checks
    }, 200)
end

-- 生成随机密码
function _M.generate_password()
    local session = auth.require_auth()
    if not session then
        return
    end
    
    -- 只有管理员可以使用此功能
    if session.role ~= "admin" then
        api_utils.json_response({
            error = "Forbidden",
            message = "只有管理员可以使用此功能"
        }, 403)
        return
    end
    
    local args = api_utils.get_args()
    local length = tonumber(args.length) or 16
    
    if length < 8 or length > 128 then
        api_utils.json_response({
            error = "Bad Request",
            message = "密码长度必须在8-128位之间"
        }, 400)
        return
    end
    
    local password = password_utils.generate_random_password(length)
    local strength = password_utils.check_password_strength(password)
    
    api_utils.json_response({
        success = true,
        password = password,
        strength = strength,
        message = "随机密码生成成功"
    }, 200)
end

-- 修改用户密码
function _M.change_password()
    local session = auth.require_auth()
    if not session then
        return
    end
    
    local args = api_utils.get_args()
    local old_password = args.old_password
    local new_password = args.new_password
    
    -- 去除前后空格
    if old_password and type(old_password) == "string" then
        old_password = old_password:match("^%s*(.-)%s*$") or old_password
    end
    if new_password and type(new_password) == "string" then
        new_password = new_password:match("^%s*(.-)%s*$") or new_password
    end
    
    if not old_password or old_password == "" or not new_password or new_password == "" then
        api_utils.json_response({
            error = "Bad Request",
            message = "旧密码和新密码不能为空"
        }, 400)
        return
    end
    
    -- 调用auth模块修改密码
    local ok, err = auth.change_password(session.username, old_password, new_password)
    if not ok then
        -- 记录审计日志（失败）
        audit_log.log_password_change(session.username, false, err or "修改密码失败")
        api_utils.json_response({
            error = "Bad Request",
            message = err or "修改密码失败"
        }, 400)
        return
    end
    
    -- 记录审计日志（成功）
    audit_log.log_password_change(session.username, true, nil)
    
    api_utils.json_response({
        success = true,
        message = "密码修改成功"
    }, 200)
end

return _M

