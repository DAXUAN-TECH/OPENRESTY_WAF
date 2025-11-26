-- 操作审计日志模块
-- 路径：项目目录下的 lua/waf/audit_log.lua（保持在项目目录，不复制到系统目录）
-- 功能：记录所有管理操作，用于安全审计和问题排查

local cjson = require "cjson"
local mysql_pool = require "waf.mysql_pool"
local auth = require "waf.auth"

local _M = {}

-- 记录审计日志
function _M.log(action_type, resource_type, resource_id, action_description, status, error_message)
    -- 获取当前用户信息
    local authenticated, session = auth.is_authenticated()
    local user_id = nil
    local username = nil
    
    if authenticated and session then
        username = session.username
        user_id = session.user_id or session.id
        
        -- 验证user_id是否存在（防止外键约束失败）
        if user_id then
            local check_sql = "SELECT id FROM waf_users WHERE id = ? LIMIT 1"
            local check_res, check_err = mysql_pool.query(check_sql, user_id)
            if not check_res or #check_res == 0 then
                -- user_id不存在，设置为nil（外键约束允许NULL）
                ngx.log(ngx.WARN, "audit_log: user_id ", user_id, " not found in waf_users, setting to NULL")
                user_id = nil
            end
        end
    end
    
    -- 获取请求信息
    local method = ngx.req.get_method()
    local path = ngx.var.request_uri:match("^([^?]+)")
    local ip_address = ngx.var.remote_addr
    local user_agent = ngx.var.http_user_agent
    
    -- 获取请求参数（仅记录非敏感参数）
    local request_params = nil
    if method == "POST" or method == "PUT" then
        ngx.req.read_body()
        local args = ngx.req.get_post_args()
        if args then
            -- 过滤敏感字段
            local filtered_args = {}
            for k, v in pairs(args) do
                if k ~= "password" and k ~= "password_hash" and k ~= "totp_secret" then
                    filtered_args[k] = v
                end
            end
            if next(filtered_args) then
                request_params = cjson.encode(filtered_args)
            end
        end
    end
    
    -- 写入数据库（不阻塞请求，但需要检查返回值）
    local ok, result = pcall(function()
        local sql = [[
            INSERT INTO waf_audit_logs (
                user_id, username, action_type, resource_type, resource_id,
                action_description, request_method, request_path, request_params,
                ip_address, user_agent, status, error_message
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]]
        local res, err = mysql_pool.query(sql,
            user_id, username, action_type, resource_type, resource_id,
            action_description, method, path, request_params,
            ip_address, user_agent, status or "success", error_message
        )
        -- 检查查询结果
        if not res then
            -- 查询失败，抛出错误以便 pcall 捕获
            error("MySQL query failed: " .. (err or "unknown error"))
        end
        return res
    end)
    
    if not ok then
        ngx.log(ngx.ERR, "Failed to write audit log (pcall error): ", tostring(result), ", action_type: ", action_type, ", username: ", tostring(username))
    elseif not result then
        ngx.log(ngx.ERR, "Failed to write audit log (query returned nil), action_type: ", action_type, ", username: ", tostring(username))
    end
end

-- 记录登录操作
function _M.log_login(username, success, error_message)
    -- 登录时可能还没有 session，直接使用传入的 username
    local user_id = nil
    local username_for_log = username
    
    -- 尝试从 session 获取 user_id（如果 session 已创建）
    local authenticated, session = auth.is_authenticated()
    if authenticated and session then
        user_id = session.user_id or session.id
        -- 如果 session 中有 username，使用 session 中的（更可靠）
        if session.username then
            username_for_log = session.username
        end
    end
    
    -- 获取请求信息
    local method = ngx.req.get_method()
    local path = ngx.var.request_uri:match("^([^?]+)")
    local ip_address = ngx.var.remote_addr
    local user_agent = ngx.var.http_user_agent
    
    -- 获取请求参数（仅记录非敏感参数）
    local request_params = nil
    if method == "POST" or method == "PUT" then
        ngx.req.read_body()
        local args = ngx.req.get_post_args()
        if args then
            -- 过滤敏感字段
            local filtered_args = {}
            for k, v in pairs(args) do
                if k ~= "password" and k ~= "password_hash" and k ~= "totp_secret" then
                    filtered_args[k] = v
                end
            end
            if next(filtered_args) then
                request_params = cjson.encode(filtered_args)
            end
        end
    end
    
    -- 写入数据库（不阻塞请求，但需要检查返回值）
    local ok, result = pcall(function()
        local sql = [[
            INSERT INTO waf_audit_logs (
                user_id, username, action_type, resource_type, resource_id,
                action_description, request_method, request_path, request_params,
                ip_address, user_agent, status, error_message
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]]
        local res, err = mysql_pool.query(sql,
            user_id, username_for_log, "login", "user", username_for_log,
            success and "用户登录成功" or "用户登录失败", method, path, request_params,
            ip_address, user_agent, success and "success" or "failed", error_message
        )
        -- 检查查询结果
        if not res then
            -- 查询失败，抛出错误以便 pcall 捕获
            error("MySQL query failed: " .. (err or "unknown error"))
        end
        return res
    end)
    
    if not ok then
        ngx.log(ngx.ERR, "Failed to write login audit log (pcall error): ", tostring(result))
    elseif not result then
        ngx.log(ngx.ERR, "Failed to write login audit log (query returned nil)")
    else
        ngx.log(ngx.DEBUG, "Login audit log written successfully for user: ", username_for_log)
    end
end

-- 记录登出操作
function _M.log_logout(username)
    -- 登出时 session 可能已失效，直接使用传入的 username
    local user_id = nil
    local username_for_log = username
    
    -- 尝试从 session 获取 user_id（如果 session 还存在）
    local authenticated, session = auth.is_authenticated()
    if authenticated and session then
        user_id = session.user_id or session.id
        -- 如果 session 中有 username，使用 session 中的（更可靠）
        if session.username then
            username_for_log = session.username
        end
    end
    
    -- 如果传入的 username 为空，尝试从 session 获取
    if not username_for_log and authenticated and session then
        username_for_log = session.username
    end
    
    -- 如果还是没有 username，使用 "unknown"
    if not username_for_log then
        username_for_log = "unknown"
        ngx.log(ngx.WARN, "log_logout: username is nil, using 'unknown'")
    end
    
    -- 获取请求信息
    local method = ngx.req.get_method()
    local path = ngx.var.request_uri:match("^([^?]+)")
    local ip_address = ngx.var.remote_addr
    local user_agent = ngx.var.http_user_agent
    
    -- 写入数据库（不阻塞请求，但需要检查返回值）
    local ok, result = pcall(function()
        local sql = [[
            INSERT INTO waf_audit_logs (
                user_id, username, action_type, resource_type, resource_id,
                action_description, request_method, request_path, request_params,
                ip_address, user_agent, status, error_message
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]]
        local res, err = mysql_pool.query(sql,
            user_id, username_for_log, "logout", "user", username_for_log,
            "用户登出", method, path, nil,
            ip_address, user_agent, "success", nil
        )
        -- 检查查询结果
        if not res then
            -- 查询失败，抛出错误以便 pcall 捕获
            error("MySQL query failed: " .. (err or "unknown error"))
        end
        return res
    end)
    
    if not ok then
        ngx.log(ngx.ERR, "Failed to write logout audit log (pcall error): ", tostring(result))
    elseif not result then
        ngx.log(ngx.ERR, "Failed to write logout audit log (query returned nil)")
    else
        ngx.log(ngx.DEBUG, "Logout audit log written successfully for user: ", username_for_log)
    end
end

-- 记录规则操作
function _M.log_rule_action(action_type, rule_id, rule_name, success, error_message)
    _M.log(
        action_type,
        "rule",
        tostring(rule_id),
        "规则操作: " .. (rule_name or ""),
        success and "success" or "failed",
        error_message
    )
end

-- 记录配置操作
function _M.log_config_action(action_type, config_key, success, error_message)
    _M.log(
        action_type,
        "config",
        config_key,
        "配置操作: " .. config_key,
        success and "success" or "failed",
        error_message
    )
end

-- 记录功能开关操作
function _M.log_feature_action(action_type, feature_key, success, error_message)
    _M.log(
        action_type,
        "feature",
        feature_key,
        "功能开关操作: " .. feature_key,
        success and "success" or "failed",
        error_message
    )
end

-- 记录代理操作
function _M.log_proxy_action(action_type, proxy_id, proxy_name, success, error_message)
    _M.log(
        action_type,
        "proxy",
        tostring(proxy_id),
        "代理操作: " .. (proxy_name or ""),
        success and "success" or "failed",
        error_message
    )
end

-- 记录TOTP操作
function _M.log_totp_action(action_type, username, success, error_message)
    _M.log(
        action_type,
        "totp",
        username,
        "双因素认证操作: " .. action_type,
        success and "success" or "failed",
        error_message
    )
end

-- 记录系统操作
function _M.log_system_action(action_type, description, success, error_message)
    _M.log(
        action_type,
        "system",
        nil,
        description or ("系统操作: " .. action_type),
        success and "success" or "failed",
        error_message
    )
end

return _M

