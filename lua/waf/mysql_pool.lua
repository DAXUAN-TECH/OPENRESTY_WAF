-- MySQL 连接池管理
-- 路径：项目目录下的 lua/waf/mysql_pool.lua（保持在项目目录，不复制到系统目录）

local mysql = require "resty.mysql"
local config = require "config"

local _M = {}
local pool = {}

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

    local ok, err, errcode, sqlstate = db:connect{
        host = config.mysql.host,
        port = config.mysql.port,
        database = config.mysql.database,
        user = config.mysql.user,
        password = config.mysql.password,
        max_packet_size = config.mysql.max_packet_size,
        charset = "utf8mb4",
    }

    if not ok then
        ngx.log(ngx.ERR, "failed to connect: ", err, ": ", errcode, " ", sqlstate)
        return nil, err
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
        db:close()
        return nil, err
    end

    -- 将连接放回连接池
    local ok, err = db:set_keepalive(10000, config.mysql.pool_size)
    if not ok then
        ngx.log(ngx.ERR, "failed to set keepalive: ", err)
        db:close()
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
        db:close()
        return nil, err
    end

    local insert_id = res.insert_id

    local ok, err = db:set_keepalive(10000, config.mysql.pool_size)
    if not ok then
        ngx.log(ngx.ERR, "failed to set keepalive: ", err)
        db:close()
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
        ["waf_cache_versions"] = true,
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
        db:close()
        return nil, err
    end

    local ok, err = db:set_keepalive(10000, config.mysql.pool_size)
    if not ok then
        ngx.log(ngx.ERR, "failed to set keepalive: ", err)
        db:close()
    end

    return res, nil
end

return _M

