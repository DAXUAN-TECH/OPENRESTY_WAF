-- MySQL 连接池管理
-- 路径：项目目录下的 lua/waf/mysql_pool.lua（保持在项目目录，不复制到系统目录）
--
-- 注意：关于 "attempt to send data on a closed socket" 错误
-- 1. 当MySQL连接超时时，socket可能已经被系统关闭
-- 2. resty.mysql库内部可能仍然尝试在已关闭的socket上发送数据（如认证信息）
-- 3. 这会导致Nginx层面的"attempt to send data on a closed socket"错误
-- 4. 这些错误虽然会在Nginx错误日志中显示，但已经被xpcall捕获和处理
-- 5. 系统会正常处理连接失败，不会崩溃或影响其他功能
-- 6. 这些错误是预期的行为，不需要担心，系统已经正确处理

local mysql = require "resty.mysql"
local config = require "config"

local _M = {}
local pool = {}

-- 缓存解析后的 MySQL host IP 地址（带过期时间，应对动态 IP）
local resolved_host_cache = {
    ip = nil,
    expire_time = 0,  -- 缓存过期时间（Unix 时间戳）
    cache_ttl = 60    -- 缓存有效期（秒），60 秒（1 分钟），应对动态 IP 快速变化
}

-- 清除 DNS 缓存（当连接失败时调用）
function _M.clear_dns_cache()
    resolved_host_cache.ip = nil
    resolved_host_cache.expire_time = 0
    ngx.log(ngx.INFO, "MySQL DNS cache cleared")
end

-- 解析域名到 IP 地址（使用系统命令，不依赖 resolver）
-- 支持缓存和自动刷新，应对动态 IP 地址
local function resolve_hostname(hostname, force_refresh)
    -- 如果已经是 IP 地址格式，直接返回
    if hostname:match("^%d+%.%d+%.%d+%.%d+$") then
        return hostname
    end
    
    local current_time = ngx.time()
    
    -- 检查缓存是否有效（未过期且未强制刷新）
    if not force_refresh and resolved_host_cache.ip and current_time < resolved_host_cache.expire_time then
        return resolved_host_cache.ip
    end
    
    -- 需要重新解析
    local resolved_ip = nil
    
    -- 使用 getent hosts 命令解析域名（Linux 系统）
    local cmd = "getent hosts " .. hostname .. " 2>/dev/null | awk '{print $1}' | head -n 1"
    local handle = io.popen(cmd)
    if handle then
        local ip = handle:read("*line")
        handle:close()
        if ip and ip:match("^%d+%.%d+%.%d+%.%d+$") then
            resolved_ip = ip
        end
    end
    
    -- 如果 getent 失败，尝试使用 nslookup（备用方案）
    if not resolved_ip then
        local nslookup_cmd = "nslookup " .. hostname .. " 2>/dev/null | grep -A 1 'Name:' | tail -n 1 | awk '{print $2}'"
        local nslookup_handle = io.popen(nslookup_cmd)
        if nslookup_handle then
            local ip = nslookup_handle:read("*line")
            nslookup_handle:close()
            if ip and ip:match("^%d+%.%d+%.%d+%.%d+$") then
                resolved_ip = ip
            end
        end
    end
    
    -- 如果解析成功，更新缓存
    if resolved_ip then
        resolved_host_cache.ip = resolved_ip
        resolved_host_cache.expire_time = current_time + resolved_host_cache.cache_ttl
        ngx.log(ngx.INFO, "Resolved MySQL hostname '", hostname, "' to IP: ", resolved_ip, " (cached for ", resolved_host_cache.cache_ttl, "s)")
        return resolved_ip
    end
    
    -- 如果解析失败，但有缓存，使用缓存（可能 DNS 暂时不可用）
    if resolved_host_cache.ip then
        ngx.log(ngx.WARN, "Failed to resolve MySQL hostname '", hostname, "', using cached IP: ", resolved_host_cache.ip)
        return resolved_host_cache.ip
    end
    
    -- 如果解析失败且无缓存，记录警告但返回原始 hostname
    ngx.log(ngx.WARN, "Failed to resolve MySQL hostname '", hostname, "' to IP address. Will use hostname directly (may require resolver configuration).")
    return hostname
end

-- SQL 转义函数
local function escape_sql(str)
    -- 检查是否为 nil 或 cjson.null
    if str == nil then
        return "NULL"
    end
    
    -- 检查是否为 cjson.null（userdata类型）
    local cjson = require "cjson"
    if str == cjson.null then
        return "NULL"
    end
    
    -- 检查类型
    local str_type = type(str)
    if str_type == "number" then
        return tostring(str)
    end
    
    -- 如果不是字符串类型，先转换为字符串
    if str_type ~= "string" then
        str = tostring(str)
    end
    
    -- 转义反斜杠（必须在单引号之前）
    str = string.gsub(str, "\\", "\\\\")
    -- 转义单引号
    str = string.gsub(str, "'", "''")
    return "'" .. str .. "'"
end

-- 构建参数化 SQL（简单实现）
local function build_sql(sql, ...)
    -- 使用select("#", ...)获取参数数量，正确处理nil值
    local arg_count = select("#", ...)
    local args = {}
    -- 将所有参数（包括nil）收集到数组中
    for i = 1, arg_count do
        args[i] = select(i, ...)
    end
    local result = sql
    local index = 1
    
    -- 替换 ? 占位符
    result = string.gsub(result, "%?", function()
        if index <= arg_count then
            local arg = args[index]
            index = index + 1
            local escaped = escape_sql(arg)
            return escaped
        else
            -- 参数不足，记录错误
            ngx.log(ngx.ERR, "build_sql: not enough arguments, expected at least ", index, " but got ", arg_count)
            return "?"
        end
    end)
    
    -- 验证是否还有未替换的占位符
    if result:match("%?") then
        ngx.log(ngx.ERR, "build_sql: warning - unplaced placeholders remain in SQL: ", result)
    end
    
    return result
end

-- 获取 MySQL 连接
function _M.get_connection()
    local db, err = mysql:new()
    if not db then
        ngx.log(ngx.ERR, "failed to instantiate mysql: ", err)
        return nil, err
    end

    db:set_timeout(config.mysql.pool_timeout)

    -- 解析 host（如果是域名，解析为 IP 地址；如果是 IP，直接使用）
    local mysql_host = resolve_hostname(config.mysql.host)

    -- 直接调用 connect；如果网络/服务异常会返回超时错误
    -- 使用 xpcall 包装 connect 调用，避免在超时时出现 "attempt to send data on a closed socket" 错误
    -- 注意：xpcall 可以正确处理多个返回值的情况
    local connect_results = {}
    local connect_ok, connect_err = xpcall(function()
        -- 将多个返回值收集到表中
        local ok, err, errcode, sqlstate = db:connect{
            host = mysql_host,
            port = config.mysql.port,
            database = config.mysql.database,
            user = config.mysql.user,
            password = config.mysql.password,
            max_packet_size = config.mysql.max_packet_size,
            charset = "utf8mb4",
        }
        connect_results.ok = ok
        connect_results.err = err
        connect_results.errcode = errcode
        connect_results.sqlstate = sqlstate
        return ok, err, errcode, sqlstate
    end, function(err)
        -- 错误处理函数：记录异常信息
        -- 注意：即使使用xpcall捕获异常，resty.mysql库内部可能仍然会在已关闭的socket上操作
        -- 这会导致"attempt to send data on a closed socket"错误，但这是预期的行为
        -- 我们只需要确保错误被正确捕获和处理，不影响系统运行
        local err_str = tostring(err) or "connection failed with exception"
        -- 如果是socket相关错误，记录为DEBUG级别（这是预期的，不需要警告）
        if err_str:match("attempt to send data on a closed socket") or 
           err_str:match("closed socket") or
           err_str:match("timeout") then
            ngx.log(ngx.DEBUG, "MySQL connect() socket error (expected): ", err_str)
        else
            ngx.log(ngx.WARN, "MySQL connect() threw an exception: ", err_str)
        end
        connect_results.ok = false
        connect_results.err = err_str
        connect_results.errcode = nil
        connect_results.sqlstate = nil
        return err
    end)
    
    local ok, err, errcode, sqlstate
    if connect_ok then
        -- xpcall 成功，从结果表中获取返回值
        ok = connect_results.ok
        err = connect_results.err
        errcode = connect_results.errcode
        sqlstate = connect_results.sqlstate
    else
        -- xpcall 失败，说明 connect 过程中抛出了异常（可能是 socket 已关闭）
        -- 注意：即使xpcall捕获了异常，resty.mysql库内部可能仍然会在已关闭的socket上操作
        -- 这会导致"attempt to send data on a closed socket"错误，但这是预期的行为
        ok = false
        err = connect_results.err or connect_err or "connection failed with exception"
        errcode = nil
        sqlstate = nil
        -- 如果是socket相关错误，记录为DEBUG级别（这是预期的，不需要警告）
        local err_str = tostring(connect_err) or ""
        if err_str:match("attempt to send data on a closed socket") or 
           err_str:match("closed socket") or
           err_str:match("timeout") then
            ngx.log(ngx.DEBUG, "MySQL connect() xpcall socket error (expected): ", err_str)
        else
            ngx.log(ngx.WARN, "MySQL connect() xpcall failed: ", err_str)
        end
    end

    if not ok then
        -- 安全关闭失败的连接（使用 pcall 避免在已关闭的 socket 上操作）
        if db then
            local close_ok, close_err = pcall(function() 
                -- 尝试关闭连接，但如果socket已经关闭，这可能会失败，这是正常的
                db:close()
            end)
            if not close_ok or close_err then
                -- 关闭失败是预期的（socket可能已经关闭），只记录DEBUG日志
                ngx.log(ngx.DEBUG, "Failed to close MySQL connection (expected if socket already closed): ", tostring(close_err or "unknown"))
            end
        end
        
        -- 连接失败时，如果使用的是域名，清除缓存并重新解析（应对动态 IP 变化）
        local original_host = config.mysql.host
        if not original_host:match("^%d+%.%d+%.%d+%.%d+$") then
            local old_ip = resolved_host_cache.ip
            local error_type = "unknown"
            if err then
                if err:match("timeout") then
                    error_type = "timeout"
                elseif err:match("refused") or err:match("Connection refused") then
                    error_type = "connection refused"
                elseif err:match("No route to host") then
                    error_type = "no route to host"
                end
            end
            
            ngx.log(ngx.WARN, "MySQL connection failed (host: ", mysql_host, ", error: ", error_type, "), clearing DNS cache and retrying with fresh resolution (original hostname: ", original_host, ")")
            _M.clear_dns_cache()
            
            -- 重新解析域名（强制刷新，获取最新 IP）
            mysql_host = resolve_hostname(original_host, true)
            
            -- 如果解析到新的 IP，记录日志
            if old_ip and mysql_host ~= old_ip and mysql_host:match("^%d+%.%d+%.%d+%.%d+$") then
                ngx.log(ngx.INFO, "MySQL IP address changed: ", old_ip, " -> ", mysql_host, " (hostname: ", original_host, ")")
            end
            
            -- 创建新连接并重试
            db, err = mysql:new()
            if db then
                db:set_timeout(config.mysql.pool_timeout)
                -- 使用 xpcall 包装重试连接，避免在超时时出现 "attempt to send data on a closed socket" 错误
                local retry_connect_results = {}
                local retry_connect_ok, retry_connect_err = xpcall(function()
                    -- 将多个返回值收集到表中
                    local ok, err, errcode, sqlstate = db:connect{
                        host = mysql_host,
                        port = config.mysql.port,
                        database = config.mysql.database,
                        user = config.mysql.user,
                        password = config.mysql.password,
                        max_packet_size = config.mysql.max_packet_size,
                        charset = "utf8mb4",
                    }
                    retry_connect_results.ok = ok
                    retry_connect_results.err = err
                    retry_connect_results.errcode = errcode
                    retry_connect_results.sqlstate = sqlstate
                    return ok, err, errcode, sqlstate
                end, function(err)
                    -- 错误处理函数：记录异常信息
                    -- 注意：即使使用xpcall捕获异常，resty.mysql库内部可能仍然会在已关闭的socket上操作
                    -- 这会导致"attempt to send data on a closed socket"错误，但这是预期的行为
                    -- 我们只需要确保错误被正确捕获和处理，不影响系统运行
                    local err_str = tostring(err) or "connection retry failed with exception"
                    -- 如果是socket相关错误，记录为DEBUG级别（这是预期的，不需要警告）
                    if err_str:match("attempt to send data on a closed socket") or 
                       err_str:match("closed socket") or
                       err_str:match("timeout") then
                        ngx.log(ngx.DEBUG, "MySQL retry connect() socket error (expected): ", err_str)
                    else
                        ngx.log(ngx.WARN, "MySQL retry connect() threw an exception: ", err_str)
                    end
                    retry_connect_results.ok = false
                    retry_connect_results.err = err_str
                    retry_connect_results.errcode = nil
                    retry_connect_results.sqlstate = nil
                    return err
                end)
                
                if retry_connect_ok then
                    -- xpcall 成功，从结果表中获取返回值
                    ok = retry_connect_results.ok
                    err = retry_connect_results.err
                    errcode = retry_connect_results.errcode
                    sqlstate = retry_connect_results.sqlstate
                else
                    -- xpcall 失败，说明 connect 过程中抛出了异常（可能是 socket 已关闭）
                    -- 注意：即使xpcall捕获了异常，resty.mysql库内部可能仍然会在已关闭的socket上操作
                    -- 这会导致"attempt to send data on a closed socket"错误，但这是预期的行为
                    ok = false
                    err = retry_connect_results.err or retry_connect_err or "connection retry failed with exception"
                    errcode = nil
                    sqlstate = nil
                    -- 如果是socket相关错误，记录为DEBUG级别（这是预期的，不需要警告）
                    local err_str = tostring(retry_connect_err) or ""
                    if err_str:match("attempt to send data on a closed socket") or 
                       err_str:match("closed socket") or
                       err_str:match("timeout") then
                        ngx.log(ngx.DEBUG, "MySQL retry connect() xpcall socket error (expected): ", err_str)
                    else
                        ngx.log(ngx.WARN, "MySQL retry connect() xpcall failed: ", err_str)
                    end
                end
                
                if ok then
                    ngx.log(ngx.INFO, "MySQL connection retry successful with new IP: ", mysql_host)
                else
                    -- 重试也失败，安全关闭
                    if db then
                        local close_ok, close_err = pcall(function() 
                            -- 尝试关闭连接，但如果socket已经关闭，这可能会失败，这是正常的
                            db:close()
                        end)
                        if not close_ok or close_err then
                            -- 关闭失败是预期的（socket可能已经关闭），只记录DEBUG日志
                            ngx.log(ngx.DEBUG, "Failed to close MySQL retry connection (expected if socket already closed): ", tostring(close_err or "unknown"))
                        end
                    end
                end
            end
        else
            -- 如果使用的是 IP 地址，不需要重试 DNS 解析，直接返回错误
            -- 连接已经在上面的 pcall 中安全关闭了，这里不需要再次关闭
        end
        
        if not ok then
            local error_msg = err or "unknown error"
            local error_details = ""
            if errcode then
                error_details = " (errcode: " .. tostring(errcode)
                if sqlstate then
                    error_details = error_details .. ", sqlstate: " .. tostring(sqlstate)
                end
                error_details = error_details .. ")"
            end
            ngx.log(ngx.ERR, "failed to connect to MySQL after retry: ", error_msg, error_details, " (host: ", mysql_host, ", original: ", original_host, ")")
            return nil, error_msg
        end
    end

    return db, nil
end

-- 执行查询（带性能监控）
function _M.query(sql, ...)
    local start_time = ngx.now() * 1000  -- 毫秒
    local db, err = _M.get_connection()
    if not db then
        return nil, err
    end

    -- 构建 SQL（如果有参数）
    local final_sql = sql
    local params = {...}
    if #params > 0 then
        final_sql = build_sql(sql, ...)
    end

    local res, err, errcode, sqlstate = db:query(final_sql)
    local duration_ms = (ngx.now() * 1000) - start_time
    
    -- 性能监控：记录慢查询（延迟加载，避免每次查询都加载模块）
    if duration_ms > 0 then
        local ok, performance_monitor = pcall(require, "waf.performance_monitor")
        if ok and performance_monitor and performance_monitor.record_slow_query then
            performance_monitor.record_slow_query(sql, duration_ms, params)
        end
    end
    
    if not res then
        ngx.log(ngx.ERR, "bad result: ", err, ": ", errcode, ": ", sqlstate)
        -- 检查错误类型，如果是连接相关错误，直接关闭连接
        local is_connection_error = false
        if err then
            if err:match("timeout") or err:match("closed") or err:match("broken") or 
               err:match("Connection refused") or err:match("No route to host") or
               err:match("attempt to send data on a closed socket") then
                is_connection_error = true
            end
        end
        
        -- 安全关闭连接，避免在已关闭的 socket 上再次操作
        if db then
            local close_ok, close_err = pcall(function() 
                if is_connection_error then
                    -- 连接错误，直接关闭
                    db:close()
                else
                    -- 非连接错误，尝试放回连接池
                    local keepalive_ok, keepalive_err = db:set_keepalive(10000, config.mysql.pool_size)
                    if not keepalive_ok then
                        -- 放回连接池失败，关闭连接
                        db:close()
                    end
                end
            end)
            if not close_ok and close_err then
                ngx.log(ngx.DEBUG, "Failed to close/set_keepalive MySQL connection (expected if socket already closed): ", tostring(close_err))
            end
        end
        return nil, err
    end

    -- 将连接放回连接池（使用 pcall 避免在已关闭的 socket 上操作）
    local ok_keepalive, err_keepalive = pcall(function()
        return db:set_keepalive(10000, config.mysql.pool_size)
    end)
    if not ok_keepalive then
        ngx.log(ngx.DEBUG, "failed to set keepalive (possibly already closed): ", tostring(err_keepalive))
        -- 如果set_keepalive失败，尝试关闭连接
        if db then
            pcall(function() db:close() end)
        end
    else
        local ok, err = ok_keepalive, err_keepalive
        if not ok then
            ngx.log(ngx.ERR, "failed to set keepalive: ", err)
            -- 如果set_keepalive失败，尝试关闭连接
            if db then
                pcall(function() db:close() end)
            end
        end
    end

    return res, nil
end

-- 执行插入（返回插入的 ID）
function _M.insert(sql, ...)
    local db, err = _M.get_connection()
    if not db then
        return nil, err
    end

    -- 构建 SQL（如果有参数）
    local final_sql = sql
    if select("#", ...) > 0 then
        final_sql = build_sql(sql, ...)
    end

    local res, err, errcode, sqlstate = db:query(final_sql)
    if not res then
        ngx.log(ngx.ERR, "bad result: ", err, ": ", errcode, ": ", sqlstate)
        -- 检查错误类型，如果是连接相关错误，直接关闭连接
        local is_connection_error = false
        if err then
            if err:match("timeout") or err:match("closed") or err:match("broken") or 
               err:match("Connection refused") or err:match("No route to host") or
               err:match("attempt to send data on a closed socket") then
                is_connection_error = true
            end
        end
        
        -- 安全关闭连接，避免在已关闭的 socket 上再次操作
        if db then
            local close_ok, close_err = pcall(function() 
                if is_connection_error then
                    -- 连接错误，直接关闭
                    db:close()
                else
                    -- 非连接错误，尝试放回连接池
                    local keepalive_ok, keepalive_err = db:set_keepalive(10000, config.mysql.pool_size)
                    if not keepalive_ok then
                        -- 放回连接池失败，关闭连接
                        db:close()
                    end
                end
            end)
            if not close_ok and close_err then
                ngx.log(ngx.DEBUG, "Failed to close/set_keepalive MySQL connection for insert (expected if socket already closed): ", tostring(close_err))
            end
        end
        return nil, err
    end

    local insert_id = res.insert_id

    -- 将连接放回连接池（使用 pcall 避免在已关闭的 socket 上操作）
    local ok_keepalive, err_keepalive = pcall(function()
        return db:set_keepalive(10000, config.mysql.pool_size)
    end)
    if not ok_keepalive then
        ngx.log(ngx.DEBUG, "failed to set keepalive for insert (possibly already closed): ", tostring(err_keepalive))
        -- 如果set_keepalive失败，尝试关闭连接
        if db then
            pcall(function() db:close() end)
        end
    else
        local ok, err = ok_keepalive, err_keepalive
        if not ok then
            ngx.log(ngx.ERR, "failed to set keepalive for insert: ", err)
            -- 如果set_keepalive失败，尝试关闭连接
            if db then
                pcall(function() db:close() end)
            end
        end
    end

    return insert_id, nil
end

-- 批量插入
function _M.batch_insert(table_name, fields, values_list)
    if not values_list or #values_list == 0 then
        return nil, "empty values list"
    end

    -- 表名白名单检查（安全增强，防止SQL注入）
    local allowed_tables = {
        ["waf_access_logs"] = true,
        ["waf_block_logs"] = true,
        ["waf_block_rules"] = true,
        ["waf_whitelist"] = true,
        ["waf_geo_codes"] = true,
        ["waf_system_config"] = true,
        ["waf_ip_frequency"] = true,
        ["waf_auto_block_logs"] = true,
        ["waf_auto_unblock_tasks"] = true,
        ["waf_users"] = true,
        ["waf_user_sessions"] = true,
        ["waf_trusted_proxies"] = true,
        ["waf_feature_switches"] = true,
        ["waf_rule_templates"] = true,
        ["waf_proxy_configs"] = true,
        ["waf_proxy_backends"] = true,
        ["waf_audit_logs"] = true,
        ["waf_csrf_tokens"] = true,
        ["waf_system_access_whitelist"] = true,
    }
    
    if not allowed_tables[table_name] then
        ngx.log(ngx.ERR, "batch_insert: invalid table name: ", table_name)
        return nil, "invalid table name"
    end

    local db, err = _M.get_connection()
    if not db then
        return nil, err
    end

    -- 构建 SQL
    local fields_str = table.concat(fields, ",")
    local values_strs = {}
    
    for i, values in ipairs(values_list) do
        local value_strs = {}
        for j, value in ipairs(values) do
            if value == nil then
                table.insert(value_strs, "NULL")
            elseif type(value) == "string" then
                -- 检查是否是日期时间格式（YYYY-MM-DD HH:MM:SS）
                if string.match(value, "^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$") then
                    table.insert(value_strs, escape_sql(value))
                else
                    table.insert(value_strs, escape_sql(value))
                end
            elseif type(value) == "number" then
                table.insert(value_strs, tostring(value))
            else
                table.insert(value_strs, escape_sql(tostring(value)))
            end
        end
        table.insert(values_strs, "(" .. table.concat(value_strs, ",") .. ")")
    end

    local sql = string.format(
        "INSERT INTO %s (%s) VALUES %s",
        table_name,
        fields_str,
        table.concat(values_strs, ",")
    )

    local res, err, errcode, sqlstate = db:query(sql)
    if not res then
        ngx.log(ngx.ERR, "batch insert failed: ", err, ": ", errcode, ": ", sqlstate)
        -- 检查错误类型，如果是连接相关错误，直接关闭连接
        local is_connection_error = false
        if err then
            if err:match("timeout") or err:match("closed") or err:match("broken") or 
               err:match("Connection refused") or err:match("No route to host") or
               err:match("attempt to send data on a closed socket") then
                is_connection_error = true
            end
        end
        
        -- 安全关闭连接，避免在已关闭的 socket 上再次操作
        if db then
            local close_ok, close_err = pcall(function() 
                if is_connection_error then
                    -- 连接错误，直接关闭
                    db:close()
                else
                    -- 非连接错误，尝试放回连接池
                    local keepalive_ok, keepalive_err = db:set_keepalive(10000, config.mysql.pool_size)
                    if not keepalive_ok then
                        -- 放回连接池失败，关闭连接
                        db:close()
                    end
                end
            end)
            if not close_ok and close_err then
                ngx.log(ngx.DEBUG, "Failed to close/set_keepalive MySQL connection for batch_insert (expected if socket already closed): ", tostring(close_err))
            end
        end
        return nil, err
    end

    -- 将连接放回连接池（使用 pcall 避免在已关闭的 socket 上操作）
    local ok_keepalive, err_keepalive = pcall(function()
        return db:set_keepalive(10000, config.mysql.pool_size)
    end)
    if not ok_keepalive then
        ngx.log(ngx.ERR, "failed to set keepalive for batch_insert: ", tostring(err_keepalive))
        -- 如果set_keepalive失败，尝试关闭连接
        if db then
            pcall(function() db:close() end)
        end
    else
        local ok, err = ok_keepalive, err_keepalive
        if not ok then
            ngx.log(ngx.ERR, "failed to set keepalive for batch_insert: ", err)
            -- 如果set_keepalive失败，尝试关闭连接
            if db then
                pcall(function() db:close() end)
            end
        end
    end

    return res, nil
end

return _M

