-- 系统管理API模块
-- 路径：项目目录下的 lua/api/system.lua（保持在项目目录，不复制到系统目录）
-- 功能：处理系统管理相关的API请求，如配置重载、系统状态等

local api_utils = require "api.utils"
local cjson = require "cjson"
local path_utils = require "waf.path_utils"
local audit_log = require "waf.audit_log"

local _M = {}

-- 查找nginx可执行文件（可移植性实现）
local function find_nginx_binary()
    -- 1. 优先从环境变量获取（最高优先级）
    local nginx_binary_env = os.getenv("NGINX_BINARY")
    if nginx_binary_env and nginx_binary_env ~= "" then
        local file = io.open(nginx_binary_env, "r")
        if file then
            file:close()
            return nginx_binary_env
        end
    end
    
    -- 2. 从 OPENRESTY_PREFIX 环境变量构建路径
    local openresty_prefix = os.getenv("OPENRESTY_PREFIX")
    if openresty_prefix and openresty_prefix ~= "" then
        local possible_paths = {
            openresty_prefix .. "/bin/openresty",
            openresty_prefix .. "/nginx/sbin/nginx"
        }
        for _, path in ipairs(possible_paths) do
            local file = io.open(path, "r")
            if file then
                file:close()
                return path
            end
        end
    end
    
    -- 3. 尝试使用 which 命令查找（跨平台兼容）
    local which_cmd = "which openresty 2>/dev/null || which nginx 2>/dev/null"
    local which_result = io.popen(which_cmd)
    if which_result then
        local which_path = which_result:read("*line")
        which_result:close()
        if which_path and which_path ~= "" then
            local file = io.open(which_path, "r")
            if file then
                file:close()
                return which_path
            end
        end
    end
    
    -- 4. 如果都找不到，返回nil（由调用者处理错误）
    return nil
end

-- 内部函数：执行nginx重载（返回结果，不发送HTTP响应）
local function do_reload_nginx()
    -- 查找nginx可执行文件
    local nginx_binary = find_nginx_binary()
    
    if not nginx_binary then
        return false, "未找到nginx可执行文件，请设置NGINX_BINARY或OPENRESTY_PREFIX环境变量"
    end
    
    -- 执行nginx配置测试
    local test_cmd = nginx_binary .. " -t 2>&1"
    local test_result = io.popen(test_cmd)
    local test_output = test_result:read("*all")
    local test_code = test_result:close()
    
    if test_code ~= 0 then
        return false, "nginx配置测试失败: " .. (test_output or "unknown error")
    end
    
    -- 执行nginx配置重新加载
    local reload_cmd = nginx_binary .. " -s reload 2>&1"
    local reload_result = io.popen(reload_cmd)
    local reload_output = reload_result:read("*all")
    local reload_code = reload_result:close()
    
    if reload_code ~= 0 then
        return false, "nginx配置重新加载失败: " .. (reload_output or "unknown error")
    end
    
    ngx.log(ngx.INFO, "nginx配置重新加载成功")
    return true, reload_output
end

-- 触发nginx配置重新加载（API接口）
function _M.reload_nginx()
    local ok, result = do_reload_nginx()
    if not ok then
        -- 记录审计日志（失败）
        audit_log.log_system_action("reload_nginx", "重新加载nginx配置", false, result)
        api_utils.json_response({
            success = false,
            error = result
        }, 500)
        return
    end
    
    -- 记录审计日志（成功）
    audit_log.log_system_action("reload_nginx", "重新加载nginx配置", true, nil)
    
    api_utils.json_response({
        success = true,
        message = "nginx配置重新加载成功",
        output = result
    })
end

-- 触发nginx配置重新加载（内部调用，返回结果）
function _M.reload_nginx_internal()
    return do_reload_nginx()
end

-- 测试nginx配置
function _M.test_nginx_config()
    -- 查找nginx可执行文件
    local nginx_binary = find_nginx_binary()
    
    if not nginx_binary then
        api_utils.json_response({
            success = false,
            error = "未找到nginx可执行文件，请设置NGINX_BINARY或OPENRESTY_PREFIX环境变量"
        }, 500)
        return
    end
    
    -- 执行nginx配置测试
    local test_cmd = nginx_binary .. " -t"
    local test_result = io.popen(test_cmd)
    local test_output = test_result:read("*all")
    local test_code = test_result:close()
    
    if test_code ~= 0 then
        -- 记录审计日志（失败）
        audit_log.log_system_action("test_nginx_config", "测试nginx配置", false, test_output)
        api_utils.json_response({
            success = false,
            error = "nginx配置测试失败",
            details = test_output
        }, 400)
        return
    end
    
    -- 记录审计日志（成功）
    audit_log.log_system_action("test_nginx_config", "测试nginx配置", true, nil)
    
    api_utils.json_response({
        success = true,
        message = "nginx配置测试通过",
        output = test_output
    })
end

-- 获取系统状态
function _M.get_status()
    -- 检查nginx进程是否运行
    local nginx_pid_file = nil
    local project_root = path_utils.get_project_root()
    if project_root then
        nginx_pid_file = project_root .. "/logs/nginx.pid"
    else
        -- 如果无法获取项目根目录，尝试从nginx配置中读取pid文件路径
        -- 这里使用相对路径，避免硬编码绝对路径
        ngx.log(ngx.WARN, "Cannot determine project root for nginx pid file")
        nginx_pid_file = nil
    end
    
    local pid_file = io.open(nginx_pid_file, "r")
    local nginx_running = false
    local nginx_pid = nil
    
    if pid_file then
        nginx_pid = pid_file:read("*line")
        pid_file:close()
        
        if nginx_pid then
            -- 检查进程是否存在
            local check_cmd = "kill -0 " .. nginx_pid .. " 2>/dev/null"
            local check_result = os.execute(check_cmd)
            nginx_running = (check_result == 0)
        end
    end
    
    api_utils.json_response({
        success = true,
        status = {
            nginx_running = nginx_running,
            nginx_pid = nginx_pid,
            timestamp = os.date("!%Y-%m-%d %H:%M:%S", ngx.time())
        }
    })
end

return _M
