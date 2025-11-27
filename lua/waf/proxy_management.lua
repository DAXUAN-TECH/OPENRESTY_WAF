-- 反向代理管理模块
-- 路径：项目目录下的 lua/waf/proxy_management.lua（保持在项目目录，不复制到系统目录）
-- 功能：实现反向代理配置的CRUD操作

local mysql_pool = require "waf.mysql_pool"
local cjson = require "cjson"
local nginx_config_generator = require "waf.nginx_config_generator"

local _M = {}

-- 验证代理配置
local function validate_proxy_config(proxy_data)
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
    
    if not proxy_data.listen_port or proxy_data.listen_port < 1 or proxy_data.listen_port > 65535 then
        return false, "监听端口必须在1-65535之间"
    end
    
    if proxy_data.proxy_type == "http" then
        if not proxy_data.server_name or proxy_data.server_name == "" then
            return false, "HTTP代理必须指定服务器名称"
        end
    end
    
    if not proxy_data.backend_address or proxy_data.backend_address == "" then
        return false, "后端地址不能为空"
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
    
    -- 检查端口是否已被占用（相同类型的代理）
    local port_check_sql = [[
        SELECT id FROM waf_proxy_configs 
        WHERE proxy_type = ? AND listen_port = ? AND status = 1
        LIMIT 1
    ]]
    local port_conflict = mysql_pool.query(port_check_sql, proxy_data.proxy_type, proxy_data.listen_port)
    if port_conflict and #port_conflict > 0 then
        return nil, "该端口已被其他启用的代理配置占用"
    end
    
    -- 处理 cjson.null，转换为 nil
    local cjson = require "cjson"
    local function null_to_nil(value)
        if value == nil or value == cjson.null then
            return nil
        end
        return value
    end
    
    -- 验证ip_rule_id（如果提供）
    local ip_rule_id = null_to_nil(proxy_data.ip_rule_id)
    if ip_rule_id then
        -- 检查规则是否存在且为IP相关类型
        local rule_check_sql = "SELECT id, rule_type FROM waf_block_rules WHERE id = ? AND status = 1 LIMIT 1"
        local rule_check = mysql_pool.query(rule_check_sql, ip_rule_id)
        if not rule_check or #rule_check == 0 then
            return nil, "指定的防护规则不存在或已禁用"
        end
        local rule_type = rule_check[1].rule_type
        if rule_type ~= "ip_whitelist" and rule_type ~= "ip_blacklist" and 
           rule_type ~= "geo_whitelist" and rule_type ~= "geo_blacklist" then
            return nil, "防护规则必须是IP白名单、IP黑名单、地域白名单或地域黑名单类型"
        end
    end
    
    -- 构建SQL
    local sql = [[
        INSERT INTO waf_proxy_configs 
        (proxy_name, proxy_type, listen_port, listen_address, server_name, location_path,
         backend_type, backend_address, backend_port, backend_path, load_balance,
         health_check_enable, health_check_interval, health_check_timeout,
         max_fails, fail_timeout, proxy_timeout, proxy_connect_timeout,
         proxy_send_timeout, proxy_read_timeout, ssl_enable, ssl_cert_path, ssl_key_path,
         description, ip_rule_id, status, priority)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]]
    
    local listen_address = proxy_data.listen_address or "0.0.0.0"
    local server_name = null_to_nil(proxy_data.server_name)
    local location_path = proxy_data.location_path or "/"
    local backend_type = proxy_data.backend_type or "single"
    local backend_port = null_to_nil(proxy_data.backend_port)
    local backend_path = null_to_nil(proxy_data.backend_path)
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
    local priority = proxy_data.priority or 0
    local ip_rule_id = null_to_nil(proxy_data.ip_rule_id)
    
    local insert_id, err = mysql_pool.insert(sql,
        proxy_data.proxy_name,
        proxy_data.proxy_type,
        proxy_data.listen_port,
        listen_address,
        server_name,
        location_path,
        backend_type,
        proxy_data.backend_address,
        backend_port,
        backend_path,
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
        ip_rule_id,
        status,
        priority
    )
    
    if err then
        ngx.log(ngx.ERR, "create proxy error: ", err)
        return nil, err
    end
    
    -- 如果是upstream类型，添加后端服务器
    if backend_type == "upstream" and proxy_data.backends and #proxy_data.backends > 0 then
        for _, backend in ipairs(proxy_data.backends) do
            local backend_sql = [[
                INSERT INTO waf_proxy_backends
                (proxy_id, backend_address, backend_port, weight, max_fails, fail_timeout, backup, down, status)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ]]
            mysql_pool.insert(backend_sql,
                insert_id,
                backend.backend_address,
                backend.backend_port,
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
    
    -- 查询列表
    local offset = (page - 1) * page_size
    local sql = string.format([[
        SELECT id, proxy_name, proxy_type, listen_port, listen_address, server_name, location_path,
               backend_type, backend_address, backend_port, backend_path, load_balance,
               health_check_enable, health_check_interval, health_check_timeout,
               max_fails, fail_timeout, proxy_timeout, proxy_connect_timeout,
               proxy_send_timeout, proxy_read_timeout, ssl_enable, ssl_cert_path, ssl_key_path,
               description, ip_rule_id, status, priority, created_at, updated_at
        FROM waf_proxy_configs
        %s
        ORDER BY priority DESC, created_at DESC
        LIMIT %d OFFSET %d
    ]], where_sql, page_size, offset)
    
    local proxies, err = mysql_pool.query(sql, unpack(query_params))
    if err then
        ngx.log(ngx.ERR, "list proxies error: ", err)
        return nil, err
    end
    
    -- 查询每个代理的后端服务器（如果是upstream类型）
    for _, proxy in ipairs(proxies or {}) do
        if proxy.backend_type == "upstream" then
            local backends_sql = [[
                SELECT id, backend_address, backend_port, weight, max_fails, fail_timeout,
                       backup, down, status
                FROM waf_proxy_backends
                WHERE proxy_id = ? AND status = 1
                ORDER BY weight DESC, id ASC
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
        SELECT id, proxy_name, proxy_type, listen_port, listen_address, server_name, location_path,
               backend_type, backend_address, backend_port, load_balance,
               health_check_enable, health_check_interval, health_check_timeout,
               max_fails, fail_timeout, proxy_timeout, proxy_connect_timeout,
               proxy_send_timeout, proxy_read_timeout, ssl_enable, ssl_cert_path, ssl_key_path,
               description, ip_rule_id, status, priority, created_at, updated_at
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
    
    -- 如果是upstream类型，查询后端服务器
    if proxy.backend_type == "upstream" then
        local backends_sql = [[
            SELECT id, backend_address, backend_port, weight, max_fails, fail_timeout,
                   backup, down, status
            FROM waf_proxy_backends
            WHERE proxy_id = ?
            ORDER BY weight DESC, id ASC
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
    
    -- 检查端口冲突
    if proxy_data.listen_port and proxy_data.listen_port ~= proxy.listen_port then
        local port_check_sql = [[
            SELECT id FROM waf_proxy_configs 
            WHERE proxy_type = ? AND listen_port = ? AND status = 1 AND id != ?
            LIMIT 1
        ]]
        local proxy_type = proxy_data.proxy_type or proxy.proxy_type
        local port_conflict = mysql_pool.query(port_check_sql, proxy_type, proxy_data.listen_port, proxy_id)
        if port_conflict and #port_conflict > 0 then
            return nil, "该端口已被其他启用的代理配置占用"
        end
    end
    
    -- 处理 cjson.null，转换为 nil
    local function null_to_nil(value)
        if value == nil or value == cjson.null then
            return nil
        end
        return value
    end
    
    -- 验证ip_rule_id（如果提供）
    if proxy_data.ip_rule_id ~= nil then
        local ip_rule_id = null_to_nil(proxy_data.ip_rule_id)
        if ip_rule_id then
            -- 检查规则是否存在且为IP相关类型
            local rule_check_sql = "SELECT id, rule_type FROM waf_block_rules WHERE id = ? AND status = 1 LIMIT 1"
            local rule_check = mysql_pool.query(rule_check_sql, ip_rule_id)
            if not rule_check or #rule_check == 0 then
                return nil, "指定的防护规则不存在或已禁用"
            end
            local rule_type = rule_check[1].rule_type
            if rule_type ~= "ip_whitelist" and rule_type ~= "ip_blacklist" and 
               rule_type ~= "geo_whitelist" and rule_type ~= "geo_blacklist" then
                return nil, "防护规则必须是IP白名单、IP黑名单、地域白名单或地域黑名单类型"
            end
        end
    end
    
    -- 构建更新字段
    local update_fields = {}
    local update_params = {}
    
    local fields_to_update = {
        "proxy_name", "proxy_type", "listen_port", "listen_address", "server_name", "location_path",
        "backend_type", "backend_address", "backend_port", "load_balance",
        "health_check_enable", "health_check_interval", "health_check_timeout",
        "max_fails", "fail_timeout", "proxy_timeout", "proxy_connect_timeout",
        "proxy_send_timeout", "proxy_read_timeout", "ssl_enable", "ssl_cert_path", "ssl_key_path",
        "description", "ip_rule_id", "priority"
    }
    
    for _, field in ipairs(fields_to_update) do
        if proxy_data[field] ~= nil and proxy_data[field] ~= cjson.null then
            table.insert(update_fields, field .. " = ?")
            -- 对于可能为null的字段，使用null_to_nil处理
            if field == "server_name" or field == "backend_port" or field == "ssl_cert_path" or 
               field == "ssl_key_path" or field == "description" or field == "ip_rule_id" then
                table.insert(update_params, null_to_nil(proxy_data[field]))
            else
                table.insert(update_params, proxy_data[field])
            end
        elseif proxy_data[field] == cjson.null then
            -- 如果明确设置为null，也更新字段
            table.insert(update_fields, field .. " = NULL")
        end
    end
    
    if proxy_data.status ~= nil then
        table.insert(update_fields, "status = " .. tonumber(proxy_data.status))
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
    
    -- 更新后端服务器（如果是upstream类型）
    if proxy_data.backends and proxy.backend_type == "upstream" then
        -- 删除旧的后端服务器
        local delete_sql = "DELETE FROM waf_proxy_backends WHERE proxy_id = ?"
        mysql_pool.query(delete_sql, proxy_id)
        
        -- 添加新的后端服务器
        for _, backend in ipairs(proxy_data.backends) do
            local backend_sql = [[
                INSERT INTO waf_proxy_backends
                (proxy_id, backend_address, backend_port, weight, max_fails, fail_timeout, backup, down, status)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ]]
            mysql_pool.insert(backend_sql,
                proxy_id,
                backend.backend_address,
                backend.backend_port,
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

