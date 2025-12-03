-- 系统管理API模块
-- 路径：项目目录下的 lua/api/system.lua（保持在项目目录，不复制到系统目录）
-- 功能：处理系统管理相关的API请求，如配置重载、系统状态等

local api_utils = require "api.utils"
local cjson = require "cjson"
local path_utils = require "waf.path_utils"
local audit_log = require "waf.audit_log"
local config_manager = require "waf.config_manager"

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

-- 管理端 SSL 文件名清理（用于生成证书/配置文件名）
local function sanitize_filename(name)
    if not name or name == "" then
        return "default"
    end
    -- 使用小写，并将非法字符替换为下划线，避免路径和Nginx语法问题
    name = tostring(name):lower()
    name = name:gsub("[^a-z0-9._%-]", "_")
    name = name:gsub("_+", "_")
    return name
end

-- 写入/更新管理端 SSL 相关文件
-- 参数：
--   enabled: 0/1
--   server_name: 管理端域名（可包含多个域名，用空格分隔）
--   ssl_pem, ssl_key: 证书/私钥内容（PEM/KEY）
local function write_admin_ssl_files(enabled, server_name, ssl_pem, ssl_key, force_https)
    local project_root = path_utils.get_project_root()
    if not project_root or project_root == "" then
        return false, "无法获取项目根目录（project_root）"
    end

    -- 目标目录：证书目录 & vhost_conf 目录
    local cert_dir = project_root .. "/conf.d/cert"
    local vhost_dir = project_root .. "/conf.d/vhost_conf"

    if not path_utils.ensure_dir(cert_dir) then
        return false, "无法创建管理端SSL证书目录: " .. cert_dir
    end
    if not path_utils.ensure_dir(vhost_dir) then
        return false, "无法创建管理端vhost目录: " .. vhost_dir
    end

    local admin_conf_path = vhost_dir .. "/waf_admin_ssl.conf"

    -- 如果未启用 SSL，则写入一个占位配置文件，仅包含注释，避免 include 报错
    enabled = tonumber(enabled) or 0
    if enabled ~= 1 then
        local f, err = io.open(admin_conf_path, "w")
        if not f then
            return false, "写入管理端SSL配置文件失败: " .. (err or "unknown error")
        end
        f:write("# 管理端未启用HTTPS（由系统设置关闭）\n")
        f:write("# 如需启用，请在系统设置中开启管理端SSL，并配置证书与域名。\n")
        f:close()
        return true
    end

    -- 启用 SSL 时必须有 server_name / 证书 / 私钥
    if not server_name or server_name == "" then
        return false, "启用管理端HTTPS时，域名(server_name)不能为空"
    end
    if not ssl_pem or ssl_pem == "" then
        return false, "启用管理端HTTPS时，SSL证书内容不能为空"
    end
    if not ssl_key or ssl_key == "" then
        return false, "启用管理端HTTPS时，SSL私钥内容不能为空"
    end

    -- 取第一个域名用于文件名，避免空格等字符
    local first_domain = server_name:match("^%s*([^%s]+)")
    local server_name_for_file = first_domain or server_name
    local server_name_safe = sanitize_filename(server_name_for_file)
    if not server_name_safe or server_name_safe == "" then
        server_name_safe = "admin"
    end

    local cert_filename = "admin_" .. server_name_safe .. ".pem"
    local key_filename  = "admin_" .. server_name_safe .. ".key"
    local cert_path = cert_dir .. "/" .. cert_filename
    local key_path  = cert_dir .. "/" .. key_filename

    -- 写入证书文件
    local cert_file, cerr = io.open(cert_path, "w")
    if not cert_file then
        return false, "写入管理端SSL证书文件失败: " .. (cerr or "unknown error")
    end
    cert_file:write(ssl_pem)
    cert_file:close()

    -- 写入私钥文件
    local key_file, kerr = io.open(key_path, "w")
    if not key_file then
        return false, "写入管理端SSL私钥文件失败: " .. (kerr or "unknown error")
    end
    key_file:write(ssl_key)
    key_file:close()

    -- 写入管理端 server 的附加 SSL 配置（由 waf.conf 动态 include）
    local conf, ferr = io.open(admin_conf_path, "w")
    if not conf then
        return false, "写入管理端SSL配置文件失败: " .. (ferr or "unknown error")
    end

    -- 这里的指令会被直接插入 waf.conf 的 server 块中
    conf:write("# 本文件由系统设置自动生成，请勿手工修改\n")
    conf:write("# 管理端 HTTPS 配置\n")
    conf:write("    listen 443 ssl;\n")
    conf:write("    server_name " .. server_name .. ";\n")
    conf:write("    ssl_certificate     " .. cert_path .. ";\n")
    conf:write("    ssl_certificate_key " .. key_path .. ";\n")
    conf:write("    ssl_protocols TLSv1.2 TLSv1.3;\n")
    conf:write("    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';\n")
    conf:write("    ssl_prefer_server_ciphers off;\n")
    conf:write("    ssl_session_cache shared:SSL:10m;\n")
    conf:write("    ssl_session_timeout 10m;\n")
    conf:close()

    return true
end

-- 更新 waf.conf 中的管理端 SSL 相关配置：
-- 1. 根据 enabled 决定是否插入 include waf_admin_ssl.conf 行
-- 2. 当启用 SSL 时，更新 server_name 为传入的域名
-- 3. 当 force_https=1 时，在 waf.conf 中插入 HTTP→HTTPS 强制跳转配置；force_https=0 时移除
local function update_waf_conf_for_admin_ssl(enabled, server_name, force_https)
    local project_root = path_utils.get_project_root()
    if not project_root or project_root == "" then
        return false, "无法获取项目根目录（project_root）"
    end

    local waf_conf_path = project_root .. "/conf.d/vhost_conf/waf.conf"
    local f, err = io.open(waf_conf_path, "r")
    if not f then
        return false, "读取 waf.conf 失败: " .. (err or "unknown error")
    end
    local content = f:read("*all")
    f:close()
    if not content or content == "" then
        return false, "waf.conf 内容为空"
    end

    enabled = tonumber(enabled) or 0
    local force_num = tonumber(force_https or 0) or 0

    -- 1) 始终先移除所有可能的 SSL 配置残留（无论格式如何）
    -- 1.1) 移除 include waf_admin_ssl.conf 行（支持各种格式和缩进）
    content = content:gsub("\n%s*include%s+%$project_root/conf%.d/vhost_conf/waf_admin_ssl%.conf;%s*\n", "\n")
    content = content:gsub("\n%s*include%s+%$project_root/conf%.d/vhost_conf/waf_admin_ssl%.conf;%s*", "\n")
    -- 1.2) 移除直接写在 waf.conf 中的 listen 443 ssl 行（如果存在）
    content = content:gsub("\n%s*listen%s+443%s+ssl;%s*\n", "\n")
    content = content:gsub("\n%s*listen%s+443%s+ssl%s*;%s*", "\n")
    -- 1.3) 移除直接写在 waf.conf 中的 ssl_certificate 相关行（如果存在）
    content = content:gsub("\n%s*ssl_certificate%s+.-;%s*\n", "\n")
    content = content:gsub("\n%s*ssl_certificate_key%s+.-;%s*\n", "\n")
    content = content:gsub("\n%s*ssl_protocols%s+.-;%s*\n", "\n")
    content = content:gsub("\n%s*ssl_ciphers%s+.-;%s*\n", "\n")
    content = content:gsub("\n%s*ssl_prefer_server_ciphers%s+.-;%s*\n", "\n")
    content = content:gsub("\n%s*ssl_session_cache%s+.-;%s*\n", "\n")
    content = content:gsub("\n%s*ssl_session_timeout%s+.-;%s*\n", "\n")

    -- 2) 如果启用 SSL，则插入 include 行
    if enabled == 1 then
        local include_line = "    include $project_root/conf.d/vhost_conf/waf_admin_ssl.conf;\n"
        local replaced = false
        -- 优先插在 server_name 行之后
        local new_content, n = content:gsub("(server_name%s+.-;%s*\n)", "%1" .. include_line, 1)
        if n > 0 then
            content = new_content
            replaced = true
        end
        if not replaced then
            -- 退而求其次：插在 listen 80; 之后
            new_content, n = content:gsub("(listen%s+80%s*;%s*\n)", "%1" .. include_line, 1)
            if n > 0 then
                content = new_content
                replaced = true
            end
        end
        if not replaced then
            -- 再不行就追加在 server 块末尾（理论上不会走到这里）
            content = content:gsub("(%s*}%s*)$", "\n" .. include_line .. "%1")
        end
    end

    -- 3) 启用 SSL 时，如果提供了域名，则更新 server_name 行（仅更新第一处）
    if enabled == 1 and server_name and server_name ~= "" then
        local new_line = "    server_name  " .. server_name .. ";"
        local new_content, n = content:gsub("server_name%s+.-;", new_line, 1)
        if n > 0 then
            content = new_content
        end
    end

    -- 4) 处理强制跳转配置：先移除旧的标记块
    content = content:gsub("\n%s*# 管理端 HTTPS 强制跳转开始（自动生成，请勿手工修改）.-# 管理端 HTTPS 强制跳转结束%s*\n", "\n")

    if enabled == 1 and force_num == 1 then
        local redirect_block = [[

    # 管理端 HTTPS 强制跳转开始（自动生成，请勿手工修改）
    if ($scheme = http) {
        return 301 https://$host$request_uri;
    }
    # 管理端 HTTPS 强制跳转结束
]]
        -- 将重定向块插入到 charset utf-8; 之后，保持结构清晰
        local new_content, n = content:gsub("(charset%s+utf%-8;%s*\n)", "%1" .. redirect_block .. "\n", 1)
        if n > 0 then
            content = new_content
        else
            -- 如果找不到 charset 行，则直接在 server 块中追加
            content = content:gsub("(%s*}%s*)$", redirect_block .. "%1")
        end
    end

    local wf, werr = io.open(waf_conf_path, "w")
    if not wf then
        return false, "写入 waf.conf 失败: " .. (werr or "unknown error")
    end
    wf:write(content)
    wf:close()

    return true
end

-- 查找OpenResty/Nginx可执行文件（可移植性实现）
-- 注意：优先查找 openresty，然后才是 nginx（因为项目使用的是 OpenResty）
-- 注意：在 timer 上下文中，io.popen() 可能受限，因此优先使用直接执行命令的方式
local function find_openresty_binary()
    -- 1. 优先从环境变量获取（最高优先级）
    local nginx_binary_env = os.getenv("NGINX_BINARY")
    if nginx_binary_env and nginx_binary_env ~= "" then
        if is_executable(nginx_binary_env) then
            ngx.log(ngx.INFO, "从NGINX_BINARY环境变量找到OpenResty可执行文件: ", nginx_binary_env)
            return nginx_binary_env
        else
            ngx.log(ngx.DEBUG, "NGINX_BINARY环境变量指定的路径不可执行: ", nginx_binary_env)
        end
    end
    
    -- 2. 从 OPENRESTY_PREFIX 环境变量构建路径（优先 OpenResty）
    --    注意：在 ngx.timer 等受限环境中，is_executable() 可能返回 false，
    --    但通过 deploy.sh 已保证 OPENRESTY_PREFIX 指向有效安装目录，
    --    因此对于 primary 路径（$OPENRESTY_PREFIX/bin/openresty），在校验失败时也直接信任返回。
    local openresty_prefix = os.getenv("OPENRESTY_PREFIX")
    if openresty_prefix and openresty_prefix ~= "" then
        local primary = openresty_prefix .. "/bin/openresty"
        if is_executable(primary) then
            ngx.log(ngx.INFO, "从OPENRESTY_PREFIX环境变量找到OpenResty可执行文件: ", primary)
            return primary
        else
            -- 在 timer 上下文中 test -x/-v 可能受限，这里直接信任 primary 路径
            ngx.log(ngx.INFO, "从OPENRESTY_PREFIX环境变量使用OpenResty可执行文件（未完整验证）: ", primary)
            return primary
        end
        -- 次要候选路径保持原有严格校验（一般用于兼容特殊安装方式）
        -- local secondary = openresty_prefix .. "/nginx/sbin/nginx"
        -- if is_executable(secondary) then
        --     ngx.log(ngx.INFO, "从OPENRESTY_PREFIX环境变量找到OpenResty可执行文件(nginx): ", secondary)
        --     return secondary
        -- end
    end
    
    -- 3. 尝试使用 which 命令查找（优先 openresty）
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
                ngx.log(ngx.INFO, "通过which命令找到OpenResty可执行文件: ", which_path)
                return which_path
            end
        end
    else
        ngx.log(ngx.DEBUG, "无法使用which命令查找OpenResty可执行文件（可能在timer上下文中受限）")
    end
    
    -- 4. 尝试常见的默认安装路径（按优先级排序，优先 OpenResty）
    -- 注意：/usr/local/openresty/bin/openresty 是最常见的OpenResty安装路径
    -- 在 timer 上下文中，test -x/-v 可能失败，但路径依然可用，因此对该路径放宽校验
    local default_paths = {
        "/usr/local/openresty/bin/openresty",  -- 最常见的OpenResty安装路径（最高优先级）
        "/usr/local/bin/openresty",
        "/usr/bin/openresty",
        "/opt/openresty/bin/openresty",
        "/usr/local/openresty/nginx/sbin/nginx",  -- OpenResty 内置的 nginx
        "/usr/local/nginx/sbin/nginx",  -- 独立的 nginx（兼容性）
        "/usr/sbin/nginx",
        "/usr/bin/nginx"
    }
    for _, path in ipairs(default_paths) do
        if is_executable(path) then
            ngx.log(ngx.INFO, "从默认路径找到OpenResty可执行文件: ", path)
            return path
        elseif path == "/usr/local/openresty/bin/openresty" then
            -- 在 timer 等受限环境中，is_executable 可能无法可靠工作，但该路径是本项目最常见安装位置
            -- 如果前面的所有检查都失败，这里直接信任该路径，避免误报“未找到可执行文件”
            ngx.log(ngx.INFO, "使用默认OpenResty路径（未完整验证）: ", path)
            return path
        end
    end
    
    -- 5. 如果都找不到，返回nil（由调用者处理错误）
    ngx.log(ngx.WARN, "无法找到OpenResty可执行文件，已尝试所有可能的路径")
    ngx.log(ngx.WARN, "请设置NGINX_BINARY或OPENRESTY_PREFIX环境变量，或确保openresty安装在默认路径")
    return nil
end

-- 内部函数：执行OpenResty重载（返回结果，不发送HTTP响应）
local function do_reload_nginx()
    -- 查找OpenResty可执行文件
    -- 注意：在 timer 上下文中，可能需要多次尝试或使用不同的方法
    local openresty_binary = find_openresty_binary()
    
    if not openresty_binary then
        -- 如果找不到，尝试直接使用最常见的路径（即使 is_executable 失败）
        -- 因为在实际执行命令时可能可以工作
        local fallback_path = "/usr/local/openresty/bin/openresty"
        ngx.log(ngx.WARN, "无法通过检查找到OpenResty可执行文件，尝试使用默认路径: ", fallback_path)
        openresty_binary = fallback_path
    end
    
    ngx.log(ngx.INFO, "使用OpenResty可执行文件: ", openresty_binary)
    
    -- 第一步：执行OpenResty配置测试（必须先测试，确保配置正确）
    -- 注意：在 timer 上下文中，worker 进程以 waf 用户运行，可能没有权限访问系统日志目录
    -- 使用 -e 选项指定错误日志到 /dev/null，避免权限问题
    -- 注意：-t 测试时不需要 PID 文件，所以不需要使用 -g 选项
    -- 命令格式：/usr/local/openresty/bin/openresty -t -e /dev/null
    ngx.log(ngx.INFO, "开始测试OpenResty配置，执行命令: ", openresty_binary, " -t")
    
    -- 使用临时错误日志，避免权限问题
    -- 注意：即使有权限错误（如无法写入日志文件），只要配置语法正确，-t 测试仍然可以通过
    local test_cmd = openresty_binary .. " -t -e /dev/null 2>&1"
    local test_result = io.popen(test_cmd)
    if not test_result then
        local error_msg = "无法执行OpenResty配置测试命令: " .. test_cmd .. " (可能在timer上下文中受限)"
        ngx.log(ngx.ERR, error_msg)
        return false, error_msg
    end
    
    local test_output = test_result:read("*all")
    local test_code = test_result:close()
    
    if test_code ~= 0 then
        -- 检查输出中是否包含 "syntax is ok"（即使有权限错误，语法正确也算通过）
        if test_output and test_output:match("syntax is ok") then
            -- 配置语法正确，即使有权限警告也可以继续
            ngx.log(ngx.WARN, "OpenResty配置语法正确，但可能存在权限警告: ", test_output)
            -- 继续执行重载，因为 reload 命令本身也会测试配置
        elseif test_output and (test_output:match("Permission denied") or test_output:match("13:")) then
            -- 如果是权限问题，尝试不使用临时文件，直接测试
            ngx.log(ngx.WARN, "配置测试因权限问题失败，尝试直接测试配置语法...")
            local simple_test_cmd = openresty_binary .. " -t -q 2>&1"
            local simple_test_result = io.popen(simple_test_cmd)
            if simple_test_result then
                local simple_test_output = simple_test_result:read("*all")
                local simple_test_code = simple_test_result:close()
                -- 检查输出中是否包含 "syntax is ok"
                if simple_test_code == 0 or (simple_test_output and simple_test_output:match("syntax is ok")) then
                    -- 语法测试通过，但可能因为权限问题无法完全测试
                    ngx.log(ngx.WARN, "配置语法测试通过，但可能存在权限问题，将尝试直接重载")
                    -- 继续执行重载，因为 reload 命令本身也会测试配置
                else
                    local error_msg = "OpenResty配置测试失败: " .. (simple_test_output or "unknown error")
                    ngx.log(ngx.ERR, error_msg, " (命令: ", simple_test_cmd, ")")
                    return false, error_msg
                end
            else
                local error_msg = "OpenResty配置测试失败（权限问题）: " .. (test_output or "unknown error")
                ngx.log(ngx.ERR, error_msg, " (命令: ", test_cmd, ")")
                return false, error_msg
            end
        else
            -- 真正的配置错误
            local error_msg = "OpenResty配置测试失败: " .. (test_output or "unknown error")
            ngx.log(ngx.ERR, error_msg, " (命令: ", test_cmd, ")")
            return false, error_msg
        end
    else
        ngx.log(ngx.INFO, "OpenResty配置测试通过: ", test_output or "success")
    end
    
    -- 第二步：执行OpenResty配置重新加载（测试通过后才重载）
    -- 说明：
    -- 1）现在 OpenResty 的 master/worker 已通过 systemd 配置为 waf 用户运行
    -- 2）/usr/local/openresty/nginx/logs 目录的权限也已在 deploy.sh 中调整为 waf:waf
    -- 3）因此在 waf 用户上下文中直接执行 openresty_binary -s reload 即可安全向 master 发送重载信号
    ngx.log(ngx.INFO, "开始重新加载OpenResty配置，直接执行命令: ", openresty_binary, " -s reload")

    local direct_reload_cmd = openresty_binary .. " -s reload 2>&1"
    local direct_reload_result = io.popen(direct_reload_cmd)
    if not direct_reload_result then
        local error_msg = "无法执行OpenResty重载命令: " .. direct_reload_cmd .. " (可能在timer上下文中受限)"
        ngx.log(ngx.ERR, error_msg)
        return false, error_msg
    end

    local direct_reload_output = direct_reload_result:read("*all")
    -- LuaJIT / Lua 5.1 的 io.popen():close() 可能返回多值：ok, reason, code
    local ok1, reason, code = direct_reload_result:close()

    -- 统一判断退出是否成功：
    -- 1）如果 ok1 是 boolean，则 true 视为成功
    -- 2）如果 ok1 是 number，则 0 视为成功
    -- 3）如果 ok1 为 nil 但 reason/code 为空，一般也可以视为成功（兼容性处理）
    local success = false
    if type(ok1) == "boolean" then
        success = ok1
    elseif type(ok1) == "number" then
        success = (ok1 == 0)
    else
        -- 某些实现可能只返回 nil，reason="exit", code=0
        if type(code) == "number" then
            success = (code == 0)
        else
            success = true
        end
    end

    if success then
        ngx.log(ngx.INFO, "OpenResty配置重新加载成功（直接执行）: ", direct_reload_output or "success")
        return true, direct_reload_output
    else
        local error_msg = "OpenResty配置重新加载失败: " .. (direct_reload_output or "unknown error")
        ngx.log(ngx.ERR, error_msg, " (命令: ", direct_reload_cmd, ", close 返回: ", tostring(ok1), ", ", tostring(reason), ", ", tostring(code), ")")
        return false, error_msg
    end
end

-- 触发OpenResty配置重新加载（API接口）
function _M.reload_nginx()
    local ok, result = do_reload_nginx()
    if not ok then
        -- 记录审计日志（失败）
        audit_log.log_system_action("reload_nginx", "重新加载OpenResty配置", false, result)
        api_utils.json_response({
            success = false,
            error = result
        }, 500)
        return
    end
    
    -- 记录审计日志（成功）
    audit_log.log_system_action("reload_nginx", "重新加载OpenResty配置", true, nil)
    
    api_utils.json_response({
        success = true,
        message = "OpenResty配置重新加载成功",
        output = result
    })
end

-- 触发OpenResty配置重新加载（内部调用，返回结果）
function _M.reload_nginx_internal()
    return do_reload_nginx()
end

-- 测试OpenResty配置
function _M.test_nginx_config()
    -- 查找OpenResty可执行文件
    local openresty_binary = find_openresty_binary()
    
    if not openresty_binary then
        api_utils.json_response({
            success = false,
            error = "未找到OpenResty可执行文件，请设置NGINX_BINARY或OPENRESTY_PREFIX环境变量"
        }, 500)
        return
    end
    
    -- 执行OpenResty配置测试（使用 -e /dev/null 避免权限问题）
    local test_cmd = openresty_binary .. " -t -e /dev/null"
    local test_result = io.popen(test_cmd)
    local test_output = test_result:read("*all")
    local test_code = test_result:close()
    
    if test_code ~= 0 then
        -- 记录审计日志（失败）
        audit_log.log_system_action("test_nginx_config", "测试OpenResty配置", false, test_output)
        api_utils.json_response({
            success = false,
            error = "OpenResty配置测试失败",
            details = test_output
        }, 400)
        return
    end
    
    -- 记录审计日志（成功）
    audit_log.log_system_action("test_nginx_config", "测试OpenResty配置", true, nil)
    
    api_utils.json_response({
        success = true,
        message = "OpenResty配置测试通过",
        output = test_output
    })
end

-- 获取管理端 SSL 与域名配置
function _M.get_admin_ssl_config()
    -- 从waf_system_config表读取配置
    local enabled = config_manager.get_config("admin_ssl_enable", "0")
    local server_name = config_manager.get_config("admin_server_name", "localhost")
    local ssl_pem = config_manager.get_config("admin_ssl_pem", "")
    local ssl_key = config_manager.get_config("admin_ssl_key", "")
    local force_https = config_manager.get_config("admin_force_https", "0")

    api_utils.json_response({
        success = true,
        data = {
            ssl_enable = tonumber(enabled) or 0,
            server_name = server_name or "",
            ssl_pem = ssl_pem or "",
            ssl_key = ssl_key or "",
            force_https = tonumber(force_https) or 0
        }
    })
end

-- 更新管理端 SSL 与域名配置
function _M.update_admin_ssl_config()
    if ngx.req.get_method() ~= "POST" then
        api_utils.json_response({ error = "Method not allowed" }, 405)
        return
    end

    -- 读取请求体（必须在解析参数之前）
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    
    -- 手动解析URL编码的body（处理包含换行符的长文本，如SSL证书）
    local args = {}
    if body then
        local content_type = ngx.req.get_headers()["Content-Type"] or ""
        if content_type:match("application/x-www-form-urlencoded") then
            -- 手动解析URL编码的body，支持包含换行符的长文本
            -- 注意：URL编码的body格式为 key1=value1&key2=value2&...
            -- 对于包含换行符的长文本，value会被URL编码，需要正确解析
            local pos = 1
            while pos <= #body do
                local key_start = pos
                local key_end = body:find("=", key_start)
                if not key_end then
                    break
                end
                local key = body:sub(key_start, key_end - 1)
                local value_start = key_end + 1
                local value_end = body:find("&", value_start)
                if not value_end then
                    value_end = #body + 1
                end
                local value = body:sub(value_start, value_end - 1)
                
                -- URL解码
                key = ngx.unescape_uri(key)
                value = ngx.unescape_uri(value)
                
                -- 存储参数（如果key已存在，取第一个值）
                if not args[key] then
                    args[key] = value
                end
                
                pos = value_end + 1
            end
        else
            -- 非form-urlencoded格式，使用标准get_args
            args = api_utils.get_args()
        end
    else
        -- 如果没有body，使用标准get_args
        args = api_utils.get_args()
    end
    
    -- 调试日志：记录接收到的参数（不记录敏感信息，只记录长度）
    local arg_info = {}
    for k, v in pairs(args) do
        if type(v) == "string" then
            arg_info[#arg_info + 1] = k .. "(" .. #v .. " chars)"
        else
            arg_info[#arg_info + 1] = k .. "(" .. type(v) .. ")"
        end
    end
    ngx.log(ngx.INFO, "update_admin_ssl_config: received args: ", table.concat(arg_info, ", "))
    
    local ssl_enable = args.ssl_enable
    local server_name = args.server_name or ""
    local ssl_pem = args.ssl_pem or ""
    local ssl_key = args.ssl_key or ""
    local force_https = args.force_https or args.admin_force_https
    
    -- 如果参数为空，尝试从URI参数获取（兼容性处理）
    if not ssl_enable then
        local uri_args = ngx.req.get_uri_args()
        ssl_enable = uri_args.ssl_enable
        if not server_name or server_name == "" then
            server_name = uri_args.server_name or ""
        end
        if not ssl_pem or ssl_pem == "" then
            ssl_pem = uri_args.ssl_pem or ""
        end
        if not ssl_key or ssl_key == "" then
            ssl_key = uri_args.ssl_key or ""
        end
        if not force_https then
            force_https = uri_args.force_https or uri_args.admin_force_https
        end
    end

    if ssl_enable == nil then
        api_utils.json_response({ error = "ssl_enable 参数不能为空" }, 400)
        return
    end

    local enable_num = tonumber(ssl_enable)
    if enable_num ~= 0 and enable_num ~= 1 then
        api_utils.json_response({ error = "ssl_enable 参数必须是0或1" }, 400)
        return
    end

    local force_num = tonumber(force_https or 0)
    if force_num ~= 0 and force_num ~= 1 then
        api_utils.json_response({ error = "force_https 参数必须是0或1" }, 400)
        return
    end

    -- 启用 SSL 时做严格校验
    if enable_num == 1 then
        if not server_name or server_name == "" then
            api_utils.json_response({ error = "启用管理端HTTPS时，必须配置管理端域名" }, 400)
            return
        end
        if not ssl_pem or ssl_pem == "" then
            api_utils.json_response({ error = "启用管理端HTTPS时，必须填写SSL证书（PEM内容）" }, 400)
            return
        end
        if not ssl_key or ssl_key == "" then
            api_utils.json_response({ error = "启用管理端HTTPS时，必须填写SSL私钥（KEY内容）" }, 400)
            return
        end
    end
    
    -- 调试日志：记录接收到的参数（不记录敏感信息，只记录长度）
    ngx.log(ngx.INFO, "update_admin_ssl_config: ssl_enable=", tostring(ssl_enable), 
            ", server_name=", server_name and #server_name or 0, " chars",
            ", ssl_pem=", ssl_pem and #ssl_pem or 0, " chars",
            ", ssl_key=", ssl_key and #ssl_key or 0, " chars",
            ", force_https=", tostring(force_https))

    -- 先写入数据库配置（确保状态持久化）
    ngx.log(ngx.INFO, "update_admin_ssl_config: 开始写入数据库配置...")
    
    local ok1, err1 = config_manager.set_config("admin_ssl_enable", enable_num, "是否为管理端启用HTTPS（1-启用，0-禁用）")
    if not ok1 then
        ngx.log(ngx.ERR, "update_admin_ssl_config: 更新 admin_ssl_enable 失败: ", tostring(err1))
        api_utils.json_response({ error = "更新 admin_ssl_enable 失败: " .. tostring(err1) }, 500)
        return
    end
    ngx.log(ngx.INFO, "update_admin_ssl_config: admin_ssl_enable 更新成功")

    local ok2, err2 = config_manager.set_config("admin_server_name", server_name, "管理端访问域名（例如：waf-admin.example.com，多域名请用空格分隔）")
    if not ok2 then
        ngx.log(ngx.ERR, "update_admin_ssl_config: 更新 admin_server_name 失败: ", tostring(err2))
        api_utils.json_response({ error = "更新 admin_server_name 失败: " .. tostring(err2) }, 500)
        return
    end
    ngx.log(ngx.INFO, "update_admin_ssl_config: admin_server_name 更新成功 (", #server_name, " chars)")

    local ok3, err3 = config_manager.set_config("admin_ssl_pem", ssl_pem, "管理端SSL证书内容（PEM格式）")
    if not ok3 then
        ngx.log(ngx.ERR, "update_admin_ssl_config: 更新 admin_ssl_pem 失败: ", tostring(err3))
        api_utils.json_response({ error = "更新 admin_ssl_pem 失败: " .. tostring(err3) }, 500)
        return
    end
    ngx.log(ngx.INFO, "update_admin_ssl_config: admin_ssl_pem 更新成功 (", #ssl_pem, " chars)")

    local ok4, err4 = config_manager.set_config("admin_ssl_key", ssl_key, "管理端SSL私钥内容（KEY格式）")
    if not ok4 then
        ngx.log(ngx.ERR, "update_admin_ssl_config: 更新 admin_ssl_key 失败: ", tostring(err4))
        api_utils.json_response({ error = "更新 admin_ssl_key 失败: " .. tostring(err4) }, 500)
        return
    end
    ngx.log(ngx.INFO, "update_admin_ssl_config: admin_ssl_key 更新成功 (", #ssl_key, " chars)")

    local ok5, err5 = config_manager.set_config("admin_force_https", force_num, "是否强制将管理端HTTP重定向到HTTPS（1-开启，0-关闭）")
    if not ok5 then
        ngx.log(ngx.ERR, "update_admin_ssl_config: 更新 admin_force_https 失败: ", tostring(err5))
        api_utils.json_response({ error = "更新 admin_force_https 失败: " .. tostring(err5) }, 500)
        return
    end
    ngx.log(ngx.INFO, "update_admin_ssl_config: admin_force_https 更新成功")

    -- 写入/更新实际的证书文件与 waf_admin_ssl.conf
    ngx.log(ngx.INFO, "update_admin_ssl_config: 开始写入SSL文件...")
    local ok_files, err_files = write_admin_ssl_files(enable_num, server_name, ssl_pem, ssl_key, force_num)
    if not ok_files then
        ngx.log(ngx.ERR, "update_admin_ssl_config: 写入管理端SSL文件失败: ", tostring(err_files))
        api_utils.json_response({ error = "写入管理端SSL文件失败: " .. tostring(err_files) }, 500)
        return
    end
    ngx.log(ngx.INFO, "update_admin_ssl_config: SSL文件写入成功")

    -- 同步更新 waf.conf 中的 include 与强制跳转配置
    ngx.log(ngx.INFO, "update_admin_ssl_config: 开始更新waf.conf...")
    local ok_waf, err_waf = update_waf_conf_for_admin_ssl(enable_num, server_name, force_num)
    if not ok_waf then
        ngx.log(ngx.ERR, "update_admin_ssl_config: 更新waf.conf失败: ", tostring(err_waf))
        api_utils.json_response({ error = "更新 waf.conf 失败: " .. tostring(err_waf) }, 500)
        return
    end
    ngx.log(ngx.INFO, "update_admin_ssl_config: waf.conf更新成功")

    -- 记录审计日志
    local action_desc = enable_num == 1 and ("启用管理端HTTPS，域名: " .. server_name) or "关闭管理端HTTPS"
    audit_log.log_system_action("update_admin_ssl", "更新管理端HTTPS配置", true, action_desc)

    -- 异步触发 nginx 重载（避免阻塞当前请求）
    ngx.timer.at(0, function()
        local ok_reload, result = _M.reload_nginx_internal()
        if not ok_reload then
            ngx.log(ngx.WARN, "更新管理端HTTPS配置后自动触发nginx重载失败: ", result or "unknown error")
        else
            ngx.log(ngx.INFO, "更新管理端HTTPS配置后自动触发nginx重载成功")
        end
    end)

    api_utils.json_response({
        success = true,
        message = "管理端HTTPS配置已更新，nginx配置正在重新加载",
        data = {
            ssl_enable = enable_num,
            server_name = server_name
        }
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
