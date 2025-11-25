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
    local has_totp = auth.user_has_totp(username)
    
    if has_totp then
        -- 如果启用了 TOTP，需要验证 TOTP 代码
        if not totp_code or totp_code == "" then
            api_utils.json_response({
                error = "TOTP Required",
                message = "请输入双因素认证代码",
                requires_totp = true
            }, 200)  -- 返回 200，但要求提供 TOTP
            return
        end
        
        -- 验证 TOTP 代码
        local user_info = auth.get_user(username)
        local totp_ok, err = totp.verify_totp(user_info.totp_secret, totp_code)
        if not totp_ok then
            -- 记录登录失败审计日志
            audit_log.log_login(username, false, "双因素认证代码错误")
            api_utils.json_response({
                error = "Unauthorized",
                message = "双因素认证代码错误"
            }, 401)
            return
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
    
    local session_id = auth.get_session_from_cookie()
    if session_id then
        auth.delete_session(session_id)
    end
    
    -- 清除Cookie
    auth.clear_session_cookie()
    
    -- 记录登出审计日志
    if username then
        audit_log.log_logout(username)
    end
    
    api_utils.json_response({
        success = true,
        message = "登出成功"
    }, 200)
end

-- 检查登录状态接口（返回CSRF Token）
function _M.check()
    local authenticated, session = auth.is_authenticated()
    if authenticated then
        -- 生成新的CSRF Token
        local csrf_token = csrf.generate_token(session.username)
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
    
    -- 生成 QR 码数据
    local qr_data = totp.generate_qr_data(secret, username, "WAF Management")
    
    -- 根据配置决定是否生成外部 QR 码 URL
    local qr_generator = config.totp and config.totp.qr_generator or "local"
    local qr_url = nil
    
    if qr_generator == "external" then
        qr_url, _ = totp.generate_qr_url(secret, username, "WAF Management")
    end
    
    -- 保存密钥（临时，需要用户验证后才能正式启用）
    -- 这里可以存储到临时缓存，用户验证后正式保存
    
    local response = {
        secret = secret,
        qr_data = qr_data,
        qr_generator = qr_generator,
        allow_manual_entry = config.totp and config.totp.allow_manual_entry ~= false,
        message = "请使用 Google Authenticator 扫描二维码或手动输入密钥，然后验证代码以启用双因素认证"
    }
    
    if qr_url then
        response.qr_url = qr_url
    end
    
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
    
    -- 验证 TOTP 代码
    local totp_ok, err = totp.verify_totp(secret, code)
    if not totp_ok then
        api_utils.json_response({
            error = "Unauthorized",
            message = "验证码错误，请重试"
        }, 401)
        return
    end
    
    -- 保存 TOTP 密钥
    local ok = auth.set_user_totp_secret(session.username, secret)
    if not ok then
        api_utils.json_response({
            error = "Internal Server Error",
            message = "保存密钥失败"
        }, 500)
        return
    end
    
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
    auth.set_user_totp_secret(session.username, nil)
    
    api_utils.json_response({
        success = true,
        message = "双因素认证已禁用"
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

return _M

