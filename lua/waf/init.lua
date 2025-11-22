-- WAF 初始化模块
-- 路径：/usr/local/openresty/nginx/lua/waf/init.lua

local _M = {}
local config = require "config"

-- 初始化缓存
local cache = ngx.shared.waf_cache

-- 初始化函数
function _M.init()
    ngx.log(ngx.INFO, "WAF module initialized")
    
    -- 预加载 GeoIP2 数据库（如果启用）
    if config.geo.enable then
        local geo_block = require "waf.geo_block"
        -- 尝试初始化数据库
        local ok, err = pcall(function()
            -- 通过查询一个测试 IP 来触发数据库加载
            geo_block.get_geo_info("8.8.8.8")
        end)
        if ok then
            ngx.log(ngx.INFO, "GeoIP2 database preloaded")
        else
            ngx.log(ngx.WARN, "GeoIP2 database preload failed: ", err)
        end
    end
end

return _M

