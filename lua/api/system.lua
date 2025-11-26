-- 系统管理API模块
-- 路径：项目目录下的 lua/api/system.lua（保持在项目目录，不复制到系统目录）
-- 功能：处理系统管理相关的API请求，如配置重载、系统状态等

local api_utils = require "api.utils"
local cjson = require "cjson"
local path_utils = require "waf.path_utils"
local audit_log = require "waf.audit_log"

local _M = {}

-- 检查文件是否存在且可执行
-- 注意：在 timer 上下文中，io.open() 和 os.execute() 可能受限
-- 因此采用直接尝试执行命令的方式，如果命令执行成功就认为文件存在且可执行
local function is_executable(path)
    if not path or path == "" then
        return false
    end
    
    -- 方法1：尝试使用 test 命令检查（在 timer 上下文中可能失败）
    local test_cmd = "test -x " .. path .. " 2>/dev/null"
    local test_result = os.execute(test_cmd)
    if test_result == 0 then
        return true
    end
    
    -- 方法2：如果 test 命令失败，尝试直接执行命令的 --version 选项（更可靠）
    -- 这样可以避免文件系统访问问题
    local version_cmd = path .. " -v 2>&1 >/dev/null"
    local version_result = os.execute(version_cmd)
    if version_result == 0 then
        return true
    end
    
    return false
end

-- 查找nginx可执行文件（可移植性实现）
-- 注意：在 timer 上下文中，io.popen() 可能受限，因此优先使用直接执行命令的方式
local function find_nginx_binary()
    -- 1. 优先从环境变量获取（最高优先级）
    local nginx_binary_env = os.getenv("NGINX_BINARY")
    if nginx_binary_env and nginx_binary_env ~= "" then
        if is_executable(nginx_binary_env) then
            ngx.log(ngx.INFO, "从NGINX_BINARY环境变量找到nginx可执行文件: ", nginx_binary_env)
            return nginx_binary_env
        else
            ngx.log(ngx.DEBUG, "NGINX_BINARY环境变量指定的路径不可执行: ", nginx_binary_env)
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
            if is_executable(path) then
                ngx.log(ngx.INFO, "从OPENRESTY_PREFIX环境变量找到nginx可执行文件: ", path)
                return path
            end
        end
    end
    
    -- 3. 尝试使用 which 命令查找（跨平台兼容）
    -- 注意：在 timer 上下文中，io.popen() 可能受限，如果失败就跳过
    local which_cmd = "which openresty 2>/dev/null || which nginx 2>/dev/null"
    local which_result = io.popen(which_cmd)
    if which_result then
        local which_path = which_result:read("*line")
        which_result:close()
        if which_path and which_path ~= "" then
            -- 清理路径（去除换行符和空格）
            which_path = which_path:gsub("^%s+", ""):gsub("%s+$", "")
            if is_executable(which_path) then
                ngx.log(ngx.INFO, "通过which命令找到nginx可执行文件: ", which_path)
                return which_path
            end
        end
    else
        ngx.log(ngx.DEBUG, "无法使用which命令查找nginx可执行文件（可能在timer上下文中受限）")
    end
    
    -- 4. 尝试常见的默认安装路径（按优先级排序）
    -- 注意：/usr/local/openresty/bin/openresty 是最常见的OpenResty安装路径
    -- 在 timer 上下文中，直接尝试执行命令比检查文件更可靠
    local default_paths = {
        "/usr/local/openresty/bin/openresty",  -- 最常见的OpenResty安装路径
        "/usr/local/bin/openresty",
        "/usr/bin/openresty",
        "/opt/openresty/bin/openresty",
        "/usr/local/openresty/nginx/sbin/nginx",
        "/usr/local/nginx/sbin/nginx",
        "/usr/sbin/nginx",
        "/usr/bin/nginx"
    }
    for _, path in ipairs(default_paths) do
        if is_executable(path) then
            ngx.log(ngx.INFO, "从默认路径找到nginx可执行文件: ", path)
            return path
        end
    end
    
    -- 5. 如果都找不到，返回nil（由调用者处理错误）
    ngx.log(ngx.WARN, "无法找到nginx可执行文件，已尝试所有可能的路径")
    ngx.log(ngx.WARN, "请设置NGINX_BINARY环境变量或确保openresty安装在默认路径")
    return nil
end

-- 内部函数：执行nginx重载（返回结果，不发送HTTP响应）
local function do_reload_nginx()
    -- 查找nginx可执行文件
    -- 注意：在 timer 上下文中，可能需要多次尝试或使用不同的方法
    local nginx_binary = find_nginx_binary()
    
    if not nginx_binary then
        -- 如果找不到，尝试直接使用最常见的路径（即使 is_executable 失败）
        -- 因为在实际执行命令时可能可以工作
        local fallback_path = "/usr/local/openresty/bin/openresty"
        ngx.log(ngx.WARN, "无法通过检查找到nginx可执行文件，尝试使用默认路径: ", fallback_path)
        nginx_binary = fallback_path
    end
    
    ngx.log(ngx.INFO, "使用nginx可执行文件: ", nginx_binary)
    
    -- 第一步：执行nginx配置测试（必须先测试，确保配置正确）
    -- 注意：在 timer 上下文中，worker 进程以 nobody 用户运行，可能没有权限访问系统日志目录
    -- 因此使用 -e 选项指定错误日志到 /dev/null，使用 -g 选项指定临时 PID 文件
    -- 命令格式：/usr/local/openresty/bin/openresty -t -e /dev/null -g "pid /tmp/nginx_test.pid"
    ngx.log(ngx.INFO, "开始测试nginx配置，执行命令: ", nginx_binary, " -t")
    
    -- 使用临时错误日志和 PID 文件，避免权限问题
    local test_cmd = nginx_binary .. " -t -e /dev/null -g \"pid /tmp/nginx_test.pid\" 2>&1"
    local test_result = io.popen(test_cmd)
    if not test_result then
        local error_msg = "无法执行nginx配置测试命令: " .. test_cmd .. " (可能在timer上下文中受限)"
        ngx.log(ngx.ERR, error_msg)
        return false, error_msg
    end
    
    local test_output = test_result:read("*all")
    local test_code = test_result:close()
    
    -- 清理临时 PID 文件（如果存在）
    os.execute("rm -f /tmp/nginx_test.pid 2>/dev/null")
    
    if test_code ~= 0 then
        -- 检查是否是权限问题导致的失败
        if test_output and (test_output:match("Permission denied") or test_output:match("13:")) then
            -- 如果是权限问题，尝试不使用临时文件，直接测试（可能仍然失败，但至少尝试了）
            ngx.log(ngx.WARN, "配置测试因权限问题失败，尝试直接测试配置语法...")
            local simple_test_cmd = nginx_binary .. " -t -q 2>&1"
            local simple_test_result = io.popen(simple_test_cmd)
            if simple_test_result then
                local simple_test_output = simple_test_result:read("*all")
                local simple_test_code = simple_test_result:close()
                if simple_test_code == 0 then
                    -- 语法测试通过，但可能因为权限问题无法完全测试
                    ngx.log(ngx.WARN, "配置语法测试通过，但可能存在权限问题，将尝试直接重载")
                    -- 继续执行重载，因为 reload 命令本身也会测试配置
                else
                    local error_msg = "nginx配置测试失败: " .. (simple_test_output or "unknown error")
                    ngx.log(ngx.ERR, error_msg, " (命令: ", simple_test_cmd, ")")
                    return false, error_msg
                end
            else
                local error_msg = "nginx配置测试失败（权限问题）: " .. (test_output or "unknown error")
                ngx.log(ngx.ERR, error_msg, " (命令: ", test_cmd, ")")
                return false, error_msg
            end
        else
            local error_msg = "nginx配置测试失败: " .. (test_output or "unknown error")
            ngx.log(ngx.ERR, error_msg, " (命令: ", test_cmd, ")")
            return false, error_msg
        end
    else
        ngx.log(ngx.INFO, "nginx配置测试通过: ", test_output or "success")
    end
    
    -- 第二步：执行nginx配置重新加载（测试通过后才重载）
    -- 命令格式：/usr/local/openresty/bin/openresty -s reload
    ngx.log(ngx.INFO, "开始重新加载nginx配置，执行命令: ", nginx_binary, " -s reload")
    local reload_cmd = nginx_binary .. " -s reload 2>&1"
    local reload_result = io.popen(reload_cmd)
    if not reload_result then
        local error_msg = "无法执行nginx重载命令: " .. reload_cmd .. " (可能在timer上下文中受限)"
        ngx.log(ngx.ERR, error_msg)
        return false, error_msg
    end
    
    local reload_output = reload_result:read("*all")
    local reload_code = reload_result:close()
    
    if reload_code ~= 0 then
        local error_msg = "nginx配置重新加载失败: " .. (reload_output or "unknown error")
        ngx.log(ngx.ERR, error_msg, " (命令: ", reload_cmd, ")")
        return false, error_msg
    end
    
    ngx.log(ngx.INFO, "nginx配置重新加载成功: ", reload_output or "success")
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
