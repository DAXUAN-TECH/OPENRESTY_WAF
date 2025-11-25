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
    
    -- 异步写入数据库（不阻塞请求）
    local ok, err = pcall(function()
        local sql = [[
            INSERT INTO waf_audit_logs (
                user_id, username, action_type, resource_type, resource_id,
                action_description, request_method, request_path, request_params,
                ip_address, user_agent, status, error_message
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]]
        mysql_pool.query(sql,
            user_id, username, action_type, resource_type, resource_id,
            action_description, method, path, request_params,
            ip_address, user_agent, status or "success", error_message
        )
    end)
    
    if not ok then
        ngx.log(ngx.ERR, "Failed to write audit log: ", err)
    end
end

-- 记录登录操作
function _M.log_login(username, success, error_message)
    _M.log(
        "login",
        "user",
        username,
        success and "用户登录成功" or "用户登录失败",
        success and "success" or "failed",
        error_message
    )
end

-- 记录登出操作
function _M.log_logout(username)
    _M.log(
        "logout",
        "user",
        username,
        "用户登出",
        "success",
        nil
    )
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

