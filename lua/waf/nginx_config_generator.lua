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

-- 生成所有代理配置
function _M.generate_all_configs()
    local project_root = path_utils.get_project_root()
    if not project_root then
        return false, "无法获取项目根目录"
    end
    
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
    path_utils.ensure_dir(project_root .. "/conf.d/set_conf")
    path_utils.ensure_dir(project_root .. "/conf.d/vhost_conf")
    
    if not proxies or #proxies == 0 then
        -- 如果没有启用的代理，生成空配置文件（避免nginx include报错）
        local empty_content = "# ============================================\n"
        empty_content = empty_content .. "# 代理配置（自动生成）\n"
        empty_content = empty_content .. "# 当前没有启用的代理配置\n"
        empty_content = empty_content .. "# ============================================\n\n"
        
        local files = {
            {path = project_root .. "/conf.d/set_conf/proxy_upstreams.conf", content = empty_content},
            {path = project_root .. "/conf.d/vhost_conf/proxy_http.conf", content = empty_content},
            {path = project_root .. "/conf.d/vhost_conf/proxy_stream.conf", content = empty_content}
        }
        
        for _, file_info in ipairs(files) do
            local fd = io.open(file_info.path, "w")
            if fd then
                fd:write(file_info.content)
                fd:close()
            end
        end
        
        return true, "没有启用的代理配置，已生成空配置文件"
    end
    
    -- 分离HTTP和TCP/UDP代理
    local http_proxies = {}
    local stream_proxies = {}
    local http_upstream_configs = {}
    local stream_upstream_configs = {}
    
    for _, proxy in ipairs(proxies) do
        -- 查询后端服务器（如果是upstream类型）
        local backends = nil
        local upstream_name = nil
        
        if proxy.backend_type == "upstream" then
            local backends_sql = [[
                SELECT id, backend_address, backend_port, weight, max_fails, fail_timeout,
                       backup, down, status
                FROM waf_proxy_backends
                WHERE proxy_id = ? AND status = 1
                ORDER BY weight DESC, id ASC
            ]]
            backends, _ = mysql_pool.query(backends_sql, proxy.id)
            
            if backends and #backends > 0 then
                if proxy.proxy_type == "http" then
                    local upstream_config, name = generate_upstream_config(proxy, backends)
                    http_upstream_configs[proxy.id] = upstream_config
                    upstream_name = name
                else
                    local upstream_config, name = generate_stream_upstream_config(proxy, backends)
                    stream_upstream_configs[proxy.id] = upstream_config
                    upstream_name = name
                end
            end
        end
        
        if proxy.proxy_type == "http" then
            table.insert(http_proxies, {
                proxy = proxy,
                upstream_name = upstream_name
            })
        else
            table.insert(stream_proxies, {
                proxy = proxy,
                upstream_name = upstream_name
            })
        end
    end
    
    -- 生成HTTP upstream配置文件
    local upstream_file = project_root .. "/conf.d/set_conf/proxy_upstreams.conf"
    local upstream_content = "# ============================================\n"
    upstream_content = upstream_content .. "# HTTP代理Upstream配置（自动生成）\n"
    upstream_content = upstream_content .. "# 请勿手动修改此文件\n"
    upstream_content = upstream_content .. "# ============================================\n\n"
    
    for _, data in ipairs(http_proxies) do
        if data.upstream_name and http_upstream_configs[data.proxy.id] then
            upstream_content = upstream_content .. http_upstream_configs[data.proxy.id]
        end
    end
    
    -- 确保目录存在
    path_utils.ensure_dir(project_root .. "/conf.d/set_conf")
    
    -- 写入upstream配置文件
    local upstream_fd = io.open(upstream_file, "w")
    if not upstream_fd then
        return false, "无法创建upstream配置文件: " .. upstream_file
    end
    upstream_fd:write(upstream_content)
    upstream_fd:close()
    
    -- 生成Stream upstream配置（在stream块中）
    local stream_upstream_content = ""
    for _, data in ipairs(stream_proxies) do
        if data.upstream_name and stream_upstream_configs[data.proxy.id] then
            stream_upstream_content = stream_upstream_content .. stream_upstream_configs[data.proxy.id]
        end
    end
    
    -- 生成HTTP server配置文件
    local http_file = project_root .. "/conf.d/vhost_conf/proxy_http.conf"
    local http_content = "# ============================================\n"
    http_content = http_content .. "# HTTP代理配置（自动生成）\n"
    http_content = http_content .. "# 请勿手动修改此文件\n"
    http_content = http_content .. "# ============================================\n\n"
    
    for _, data in ipairs(http_proxies) do
        http_content = http_content .. generate_http_server_config(data.proxy, data.upstream_name)
    end
    
    -- 确保目录存在
    path_utils.ensure_dir(project_root .. "/conf.d/vhost_conf")
    
    -- 写入HTTP配置文件
    local http_fd = io.open(http_file, "w")
    if not http_fd then
        return false, "无法创建HTTP配置文件: " .. http_file
    end
    http_fd:write(http_content)
    http_fd:close()
    
    -- 生成TCP/UDP stream配置文件
    local stream_file = project_root .. "/conf.d/vhost_conf/proxy_stream.conf"
    local stream_content = "# ============================================\n"
    stream_content = stream_content .. "# TCP/UDP代理配置（自动生成）\n"
    stream_content = stream_content .. "# 请勿手动修改此文件\n"
    stream_content = stream_content .. "# ============================================\n\n"
    
    -- 先写入stream upstream配置
    if stream_upstream_content ~= "" then
        stream_content = stream_content .. stream_upstream_content
    end
    
    -- 再写入stream server配置
    for _, data in ipairs(stream_proxies) do
        stream_content = stream_content .. generate_stream_server_config(data.proxy, data.upstream_name)
    end
    
    -- 写入stream配置文件
    local stream_fd = io.open(stream_file, "w")
    if not stream_fd then
        return false, "无法创建stream配置文件: " .. stream_file
    end
    stream_fd:write(stream_content)
    stream_fd:close()
    
    ngx.log(ngx.INFO, "nginx配置生成成功: HTTP=" .. #http_proxies .. ", Stream=" .. #stream_proxies)
    return true, "配置生成成功"
end

-- 清理生成的配置文件
function _M.cleanup_configs()
    local project_root = path_utils.get_project_root()
    if not project_root then
        return false, "无法获取项目根目录"
    end
    
    local files = {
        project_root .. "/conf.d/set_conf/proxy_upstreams.conf",
        project_root .. "/conf.d/vhost_conf/proxy_http.conf",
        project_root .. "/conf.d/vhost_conf/proxy_stream.conf"
    }
    
    for _, file in ipairs(files) do
        local fd = io.open(file, "r")
        if fd then
            fd:close()
            os.remove(file)
        end
    end
    
    return true, "清理完成"
end

return _M

