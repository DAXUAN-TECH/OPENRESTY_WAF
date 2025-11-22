-- MySQL 连接池管理
-- 路径：项目目录下的 lua/waf/mysql_pool.lua（保持在项目目录，不复制到系统目录）

local mysql = require "resty.mysql"
local config = require "config"

local _M = {}
local pool = {}

-- SQL 转义函数
local function escape_sql(str)
    if str == nil then
        return "NULL"
    end
    if type(str) == "number" then
        return tostring(str)
    end
    -- 转义单引号
    str = string.gsub(str, "'", "''")
    return "'" .. str .. "'"
end

-- 构建参数化 SQL（简单实现）
local function build_sql(sql, ...)
    local args = {...}
    local result = sql
    local index = 1
    
    -- 替换 ? 占位符
    result = string.gsub(result, "%?", function()
        if index <= #args then
            local arg = args[index]
            index = index + 1
            return escape_sql(arg)
        else
            return "?"
        end
    end)
    
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

-- 执行查询
function _M.query(sql, ...)
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

