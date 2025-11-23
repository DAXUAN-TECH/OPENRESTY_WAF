-- WAF 初始化模块
-- 路径：项目目录下的 lua/waf/init.lua（保持在项目目录，不复制到系统目录）

local _M = {}
local config = require "config"

-- 初始化函数
function _M.init()
    ngx.log(ngx.INFO, "WAF module initialized")
    
    -- 动态设置 GeoIP2 数据库路径（如果未配置）
    if config.geo.enable and not config.geo.geoip_db_path then
        -- 获取项目根目录（从 nginx 变量）
        local project_root = ngx.var.project_root
        if not project_root or project_root == "" then
            -- 如果变量未设置，尝试从 lua_package_path 推断
            -- package.path 中第一个路径通常是项目根目录下的 lua
            local first_path = package.path:match("([^;]+)")
            if first_path then
                -- 提取路径：从 lua/?.lua 推断项目根目录
                project_root = first_path:match("(.+)/lua/%?%.lua")
            end
        end
        
        if project_root and project_root ~= "" then
            config.geo.geoip_db_path = project_root .. "/lua/geoip/GeoLite2-City.mmdb"
            ngx.log(ngx.INFO, "GeoIP2 database path auto-configured: ", config.geo.geoip_db_path)
        else
            ngx.log(ngx.WARN, "GeoIP2 database path not configured and cannot auto-detect project root")
        end
    end
    
    -- 预加载 GeoIP2 数据库（如果启用）
    -- 注意：在 init_by_lua 阶段无法访问 ngx.shared，所以这里只做基本检查
    if config.geo.enable then
        if not config.geo.geoip_db_path then
            ngx.log(ngx.WARN, "GeoIP2 database path not configured")
        else
            ngx.log(ngx.INFO, "GeoIP2 enabled, database path: ", config.geo.geoip_db_path)
        end
    end
end

return _M

