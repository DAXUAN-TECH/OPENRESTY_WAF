-- Web界面处理模块（路由分发器）
-- 路径：项目目录下的 lua/web/handler.lua（保持在项目目录，不复制到系统目录）
-- 功能：作为Web界面路由分发器，根据请求路径返回相应的HTML文件或监控指标

local feature_switches = require "waf.feature_switches"
local metrics = require "waf.metrics"
local config = require "config"
local auth = require "waf.auth"
local path_utils = require "waf.path_utils"

local _M = {}

-- 读取并返回HTML文件
local function serve_html_file(filename)
    local project_root = path_utils.get_project_root()
    if not project_root then
        ngx.status = 500
        ngx.say("Failed to determine project root")
        return
    end
    
    local file_path = project_root .. "/lua/web/" .. filename
    local file = io.open(file_path, "r")
    if file then
        local content = file:read("*all")
        file:close()
        ngx.header.content_type = "text/html; charset=utf-8"
        ngx.say(content)
    else
        ngx.status = 404
        ngx.say("File not found: " .. file_path)
    end
end

-- 检查认证（需要登录的页面）
local function check_auth()
    local authenticated, session = auth.is_authenticated()
    if not authenticated then
        -- 未登录，重定向到登录页面
        ngx.redirect("/login?redirect=" .. ngx.escape_uri(ngx.var.request_uri))
        return false
    end
    return true, session
end

-- Web界面路由分发主函数
function _M.route()
    local uri = ngx.var.request_uri or ""
    local path = uri:match("^([^?]+)") or "/"
    
    -- 登录页面（不需要认证）
    if path == "/login" then
        return serve_html_file("login.html")
    end
    
    -- 以下页面需要认证（包括metrics端点）
    -- 检查是否已登录
    local auth_ok, session = check_auth()
    if not auth_ok then
        return  -- 已重定向到登录页面
    end
    
    -- Prometheus 指标导出端点（需要登录）
    if path == "/metrics" then
        -- 检查指标功能是否启用
        if config.metrics and config.metrics.enable then
            ngx.header.content_type = "text/plain; version=0.0.4"
            ngx.say(metrics.get_prometheus_metrics())
        else
            ngx.status = 404
            ngx.say("Metrics not enabled")
        end
        return
    end
    
    -- 规则管理界面
    if path == "/admin/rules" then
        -- 检查功能开关（规则管理功能必须启用）
        if not feature_switches.is_enabled("rule_management_ui") then
            ngx.status = 403
            ngx.header.content_type = "text/html; charset=utf-8"
            ngx.say("<html><body><h1>403 Forbidden</h1><p>规则管理界面功能已禁用</p></body></html>")
            return
        end
        return serve_html_file("rule_management.html")
    end
    
    -- 功能管理界面（必须可用，用于管理功能开关）
    if path == "/admin/features" then
        return serve_html_file("features.html")
    end
    
    -- 统计报表界面
    if path == "/admin/stats" then
        -- 检查功能开关
        if not feature_switches.is_enabled("stats") then
            ngx.status = 403
            ngx.header.content_type = "text/html; charset=utf-8"
            ngx.say("<html><body><h1>403 Forbidden</h1><p>统计报表功能已禁用</p></body></html>")
            return
        end
        return serve_html_file("stats.html")
    end
    
    -- 监控面板界面
    if path == "/admin/monitor" then
        -- 检查功能开关
        if not feature_switches.is_enabled("monitor") then
            ngx.status = 403
            ngx.header.content_type = "text/html; charset=utf-8"
            ngx.say("<html><body><h1>403 Forbidden</h1><p>监控面板功能已禁用</p></body></html>")
            return
        end
        return serve_html_file("monitor.html")
    end
    
    -- 反向代理管理界面
    if path == "/admin/proxy" then
        -- 检查功能开关
        if not feature_switches.is_enabled("proxy_management") then
            ngx.status = 403
            ngx.header.content_type = "text/html; charset=utf-8"
            ngx.say("<html><body><h1>403 Forbidden</h1><p>反向代理管理功能已禁用</p></body></html>")
            return
        end
        return serve_html_file("proxy_management.html")
    end
    
    -- 默认首页（根路径和管理首页）
    if path == "/" or path == "/admin" or path == "/admin/" then
        ngx.status = 200
        ngx.header.content_type = "text/html; charset=utf-8"
        local username = session and session.username or "用户"
        ngx.say([[
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>WAF 管理界面</title>
    <style>
        body { font-family: Arial, sans-serif; padding: 50px; }
        .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 30px; }
        h1 { color: #333; margin: 0; }
        .user-info { color: #666; }
        .user-info a { color: #0066cc; text-decoration: none; margin-left: 10px; }
        .user-info a:hover { text-decoration: underline; }
        ul { list-style: none; padding: 0; }
        li { margin: 10px 0; }
        a { color: #0066cc; text-decoration: none; font-size: 18px; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="header">
        <h1>WAF 管理界面</h1>
        <div class="user-info">
            欢迎，]] .. ngx.escape_html(username) .. [[
            <a href="/api/auth/logout">退出</a>
        </div>
    </div>
    <ul>
        <li><a href="/admin/features">功能管理</a></li>
        <li><a href="/admin/rules">规则管理</a></li>
        <li><a href="/admin/proxy">反向代理</a></li>
        <li><a href="/admin/stats">统计报表</a></li>
        <li><a href="/admin/monitor">监控面板</a></li>
        <li><a href="/metrics">监控指标</a></li>
    </ul>
</body>
</html>
        ]])
        return
    end
    
    -- 未匹配的路径
    ngx.status = 404
    ngx.header.content_type = "text/html; charset=utf-8"
    ngx.say("<html><body><h1>404 Not Found</h1><p>页面不存在: " .. ngx.escape_html(path) .. "</p></body></html>")
end

return _M

