-- 错误页面工具模块
-- 路径：项目目录下的 lua/waf/error_pages.lua
-- 功能：统一处理各种错误页面（403、404等）

local path_utils = require "waf.path_utils"

local _M = {}

-- 返回403错误页面
-- @param ip_address string 可选，IP地址（用于替换模板中的{{IP_ADDRESS}}）
-- @param custom_message string 可选，自定义消息（用于替换模板中的{{MESSAGE}}）
-- @return boolean 是否成功返回页面
function _M.return_403(ip_address, custom_message)
    ngx.status = 403
    ngx.header.content_type = "text/html; charset=utf-8"
    
    local ip_display = ip_address or ngx.var.remote_addr or "unknown"
    local message = custom_message or "很抱歉，您当前没有访问此系统的权限。"
    
    -- 读取403错误页面HTML文件
    local project_root = path_utils.get_project_root()
    if project_root then
        local html_file_path = project_root .. "/conf.d/web/403_waf.html"
        local html_file = io.open(html_file_path, "r")
        if html_file then
            local html_content = html_file:read("*all")
            html_file:close()
            if html_content then
                -- 替换IP地址占位符
                html_content = html_content:gsub("{{IP_ADDRESS}}", ip_display)
                -- 替换消息占位符（如果模板中有的话）
                html_content = html_content:gsub("{{MESSAGE}}", message)
                ngx.say(html_content)
                ngx.exit(403)
                return true
            end
        end
    end
    
    -- 如果读取文件失败，使用简单的错误信息
    ngx.log(ngx.ERR, "Failed to read 403_waf.html file, using fallback error message")
    ngx.say("<!DOCTYPE html><html><head><meta charset='UTF-8'><title>无访问权限</title></head><body><h1>403 Forbidden</h1><p>您的IP地址（" .. ip_display .. "）" .. message .. "</p></body></html>")
    ngx.exit(403)
    return false
end

return _M

