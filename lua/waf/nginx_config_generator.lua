-- Nginx配置生成器模块
-- 路径：项目目录下的 lua/waf/nginx_config_generator.lua（保持在项目目录，不复制到系统目录）
-- 功能：根据数据库中的代理配置自动生成nginx配置文件

local mysql_pool = require "waf.mysql_pool"
local path_utils = require "waf.path_utils"
local cjson = require "cjson"

local _M = {}

-- 将 cjson.null 转换为 nil
local function null_to_nil(value)
    if value == nil or value == cjson.null then
        return nil
    end
    return value
end

-- 规范化端口值（去除空格，确保是数字或数字字符串）
local function normalize_port(port)
    if not port then
        return nil
    end
    -- 转换为字符串并去除前后空格
    local port_str = tostring(port):gsub("^%s+", ""):gsub("%s+$", "")
    -- 如果是空字符串，返回nil
    if port_str == "" then
        return nil
    end
    return port_str
end

-- 转义nginx配置值（防止注入攻击）
local function escape_nginx_value(value)
    if not value then
        return ""
    end
    -- 转义特殊字符
    value = tostring(value)
    -- 去除前导和尾随空格
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    value = value:gsub(";", "\\;")
    value = value:gsub("\\", "\\\\")
    value = value:gsub("\"", "\\\"")
    value = value:gsub("'", "\\'")
    value = value:gsub("\n", " ")
    value = value:gsub("\r", " ")
    return value
end

-- 生成安全的文件名（转义特殊字符，避免文件系统问题）
local function sanitize_filename(value)
    if not value then
        return ""
    end
    -- 转换为字符串
    value = tostring(value)
    -- 去除前导和尾随空格
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    -- 替换不允许的文件名字符
    value = value:gsub("/", "_")  -- 路径分隔符
    value = value:gsub("\\", "_")  -- 反斜杠
    value = value:gsub(":", "_")  -- 冒号（Windows不支持）
    value = value:gsub("*", "_")  -- 星号
    value = value:gsub("?", "_")  -- 问号
    value = value:gsub("\"", "_")  -- 双引号
    value = value:gsub("<", "_")  -- 小于号
    value = value:gsub(">", "_")  -- 大于号
    value = value:gsub("|", "_")  -- 管道符
    value = value:gsub(" ", "_")  -- 空格
    value = value:gsub("\n", "_")  -- 换行符
    value = value:gsub("\r", "_")  -- 回车符
    value = value:gsub("\t", "_")  -- 制表符
    -- 去除连续的下划线
    value = value:gsub("_+", "_")
    -- 去除开头和结尾的下划线
    value = value:gsub("^_+", ""):gsub("_+$", "")
    -- 如果为空，使用默认值
    if value == "" then
        value = "default"
    end
    return value
end

-- 生成安全的 upstream 名称（用于 nginx 配置中的 upstream 块名称）
-- upstream 名称只能包含字母、数字、下划线，不能包含其他特殊字符
local function sanitize_upstream_name(value)
    if not value then
        return ""
    end
    -- 转换为字符串
    value = tostring(value)
    -- 去除前导和尾随空格
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    -- 替换不允许的字符为下划线（upstream 名称只能包含字母、数字、下划线）
    value = value:gsub("[^%w_]", "_")  -- 保留字母、数字、下划线，其他替换为下划线
    -- 去除连续的下划线
    value = value:gsub("_+", "_")
    -- 去除开头和结尾的下划线
    value = value:gsub("^_+", ""):gsub("_+$", "")
    -- 确保以字母或下划线开头（nginx upstream 名称必须以字母或下划线开头）
    -- 注意：不在函数内添加 "upstream_" 前缀，因为调用者会手动添加
    if value ~= "" and not value:match("^[%a_]") then
        value = "up_" .. value  -- 使用短前缀，避免与调用者的 "upstream_" 前缀重复
    end
    -- 如果为空，使用默认值
    if value == "" then
        value = "default"
    end
    return value
end

-- 生成upstream配置（用于单个location）
local function generate_upstream_config_for_location(proxy, backends, upstream_name)
    if not backends or #backends == 0 then
        return nil
    end
    
    if not upstream_name then
        upstream_name = "upstream_" .. tostring(proxy.id)
    end
    
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
            -- 处理 cjson.null，确保 backend_address 和 backend_port 不为 nil
            local backend_address = null_to_nil(backend.backend_address)
            local backend_port = normalize_port(backend.backend_port)
            
            if not backend_address or not backend_port then
                ngx.log(ngx.WARN, "跳过无效的后端服务器配置（地址或端口为空）: ", cjson.encode(backend))
                goto continue
            end
            
            local server_line = "    server " .. escape_nginx_value(backend_address) .. ":" .. backend_port
            local weight = null_to_nil(backend.weight)
            if weight and weight > 1 then
                server_line = server_line .. " weight=" .. weight
            end
            local max_fails = null_to_nil(backend.max_fails)
            if max_fails then
                server_line = server_line .. " max_fails=" .. max_fails
            end
            local fail_timeout = null_to_nil(backend.fail_timeout)
            if fail_timeout then
                server_line = server_line .. " fail_timeout=" .. fail_timeout .. "s"
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
        ::continue::
    end
    
    -- Keepalive配置（HTTP代理）
    if proxy.proxy_type == "http" then
        config = config .. "    keepalive 1024;\n"
        config = config .. "    keepalive_requests 10000;\n"
        config = config .. "    keepalive_timeout 60s;\n"
    end
    
    config = config .. "}\n\n"
    return config
end

-- 生成upstream配置（向后兼容，用于单个upstream）
local function generate_upstream_config(proxy, backends)
    if not backends or #backends == 0 then
        return "", nil
    end
    
    local upstream_name = "upstream_" .. tostring(proxy.id)
    local config = generate_upstream_config_for_location(proxy, backends, upstream_name)
    if config then
        return config, upstream_name
    else
        return "", nil
    end
end

-- 生成HTTP server块配置
local function generate_http_server_config(proxy, upstream_name, backends)
    local config = "server {\n"
    
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
    local ip_rule_ids = proxy.ip_rule_ids
    if ip_rule_ids and type(ip_rule_ids) == "table" and #ip_rule_ids > 0 then
        config = config .. "\n    # WAF封控检查（关联防护规则ID: " .. table.concat(ip_rule_ids, ",") .. "）\n"
        -- 将规则ID数组转换为Lua表字符串
        local rule_ids_str = "{"
        for i, rule_id in ipairs(ip_rule_ids) do
            if i > 1 then
                rule_ids_str = rule_ids_str .. ","
            end
            rule_ids_str = rule_ids_str .. rule_id
        end
        rule_ids_str = rule_ids_str .. "}"
        config = config .. "    set $proxy_ip_rule_ids '" .. rule_ids_str .. "';\n"
        config = config .. "    access_by_lua_block {\n"
        config = config .. "        local rule_ids_str = ngx.var.proxy_ip_rule_ids\n"
        config = config .. "        local rule_ids = {}\n"
        config = config .. "        if rule_ids_str then\n"
        config = config .. "            -- 解析Lua表字符串（格式：{1,2,3}）\n"
        config = config .. "            local ids_str = rule_ids_str:match(\"^%s*{%s*(.-)%s*}%s*$\")\n"
        config = config .. "            if ids_str then\n"
        config = config .. "                for id_str in ids_str:gmatch(\"([^,]+)\") do\n"
        config = config .. "                    local id = tonumber(id_str:match(\"^%s*(.-)%s*$\"))\n"
        config = config .. "                    if id then\n"
        config = config .. "                        table.insert(rule_ids, id)\n"
        config = config .. "                    end\n"
        config = config .. "                end\n"
        config = config .. "            else\n"
        config = config .. "                -- 兼容旧格式：单个规则ID\n"
        config = config .. "                local single_id = tonumber(rule_ids_str)\n"
        config = config .. "                if single_id then\n"
        config = config .. "                    rule_ids = {single_id}\n"
        config = config .. "                end\n"
        config = config .. "            end\n"
        config = config .. "        end\n"
        config = config .. "        require(\"waf.ip_block\").check_multiple(rule_ids)\n"
        config = config .. "    }\n"
    end
    
    -- 日志采集
    config = config .. "\n    # 日志采集\n"
    config = config .. "    log_by_lua_block {\n"
    config = config .. "        require(\"waf.log_collect\").collect()\n"
    config = config .. "    }\n"
    
    -- Location配置
    -- 必须使用location_paths字段，不再支持向后兼容
    local location_paths = proxy.location_paths
    if location_paths and type(location_paths) == "table" and #location_paths > 0 then
        -- 生成多个location块，每个location使用独立的upstream配置
        for loc_index, loc in ipairs(location_paths) do
            if loc.location_path and loc.location_path ~= "" then
                config = config .. "\n    location " .. escape_nginx_value(loc.location_path) .. " {\n"
                
                -- 为每个location使用独立的upstream配置
                -- 新命名格式：upstream_$proxy_name_$location_path
                local proxy_name_safe = sanitize_upstream_name(proxy.proxy_name)
                local location_path_safe = sanitize_upstream_name(loc.location_path)
                local location_upstream_name = "upstream_" .. proxy_name_safe .. "_" .. location_path_safe
                
                -- 筛选属于当前location的后端服务器
                local location_backends = {}
                if backends then
                    for _, backend in ipairs(backends) do
                        local backend_location_path = null_to_nil(backend.location_path)
                        if backend_location_path == loc.location_path then
                            table.insert(location_backends, backend)
                        end
                    end
                end
                
                -- 代理到后端
                if #location_backends > 0 then
                    -- 使用location配置中的backend_path，如果没有则使用后端服务器的backend_path
                    local backend_path = loc.backend_path
                    if not backend_path or backend_path == "" then
                        -- 检查后端服务器是否有路径配置
                        local first_path = location_backends[1].backend_path
                        if first_path == nil or first_path == cjson.null then
                            first_path = nil
                        elseif type(first_path) == "string" and first_path:match("^%s*$") then
                            first_path = nil
                        end
                        
                        local all_same = true
                        if first_path and first_path ~= "" then
                            for i = 2, #location_backends do
                                local path = location_backends[i].backend_path
                                if path == nil or path == cjson.null then
                                    path = nil
                                elseif type(path) == "string" and path:match("^%s*$") then
                                    path = nil
                                end
                                if path ~= first_path then
                                    all_same = false
                                    break
                                end
                            end
                            if all_same then
                                backend_path = first_path
                            end
                        end
                    end
                    
                    -- 如果后端服务器有路径，在proxy_pass中添加路径
                    -- 确保 backend_path 正确转换为字符串，并且只有在非空时才拼接
                    local backend_path_str = nil
                    -- 先处理 cjson.null
                    if backend_path and backend_path ~= cjson.null then
                        backend_path_str = tostring(backend_path)
                        -- 去除前后空格
                        backend_path_str = backend_path_str:gsub("^%s+", ""):gsub("%s+$", "")
                        -- 如果为空字符串，设置为 nil
                        if backend_path_str == "" then
                            backend_path_str = nil
                        end
                    end
                    
                    if backend_path_str and backend_path_str ~= "" then
                        -- 有目标路径，拼接路径
                        config = config .. "        proxy_pass http://" .. location_upstream_name .. escape_nginx_value(backend_path_str) .. ";\n"
                    else
                        -- 没有目标路径，直接代理到根路径
                        config = config .. "        proxy_pass http://" .. location_upstream_name .. ";\n"
                    end
                else
                    ngx.log(ngx.ERR, "generate_http_config: no backends for location=", loc.location_path, ", proxy_id=", proxy.id, ", proxy_name=", proxy.proxy_name)
                    config = config .. "        # 错误：缺少后端服务器配置\n"
                    config = config .. "        return 503;\n"
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
            end
        end
    else
        -- 如果没有location_paths，记录错误并返回503
        ngx.log(ngx.ERR, "generate_http_config: no location_paths for proxy_id=", proxy.id, ", proxy_name=", proxy.proxy_name)
        config = config .. "\n    # 错误：缺少location_paths配置\n"
        config = config .. "    location / {\n"
        config = config .. "        return 503;\n"
        config = config .. "    }\n"
    end
    
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
    
    -- 新命名格式：stream_$proxy_type
    local proxy_type_safe = sanitize_upstream_name(proxy.proxy_type)
    local upstream_name = "stream_" .. proxy_type_safe
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
            -- 处理 cjson.null，确保 backend_address 和 backend_port 不为 nil
            local backend_address = null_to_nil(backend.backend_address)
            local backend_port = normalize_port(backend.backend_port)
            
            if not backend_address or not backend_port then
                ngx.log(ngx.WARN, "跳过无效的后端服务器配置（地址或端口为空）: ", cjson.encode(backend))
                goto continue
            end
            
            local server_line = "    server " .. escape_nginx_value(backend_address) .. ":" .. backend_port
            local weight = null_to_nil(backend.weight)
            if weight and weight > 1 then
                server_line = server_line .. " weight=" .. weight
            end
            local max_fails = null_to_nil(backend.max_fails)
            if max_fails then
                server_line = server_line .. " max_fails=" .. max_fails
            end
            local fail_timeout = null_to_nil(backend.fail_timeout)
            if fail_timeout then
                server_line = server_line .. " fail_timeout=" .. fail_timeout .. "s"
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
        ::continue::
    end
    
    config = config .. "}\n\n"
    return config, upstream_name
end

-- 生成TCP/UDP stream server块配置
local function generate_stream_server_config(proxy, upstream_name)
    local config = "server {\n"
    
    -- 监听端口
    config = config .. "    listen " .. proxy.listen_port
    if proxy.proxy_type == "udp" then
        config = config .. " udp"
    end
    config = config .. ";\n"
    
    -- WAF封控检查（如果关联了防护规则）
    local ip_rule_ids = proxy.ip_rule_ids
    if ip_rule_ids and type(ip_rule_ids) == "table" and #ip_rule_ids > 0 then
        config = config .. "\n    # WAF封控检查（关联防护规则ID: " .. table.concat(ip_rule_ids, ",") .. "）\n"
        -- 将规则ID数组转换为Lua表字符串
        local rule_ids_str = "{"
        for i, rule_id in ipairs(ip_rule_ids) do
            if i > 1 then
                rule_ids_str = rule_ids_str .. ","
            end
            rule_ids_str = rule_ids_str .. rule_id
        end
        rule_ids_str = rule_ids_str .. "}"
        config = config .. "    set $proxy_ip_rule_ids '" .. rule_ids_str .. "';\n"
        config = config .. "    preread_by_lua_block {\n"
        config = config .. "        local rule_ids_str = ngx.var.proxy_ip_rule_ids\n"
        config = config .. "        local rule_ids = {}\n"
        config = config .. "        if rule_ids_str then\n"
        config = config .. "            -- 解析Lua表字符串（格式：{1,2,3}）\n"
        config = config .. "            local ids_str = rule_ids_str:match(\"^%s*{%s*(.-)%s*}%s*$\")\n"
        config = config .. "            if ids_str then\n"
        config = config .. "                for id_str in ids_str:gmatch(\"([^,]+)\") do\n"
        config = config .. "                    local id = tonumber(id_str:match(\"^%s*(.-)%s*$\"))\n"
        config = config .. "                    if id then\n"
        config = config .. "                        table.insert(rule_ids, id)\n"
        config = config .. "                    end\n"
        config = config .. "                end\n"
        config = config .. "            else\n"
        config = config .. "                -- 兼容旧格式：单个规则ID\n"
        config = config .. "                local single_id = tonumber(rule_ids_str)\n"
        config = config .. "                if single_id then\n"
        config = config .. "                    rule_ids = {single_id}\n"
        config = config .. "                end\n"
        config = config .. "            end\n"
        config = config .. "        end\n"
        config = config .. "        require(\"waf.ip_block\").check_stream_multiple(rule_ids)\n"
        config = config .. "    }\n"
    end
    
    -- 代理到后端
    -- 注意：只支持upstream类型（多个后端服务器），使用upstream配置
    if upstream_name then
        config = config .. "    proxy_pass " .. upstream_name .. ";\n"
    else
        -- 如果没有upstream配置，记录错误（不应该发生，因为现在只支持upstream类型）
        ngx.log(ngx.ERR, "generate_tcp_udp_config: no upstream config for proxy_id=", proxy.id, ", proxy_name=", proxy.proxy_name)
        config = config .. "    # 错误：缺少后端服务器配置\n"
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
local function generate_http_proxy_file(proxy, upstream_name, backends)
    local config = "# ============================================\n"
    config = config .. "# 代理配置: " .. escape_nginx_value(proxy.proxy_name) .. " (ID: " .. tostring(proxy.id) .. ")\n"
    config = config .. "# 自动生成，请勿手动修改\n"
    config = config .. "# ============================================\n\n"
    
    -- 写入server配置（upstream配置已单独生成）
    config = config .. generate_http_server_config(proxy, upstream_name, backends)
    
    return config
end

-- 生成单个Stream代理的server配置（不包含upstream）
local function generate_stream_proxy_file(proxy, upstream_name)
    local config = "# ============================================\n"
    config = config .. "# 代理配置: " .. escape_nginx_value(proxy.proxy_name) .. " (ID: " .. tostring(proxy.id) .. ")\n"
    config = config .. "# 类型: " .. string.upper(proxy.proxy_type) .. "\n"
    config = config .. "# 自动生成，请勿手动修改\n"
    config = config .. "# ============================================\n\n"
    
    -- 写入server配置（upstream配置已单独生成）
    config = config .. generate_stream_server_config(proxy, upstream_name)
    
    return config
end

-- 清理已删除或禁用的代理的配置文件
local function cleanup_orphaned_files(project_root, active_proxy_ids, active_proxy_names, active_location_files)
    active_proxy_names = active_proxy_names or {}
    active_location_files = active_location_files or {}
    local deleted_count = 0
    local failed_count = 0
    
    -- HTTP/HTTPS upstream配置文件
    -- 新命名格式：http_upstream_$proxy_name_$location_path.conf 或 http_upstream_$proxy_name.conf
    local http_upstream_dir = project_root .. "/conf.d/upstream/http_https"
    local http_upstream_cmd = "find " .. http_upstream_dir .. " -maxdepth 1 -name 'http_upstream_*.conf' 2>/dev/null"
    local http_upstream_files = io.popen(http_upstream_cmd)
    if http_upstream_files then
        for file in http_upstream_files:lines() do
            local filename = file:match("([^/]+)$")  -- 获取文件名
            -- 检查是否是活跃的文件（通过文件名匹配）
            local is_active = false
            if filename and active_location_files[filename] then
                is_active = true
            else
                -- 检查是否是单upstream文件（格式：http_upstream_$proxy_name.conf）
                for proxy_name, _ in pairs(active_proxy_names) do
                    if filename == "http_upstream_" .. proxy_name .. ".conf" then
                        is_active = true
                        break
                    end
                end
            end
            
            if not is_active then
                local ok, err = os.remove(file)
                if ok then
                    ngx.log(ngx.INFO, "删除已删除或禁用的代理的HTTP upstream配置文件: ", file)
                    deleted_count = deleted_count + 1
                else
                    ngx.log(ngx.WARN, "删除upstream配置文件失败: ", file, ", 错误: ", err or "unknown")
                    failed_count = failed_count + 1
                end
            end
        end
        http_upstream_files:close()
    end
    
    -- HTTP/HTTPS server配置文件
    -- 新命名格式：proxy_http_$proxy_name.conf
    local http_server_dir = project_root .. "/conf.d/vhost_conf/http_https"
    local http_server_cmd = "find " .. http_server_dir .. " -maxdepth 1 -name 'proxy_http_*.conf' 2>/dev/null"
    local http_server_files = io.popen(http_server_cmd)
    if http_server_files then
        for file in http_server_files:lines() do
            local filename = file:match("([^/]+)$")  -- 获取文件名
            -- 检查是否是活跃的文件（通过代理名称匹配）
            local is_active = false
            for proxy_name, _ in pairs(active_proxy_names) do
                if filename == "proxy_http_" .. proxy_name .. ".conf" then
                    is_active = true
                    break
                end
            end
            
            if not is_active then
                local ok, err = os.remove(file)
                if ok then
                    ngx.log(ngx.INFO, "删除已删除或禁用的代理的HTTP server配置文件: ", file)
                    deleted_count = deleted_count + 1
                else
                    ngx.log(ngx.WARN, "删除server配置文件失败: ", file, ", 错误: ", err or "unknown")
                    failed_count = failed_count + 1
                end
            end
        end
        http_server_files:close()
    end
    
    -- TCP/UDP upstream配置文件
    -- 新命名格式：stream_upstream_$proxy_name.conf 或 tcp_upstream_$proxy_name.conf 或 udp_upstream_$proxy_name.conf
    local stream_upstream_dir = project_root .. "/conf.d/upstream/tcp_udp"
    local stream_upstream_cmd = "find " .. stream_upstream_dir .. " -maxdepth 1 -name '*_upstream_*.conf' 2>/dev/null"
    local stream_upstream_files = io.popen(stream_upstream_cmd)
    if stream_upstream_files then
        for file in stream_upstream_files:lines() do
            local filename = file:match("([^/]+)$")  -- 获取文件名
            -- 检查是否是活跃的文件（通过代理名称匹配）
            local is_active = false
            for proxy_name, _ in pairs(active_proxy_names) do
                if filename == "stream_upstream_" .. proxy_name .. ".conf" or
                   filename == "tcp_upstream_" .. proxy_name .. ".conf" or
                   filename == "udp_upstream_" .. proxy_name .. ".conf" then
                    is_active = true
                    break
                end
            end
            
            if not is_active then
                local ok, err = os.remove(file)
                if ok then
                    ngx.log(ngx.INFO, "删除已删除或禁用的代理的Stream upstream配置文件: ", file)
                    deleted_count = deleted_count + 1
                else
                    ngx.log(ngx.WARN, "删除upstream配置文件失败: ", file, ", 错误: ", err or "unknown")
                    failed_count = failed_count + 1
                end
            end
        end
        stream_upstream_files:close()
    end
    
    -- TCP/UDP server配置文件
    -- 新命名格式：proxy_stream_$proxy_name.conf 或 proxy_tcp_$proxy_name.conf 或 proxy_udp_$proxy_name.conf
    local stream_server_dir = project_root .. "/conf.d/vhost_conf/tcp_udp"
    local stream_server_cmd = "find " .. stream_server_dir .. " -maxdepth 1 -name 'proxy_*.conf' 2>/dev/null"
    local stream_server_files = io.popen(stream_server_cmd)
    if stream_server_files then
        for file in stream_server_files:lines() do
            local filename = file:match("([^/]+)$")  -- 获取文件名
            -- 检查是否是活跃的文件（通过代理名称匹配）
            local is_active = false
            for proxy_name, _ in pairs(active_proxy_names) do
                if filename == "proxy_stream_" .. proxy_name .. ".conf" or
                   filename == "proxy_tcp_" .. proxy_name .. ".conf" or
                   filename == "proxy_udp_" .. proxy_name .. ".conf" then
                    is_active = true
                    break
                end
            end
            
            if not is_active then
                local ok, err = os.remove(file)
                if ok then
                    ngx.log(ngx.INFO, "删除已删除或禁用的代理的Stream server配置文件: ", file)
                    deleted_count = deleted_count + 1
                else
                    ngx.log(ngx.WARN, "删除server配置文件失败: ", file, ", 错误: ", err or "unknown")
                    failed_count = failed_count + 1
                end
            end
        end
        stream_server_files:close()
    end
    
    if deleted_count > 0 then
        ngx.log(ngx.INFO, "清理完成: 删除了 ", deleted_count, " 个配置文件")
    end
    if failed_count > 0 then
        ngx.log(ngx.WARN, "清理完成: ", failed_count, " 个配置文件删除失败")
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
    -- 注意：只查询 status = 1 的代理，禁用的代理（status = 0）不会被查询
    -- 禁用的代理的配置文件会在 cleanup_orphaned_files() 中被清理
        local sql = [[
            SELECT id, proxy_name, proxy_type, listen_port, listen_address, server_name, location_paths,
               backend_type, load_balance,
               ssl_enable, ssl_cert_path, ssl_key_path,
               proxy_timeout, proxy_connect_timeout, proxy_send_timeout, proxy_read_timeout,
               status
            FROM waf_proxy_configs
            WHERE status = 1
            ORDER BY id ASC
        ]]
    
    local proxies, err = mysql_pool.query(sql)
    if err then
        ngx.log(ngx.ERR, "查询代理配置失败: ", err)
        return false, "查询代理配置失败: " .. err
    end
    
    -- 确保目录存在
    local dirs = {
        project_root .. "/conf.d/http_set",
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
        cleanup_orphaned_files(project_root, active_proxy_ids, {})
        return true, "没有启用的代理配置，已清理所有配置文件"
    end
    
    -- 构建活跃代理名称映射（用于清理已删除的配置文件，基于新命名格式）
    local active_proxy_names = {}
    -- 构建活跃代理的 location_path 映射（用于清理 location upstream 文件）
    local active_location_files = {}
    
    -- 为每个代理生成独立的配置文件
    for _, proxy in ipairs(proxies) do
        active_proxy_ids[proxy.id] = true
        -- 记录代理名称（用于新命名格式的文件清理）
        local proxy_name_safe = sanitize_filename(proxy.proxy_name)
        if proxy_name_safe and proxy_name_safe ~= "" then
            active_proxy_names[proxy_name_safe] = true
        end
        
        -- 解析location_paths JSON字段
        if proxy.location_paths then
            local ok, decoded_location_paths = pcall(cjson.decode, proxy.location_paths)
            if ok and decoded_location_paths and type(decoded_location_paths) == "table" then
                proxy.location_paths = decoded_location_paths
            else
                proxy.location_paths = nil
            end
        else
            proxy.location_paths = nil
        end
        
        -- 查询后端服务器并生成upstream配置
        -- 注意：只支持upstream类型（多个后端服务器），不再支持single类型
        local backends = nil
        local upstream_name = nil
        local upstream_config = nil
        
        -- 从数据库查询多个后端服务器（包含location_path字段）
        local backends_sql = [[
            SELECT id, location_path, backend_address, backend_port, backend_path, weight, max_fails, fail_timeout,
                   backup, down, status
            FROM waf_proxy_backends
            WHERE proxy_id = ? AND status = 1
            ORDER BY location_path, weight DESC, id ASC
        ]]
        backends, _ = mysql_pool.query(backends_sql, proxy.id)
        
        -- 对于HTTP/HTTPS代理，如果使用location_paths，为每个location生成独立的upstream配置
        if proxy.proxy_type == "http" and proxy.location_paths and type(proxy.location_paths) == "table" and #proxy.location_paths > 0 then
            -- 为每个location生成独立的upstream配置
            local upstream_dir = project_root .. "/conf.d/upstream/http_https"
            
            -- 确保父目录存在且有正确权限
            local upstream_parent_dir = project_root .. "/conf.d/upstream"
            local parent_dir_ok = path_utils.ensure_dir(upstream_parent_dir)
            if not parent_dir_ok then
                ngx.log(ngx.ERR, "无法创建upstream父目录: ", upstream_parent_dir)
                return false, "无法创建upstream父目录: " .. upstream_parent_dir
            end
            
            -- 确保目标目录存在
            local dir_ok = path_utils.ensure_dir(upstream_dir)
            if not dir_ok then
                ngx.log(ngx.ERR, "无法创建upstream目录: ", upstream_dir)
                return false, "无法创建upstream目录: " .. upstream_dir
            end
            
            -- 检查目录是否有写入权限
            local test_file, err_msg = io.open(upstream_dir .. "/.test_write", "w")
            if test_file then
                test_file:close()
                local remove_ok, remove_err = os.remove(upstream_dir .. "/.test_write")
                if not remove_ok then
                    ngx.log(ngx.WARN, "无法删除测试文件: ", upstream_dir .. "/.test_write", ", 错误: ", tostring(remove_err))
                end
            else
                -- 获取更详细的错误信息
                local detailed_err = err_msg or "unknown error"
                
                -- 尝试获取目录权限信息（用于诊断）
                local dir_info = ""
                local stat_cmd = "stat -c '所有者:%U:%G 权限:%a 类型:%F' '" .. upstream_dir .. "' 2>&1"
                local stat_file = io.popen(stat_cmd)
                if stat_file then
                    local stat_output = stat_file:read("*a")
                    stat_file:close()
                    if stat_output and stat_output ~= "" then
                        dir_info = ", 目录信息: " .. stat_output:gsub("\n", " "):gsub("%s+", " ")
                    end
                end
                
                -- 尝试获取当前进程用户信息
                local current_user = os.getenv("USER") or os.getenv("USERNAME") or "unknown"
                local worker_pid_ok, worker_pid = pcall(function() return ngx.worker.pid() end)
                local pid = (worker_pid_ok and worker_pid) or "$$"
                local process_user_cmd = "ps -o user= -p " .. pid .. " 2>&1"
                local process_user_file = io.popen(process_user_cmd)
                if process_user_file then
                    local process_user_output = process_user_file:read("*a")
                    process_user_file:close()
                    if process_user_output and process_user_output ~= "" then
                        current_user = process_user_output:gsub("%s+", "")
                    end
                end
                
                -- 尝试获取父目录权限信息
                local parent_info = ""
                local parent_stat_cmd = "stat -c '所有者:%U:%G 权限:%a' '" .. upstream_parent_dir .. "' 2>&1"
                local parent_stat_file = io.popen(parent_stat_cmd)
                if parent_stat_file then
                    local parent_stat_output = parent_stat_file:read("*a")
                    parent_stat_file:close()
                    if parent_stat_output and parent_stat_output ~= "" then
                        parent_info = ", 父目录信息: " .. parent_stat_output:gsub("\n", " "):gsub("%s+", " ")
                    end
                end
                
                -- 检查进程用户是否与目录所有者匹配
                local user_mismatch = ""
                local fix_suggestion = ""
                if dir_info:match("所有者:([^:]+):") then
                    local dir_owner = dir_info:match("所有者:([^:]+):")
                    if current_user ~= dir_owner and current_user ~= "unknown" then
                        user_mismatch = ", ⚠️ 进程用户(" .. current_user .. ")与目录所有者(" .. dir_owner .. ")不匹配"
                        fix_suggestion = ", 修复步骤: 1) 检查 /etc/systemd/system/openresty.service 中的 User= 和 Group= 配置; 2) 执行 systemctl daemon-reload; 3) 执行 systemctl restart openresty"
                    end
                end
                
                ngx.log(ngx.ERR, "upstream目录无写入权限: ", upstream_dir, 
                    ", 错误: ", detailed_err,
                    ", 进程用户: ", current_user,
                    dir_info,
                    parent_info,
                    user_mismatch,
                    ", 修复建议: chown -R waf:waf ", upstream_dir, " && chmod 755 ", upstream_dir,
                    fix_suggestion)
                return false, "upstream目录无写入权限: " .. upstream_dir .. " (错误: " .. detailed_err .. ", 进程用户: " .. current_user .. user_mismatch .. ")"
            end
            
            -- 为每个location生成upstream配置
            for loc_index, loc in ipairs(proxy.location_paths) do
                if loc.location_path and loc.location_path ~= "" then
                    -- 筛选属于当前location的后端服务器
                    local location_backends = {}
                    for _, backend in ipairs(backends or {}) do
                        local backend_location_path = null_to_nil(backend.location_path)
                        if backend_location_path == loc.location_path then
                            table.insert(location_backends, backend)
                        end
                    end
                    
                    -- 如果该location有后端服务器，生成upstream配置
                    if #location_backends > 0 then
                        -- 生成upstream名称：upstream_$proxy_name_$location_path
                        local proxy_name_safe = sanitize_upstream_name(proxy.proxy_name)
                        local location_path_safe = sanitize_upstream_name(loc.location_path)
                        local location_upstream_name = "upstream_" .. proxy_name_safe .. "_" .. location_path_safe
                        local location_upstream_config = generate_upstream_config_for_location(proxy, location_backends, location_upstream_name)
                        
                        if location_upstream_config then
                            -- 生成独立的upstream配置文件
                            -- 新命名格式：http_upstream_$proxy_name_$location_path.conf
                            local proxy_name_safe = sanitize_filename(proxy.proxy_name)
                            local location_path_safe = sanitize_filename(loc.location_path)
                            local location_upstream_filename = "http_upstream_" .. proxy_name_safe .. "_" .. location_path_safe .. ".conf"
                            local location_upstream_file = upstream_dir .. "/" .. location_upstream_filename
                            
                            -- 记录活跃的 location upstream 文件（用于清理）
                            active_location_files[location_upstream_filename] = true
                            
                            local upstream_fd = io.open(location_upstream_file, "w")
                            if upstream_fd then
                                local upstream_file_content = "# ============================================\n"
                                upstream_file_content = upstream_file_content .. "# Upstream配置: " .. escape_nginx_value(proxy.proxy_name) .. " (代理ID: " .. tostring(proxy.id) .. ")\n"
                                upstream_file_content = upstream_file_content .. "# Location路径: " .. escape_nginx_value(loc.location_path) .. "\n"
                                upstream_file_content = upstream_file_content .. "# 类型: " .. string.upper(proxy.proxy_type) .. "\n"
                                upstream_file_content = upstream_file_content .. "# 后端类型: 多个后端（负载均衡）\n"
                                upstream_file_content = upstream_file_content .. "# 自动生成，请勿手动修改\n"
                                upstream_file_content = upstream_file_content .. "# ============================================\n\n"
                                upstream_file_content = upstream_file_content .. location_upstream_config
                                upstream_fd:write(upstream_file_content)
                                upstream_fd:close()
                                ngx.log(ngx.INFO, "生成location upstream配置文件: ", location_upstream_file, " (location: ", loc.location_path, ")")
                            else
                                ngx.log(ngx.ERR, "无法创建location upstream配置文件: ", location_upstream_file)
                                return false, "无法创建location upstream配置文件: " .. location_upstream_file
                            end
                        end
                    end
                end
            end
        else
            -- 向后兼容：如果没有location_paths或不是HTTP代理，使用原来的逻辑（单个upstream配置）
            if backends and #backends > 0 then
                if proxy.proxy_type == "http" then
                    upstream_config, upstream_name = generate_upstream_config(proxy, backends)
                else
                    upstream_config, upstream_name = generate_stream_upstream_config(proxy, backends)
                end
                
                -- 生成独立的upstream配置文件
                if upstream_config and upstream_name then
                    -- 根据代理类型确定upstream配置文件目录和文件名
                    local upstream_subdir = ""
                    local upstream_filename = ""
                    if proxy.proxy_type == "http" then
                        upstream_subdir = "http_https"
                        -- HTTP/HTTPS upstream文件名使用新格式：http_upstream_$proxy_name.conf
                        local proxy_name_safe = sanitize_filename(proxy.proxy_name)
                        upstream_filename = "http_upstream_" .. proxy_name_safe .. ".conf"
                    else
                        upstream_subdir = "tcp_udp"
                        -- TCP/UDP upstream文件名使用新格式：stream_upstream_$proxy_name.conf 或 tcp_upstream_$proxy_name.conf 或 udp_upstream_$proxy_name.conf
                        local proxy_name_safe = sanitize_filename(proxy.proxy_name)
                        local proxy_type_prefix = "stream"
                        if proxy.proxy_type == "tcp" then
                            proxy_type_prefix = "tcp"
                        elseif proxy.proxy_type == "udp" then
                            proxy_type_prefix = "udp"
                        end
                        upstream_filename = proxy_type_prefix .. "_upstream_" .. proxy_name_safe .. ".conf"
                    end
                    
                    local upstream_file = project_root .. "/conf.d/upstream/" .. upstream_subdir .. "/" .. upstream_filename
                    
                    -- 确保upstream子目录存在
                    local upstream_dir = project_root .. "/conf.d/upstream/" .. upstream_subdir
                    
                    -- 确保父目录存在且有正确权限
                    local upstream_parent_dir = project_root .. "/conf.d/upstream"
                    local parent_dir_ok = path_utils.ensure_dir(upstream_parent_dir)
                    if not parent_dir_ok then
                        ngx.log(ngx.ERR, "无法创建upstream父目录: ", upstream_parent_dir)
                        return false, "无法创建upstream父目录: " .. upstream_parent_dir
                    end
                    
                    local dir_ok = path_utils.ensure_dir(upstream_dir)
                    if not dir_ok then
                        ngx.log(ngx.ERR, "无法创建upstream目录: ", upstream_dir)
                        return false, "无法创建upstream目录: " .. upstream_dir
                    end
                    
                    -- 检查目录是否存在且有写入权限
                    local test_file, err_msg = io.open(upstream_dir .. "/.test_write", "w")
                    if test_file then
                        test_file:close()
                        local remove_ok, remove_err = os.remove(upstream_dir .. "/.test_write")
                        if not remove_ok then
                            ngx.log(ngx.WARN, "无法删除测试文件: ", upstream_dir .. "/.test_write", ", 错误: ", tostring(remove_err))
                        end
                    else
                        -- 获取更详细的错误信息
                        local detailed_err = err_msg or "unknown error"
                        
                        -- 尝试获取目录权限信息（用于诊断）
                        local dir_info = ""
                        local stat_cmd = "stat -c '所有者:%U:%G 权限:%a 类型:%F' '" .. upstream_dir .. "' 2>&1"
                        local stat_file = io.popen(stat_cmd)
                        if stat_file then
                            local stat_output = stat_file:read("*a")
                            stat_file:close()
                            if stat_output and stat_output ~= "" then
                                dir_info = ", 目录信息: " .. stat_output:gsub("\n", " "):gsub("%s+", " ")
                            end
                        end
                        
                        -- 尝试获取当前进程用户信息
                        local current_user = os.getenv("USER") or os.getenv("USERNAME") or "unknown"
                        local worker_pid_ok, worker_pid = pcall(function() return ngx.worker.pid() end)
                        local pid = (worker_pid_ok and worker_pid) or "$$"
                        local process_user_cmd = "ps -o user= -p " .. pid .. " 2>&1"
                        local process_user_file = io.popen(process_user_cmd)
                        if process_user_file then
                            local process_user_output = process_user_file:read("*a")
                            process_user_file:close()
                            if process_user_output and process_user_output ~= "" then
                                current_user = process_user_output:gsub("%s+", "")
                            end
                        end
                        
                        -- 尝试获取父目录权限信息
                        local parent_info = ""
                        local parent_stat_cmd = "stat -c '所有者:%U:%G 权限:%a' '" .. upstream_parent_dir .. "' 2>&1"
                        local parent_stat_file = io.popen(parent_stat_cmd)
                        if parent_stat_file then
                            local parent_stat_output = parent_stat_file:read("*a")
                            parent_stat_file:close()
                            if parent_stat_output and parent_stat_output ~= "" then
                                parent_info = ", 父目录信息: " .. parent_stat_output:gsub("\n", " "):gsub("%s+", " ")
                            end
                        end
                        
                        -- 检查进程用户是否与目录所有者匹配
                        local user_mismatch = ""
                        local fix_suggestion = ""
                        if dir_info:match("所有者:([^:]+):") then
                            local dir_owner = dir_info:match("所有者:([^:]+):")
                            if current_user ~= dir_owner and current_user ~= "unknown" then
                                user_mismatch = ", ⚠️ 进程用户(" .. current_user .. ")与目录所有者(" .. dir_owner .. ")不匹配"
                                fix_suggestion = ", 修复步骤: 1) 检查 /etc/systemd/system/openresty.service 中的 User= 和 Group= 配置; 2) 执行 systemctl daemon-reload; 3) 执行 systemctl restart openresty"
                            end
                        end
                        
                        ngx.log(ngx.ERR, "upstream目录无写入权限: ", upstream_dir, 
                            ", 错误: ", detailed_err,
                            ", 进程用户: ", current_user,
                            dir_info,
                            parent_info,
                            user_mismatch,
                            ", 修复建议: chown -R waf:waf ", upstream_dir, " && chmod 755 ", upstream_dir,
                            fix_suggestion)
                        return false, "upstream目录无写入权限: " .. upstream_dir .. " (错误: " .. detailed_err .. ", 进程用户: " .. current_user .. user_mismatch .. ")"
                    end
                    
                    local upstream_fd = io.open(upstream_file, "w")
                    if upstream_fd then
                        local upstream_file_content = "# ============================================\n"
                        upstream_file_content = upstream_file_content .. "# Upstream配置: " .. escape_nginx_value(proxy.proxy_name) .. " (代理ID: " .. tostring(proxy.id) .. ")\n"
                        upstream_file_content = upstream_file_content .. "# 类型: " .. string.upper(proxy.proxy_type) .. "\n"
                        upstream_file_content = upstream_file_content .. "# 后端类型: 多个后端（负载均衡）\n"
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
        end
        
        -- 根据代理类型生成对应的server配置文件
        if proxy.proxy_type == "http" then
            -- 生成HTTP代理server配置文件
            local config_content = generate_http_proxy_file(proxy, upstream_name, backends)
            -- HTTP/HTTPS server配置放在 vhost_conf/http_https 子目录
            -- 新命名格式：proxy_http_$proxy_name.conf
            local proxy_name_safe = sanitize_filename(proxy.proxy_name)
            local config_file = project_root .. "/conf.d/vhost_conf/http_https/proxy_http_" .. proxy_name_safe .. ".conf"
            
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
            -- 新命名格式：proxy_stream_$proxy_name.conf 或 proxy_tcp_$proxy_name.conf 或 proxy_udp_$proxy_name.conf
            local proxy_name_safe = sanitize_filename(proxy.proxy_name)
            local proxy_type_prefix = "stream"
            if proxy.proxy_type == "tcp" then
                proxy_type_prefix = "tcp"
            elseif proxy.proxy_type == "udp" then
                proxy_type_prefix = "udp"
            end
            local config_file = project_root .. "/conf.d/vhost_conf/tcp_udp/proxy_" .. proxy_type_prefix .. "_" .. proxy_name_safe .. ".conf"
            
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
    
    -- 清理已删除或禁用的代理的配置文件
    -- 注意：active_proxy_ids 只包含 status = 1 的代理ID
    -- 所以禁用的代理（status = 0）和已删除的代理的配置文件都会被清理
    cleanup_orphaned_files(project_root, active_proxy_ids, active_proxy_names, active_location_files)
    
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
    local http_upstream_cmd = "find " .. http_upstream_dir .. " -maxdepth 1 -name 'http_upstream_*.conf' 2>/dev/null"
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


