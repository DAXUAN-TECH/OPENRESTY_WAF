-- 反向代理管理模块
-- 路径：项目目录下的 lua/waf/proxy_management.lua（保持在项目目录，不复制到系统目录）
-- 功能：实现反向代理配置的CRUD操作

local mysql_pool = require "waf.mysql_pool"
local cjson = require "cjson"
local nginx_config_generator = require "waf.nginx_config_generator"

local _M = {}

-- 验证代理配置
local function validate_proxy_config(proxy_data)
    -- 处理 cjson.null，转换为 nil
    local cjson = require "cjson"
    local function null_to_nil(value)
        if value == nil or value == cjson.null then
            return nil
        end
        return value
    end
    
    if not proxy_data.proxy_name or proxy_data.proxy_name == "" then
        return false, "代理名称不能为空"
    end
    
    if not proxy_data.proxy_type then
        return false, "代理类型不能为空"
    end
    
    local valid_types = {http = true, tcp = true, udp = true}
    if not valid_types[proxy_data.proxy_type] then
        return false, "无效的代理类型（支持：http、tcp、udp）"
    end
    
    -- 处理 listen_port，确保不是 cjson.null，并转换为数字
    local listen_port = null_to_nil(proxy_data.listen_port)
    if listen_port then
        listen_port = tonumber(listen_port)
    end
    if not listen_port or listen_port < 1 or listen_port > 65535 then
        return false, "监听端口必须在1-65535之间"
    end
    
    -- 验证 server_name（监听域名）
    -- HTTP/HTTPS 代理：server_name 可以为空（使用默认server块）
    -- TCP/UDP 代理：server_name 必须为空（TCP/UDP 代理不支持域名）
    local server_name = null_to_nil(proxy_data.server_name)
    if proxy_data.proxy_type ~= "http" then
        if server_name and server_name ~= "" then
            return false, "TCP/UDP 代理不支持监听域名配置"
        end
    end
    
    -- 验证后端服务器列表（只支持upstream类型）
    if not proxy_data.backends or type(proxy_data.backends) ~= "table" or #proxy_data.backends == 0 then
        return false, "后端服务器列表不能为空，至少需要添加一个后端服务器"
    end
    
    -- 验证每个后端服务器
    for i, backend in ipairs(proxy_data.backends) do
        if not backend.backend_address or backend.backend_address == "" then
            return false, string.format("第%d个后端服务器的地址不能为空", i)
        end
        -- 处理 backend_port，确保不是 cjson.null，并转换为数字
        local backend_port = null_to_nil(backend.backend_port)
        if backend_port then
            backend_port = tonumber(backend_port)
        end
        if not backend_port or backend_port < 1 or backend_port > 65535 then
            return false, string.format("第%d个后端服务器的端口必须在1-65535之间", i)
        end
        -- 只有HTTP/HTTPS代理才允许有backend_path，TCP/UDP代理不应该有backend_path
        if proxy_data.proxy_type ~= "http" then
            local backend_path = null_to_nil(backend.backend_path)
            if backend_path and backend_path ~= "" then
                return false, string.format("第%d个后端服务器：TCP/UDP代理不支持后端路径配置", i)
            end
            -- 清除 TCP/UDP 代理的 backend_path 字段（如果存在）
            backend.backend_path = nil
        end
    end
    
    -- 验证代理名称（防止SQL注入，只允许字母、数字、下划线、中文字符和常见分隔符）
    if not proxy_data.proxy_name:match("^[%w%u4e00-%u9fa5_%-%.%s]+$") then
        return false, "代理名称包含非法字符，只允许字母、数字、下划线、中文字符和常见分隔符"
    end
    
    -- 限制代理名称长度
    if #proxy_data.proxy_name > 100 then
        return false, "代理名称长度不能超过100个字符"
    end
    
    return true, nil
end

-- 创建代理配置
function _M.create_proxy(proxy_data)
    -- 验证配置
    local valid, err = validate_proxy_config(proxy_data)
    if not valid then
        return nil, err
    end
    
    -- 检查代理名称是否已存在
    local check_sql = "SELECT id FROM waf_proxy_configs WHERE proxy_name = ? LIMIT 1"
    local existing = mysql_pool.query(check_sql, proxy_data.proxy_name)
    if existing and #existing > 0 then
        return nil, "代理名称已存在"
    end
    
    -- 处理 cjson.null，转换为 nil
    local cjson = require "cjson"
    local function null_to_nil(value)
        if value == nil or value == cjson.null then
            return nil
        end
        return value
    end
    
    -- 确保 listen_port 是数字（验证函数已经验证过，这里再次确保）
    local listen_port = tonumber(proxy_data.listen_port)
    if not listen_port then
        return nil, "监听端口必须是有效的数字"
    end
    
    -- 检查端口是否已被占用（相同类型的代理）
    -- 对于HTTP/HTTPS代理，如果使用server_name（域名），可以共享端口
    local server_name = null_to_nil(proxy_data.server_name)
    local port_check_sql
    if proxy_data.proxy_type == "http" and server_name and server_name ~= "" then
        -- HTTP/HTTPS代理且有域名：检查是否有相同域名的代理占用端口，或是否有无域名的代理占用端口
        port_check_sql = [[
            SELECT id FROM waf_proxy_configs 
            WHERE proxy_type = ? AND listen_port = ? AND status = 1
            AND (server_name = ? OR server_name IS NULL OR server_name = '')
            LIMIT 1
        ]]
        local port_conflict = mysql_pool.query(port_check_sql, proxy_data.proxy_type, listen_port, server_name)
        if port_conflict and #port_conflict > 0 then
            return nil, "该端口已被其他启用的代理配置占用（相同域名或无域名的代理不能共享端口）"
        end
    elseif proxy_data.proxy_type == "http" then
        -- HTTP/HTTPS代理但无域名：不能与任何其他代理共享端口
        port_check_sql = [[
            SELECT id FROM waf_proxy_configs 
            WHERE proxy_type = ? AND listen_port = ? AND status = 1
            LIMIT 1
        ]]
        local port_conflict = mysql_pool.query(port_check_sql, proxy_data.proxy_type, listen_port)
        if port_conflict and #port_conflict > 0 then
            return nil, "该端口已被其他启用的代理配置占用（无域名的代理不能与其他代理共享端口）"
        end
    else
        -- TCP/UDP代理：严格的端口占用检查
        port_check_sql = [[
            SELECT id FROM waf_proxy_configs 
            WHERE proxy_type = ? AND listen_port = ? AND status = 1
            LIMIT 1
        ]]
        local port_conflict = mysql_pool.query(port_check_sql, proxy_data.proxy_type, listen_port)
        if port_conflict and #port_conflict > 0 then
            return nil, "该端口已被其他启用的代理配置占用"
        end
    end
    
    -- 验证ip_rule_ids（如果提供，支持多个规则ID，但必须遵守互斥关系）
    local ip_rule_ids = nil
    if proxy_data.ip_rule_ids and type(proxy_data.ip_rule_ids) == "table" and #proxy_data.ip_rule_ids > 0 then
        ip_rule_ids = proxy_data.ip_rule_ids
        -- 规则互斥关系定义
        local rule_conflicts = {
            ip_whitelist = {"ip_blacklist"},
            ip_blacklist = {"ip_whitelist"},
            geo_whitelist = {"geo_blacklist"},
            geo_blacklist = {"geo_whitelist"}
        }
        
        -- 验证所有规则是否存在且为IP相关类型
        local rule_types = {}
        for _, rule_id in ipairs(ip_rule_ids) do
            local rule_check_sql = "SELECT id, rule_type FROM waf_block_rules WHERE id = ? AND status = 1 LIMIT 1"
            local rule_check = mysql_pool.query(rule_check_sql, rule_id)
            if not rule_check or #rule_check == 0 then
                return nil, "指定的防护规则不存在或已禁用: " .. tostring(rule_id)
            end
            local rule_type = rule_check[1].rule_type
            if rule_type ~= "ip_whitelist" and rule_type ~= "ip_blacklist" and 
               rule_type ~= "geo_whitelist" and rule_type ~= "geo_blacklist" then
                return nil, "防护规则必须是IP白名单、IP黑名单、地域白名单或地域黑名单类型: " .. tostring(rule_id)
            end
            table.insert(rule_types, rule_type)
        end
        
        -- 检查规则互斥关系
        for i, rule_type in ipairs(rule_types) do
            local conflicts = rule_conflicts[rule_type]
            if conflicts then
                for _, conflict_type in ipairs(conflicts) do
                    for j = i + 1, #rule_types do
                        if rule_types[j] == conflict_type then
                            local type_names = {
                                ip_whitelist = "IP白名单",
                                ip_blacklist = "IP黑名单",
                                geo_whitelist = "地域白名单",
                                geo_blacklist = "地域黑名单"
                            }
                            return nil, "不能同时选择" .. (type_names[rule_type] or rule_type) .. "和" .. (type_names[conflict_type] or conflict_type)
                        end
                    end
                end
            end
        end
    end
    
    -- 构建SQL
    local sql = [[
        INSERT INTO waf_proxy_configs 
        (proxy_name, proxy_type, listen_port, listen_address, server_name, location_paths,
         backend_type, load_balance,
         health_check_enable, health_check_interval, health_check_timeout,
         max_fails, fail_timeout, proxy_timeout, proxy_connect_timeout,
         proxy_send_timeout, proxy_read_timeout, ssl_enable, ssl_cert_path, ssl_key_path,
         description, ip_rule_ids, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]]
    
    local listen_address = proxy_data.listen_address or "0.0.0.0"
    -- 对于 TCP/UDP 代理，server_name 必须为 nil
    local server_name = nil
    if proxy_data.proxy_type == "http" then
        server_name = null_to_nil(proxy_data.server_name)
    end
    
    -- 处理location_paths（多个location_path配置）
    local location_paths_json = nil
    if proxy_data.proxy_type == "http" and proxy_data.location_paths then
        -- 验证location_paths格式
        if type(proxy_data.location_paths) == "table" and #proxy_data.location_paths > 0 then
            -- 验证每个location_path配置
            for i, loc in ipairs(proxy_data.location_paths) do
                if not loc.location_path or loc.location_path == "" then
                    return nil, "location_paths[" .. i .. "]的location_path不能为空"
                end
            end
            location_paths_json = cjson.encode(proxy_data.location_paths)
        end
    end
    -- 只支持多个后端（负载均衡），不再支持单个后端
    local backend_type = "upstream"
    local load_balance = proxy_data.load_balance or "round_robin"
    local health_check_enable = proxy_data.health_check_enable ~= nil and proxy_data.health_check_enable ~= cjson.null and proxy_data.health_check_enable or 1
    local health_check_interval = proxy_data.health_check_interval or 10
    local health_check_timeout = proxy_data.health_check_timeout or 3
    local max_fails = proxy_data.max_fails or 3
    local fail_timeout = proxy_data.fail_timeout or 30
    local proxy_timeout = proxy_data.proxy_timeout or 60
    local proxy_connect_timeout = proxy_data.proxy_connect_timeout or 60
    local proxy_send_timeout = proxy_data.proxy_send_timeout or 60
    local proxy_read_timeout = proxy_data.proxy_read_timeout or 60
    local ssl_enable = proxy_data.ssl_enable or 0
    local ssl_cert_path = null_to_nil(proxy_data.ssl_cert_path)
    local ssl_key_path = null_to_nil(proxy_data.ssl_key_path)
    local description = null_to_nil(proxy_data.description)
    local status = proxy_data.status or 1
    
    -- 将规则ID数组转换为JSON字符串
    local ip_rule_ids_json = nil
    if ip_rule_ids and #ip_rule_ids > 0 then
        local cjson = require "cjson"
        ip_rule_ids_json = cjson.encode(ip_rule_ids)
    end
    
    local insert_id, err = mysql_pool.insert(sql,
        proxy_data.proxy_name,
        proxy_data.proxy_type,
        listen_port,
        listen_address,
        server_name,
        location_paths_json,
        backend_type,
        load_balance,
        health_check_enable,
        health_check_interval,
        health_check_timeout,
        max_fails,
        fail_timeout,
        proxy_timeout,
        proxy_connect_timeout,
        proxy_send_timeout,
        proxy_read_timeout,
        ssl_enable,
        ssl_cert_path,
        ssl_key_path,
        description,
        ip_rule_ids_json,
        status
    )
    
    if err then
        ngx.log(ngx.ERR, "create proxy error: ", err)
        return nil, err
    end
    
    -- 添加后端服务器（只支持upstream类型）
    if proxy_data.backends and #proxy_data.backends > 0 then
        for _, backend in ipairs(proxy_data.backends) do
            local backend_sql = [[
                INSERT INTO waf_proxy_backends
                (proxy_id, location_path, backend_address, backend_port, backend_path, weight, max_fails, fail_timeout, backup, down, status)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ]]
            -- 只有HTTP/HTTPS代理才允许有location_path和backend_path，TCP/UDP代理应该为nil
            local location_path = nil
            local backend_path = nil
            if proxy_data.proxy_type == "http" then
                location_path = null_to_nil(backend.location_path)
                backend_path = null_to_nil(backend.backend_path)
            end
            mysql_pool.insert(backend_sql,
                insert_id,
                location_path,
                backend.backend_address,
                backend.backend_port,
                backend_path,
                backend.weight or 1,
                backend.max_fails or 3,
                backend.fail_timeout or 30,
                backend.backup or 0,
                backend.down or 0,
                backend.status or 1
            )
        end
    end
    
    ngx.log(ngx.INFO, "proxy created: ", insert_id)
    
    -- 如果代理已启用，生成nginx配置
    if status == 1 then
        local ok, err = nginx_config_generator.generate_all_configs()
        if not ok then
            ngx.log(ngx.WARN, "生成nginx配置失败: ", err or "unknown error")
        end
    end
    
    return {id = insert_id}, nil
end

-- 查询代理配置列表
function _M.list_proxies(params)
    params = params or {}
    local proxy_type = params.proxy_type
    local status = params.status
    local page = params.page or 1
    local page_size = params.page_size or 20
    
    -- 构建WHERE条件
    local where_clauses = {}
    local query_params = {}
    
    if proxy_type then
        table.insert(where_clauses, "proxy_type = ?")
        table.insert(query_params, proxy_type)
    end
    if status ~= nil then
        table.insert(where_clauses, "status = ?")
        table.insert(query_params, status)
    end
    
    local where_sql = ""
    if #where_clauses > 0 then
        where_sql = "WHERE " .. table.concat(where_clauses, " AND ")
    end
    
    -- 查询总数
    local count_sql = "SELECT COUNT(*) as total FROM waf_proxy_configs " .. where_sql
    local count_res, err = mysql_pool.query(count_sql, unpack(query_params))
    if err then
        ngx.log(ngx.ERR, "count proxies error: ", err)
        return nil, err
    end
    
    local total = count_res[1] and count_res[1].total or 0
    
    -- 查询列表（LEFT JOIN规则表获取规则名称和类型）
    local offset = (page - 1) * page_size
        local sql = string.format([[
        SELECT p.id, p.proxy_name, p.proxy_type, p.listen_port, p.listen_address, p.server_name, p.location_paths,
               p.backend_type, p.load_balance,
               p.health_check_enable, p.health_check_interval, p.health_check_timeout,
               p.max_fails, p.fail_timeout, p.proxy_timeout, p.proxy_connect_timeout,
               p.proxy_send_timeout, p.proxy_read_timeout, p.ssl_enable, p.ssl_cert_path, p.ssl_key_path,
               p.description, p.ip_rule_ids, p.status, p.priority, p.created_at, p.updated_at
        FROM waf_proxy_configs p
        %s
        ORDER BY p.priority DESC, p.created_at DESC
        LIMIT %d OFFSET %d
    ]], where_sql, page_size, offset)
    
    local proxies, err = mysql_pool.query(sql, unpack(query_params))
    if err then
        ngx.log(ngx.ERR, "list proxies error: ", err)
        return nil, err
    end
    
    -- 查询每个代理的后端服务器和防护规则（如果是upstream类型）
    for _, proxy in ipairs(proxies or {}) do
        -- 从ip_rule_ids字段读取规则ID数组（JSON格式）
        local rule_ids = nil
        if proxy.ip_rule_ids then
            local cjson = require "cjson"
            local ok, decoded_rule_ids = pcall(cjson.decode, proxy.ip_rule_ids)
            if ok and decoded_rule_ids and type(decoded_rule_ids) == "table" then
                rule_ids = decoded_rule_ids
                proxy.ip_rule_ids = decoded_rule_ids
                -- 调试日志：记录解析的规则ID
                ngx.log(ngx.DEBUG, "proxy_id=", proxy.id, ", decoded rule_ids: ", cjson.encode(rule_ids), ", count: ", #rule_ids)
            else
                -- 解码失败，保存原始值用于日志
                local raw_value = proxy.ip_rule_ids
                proxy.ip_rule_ids = nil
                -- 只在解码失败且原始值不为空时记录警告（可能是数据格式错误）
                if raw_value and raw_value ~= "" then
                    ngx.log(ngx.WARN, "proxy_id=", proxy.id, ", failed to decode ip_rule_ids, raw value: ", tostring(raw_value))
                end
            end
        else
            proxy.ip_rule_ids = nil
        end
        
        -- 从location_paths字段读取location_paths数组（JSON格式）
        if proxy.location_paths then
            local cjson = require "cjson"
            local ok, decoded_location_paths = pcall(cjson.decode, proxy.location_paths)
            if ok and decoded_location_paths and type(decoded_location_paths) == "table" then
                proxy.location_paths = decoded_location_paths
            else
                proxy.location_paths = nil
            end
        else
            proxy.location_paths = nil
        end
        
        -- 根据ip_rule_ids查询规则信息（用于列表显示）
        if rule_ids and #rule_ids > 0 then
            -- 查询所有规则的名称和类型（用于列表显示，每行显示一个规则）
            -- 构建IN子句的占位符和参数
            local placeholders = {}
            local params = {}
            for i = 1, #rule_ids do
                table.insert(placeholders, "?")
                table.insert(params, rule_ids[i])
            end
            local rule_info_sql = "SELECT id, rule_name, rule_type FROM waf_block_rules WHERE id IN (" .. table.concat(placeholders, ",") .. ") AND status = 1 ORDER BY id ASC"
            local rule_info = mysql_pool.query(rule_info_sql, unpack(params))
            if rule_info and #rule_info > 0 then
                -- 按照rule_ids的顺序排序规则（保持用户选择的顺序）
                local rule_map = {}
                for _, rule in ipairs(rule_info) do
                    -- 处理MySQL返回的字段名（可能是大写或下划线格式）
                    local rule_id = rule.id or rule.ID or rule.rule_id or rule.RULE_ID
                    local rule_name = rule.rule_name or rule.RULE_NAME or rule.ruleName
                    local rule_type = rule.rule_type or rule.RULE_TYPE or rule.ruleType
                    if rule_id then
                        -- 确保rule_id是数字类型（用于匹配）
                        rule_id = tonumber(rule_id) or rule_id
                        rule_map[rule_id] = {
                            id = tonumber(rule_id) or rule_id,
                            rule_name = rule_name or "",
                            rule_type = rule_type or ""
                        }
                    end
                end
                local ordered_rules = {}
                for _, rule_id in ipairs(rule_ids) do
                    -- 确保rule_id是数字类型（用于匹配）
                    local rule_id_num = tonumber(rule_id) or rule_id
                    if rule_map[rule_id_num] then
                        -- 创建一个新的table，确保字段名正确（避免MySQL返回的字段名问题）
                        local rule_item = {
                            id = rule_map[rule_id_num].id,
                            rule_name = rule_map[rule_id_num].rule_name,
                            rule_type = rule_map[rule_id_num].rule_type
                        }
                        table.insert(ordered_rules, rule_item)
                    else
                        -- 调试日志：记录未匹配的rule_id
                        ngx.log(ngx.WARN, "proxy_id=", proxy.id, ", rule_id=", rule_id, " not found in rule_map")
                    end
                end
                -- 保存所有规则的详细信息（确保是数组格式）
                if #ordered_rules > 0 then
                    proxy.rules = ordered_rules
                    -- 为了向后兼容，保留第一个规则的名称和类型
                    proxy.rule_name = ordered_rules[1].rule_name
                    proxy.rule_type = ordered_rules[1].rule_type
                    -- 调试日志：记录规则数量
                    ngx.log(ngx.DEBUG, "proxy_id=", proxy.id, ", found ", #ordered_rules, " rules")
                else
                    proxy.rules = {}
                    proxy.rule_name = nil
                    proxy.rule_type = nil
                    ngx.log(ngx.WARN, "proxy_id=", proxy.id, ", ordered_rules is empty after mapping")
                end
            else
                proxy.rules = {}
                proxy.rule_name = nil
                proxy.rule_type = nil
                ngx.log(ngx.WARN, "proxy_id=", proxy.id, ", no rules found in database for rule_ids: ", cjson.encode(rule_ids))
            end
        else
            proxy.rules = {}
            proxy.rule_name = nil
            proxy.rule_type = nil
        end
        
        if proxy.backend_type == "upstream" then
            local backends_sql = [[
                SELECT id, location_path, backend_address, backend_port, backend_path, weight, max_fails, fail_timeout,
                       backup, down, status
                FROM waf_proxy_backends
                WHERE proxy_id = ? AND status = 1
                ORDER BY location_path, weight DESC, id ASC
            ]]
            local backends, _ = mysql_pool.query(backends_sql, proxy.id)
            proxy.backends = backends or {}
        end
    end
    
    return {
        proxies = proxies or {},
        total = total,
        page = page,
        page_size = page_size,
        total_pages = math.ceil(total / page_size)
    }, nil
end

-- 查询代理配置详情
function _M.get_proxy(proxy_id)
    if not proxy_id then
        return nil, "代理ID不能为空"
    end
    
    local sql = [[
        SELECT id, proxy_name, proxy_type, listen_port, listen_address, server_name, location_paths,
               backend_type, load_balance,
               health_check_enable, health_check_interval, health_check_timeout,
               max_fails, fail_timeout, proxy_timeout, proxy_connect_timeout,
               proxy_send_timeout, proxy_read_timeout, ssl_enable, ssl_cert_path, ssl_key_path,
               description, ip_rule_ids, status, created_at, updated_at
        FROM waf_proxy_configs
        WHERE id = ?
        LIMIT 1
    ]]
    
    local proxies, err = mysql_pool.query(sql, proxy_id)
    if err then
        ngx.log(ngx.ERR, "get proxy error: ", err)
        return nil, err
    end
    
    if not proxies or #proxies == 0 then
        return nil, "代理配置不存在"
    end
    
    local proxy = proxies[1]
    
    -- 从ip_rule_ids字段读取规则ID数组（JSON格式）
    if proxy.ip_rule_ids then
        local cjson = require "cjson"
        local ok, rule_ids = pcall(cjson.decode, proxy.ip_rule_ids)
        if ok and rule_ids and type(rule_ids) == "table" then
            proxy.ip_rule_ids = rule_ids
        else
            proxy.ip_rule_ids = nil
        end
    else
        proxy.ip_rule_ids = nil
    end
    
    -- 从location_paths字段读取location_paths数组（JSON格式）
    if proxy.location_paths then
        local cjson = require "cjson"
        local ok, decoded_location_paths = pcall(cjson.decode, proxy.location_paths)
        if ok and decoded_location_paths and type(decoded_location_paths) == "table" then
            proxy.location_paths = decoded_location_paths
        else
            proxy.location_paths = nil
        end
    else
        proxy.location_paths = nil
    end
    
    -- 查询后端服务器（只支持upstream类型）
    if proxy.backend_type == "upstream" then
        local backends_sql = [[
            SELECT id, location_path, backend_address, backend_port, backend_path, weight, max_fails, fail_timeout,
                   backup, down, status
            FROM waf_proxy_backends
            WHERE proxy_id = ?
            ORDER BY location_path, weight DESC, id ASC
        ]]
        local backends, _ = mysql_pool.query(backends_sql, proxy_id)
        proxy.backends = backends or {}
    end
    
    return proxy, nil
end

-- 更新代理配置
function _M.update_proxy(proxy_id, proxy_data)
    if not proxy_id then
        return nil, "代理ID不能为空"
    end
    
    -- 检查代理是否存在
    local proxy, err = _M.get_proxy(proxy_id)
    if err then
        return nil, err
    end
    
    -- 验证配置（如果提供了必填字段）
    if proxy_data.proxy_name or proxy_data.proxy_type or proxy_data.listen_port then
        local temp_data = {}
        for k, v in pairs(proxy) do
            temp_data[k] = v
        end
        for k, v in pairs(proxy_data) do
            temp_data[k] = v
        end
        local valid, err_msg = validate_proxy_config(temp_data)
        if not valid then
            return nil, err_msg
        end
    end
    
    -- 检查代理名称是否已被其他配置使用
    if proxy_data.proxy_name and proxy_data.proxy_name ~= proxy.proxy_name then
        local check_sql = "SELECT id FROM waf_proxy_configs WHERE proxy_name = ? AND id != ? LIMIT 1"
        local existing = mysql_pool.query(check_sql, proxy_data.proxy_name, proxy_id)
        if existing and #existing > 0 then
            return nil, "代理名称已被其他配置使用"
        end
    end
    
    -- 处理 cjson.null，转换为 nil
    local cjson = require "cjson"
    local function null_to_nil(value)
        if value == nil or value == cjson.null then
            return nil
        end
        return value
    end
    
    -- 检查端口冲突
    -- 需要检查的情况：
    -- 1. 端口改变了
    -- 2. HTTP/HTTPS代理的server_name改变了（从有域名改为无域名，或从无域名改为有域名）
    local listen_port = proxy_data.listen_port and tonumber(proxy_data.listen_port) or tonumber(proxy.listen_port)
    local proxy_type = proxy_data.proxy_type or proxy.proxy_type
    local new_server_name = null_to_nil(proxy_data.server_name)
    local old_server_name = null_to_nil(proxy.server_name)
    
    -- 判断是否需要检查端口占用
    local port_changed = proxy_data.listen_port and listen_port ~= tonumber(proxy.listen_port)
    local server_name_changed = false
    if proxy_type == "http" then
        -- 检查server_name是否改变（包括从有域名改为无域名，或从无域名改为有域名）
        if proxy_data.server_name ~= nil then
            -- 如果更新数据中有server_name，检查是否与现有值不同
            local new_sn = new_server_name or ""
            local old_sn = old_server_name or ""
            if new_sn ~= old_sn then
                server_name_changed = true
            end
        end
    end
    
    if port_changed or server_name_changed then
        if not listen_port then
            return nil, "监听端口必须是有效的数字"
        end
        
        -- 确定要使用的server_name（优先使用新的，如果没有则使用旧的）
        local server_name = new_server_name
        if not server_name then
            server_name = old_server_name
        end
        
        local port_check_sql
        if proxy_type == "http" and server_name and server_name ~= "" then
            -- HTTP/HTTPS代理且有域名：检查是否有相同域名的代理占用端口，或是否有无域名的代理占用端口
            port_check_sql = [[
                SELECT id FROM waf_proxy_configs 
                WHERE proxy_type = ? AND listen_port = ? AND status = 1 AND id != ?
                AND (server_name = ? OR server_name IS NULL OR server_name = '')
                LIMIT 1
            ]]
            local port_conflict = mysql_pool.query(port_check_sql, proxy_type, listen_port, proxy_id, server_name)
            if port_conflict and #port_conflict > 0 then
                return nil, "该端口已被其他启用的代理配置占用（相同域名或无域名的代理不能共享端口）"
            end
        elseif proxy_type == "http" then
            -- HTTP/HTTPS代理但无域名：不能与任何其他代理共享端口
            port_check_sql = [[
                SELECT id FROM waf_proxy_configs 
                WHERE proxy_type = ? AND listen_port = ? AND status = 1 AND id != ?
                LIMIT 1
            ]]
            local port_conflict = mysql_pool.query(port_check_sql, proxy_type, listen_port, proxy_id)
            if port_conflict and #port_conflict > 0 then
                return nil, "该端口已被其他启用的代理配置占用（无域名的代理不能与其他代理共享端口）"
            end
        else
            -- TCP/UDP代理：严格的端口占用检查（只在端口改变时检查）
            if port_changed then
                port_check_sql = [[
                    SELECT id FROM waf_proxy_configs 
                    WHERE proxy_type = ? AND listen_port = ? AND status = 1 AND id != ?
                    LIMIT 1
                ]]
                local port_conflict = mysql_pool.query(port_check_sql, proxy_type, listen_port, proxy_id)
                if port_conflict and #port_conflict > 0 then
                    return nil, "该端口已被其他启用的代理配置占用"
                end
            end
        end
    end
    
    -- 验证ip_rule_ids（如果提供，支持多个规则ID，但必须遵守互斥关系）
    local ip_rule_ids = nil
    if proxy_data.ip_rule_ids and type(proxy_data.ip_rule_ids) == "table" and #proxy_data.ip_rule_ids > 0 then
        ip_rule_ids = proxy_data.ip_rule_ids
        -- 规则互斥关系定义
        local rule_conflicts = {
            ip_whitelist = {"ip_blacklist"},
            ip_blacklist = {"ip_whitelist"},
            geo_whitelist = {"geo_blacklist"},
            geo_blacklist = {"geo_whitelist"}
        }
        
        -- 验证所有规则是否存在且为IP相关类型
        local rule_types = {}
        for _, rule_id in ipairs(ip_rule_ids) do
            local rule_check_sql = "SELECT id, rule_type FROM waf_block_rules WHERE id = ? AND status = 1 LIMIT 1"
            local rule_check = mysql_pool.query(rule_check_sql, rule_id)
            if not rule_check or #rule_check == 0 then
                return nil, "指定的防护规则不存在或已禁用: " .. tostring(rule_id)
            end
            local rule_type = rule_check[1].rule_type
            if rule_type ~= "ip_whitelist" and rule_type ~= "ip_blacklist" and 
               rule_type ~= "geo_whitelist" and rule_type ~= "geo_blacklist" then
                return nil, "防护规则必须是IP白名单、IP黑名单、地域白名单或地域黑名单类型: " .. tostring(rule_id)
            end
            table.insert(rule_types, rule_type)
        end
        
        -- 检查规则互斥关系
        for i, rule_type in ipairs(rule_types) do
            local conflicts = rule_conflicts[rule_type]
            if conflicts then
                for _, conflict_type in ipairs(conflicts) do
                    for j = i + 1, #rule_types do
                        if rule_types[j] == conflict_type then
                            local type_names = {
                                ip_whitelist = "IP白名单",
                                ip_blacklist = "IP黑名单",
                                geo_whitelist = "地域白名单",
                                geo_blacklist = "地域黑名单"
                            }
                            return nil, "不能同时选择" .. (type_names[rule_type] or rule_type) .. "和" .. (type_names[conflict_type] or conflict_type)
                        end
                    end
                end
            end
        end
    end
    
    
    -- 构建更新字段
    local update_fields = {}
    local update_params = {}
    
    local fields_to_update = {
        "proxy_name", "proxy_type", "listen_port", "listen_address", "server_name", "location_paths",
        "backend_type", "load_balance",
        "health_check_enable", "health_check_interval", "health_check_timeout",
        "max_fails", "fail_timeout", "proxy_timeout", "proxy_connect_timeout",
        "proxy_send_timeout", "proxy_read_timeout", "ssl_enable", "ssl_cert_path", "ssl_key_path",
        "description"
    }
    
    for _, field in ipairs(fields_to_update) do
        if proxy_data[field] ~= nil and proxy_data[field] ~= cjson.null then
            table.insert(update_fields, field .. " = ?")
            -- 对于可能为null的字段，使用null_to_nil处理
            if field == "server_name" then
                -- TCP/UDP 代理的 server_name 必须为 nil
                if proxy.proxy_type ~= "http" then
                    table.insert(update_params, nil)
                else
                    table.insert(update_params, null_to_nil(proxy_data[field]))
                end
            elseif field == "ssl_cert_path" or field == "ssl_key_path" or field == "description" then
                table.insert(update_params, null_to_nil(proxy_data[field]))
            elseif field == "location_paths" then
                -- location_paths字段需要特殊处理：如果是HTTP代理且有值，转换为JSON；否则为nil
                if proxy.proxy_type == "http" and proxy_data[field] and type(proxy_data[field]) == "table" and #proxy_data[field] > 0 then
                    -- 验证每个location_path配置
                    for i, loc in ipairs(proxy_data[field]) do
                        if not loc.location_path or loc.location_path == "" then
                            return nil, "location_paths[" .. i .. "]的location_path不能为空"
                        end
                    end
                    table.insert(update_params, cjson.encode(proxy_data[field]))
                else
                    table.insert(update_params, nil)
                end
            else
                table.insert(update_params, proxy_data[field])
            end
        elseif proxy_data[field] == cjson.null then
            -- 如果明确设置为null，也更新字段
            -- 对于 server_name，如果是 TCP/UDP 代理，强制设置为 NULL
            if field == "server_name" and proxy.proxy_type ~= "http" then
                table.insert(update_fields, field .. " = NULL")
            else
                table.insert(update_fields, field .. " = NULL")
            end
        end
    end
    
    -- 处理ip_rule_ids字段（如果提供）
    if proxy_data.ip_rule_ids ~= nil then
        if ip_rule_ids and #ip_rule_ids > 0 then
            -- 将规则ID数组转换为JSON字符串
            local ip_rule_ids_json = cjson.encode(ip_rule_ids)
            table.insert(update_fields, "ip_rule_ids = ?")
            table.insert(update_params, ip_rule_ids_json)
        else
            -- 如果ip_rule_ids为空，设置为NULL
            table.insert(update_fields, "ip_rule_ids = NULL")
        end
    end
    
    if proxy_data.status ~= nil then
        table.insert(update_fields, "status = ?")
        table.insert(update_params, tonumber(proxy_data.status))
    end
    
    if #update_fields == 0 then
        return nil, "没有需要更新的字段"
    end
    
    table.insert(update_params, proxy_id)
    
    -- 执行更新
    local sql = "UPDATE waf_proxy_configs SET " .. table.concat(update_fields, ", ") .. " WHERE id = ?"
    local res, err = mysql_pool.query(sql, unpack(update_params))
    if err then
        ngx.log(ngx.ERR, "update proxy error: ", err)
        return nil, err
    end
    
    -- 更新后端服务器（只支持upstream类型）
    if proxy_data.backends and proxy.backend_type == "upstream" then
        -- 删除旧的后端服务器
        local delete_sql = "DELETE FROM waf_proxy_backends WHERE proxy_id = ?"
        mysql_pool.query(delete_sql, proxy_id)
        
        -- 添加新的后端服务器
        for _, backend in ipairs(proxy_data.backends) do
            local backend_sql = [[
                INSERT INTO waf_proxy_backends
                (proxy_id, location_path, backend_address, backend_port, backend_path, weight, max_fails, fail_timeout, backup, down, status)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ]]
            -- 只有HTTP/HTTPS代理才允许有location_path和backend_path，TCP/UDP代理应该为nil
            local location_path = nil
            local backend_path = nil
            if proxy.proxy_type == "http" then
                location_path = null_to_nil(backend.location_path)
                backend_path = null_to_nil(backend.backend_path)
            end
            mysql_pool.insert(backend_sql,
                proxy_id,
                location_path,
                backend.backend_address,
                backend.backend_port,
                backend_path,
                backend.weight or 1,
                backend.max_fails or 3,
                backend.fail_timeout or 30,
                backend.backup or 0,
                backend.down or 0,
                backend.status or 1
            )
        end
    end
    
    ngx.log(ngx.INFO, "proxy updated: ", proxy_id)
    
    -- 注意：如果状态发生变化，需要重新生成nginx配置
    -- 但是，如果是从 disable_proxy() 或 enable_proxy() 调用的，它们会自己调用 generate_all_configs()
    -- 所以这里只在直接调用 update_proxy() 时才重新生成配置
    -- 检查状态是否发生变化
    local updated_proxy, _ = _M.get_proxy(proxy_id)
    if updated_proxy then
        -- 如果状态发生变化（启用或禁用），重新生成nginx配置
        if proxy_data.status ~= nil then
            local ok, err = nginx_config_generator.generate_all_configs()
            if not ok then
                ngx.log(ngx.WARN, "生成nginx配置失败: ", err or "unknown error")
            else
                ngx.log(ngx.INFO, "代理状态已更新，nginx配置已重新生成")
            end
        end
    end
    
    return {id = proxy_id}, nil
end

-- 删除代理配置
function _M.delete_proxy(proxy_id)
    if not proxy_id then
        return nil, "代理ID不能为空"
    end
    
    -- 检查代理是否存在
    local proxy, err = _M.get_proxy(proxy_id)
    if err then
        return nil, err
    end
    
    -- 执行删除（外键约束会自动删除后端服务器）
    local sql = "DELETE FROM waf_proxy_configs WHERE id = ?"
    local res, err = mysql_pool.query(sql, proxy_id)
    if err then
        ngx.log(ngx.ERR, "delete proxy error: ", err)
        return nil, err
    end
    
    ngx.log(ngx.INFO, "proxy deleted: ", proxy_id)
    
    -- 重新生成nginx配置（排除已删除的代理）
    local ok, err = nginx_config_generator.generate_all_configs()
    if not ok then
        ngx.log(ngx.WARN, "生成nginx配置失败: ", err or "unknown error")
    end
    
    return {id = proxy_id}, nil
end

-- 启用代理配置
function _M.enable_proxy(proxy_id)
    local result, err = _M.update_proxy(proxy_id, {status = 1})
    if result then
        -- 重新生成nginx配置
        local ok, gen_err = nginx_config_generator.generate_all_configs()
        if not ok then
            ngx.log(ngx.WARN, "生成nginx配置失败: ", gen_err or "unknown error")
        end
    end
    return result, err
end

-- 禁用代理配置
function _M.disable_proxy(proxy_id)
    -- 先获取代理信息，用于后续清理配置文件
    local proxy, err = _M.get_proxy(proxy_id)
    if err then
        return nil, err
    end
    
    -- 更新数据库状态为禁用
    local result, err = _M.update_proxy(proxy_id, {status = 0})
    if not result then
        return nil, err
    end
    
    -- 重新生成nginx配置（会排除禁用的代理，并清理其配置文件）
    local ok, gen_err = nginx_config_generator.generate_all_configs()
    if not ok then
        ngx.log(ngx.WARN, "生成nginx配置失败: ", gen_err or "unknown error")
        -- 即使配置生成失败，也继续执行，因为数据库状态已更新
    else
        ngx.log(ngx.INFO, "代理已禁用，nginx配置已重新生成，配置文件已清理")
    end
    
    return result, err
end

return _M

