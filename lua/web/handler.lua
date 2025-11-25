-- Web界面处理模块（路由分发器）
-- 路径：项目目录下的 lua/web/handler.lua（保持在项目目录，不复制到系统目录）
-- 功能：作为Web界面路由分发器，根据请求路径返回相应的HTML文件或监控指标

local feature_switches = require "waf.feature_switches"
local metrics = require "waf.metrics"
local config = require "config"
local auth = require "waf.auth"
local path_utils = require "waf.path_utils"
local web_utils = require "web.web_utils"

local _M = {}

-- HTML 转义函数（使用公共模块）
local function escape_html(text)
    return web_utils.escape_html(text)
end

-- 读取HTML文件内容
local function read_html_file(filename)
    local project_root = path_utils.get_project_root()
    
    if not project_root then
        ngx.log(ngx.ERR, "Failed to determine project root for serving HTML file: ", filename)
        return nil
    end
    
    local file_path = project_root .. "/lua/web/" .. filename
    
    -- 尝试打开文件
    local file, open_err = io.open(file_path, "r")
    if file then
        local content = file:read("*all")
        file:close()
        if content then
            return content
        else
            ngx.log(ngx.ERR, "Failed to read content from HTML file: ", file_path)
            return nil
        end
    else
        -- 记录详细的错误信息
        ngx.log(ngx.ERR, "HTML file not found: ", file_path, " (project_root: ", project_root, ", open error: ", tostring(open_err), ")")
        
        -- 尝试备用路径（如果项目根目录检测有问题）
        -- 尝试从当前文件路径推断
        local current_file = debug.getinfo(1, "S").source
        if current_file then
            current_file = current_file:gsub("^@", "")
            local alt_project_root = current_file:match("(.+)/lua/web/handler%.lua")
            if alt_project_root and alt_project_root ~= project_root then
                local alt_file_path = alt_project_root .. "/lua/web/" .. filename
                local alt_file = io.open(alt_file_path, "r")
                if alt_file then
                    ngx.log(ngx.WARN, "Using alternative path for HTML file: ", alt_file_path)
                    local content = alt_file:read("*all")
                    alt_file:close()
                    if content then
                        return content
                    end
                end
            end
        end
        
        return nil
    end
end

-- 生成带布局的HTML页面
local function serve_html_with_layout(filename, page_title, session)
    local content = read_html_file(filename)
    if not content then
        ngx.status = 404
        ngx.header.content_type = "text/html; charset=utf-8"
        ngx.say([[
<html><body>
<h1>404 Not Found</h1>
<p>File not found: ]] .. escape_html(filename) .. [[</p>
</body></html>
        ]])
        return
    end
    
    local username = session and session.username or "用户"
    
    -- 读取布局模板
    local layout_content = read_html_file("layout.html")
    if not layout_content then
        -- 如果布局文件不存在，直接返回内容
        ngx.header.content_type = "text/html; charset=utf-8"
        ngx.say(content)
        return
    end
    
    -- 提取额外的样式和脚本（在替换CONTENT之前）
    local extra_styles = ""
    local extra_scripts = ""
    local body_content = content
    
    -- 提取style标签（支持多行）
    for style_match in content:gmatch("<style>([%s%S]-)</style>") do
        -- 移除body样式定义，避免与layout.html的body样式冲突
        -- 匹配 body { ... } 或 body{ ... } 等格式（支持多行）
        local cleaned_style = style_match
        -- 移除body选择器的样式块（支持多行，匹配嵌套的大括号）
        -- 使用平衡匹配来正确处理嵌套的大括号
        local function remove_body_style(style_text)
            local result = style_text
            -- 匹配 body 后跟可选的选择器，然后是 { ... }
            -- 使用平衡匹配处理嵌套大括号
            local pattern = "body[^%{]*%b{}"
            local changed = true
            while changed do
                local old_result = result
                result = result:gsub(pattern, "")
                changed = (result ~= old_result)
            end
            return result
        end
        cleaned_style = remove_body_style(cleaned_style)
        
        -- 清理多余的空白行
        cleaned_style = cleaned_style:gsub("\n%s*\n%s*\n+", "\n\n")
        
        if cleaned_style:match("%S") then  -- 如果还有非空白内容
            extra_styles = extra_styles .. "<style>" .. cleaned_style .. "</style>\n"
        end
        -- 从内容中移除style标签
        body_content = body_content:gsub("<style>[%s%S]-</style>", "", 1)
    end
    
    -- 提取外部script标签（带src属性）
    for script_tag in content:gmatch('<script[^>]*src="[^"]+"[^>]*></script>') do
        extra_scripts = extra_scripts .. script_tag .. "\n"
        -- 从内容中移除script标签
        body_content = body_content:gsub('<script[^>]*src="[^"]+"[^>]*></script>', "", 1)
    end
    
    -- 提取内联script标签（支持多行）
    for script_match in content:gmatch("<script>([%s%S]-)</script>") do
        extra_scripts = extra_scripts .. "<script>" .. script_match .. "</script>\n"
        -- 从内容中移除script标签
        body_content = body_content:gsub("<script>[%s%S]-</script>", "", 1)
    end
    
    -- 如果内容包含完整的HTML结构（DOCTYPE、html、body标签），提取body标签内的内容
    -- 这样可以避免嵌套的body标签和样式冲突
    if body_content:match("<!DOCTYPE") or body_content:match("<html") then
        -- 提取body标签内的内容（不包含body标签本身）
        local body_match = body_content:match("<body[^>]*>([%s%S]-)</body>")
        if body_match then
            body_content = body_match
        else
            -- 如果没有找到body标签，尝试移除DOCTYPE、html、head标签
            body_content = body_content:gsub("<!DOCTYPE[^>]*>", "")
            body_content = body_content:gsub("<html[^>]*>", "")
            body_content = body_content:gsub("</html>", "")
            body_content = body_content:gsub("<head>.-</head>", "")
        end
    end
    
    -- 替换布局模板中的占位符
    layout_content = layout_content:gsub("{{TITLE}}", escape_html(page_title))
    layout_content = layout_content:gsub("{{PAGE_TITLE}}", escape_html(page_title))
    layout_content = layout_content:gsub("{{USERNAME}}", escape_html(username))
    layout_content = layout_content:gsub("{{CONTENT}}", body_content)
    layout_content = layout_content:gsub("{{EXTRA_STYLES}}", extra_styles)
    layout_content = layout_content:gsub("{{EXTRA_SCRIPTS}}", extra_scripts)
    
    ngx.header.content_type = "text/html; charset=utf-8"
    ngx.say(layout_content)
end

-- 读取并返回HTML文件（兼容旧代码，不使用布局）
local function serve_html_file(filename)
    local content = read_html_file(filename)
    if content then
        ngx.header.content_type = "text/html; charset=utf-8"
        ngx.say(content)
    else
        ngx.status = 404
        ngx.header.content_type = "text/html; charset=utf-8"
        ngx.say([[
<html><body>
<h1>404 Not Found</h1>
<p>File not found: ]] .. escape_html(filename) .. [[</p>
</body></html>
        ]])
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
    
    -- 防护管理界面
    if path == "/admin/rules" then
        -- 检查功能开关（防护管理功能必须启用）
        if not feature_switches.is_enabled("rule_management_ui") then
            ngx.status = 403
            ngx.header.content_type = "text/html; charset=utf-8"
            ngx.say("<html><body><h1>403 Forbidden</h1><p>防护管理界面功能已禁用</p></body></html>")
            return
        end
        return serve_html_with_layout("rule_management.html", "防护管理", session)
    end
    
    -- 功能管理界面（必须可用，用于管理功能开关）
    if path == "/admin/features" then
        return serve_html_with_layout("features.html", "功能管理", session)
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
        return serve_html_with_layout("stats.html", "统计报表", session)
    end
    
    -- Dashboard界面（原监控面板）
    if path == "/admin/dashboard" or path == "/admin/monitor" then
        -- 检查功能开关
        if not feature_switches.is_enabled("monitor") then
            ngx.status = 403
            ngx.header.content_type = "text/html; charset=utf-8"
            ngx.say("<html><body><h1>403 Forbidden</h1><p>Dashboard功能已禁用</p></body></html>")
            return
        end
        return serve_html_with_layout("dashboard.html", "Dashboard", session)
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
        return serve_html_with_layout("proxy_management.html", "反向代理", session)
    end
    
    -- 用户设置页面
    if path == "/admin/settings" or path == "/admin/profile" then
        return serve_html_with_layout("user_settings.html", "用户设置", session)
    end
    
    -- 日志查看页面
    if path == "/admin/logs" then
        return serve_html_with_layout("logs.html", "日志查看", session)
    end
    
    -- 静态文件服务（JavaScript、CSS等）
    if path:match("%.js$") or path:match("%.css$") then
        local filename = path:match("([^/]+)$")
        if filename then
            local project_root = path_utils.get_project_root()
            if project_root then
                local file_path = project_root .. "/lua/web/" .. filename
                local file = io.open(file_path, "r")
                if file then
                    local content = file:read("*all")
                    file:close()
                    if path:match("%.js$") then
                        ngx.header.content_type = "application/javascript; charset=utf-8"
                    elseif path:match("%.css$") then
                        ngx.header.content_type = "text/css; charset=utf-8"
                    end
                    ngx.say(content)
                    return
                end
            end
        end
        ngx.status = 404
        return
    end
    
    -- 默认首页（根路径和管理首页）- 重定向到Dashboard
    if path == "/" or path == "/admin" or path == "/admin/" then
        ngx.redirect("/admin/dashboard")
        return
    end
    
    -- 未匹配的路径
    ngx.status = 404
    ngx.header.content_type = "text/html; charset=utf-8"
    ngx.say("<html><body><h1>404 Not Found</h1><p>页面不存在: " .. escape_html(path) .. "</p></body></html>")
end

return _M

