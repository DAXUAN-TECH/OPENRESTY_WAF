-- 系统管理API模块
-- 路径：项目目录下的 lua/api/system.lua（保持在项目目录，不复制到系统目录）
-- 功能：处理系统管理相关的API请求，如配置重载、系统状态等

local api_utils = require "api.utils"
local cjson = require "cjson"
local path_utils = require "waf.path_utils"

local _M = {}

-- 内部函数：执行nginx重载（返回结果，不发送HTTP响应）
local function do_reload_nginx()
    -- 检查是否有nginx可执行文件
    local nginx_binary = nil
    
    -- 优先从环境变量获取（可移植性）
    local openresty_prefix = os.getenv("OPENRESTY_PREFIX") or "/usr/local/openresty"
    
    -- 尝试常见的nginx路径（按优先级排序）
    local possible_paths = {
        openresty_prefix .. "/bin/openresty",
        openresty_prefix .. "/nginx/sbin/nginx",
        os.getenv("NGINX_BINARY"),  -- 环境变量指定
        "/usr/local/openresty/bin/openresty",
        "/usr/local/openresty/nginx/sbin/nginx",
        "/usr/sbin/nginx",
        "/usr/bin/nginx",
        "/sbin/nginx",
        "/bin/nginx"
    }
    
    for _, path in ipairs(possible_paths) do
        if path then
            local file = io.open(path, "r")
            if file then
                file:close()
                nginx_binary = path
                break
            end
        end
    end
    
    if not nginx_binary then
        return false, "未找到nginx可执行文件，请设置OPENRESTY_PREFIX环境变量或检查nginx安装路径"
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
        api_utils.json_response({
            success = false,
            error = result
        }, 500)
        return
    end
    
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
    -- 检查是否有nginx可执行文件
    local nginx_binary = nil
    
    -- 优先从环境变量获取（可移植性）
    local openresty_prefix = os.getenv("OPENRESTY_PREFIX") or "/usr/local/openresty"
    
    -- 尝试常见的nginx路径（按优先级排序）
    local possible_paths = {
        openresty_prefix .. "/bin/openresty",
        openresty_prefix .. "/nginx/sbin/nginx",
        os.getenv("NGINX_BINARY"),  -- 环境变量指定
        "/usr/local/openresty/bin/openresty",
        "/usr/local/openresty/nginx/sbin/nginx",
        "/usr/sbin/nginx",
        "/usr/bin/nginx",
        "/sbin/nginx",
        "/bin/nginx"
    }
    
    for _, path in ipairs(possible_paths) do
        if path then
            local file = io.open(path, "r")
            if file then
                file:close()
                nginx_binary = path
                break
            end
        end
    end
    
    if not nginx_binary then
        api_utils.json_response({
            success = false,
            error = "未找到nginx可执行文件，请设置OPENRESTY_PREFIX环境变量或检查nginx安装路径"
        }, 500)
        return
    end
    
    -- 执行nginx配置测试
    local test_cmd = nginx_binary .. " -t"
    local test_result = io.popen(test_cmd)
    local test_output = test_result:read("*all")
    local test_code = test_result:close()
    
    if test_code ~= 0 then
        api_utils.json_response({
            success = false,
            error = "nginx配置测试失败",
            details = test_output
        }, 400)
        return
    end
    
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

