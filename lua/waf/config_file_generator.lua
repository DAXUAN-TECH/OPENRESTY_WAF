-- 配置文件生成模块
-- 路径：项目目录下的 lua/waf/config_file_generator.lua（保持在项目目录，不复制到系统目录）
-- 功能：自动生成和更新 waf.conf 配置文件，确保前后端只有一个 location
-- 说明：此模块根据数据库配置自动生成 nginx 配置文件，避免手动配置

local path_utils = require "waf.path_utils"
local config_manager = require "waf.config_manager"
local cjson = require "cjson"

local _M = {}

-- 生成 waf.conf 配置文件内容
function _M.generate_waf_conf()
    local project_root = path_utils.get_project_root()
    if not project_root then
        return nil, "无法获取项目根目录"
    end
    
    -- 从数据库读取配置
    local listen_port = tonumber(config_manager.get_config("waf_listen_port", 80, "number")) or 80
    local server_name = config_manager.get_config("waf_server_name", "localhost", "string") or "localhost"
    local client_max_body_size = config_manager.get_config("waf_client_max_body_size", "10m", "string") or "10m"
    
    -- 生成配置文件内容
    local conf_content = string.format([[
# ============================================
# WAF 管理服务配置（自动生成）
# ============================================
# 注意：此文件由系统自动生成，请勿手动修改
# 如需修改配置，请通过Web界面或数据库配置
# 生成时间：%s
# ============================================

server {
    # ============================================
    # 基础配置
    # ============================================
    
    # 监听端口（HTTP）
    listen       %d;
    
    # 服务器名称
    server_name  %s;
    
    # 字符集设置
    charset utf-8;
    
    # 客户端请求体最大大小
    client_max_body_size %s;
    
    # ============================================
    # WAF 安全配置
    # ============================================
    
    # WAF 封控检查（在 access 阶段执行，优先级最高）
    # 注意：管理接口通常需要跳过封控检查，但保留此配置以防需要
    # access_by_lua_block {
    #     require("waf.ip_block").check()
    # }
    
    # 日志采集（在 log 阶段执行，不阻塞请求）
    log_by_lua_block {
        require("waf.log_collect").collect()
    }
    
    # ============================================
    # API 路由分发（统一入口）
    # 注意：所有 /api/* 路径都由路由分发器处理
    # 路由逻辑在 lua/api/handler.lua 中实现
    # ============================================
    
    location /api/ {
        access_log off;
        
        access_by_lua_block {
            -- 跳过封控检查（功能开关检查在 API 代码中）
        }
        
        content_by_lua_block {
            local api_handler = require "api.handler"
            api_handler.route()
        }
        
        # 限制访问（建议只允许内网访问）
        # allow 127.0.0.1;
        # allow 10.0.0.0/8;
        # deny all;
    }
    
    # ============================================
    # Web管理界面和监控端点（统一入口，只有一个 location）
    # 所有非 /api/* 的路径都由路由分发器处理
    # 路由逻辑在 lua/web/handler.lua 中实现
    # 注意：/api/* 路径会被上面的 location /api/ 优先匹配
    # ============================================
    
    location / {
        access_log off;
        
        access_by_lua_block {
            -- 跳过封控检查（功能开关检查在路由分发器中）
        }
        
        content_by_lua_block {
            local web_handler = require "web.handler"
            web_handler.route()
        }
        
        # 限制访问（建议只允许内网访问）
        # allow 127.0.0.1;
        # allow 10.0.0.0/8;
        # deny all;
    }
    
    # ============================================
    # 禁止访问的路径（安全配置）
    # ============================================
    
    # 禁止访问隐藏文件（.htaccess、.git 等）
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    # 禁止访问备份文件
    location ~ ~$ {
        deny all;
        access_log off;
        log_not_found off;
    }
}
]], 
        os.date("!%Y-%m-%d %H:%M:%S", ngx.time()),
        listen_port,
        server_name,
        client_max_body_size
    )
    
    return conf_content, nil
end

-- 更新 waf.conf 文件
function _M.update_waf_conf()
    local project_root = path_utils.get_project_root()
    if not project_root then
        return false, "无法获取项目根目录"
    end
    
    local conf_file = project_root .. "/conf.d/vhost_conf/waf.conf"
    local conf_content, err = _M.generate_waf_conf()
    
    if err then
        return false, err
    end
    
    -- 写入文件（使用安全的方式）
    local file = io.open(conf_file, "w")
    if not file then
        return false, "无法打开配置文件: " .. conf_file
    end
    
    file:write(conf_content)
    file:close()
    
    ngx.log(ngx.INFO, "waf.conf 配置文件已更新: ", conf_file)
    return true, nil
end

-- 检查配置文件是否需要更新
function _M.check_config_update()
    -- 检查配置版本号
    local config_version = tonumber(config_manager.get_config("waf_conf_version", 1, "number")) or 1
    local cached_version = ngx.shared.waf_cache:get("waf_conf_version") or 0
    
    if config_version > cached_version then
        -- 需要更新
        local ok, err = _M.update_waf_conf()
        if ok then
            ngx.shared.waf_cache:set("waf_conf_version", config_version, 0)
            return true
        else
            ngx.log(ngx.ERR, "更新 waf.conf 失败: ", err)
            return false
        end
    end
    
    return false
end

return _M

