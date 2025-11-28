-- Web工具函数模块
-- 路径：项目目录下的 lua/web/web_utils.lua（保持在项目目录，不复制到系统目录）
-- 功能：提供Web界面处理中常用的工具函数，避免重复代码

local _M = {}

-- HTML 转义函数（OpenResty 没有内置的 ngx.escape_html）
function _M.escape_html(text)
    if not text then
        return ""
    end
    text = tostring(text)
    -- 转义 HTML 特殊字符
    text = text:gsub("&", "&amp;")
    text = text:gsub("<", "&lt;")
    text = text:gsub(">", "&gt;")
    text = text:gsub('"', "&quot;")
    text = text:gsub("'", "&#39;")
    return text
end

return _M

