-- Nginx配置生成器模块
-- 路径：项目目录下的 lua/waf/nginx_config_generator.lua（保持在项目目录，不复制到系统目录）
-- 功能：根据数据库中的代理配置自动生成nginx配置文件

local mysql_pool = require "waf.mysql_pool"
local path_utils = require "waf.path_utils"
local cjson = require "cjson"

local _M = {}

-- 转义nginx配置值（防止注入攻击）
local function escape_nginx_value(value)
    if not value then
        return ""
    end
    -- 转义特殊字符
    value = tostring(value)
    value = value:gsub(";", "\\;")
    value = value:gsub("\\", "\\\\")
    value = value:gsub("\"", "\\\"")
    value = value:gsub("'", "\\'")
    value = value:gsub("\n", " ")
    value = value:gsub("\r", " ")
    return value
end

-- 生成upstream配置
local function generate_upstream_config(proxy, backends)
    if not backends or #backends == 0 then
        return ""
    end
    
    local upstream_name = "upstream_" .. proxy.id
    local config = "upstream " .. upstream_name .. " {\n"
    
    -- 负载均衡算法
    if proxy.load_balance == "least_conn" then
        config = config .. "    least_conn;\n"
    elseif proxy.load_balance == "ip_hash" then
        config = config .. "    ip_hash;\n"
    end
    
    -- 后端服务器
    for _, backend in ipairs(backends) do
        if backend.status == 1 then
            local server_line = "    server " .. escape_nginx_value(backend.backend_address) .. ":" .. backend.backend_port
            if backend.weight and backend.weight > 1 then
                server_line = server_line .. " weight=" .. backend.weight
            end
            if backend.max_fails then
                server_line = server_line .. " max_fails=" .. backend.max_fails
            end
            if backend.fail_timeout then
                server_line = server_line .. " fail_timeout=" .. backend.fail_timeout .. "s"
            end
            if backend.backup == 1 then
                server_line = server_line .. " backup"
            end
            if backend.down == 1 then
                server_line = server_line .. " down"
            end
            server_line = server_line .. ";\n"
            config = config .. server_line
        end
    end
    
    -- Keepalive配置（HTTP代理）
    if proxy.proxy_type == "http" then
        config = config .. "    keepalive 1024;\n"
        config = config .. "    keepalive_requests 10000;\n"
        config = config .. "    keepalive_timeout 60s;\n"
    end
    
    config = config .. "}\n\n"
    return config, upstream_name
end

-- 生成HTTP server块配置
local function generate_http_server_config(proxy, upstream_name)
    local config = "# ============================================\n"
    config = config .. "# 代理配置: " .. escape_nginx_value(proxy.proxy_name) .. " (ID: " .. proxy.id .. ")\n"
    config = config .. "# 自动生成，请勿手动修改\n"
    config = config .. "# ============================================\n\n"
    config = config .. "server {\n"
    
    -- 监听端口
    local listen_line = "    listen       " .. proxy.listen_port
    if proxy.ssl_enable == 1 then
        listen_line = listen_line .. " ssl"
        if proxy.ssl_cert_path and proxy.ssl_key_path then
            listen_line = listen_line .. " http2"
        end
    end
    listen_line = listen_line .. ";\n"
    config = config .. listen_line
    
    -- 服务器名称
    if proxy.server_name then
        config = config .. "    server_name  " .. escape_nginx_value(proxy.server_name) .. ";\n"
    end
    
    -- 字符集
    config = config .. "    charset utf-8;\n"
    
    -- 客户端请求体大小
    config = config .. "    client_max_body_size 10m;\n"
    
    -- SSL配置
    if proxy.ssl_enable == 1 and proxy.ssl_cert_path and proxy.ssl_key_path then
        config = config .. "\n    # SSL配置\n"
        config = config .. "    ssl_certificate     " .. escape_nginx_value(proxy.ssl_cert_path) .. ";\n"
        config = config .. "    ssl_certificate_key " .. escape_nginx_value(proxy.ssl_key_path) .. ";\n"
        config = config .. "    ssl_protocols TLSv1.2 TLSv1.3;\n"
        config = config .. "    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';\n"
        config = config .. "    ssl_prefer_server_ciphers off;\n"
        config = config .. "    ssl_session_cache shared:SSL:10m;\n"
        config = config .. "    ssl_session_timeout 10m;\n"
    end
    
    -- WAF封控检查（如果关联了防护规则）
    if proxy.ip_rule_id then
        config = config .. "\n    # WAF封控检查（关联防护规则ID: " .. proxy.ip_rule_id .. "）\n"
        config = config .. "    access_by_lua_block {\n"
        config = config .. "        require(\"waf.ip_block\").check()\n"
        config = config .. "    }\n"
    end
    
    -- 日志采集
    config = config .. "\n    # 日志采集\n"
    config = config .. "    log_by_lua_block {\n"
    config = config .. "        require(\"waf.log_collect\").collect()\n"
    config = config .. "    }\n"
    
    -- Location配置
    config = config .. "\n    location " .. escape_nginx_value(proxy.location_path or "/") .. " {\n"
    
    -- 代理到后端
    if proxy.backend_type == "upstream" and upstream_name then
        config = config .. "        proxy_pass http://" .. upstream_name .. ";\n"
    else
        local backend_url = "http://" .. escape_nginx_value(proxy.backend_address)
        if proxy.backend_port then
            backend_url = backend_url .. ":" .. proxy.backend_port
        end
        config = config .. "        proxy_pass " .. backend_url .. ";\n"
    end
    
    -- 请求头设置
    config = config .. "\n        # 请求头设置\n"
    config = config .. "        proxy_set_header Host $host;\n"
    config = config .. "        proxy_set_header X-Real-IP $remote_addr;\n"
    config = config .. "        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n"
    config = config .. "        proxy_set_header X-Forwarded-Proto $scheme;\n"
    config = config .. "        proxy_set_header Connection \"\";\n"
    
    -- HTTP版本
    config = config .. "\n        # HTTP版本\n"
    config = config .. "        proxy_http_version 1.1;\n"
    
    -- 超时设置
    config = config .. "\n        # 超时设置\n"
    if proxy.proxy_connect_timeout then
        config = config .. "        proxy_connect_timeout " .. proxy.proxy_connect_timeout .. "s;\n"
    end
    if proxy.proxy_send_timeout then
        config = config .. "        proxy_send_timeout " .. proxy.proxy_send_timeout .. "s;\n"
    end
    if proxy.proxy_read_timeout then
        config = config .. "        proxy_read_timeout " .. proxy.proxy_read_timeout .. "s;\n"
    end
    
    config = config .. "    }\n"
    
    -- 禁止访问隐藏文件
    config = config .. "\n    # 禁止访问隐藏文件\n"
    config = config .. "    location ~ /\\. {\n"
    config = config .. "        deny all;\n"
    config = config .. "        access_log off;\n"
    config = config .. "    }\n"
    
    config = config .. "}\n\n"
    return config
end

-- 生成TCP/UDP stream upstream配置
local function generate_stream_upstream_config(proxy, backends)
    if not backends or #backends == 0 then
        return ""
    end
    
    local upstream_name = "stream_upstream_" .. proxy.id
    local config = "upstream " .. upstream_name .. " {\n"
    
    -- 负载均衡算法
    if proxy.load_balance == "least_conn" then
        config = config .. "    least_conn;\n"
    elseif proxy.load_balance == "ip_hash" then
        config = config .. "    ip_hash;\n"
    end
    
    -- 后端服务器
    for _, backend in ipairs(backends) do
        if backend.status == 1 then
            local server_line = "    server " .. escape_nginx_value(backend.backend_address) .. ":" .. backend.backend_port
            if backend.weight and backend.weight > 1 then
                server_line = server_line .. " weight=" .. backend.weight
            end
            if backend.max_fails then
                server_line = server_line .. " max_fails=" .. backend.max_fails
            end
            if backend.fail_timeout then
                server_line = server_line .. " fail_timeout=" .. backend.fail_timeout .. "s"
            end
            if backend.backup == 1 then
                server_line = server_line .. " backup"
            end
            if backend.down == 1 then
                server_line = server_line .. " down"
            end
            server_line = server_line .. ";\n"
            config = config .. server_line
        end
    end
    
    config = config .. "}\n\n"
    return config, upstream_name
end

-- 生成TCP/UDP stream server块配置
local function generate_stream_server_config(proxy, upstream_name)
    local config = "# ============================================\n"
    config = config .. "# 代理配置: " .. escape_nginx_value(proxy.proxy_name) .. " (ID: " .. proxy.id .. ")\n"
    config = config .. "# 类型: " .. string.upper(proxy.proxy_type) .. "\n"
    config = config .. "# 自动生成，请勿手动修改\n"
    config = config .. "# ============================================\n\n"
    config = config .. "server {\n"
    
    -- 监听端口
    config = config .. "    listen " .. proxy.listen_port
    if proxy.proxy_type == "udp" then
        config = config .. " udp"
    end
    config = config .. ";\n"
    
    -- 代理到后端
    if proxy.backend_type == "upstream" and upstream_name then
        config = config .. "    proxy_pass " .. upstream_name .. ";\n"
    else
        local backend_address = escape_nginx_value(proxy.backend_address)
        local backend_port = proxy.backend_port or 8080
        config = config .. "    proxy_pass " .. backend_address .. ":" .. backend_port .. ";\n"
    end
    
    -- 超时设置
    if proxy.proxy_timeout then
        config = config .. "    proxy_timeout " .. proxy.proxy_timeout .. "s;\n"
    end
    if proxy.proxy_connect_timeout then
        config = config .. "    proxy_connect_timeout " .. proxy.proxy_connect_timeout .. "s;\n"
    end
    
    config = config .. "}\n\n"
    return config
end

-- 生成单个HTTP代理的server配置（不包含upstream）
local function generate_http_proxy_file(proxy, upstream_name)
    local config = "# ============================================\n"
    config = config .. "# 代理配置: " .. escape_nginx_value(proxy.proxy_name) .. " (ID: " .. proxy.id .. ")\n"
    config = config .. "# 自动生成，请勿手动修改\n"
    config = config .. "# ============================================\n\n"
    
    -- 写入server配置（upstream配置已单独生成）
    config = config .. generate_http_server_config(proxy, upstream_name)
    
    return config
end

-- 生成单个Stream代理的server配置（不包含upstream）
local function generate_stream_proxy_file(proxy, upstream_name)
    local config = "# ============================================\n"
    config = config .. "# 代理配置: " .. escape_nginx_value(proxy.proxy_name) .. " (ID: " .. proxy.id .. ")\n"
    config = config .. "# 类型: " .. string.upper(proxy.proxy_type) .. "\n"
    config = config .. "# 自动生成，请勿手动修改\n"
    config = config .. "# ============================================\n\n"
    
    -- 写入server配置（upstream配置已单独生成）
    config = config .. generate_stream_server_config(proxy, upstream_name)
    
    return config
end

-- 清理已删除代理的配置文件
local function cleanup_orphaned_files(project_root, active_proxy_ids)
    -- HTTP/HTTPS upstream配置文件
    local http_upstream_dir = project_root .. "/conf.d/upstream/http_https"
    local http_upstream_cmd = "find " .. http_upstream_dir .. " -maxdepth 1 -name 'upstream_*.conf' 2>/dev/null"
    local http_upstream_files = io.popen(http_upstream_cmd)
    if http_upstream_files then
        for file in http_upstream_files:lines() do
            local proxy_id = file:match("upstream_(%d+)%.conf")
            if proxy_id then
                proxy_id = tonumber(proxy_id)
                if not active_proxy_ids[proxy_id] then
                    local ok, err = os.remove(file)
                    if ok then
                        ngx.log(ngx.INFO, "删除已删除代理的HTTP upstream配置文件: ", file)
                    else
                        ngx.log(ngx.WARN, "删除upstream配置文件失败: ", file, ", 错误: ", err or "unknown")
                    end
                end
            end
        end
        http_upstream_files:close()
    end
    
    -- HTTP/HTTPS server配置文件
    local http_server_dir = project_root .. "/conf.d/vhost_conf/http_https"
    local http_server_cmd = "find " .. http_server_dir .. " -maxdepth 1 -name 'proxy_http_*.conf' 2>/dev/null"
    local http_server_files = io.popen(http_server_cmd)
    if http_server_files then
        for file in http_server_files:lines() do
            local proxy_id = file:match("proxy_http_(%d+)%.conf")
            if proxy_id then
                proxy_id = tonumber(proxy_id)
                if not active_proxy_ids[proxy_id] then
                    local ok, err = os.remove(file)
                    if ok then
                        ngx.log(ngx.INFO, "删除已删除代理的HTTP server配置文件: ", file)
                    else
                        ngx.log(ngx.WARN, "删除server配置文件失败: ", file, ", 错误: ", err or "unknown")
                    end
                end
            end
        end
        http_server_files:close()
    end
    
    -- TCP/UDP upstream配置文件
    local stream_upstream_dir = project_root .. "/conf.d/upstream/tcp_udp"
    local stream_upstream_cmd = "find " .. stream_upstream_dir .. " -maxdepth 1 -name 'stream_upstream_*.conf' 2>/dev/null"
    local stream_upstream_files = io.popen(stream_upstream_cmd)
    if stream_upstream_files then
        for file in stream_upstream_files:lines() do
            local proxy_id = file:match("stream_upstream_(%d+)%.conf")
            if proxy_id then
                proxy_id = tonumber(proxy_id)
                if not active_proxy_ids[proxy_id] then
                    local ok, err = os.remove(file)
                    if ok then
                        ngx.log(ngx.INFO, "删除已删除代理的Stream upstream配置文件: ", file)
                    else
                        ngx.log(ngx.WARN, "删除upstream配置文件失败: ", file, ", 错误: ", err or "unknown")
                    end
                end
            end
        end
        stream_upstream_files:close()
    end
    
    -- TCP/UDP server配置文件
    local stream_server_dir = project_root .. "/conf.d/vhost_conf/tcp_udp"
    local stream_server_cmd = "find " .. stream_server_dir .. " -maxdepth 1 -name 'proxy_stream_*.conf' 2>/dev/null"
    local stream_server_files = io.popen(stream_server_cmd)
    if stream_server_files then
        for file in stream_server_files:lines() do
            local proxy_id = file:match("proxy_stream_(%d+)%.conf")
            if proxy_id then
                proxy_id = tonumber(proxy_id)
                if not active_proxy_ids[proxy_id] then
                    local ok, err = os.remove(file)
                    if ok then
                        ngx.log(ngx.INFO, "删除已删除代理的Stream server配置文件: ", file)
                    else
                        ngx.log(ngx.WARN, "删除server配置文件失败: ", file, ", 错误: ", err or "unknown")
                    end
                end
            end
        end
        stream_server_files:close()
    end
end

-- 生成所有代理配置
function _M.generate_all_configs()
    local project_root = path_utils.get_project_root()
    if not project_root then
        ngx.log(ngx.ERR, "无法获取项目根目录，package.path: ", package.path)
        return false, "无法获取项目根目录，请检查配置"
    end
    
    -- 验证项目根目录是否有效
    local confd_path = project_root .. "/conf.d"
    local test_file = io.open(confd_path, "r")
    if not test_file then
        ngx.log(ngx.ERR, "项目根目录无效，conf.d目录不存在: ", confd_path, ", project_root: ", project_root)
        return false, "项目根目录无效，conf.d目录不存在: " .. confd_path
    end
    test_file:close()
    
    ngx.log(ngx.INFO, "使用项目根目录: ", project_root)
    
    -- 获取所有启用的代理配置
    local sql = [[
        SELECT id, proxy_name, proxy_type, listen_port, listen_address, server_name, location_path,
               backend_type, backend_address, backend_port, load_balance,
               ssl_enable, ssl_cert_path, ssl_key_path,
               proxy_timeout, proxy_connect_timeout, proxy_send_timeout, proxy_read_timeout,
               ip_rule_id, status, priority
        FROM waf_proxy_configs
        WHERE status = 1
        ORDER BY priority DESC, id ASC
    ]]
    
    local proxies, err = mysql_pool.query(sql)
    if err then
        ngx.log(ngx.ERR, "查询代理配置失败: ", err)
        return false, "查询代理配置失败: " .. err
    end
    
    -- 确保目录存在
    local dirs = {
        project_root .. "/conf.d/set_conf",
        project_root .. "/conf.d/vhost_conf",
        project_root .. "/conf.d/vhost_conf/http_https",
        project_root .. "/conf.d/vhost_conf/tcp_udp",
        project_root .. "/conf.d/upstream",
        project_root .. "/conf.d/upstream/http_https",
        project_root .. "/conf.d/upstream/tcp_udp"
    }
    
    for _, dir in ipairs(dirs) do
        local ok = path_utils.ensure_dir(dir)
        if not ok then
            ngx.log(ngx.ERR, "无法创建目录: ", dir)
            return false, "无法创建目录: " .. dir
        end
        ngx.log(ngx.DEBUG, "目录已确保存在: ", dir)
    end
    
    -- 构建活跃代理ID映射（用于清理已删除的配置文件）
    local active_proxy_ids = {}
    
    if not proxies or #proxies == 0 then
        -- 如果没有启用的代理，清理所有代理配置文件
        cleanup_orphaned_files(project_root, active_proxy_ids)
        return true, "没有启用的代理配置，已清理所有配置文件"
    end
    
    -- 为每个代理生成独立的配置文件
    for _, proxy in ipairs(proxies) do
        active_proxy_ids[proxy.id] = true
        
        -- 查询后端服务器并生成upstream配置
        -- 注意：无论是single还是upstream类型，都生成upstream配置文件，便于统一管理和后续扩展
        local backends = nil
        local upstream_name = nil
        local upstream_config = nil
        
        if proxy.backend_type == "upstream" then
            -- upstream类型：从数据库查询多个后端服务器
            local backends_sql = [[
                SELECT id, backend_address, backend_port, weight, max_fails, fail_timeout,
                       backup, down, status
                FROM waf_proxy_backends
                WHERE proxy_id = ? AND status = 1
                ORDER BY weight DESC, id ASC
            ]]
            backends, _ = mysql_pool.query(backends_sql, proxy.id)
        else
            -- single类型：从proxy配置中构建单个后端服务器
            if proxy.backend_address and proxy.backend_port then
                backends = {{
                    backend_address = proxy.backend_address,
                    backend_port = proxy.backend_port,
                    weight = 1,
                    max_fails = proxy.max_fails or 3,
                    fail_timeout = proxy.fail_timeout or 30,
                    backup = 0,
                    down = 0,
                    status = 1
                }}
            end
        end
        
        -- 生成upstream配置（如果有后端服务器）
        if backends and #backends > 0 then
            if proxy.proxy_type == "http" then
                upstream_config, upstream_name = generate_upstream_config(proxy, backends)
            else
                upstream_config, upstream_name = generate_stream_upstream_config(proxy, backends)
            end
            
            -- 生成独立的upstream配置文件
            if upstream_config and upstream_name then
                -- 根据代理类型确定upstream配置文件目录
                local upstream_subdir = ""
                if proxy.proxy_type == "http" then
                    upstream_subdir = "http_https"
                else
                    upstream_subdir = "tcp_udp"
                end
                
                local upstream_file = project_root .. "/conf.d/upstream/" .. upstream_subdir .. "/" .. upstream_name .. ".conf"
                
                -- 确保upstream子目录存在
                local upstream_dir = project_root .. "/conf.d/upstream/" .. upstream_subdir
                local dir_ok = path_utils.ensure_dir(upstream_dir)
                if not dir_ok then
                    ngx.log(ngx.ERR, "无法创建upstream目录: ", upstream_dir)
                    return false, "无法创建upstream目录: " .. upstream_dir
                end
                
                -- 检查目录是否存在且有写入权限
                local test_file = io.open(upstream_dir .. "/.test_write", "w")
                if test_file then
                    test_file:close()
                    os.remove(upstream_dir .. "/.test_write")
                else
                    ngx.log(ngx.ERR, "upstream目录无写入权限: ", upstream_dir, ", 请检查目录权限（应为 755 且所有者应为 nobody）")
                    return false, "upstream目录无写入权限: " .. upstream_dir
                end
                
                local upstream_fd = io.open(upstream_file, "w")
                if upstream_fd then
                    local upstream_file_content = "# ============================================\n"
                    upstream_file_content = upstream_file_content .. "# Upstream配置: " .. escape_nginx_value(proxy.proxy_name) .. " (代理ID: " .. proxy.id .. ")\n"
                    upstream_file_content = upstream_file_content .. "# 类型: " .. string.upper(proxy.proxy_type) .. "\n"
                    upstream_file_content = upstream_file_content .. "# 后端类型: " .. (proxy.backend_type == "upstream" and "多个后端（负载均衡）" or "单个后端") .. "\n"
                    upstream_file_content = upstream_file_content .. "# 自动生成，请勿手动修改\n"
                    upstream_file_content = upstream_file_content .. "# ============================================\n\n"
                    upstream_file_content = upstream_file_content .. upstream_config
                    upstream_fd:write(upstream_file_content)
                    upstream_fd:close()
                    ngx.log(ngx.INFO, "生成upstream配置文件: ", upstream_file, " (后端类型: ", proxy.backend_type, ")")
                else
                    -- 尝试获取更详细的错误信息
                    local err_msg = "无法创建upstream配置文件: " .. upstream_file
                    -- 检查文件是否已存在但无法写入
                    local test_read = io.open(upstream_file, "r")
                    if test_read then
                        test_read:close()
                        err_msg = err_msg .. " (文件已存在但无写入权限，请检查文件权限)"
                    else
                        err_msg = err_msg .. " (可能原因：目录不存在、权限不足、磁盘空间不足或inode不足)"
                    end
                    ngx.log(ngx.ERR, err_msg, ", 项目根目录: ", project_root, ", upstream目录: ", upstream_dir)
                    return false, err_msg
                end
            end
        end
        
        -- 根据代理类型生成对应的server配置文件
        if proxy.proxy_type == "http" then
            -- 生成HTTP代理server配置文件
            local config_content = generate_http_proxy_file(proxy, upstream_name)
            -- HTTP/HTTPS server配置放在 vhost_conf/http_https 子目录
            local config_file = project_root .. "/conf.d/vhost_conf/http_https/proxy_http_" .. proxy.id .. ".conf"
            
            -- 确保vhost_conf/http_https目录存在
            local http_dir = project_root .. "/conf.d/vhost_conf/http_https"
            local dir_ok = path_utils.ensure_dir(http_dir)
            if not dir_ok then
                ngx.log(ngx.ERR, "无法创建vhost_conf/http_https目录: ", http_dir)
                return false, "无法创建vhost_conf/http_https目录: " .. http_dir
            end
            
            -- 检查目录是否有写入权限
            local test_file = io.open(http_dir .. "/.test_write", "w")
            if test_file then
                test_file:close()
                os.remove(http_dir .. "/.test_write")
            else
                ngx.log(ngx.ERR, "vhost_conf/http_https目录无写入权限: ", http_dir, ", 请检查目录权限（应为 755 且所有者应为 nobody）")
                return false, "vhost_conf/http_https目录无写入权限: " .. http_dir
            end
            
            local fd = io.open(config_file, "w")
            if not fd then
                -- 尝试获取更详细的错误信息
                local err_msg = "无法创建HTTP代理配置文件: " .. config_file
                -- 检查文件是否已存在但无法写入
                local test_read = io.open(config_file, "r")
                if test_read then
                    test_read:close()
                    err_msg = err_msg .. " (文件已存在但无写入权限，请检查文件权限)"
                else
                    err_msg = err_msg .. " (可能原因：目录不存在、权限不足、磁盘空间不足或inode不足)"
                end
                ngx.log(ngx.ERR, err_msg, ", 项目根目录: ", project_root, ", vhost_conf/http_https目录: ", http_dir)
                return false, err_msg
            else
                fd:write(config_content)
                fd:close()
                ngx.log(ngx.INFO, "生成HTTP代理配置文件: ", config_file)
            end
        else
            -- 生成Stream代理server配置文件
            local config_content = generate_stream_proxy_file(proxy, upstream_name)
            -- TCP/UDP server配置放在 vhost_conf/tcp_udp 子目录
            local config_file = project_root .. "/conf.d/vhost_conf/tcp_udp/proxy_stream_" .. proxy.id .. ".conf"
            
            -- 确保vhost_conf/tcp_udp目录存在
            local tcp_dir = project_root .. "/conf.d/vhost_conf/tcp_udp"
            local dir_ok = path_utils.ensure_dir(tcp_dir)
            if not dir_ok then
                ngx.log(ngx.ERR, "无法创建vhost_conf/tcp_udp目录: ", tcp_dir)
                return false, "无法创建vhost_conf/tcp_udp目录: " .. tcp_dir
            end
            
            -- 检查目录是否有写入权限
            local test_file = io.open(tcp_dir .. "/.test_write", "w")
            if test_file then
                test_file:close()
                os.remove(tcp_dir .. "/.test_write")
            else
                ngx.log(ngx.ERR, "vhost_conf/tcp_udp目录无写入权限: ", tcp_dir, ", 请检查目录权限（应为 755 且所有者应为 nobody）")
                return false, "vhost_conf/tcp_udp目录无写入权限: " .. tcp_dir
            end
            
            local fd = io.open(config_file, "w")
            if not fd then
                -- 尝试获取更详细的错误信息
                local err_msg = "无法创建Stream代理配置文件: " .. config_file
                -- 检查文件是否已存在但无法写入
                local test_read = io.open(config_file, "r")
                if test_read then
                    test_read:close()
                    err_msg = err_msg .. " (文件已存在但无写入权限，请检查文件权限)"
                else
                    err_msg = err_msg .. " (可能原因：目录不存在、权限不足、磁盘空间不足或inode不足)"
                end
                ngx.log(ngx.ERR, err_msg, ", 项目根目录: ", project_root, ", vhost_conf/tcp_udp目录: ", tcp_dir)
                return false, err_msg
            else
                fd:write(config_content)
                fd:close()
                ngx.log(ngx.INFO, "生成Stream代理配置文件: ", config_file)
            end
        end
    end
    
    -- 清理已删除代理的配置文件
    cleanup_orphaned_files(project_root, active_proxy_ids)
    
    ngx.log(ngx.INFO, "nginx配置生成成功: 共生成 " .. #proxies .. " 个代理配置文件")
    return true, "配置生成成功，共生成 " .. #proxies .. " 个代理配置文件"
end

-- 清理生成的配置文件
function _M.cleanup_configs()
    local project_root = path_utils.get_project_root()
    if not project_root then
        return false, "无法获取项目根目录"
    end
    
    -- 清理所有代理配置文件
    -- 注意：代理配置文件已移到 http_https 和 tcp_udp 子目录
    -- 这里不再清理 vhost_conf 中的代理配置文件（它们已移到对应子目录）
    -- vhost_conf 目录保留用于手动配置的server（如waf.conf等）
    
    -- 清理所有HTTP/HTTPS upstream配置文件
    local http_upstream_dir = project_root .. "/conf.d/upstream/http_https"
    local http_upstream_cmd = "find " .. http_upstream_dir .. " -maxdepth 1 -name 'upstream_*.conf' 2>/dev/null"
    local http_upstream_files = io.popen(http_upstream_cmd)
    if http_upstream_files then
        for file in http_upstream_files:lines() do
            local ok, err = os.remove(file)
            if ok then
                ngx.log(ngx.INFO, "删除HTTP upstream配置文件: ", file)
            else
                ngx.log(ngx.WARN, "删除HTTP upstream配置文件失败: ", file, ", 错误: ", err or "unknown")
            end
        end
        http_upstream_files:close()
    end
    
    -- 清理所有HTTP/HTTPS server配置文件
    local http_server_dir = project_root .. "/conf.d/vhost_conf/http_https"
    local http_server_cmd = "find " .. http_server_dir .. " -maxdepth 1 -name 'proxy_http_*.conf' 2>/dev/null"
    local http_server_files = io.popen(http_server_cmd)
    if http_server_files then
        for file in http_server_files:lines() do
            local ok, err = os.remove(file)
            if ok then
                ngx.log(ngx.INFO, "删除HTTP server配置文件: ", file)
            else
                ngx.log(ngx.WARN, "删除HTTP server配置文件失败: ", file, ", 错误: ", err or "unknown")
            end
        end
        http_server_files:close()
    end
    
    -- 清理所有TCP/UDP upstream配置文件
    local stream_upstream_dir = project_root .. "/conf.d/upstream/tcp_udp"
    local stream_upstream_cmd = "find " .. stream_upstream_dir .. " -maxdepth 1 -name 'stream_upstream_*.conf' 2>/dev/null"
    local stream_upstream_files = io.popen(stream_upstream_cmd)
    if stream_upstream_files then
        for file in stream_upstream_files:lines() do
            local ok, err = os.remove(file)
            if ok then
                ngx.log(ngx.INFO, "删除Stream upstream配置文件: ", file)
            else
                ngx.log(ngx.WARN, "删除Stream upstream配置文件失败: ", file, ", 错误: ", err or "unknown")
            end
        end
        stream_upstream_files:close()
    end
    
    -- 清理所有TCP/UDP server配置文件
    local stream_server_dir = project_root .. "/conf.d/vhost_conf/tcp_udp"
    local stream_server_cmd = "find " .. stream_server_dir .. " -maxdepth 1 -name 'proxy_stream_*.conf' 2>/dev/null"
    local stream_server_files = io.popen(stream_server_cmd)
    if stream_server_files then
        for file in stream_server_files:lines() do
            local ok, err = os.remove(file)
            if ok then
                ngx.log(ngx.INFO, "删除Stream server配置文件: ", file)
            else
                ngx.log(ngx.WARN, "删除Stream server配置文件失败: ", file, ", 错误: ", err or "unknown")
            end
        end
        stream_server_files:close()
    end
    
    return true, "清理完成"
end

return _M


