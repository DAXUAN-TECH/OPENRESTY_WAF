-- 日志查看API模块
-- 路径：项目目录下的 lua/api/logs.lua
-- 功能：提供日志查询API，支持访问日志、封控日志、审计日志等

local mysql_pool = require "waf.mysql_pool"
local api_utils = require "api.utils"
local auth = require "waf.auth"

local _M = {}

-- 获取访问日志列表
function _M.get_access_logs()
    local session = auth.require_auth()
    if not session then
        return
    end
    
    local args = api_utils.get_args()
    local page = tonumber(args.page) or 1
    local page_size = tonumber(args.page_size) or 50
    local offset = (page - 1) * page_size
    
    -- 查询条件
    local where_clauses = {}
    local params = {}
    
    -- IP过滤
    if args.client_ip and args.client_ip ~= "" then
        table.insert(where_clauses, "client_ip = ?")
        table.insert(params, args.client_ip)
    end
    
    -- 域名过滤
    if args.request_domain and args.request_domain ~= "" then
        table.insert(where_clauses, "request_domain = ?")
        table.insert(params, args.request_domain)
    end
    
    -- 路径过滤
    if args.request_path and args.request_path ~= "" then
        table.insert(where_clauses, "request_path LIKE ?")
        table.insert(params, "%" .. args.request_path .. "%")
    end
    
    -- 状态码过滤
    if args.status_code and args.status_code ~= "" then
        table.insert(where_clauses, "status_code = ?")
        table.insert(params, tonumber(args.status_code))
    end
    
    -- 时间范围过滤
    if args.start_time and args.start_time ~= "" then
        table.insert(where_clauses, "request_time >= ?")
        table.insert(params, args.start_time)
    end
    
    if args.end_time and args.end_time ~= "" then
        table.insert(where_clauses, "request_time <= ?")
        table.insert(params, args.end_time)
    end
    
    -- 构建WHERE子句
    local where_sql = ""
    if #where_clauses > 0 then
        where_sql = "WHERE " .. table.concat(where_clauses, " AND ")
    end
    
    -- 查询总数
    local count_sql = "SELECT COUNT(*) as total FROM waf_access_logs " .. where_sql
    local count_res, count_err = mysql_pool.query(count_sql, unpack(params))
    
    if count_err then
        api_utils.json_response({
            error = "Internal Server Error",
            message = "查询日志总数失败: " .. (count_err or "unknown error")
        }, 500)
        return
    end
    
    local total = 0
    if count_res and #count_res > 0 then
        total = tonumber(count_res[1].total) or 0
    end
    
    -- 查询日志列表
    local sql = string.format([[
        SELECT 
            id, client_ip, request_domain, request_path, request_method,
            status_code, user_agent, referer, request_time, response_time, created_at
        FROM waf_access_logs
        %s
        ORDER BY request_time DESC
        LIMIT ? OFFSET ?
    ]], where_sql)
    
    table.insert(params, page_size)
    table.insert(params, offset)
    
    local res, err = mysql_pool.query(sql, unpack(params))
    
    if err then
        api_utils.json_response({
            error = "Internal Server Error",
            message = "查询日志失败: " .. (err or "unknown error")
        }, 500)
        return
    end
    
    api_utils.json_response({
        success = true,
        data = res or {},
        pagination = {
            page = page,
            page_size = page_size,
            total = total,
            total_pages = math.ceil(total / page_size)
        }
    }, 200)
end

-- 获取封控日志列表
function _M.get_block_logs()
    local session = auth.require_auth()
    if not session then
        return
    end
    
    local args = api_utils.get_args()
    local page = tonumber(args.page) or 1
    local page_size = tonumber(args.page_size) or 50
    local offset = (page - 1) * page_size
    
    -- 查询条件
    local where_clauses = {}
    local params = {}
    
    -- IP过滤
    if args.client_ip and args.client_ip ~= "" then
        table.insert(where_clauses, "client_ip = ?")
        table.insert(params, args.client_ip)
    end
    
    -- 封控原因过滤
    if args.block_reason and args.block_reason ~= "" then
        table.insert(where_clauses, "block_reason = ?")
        table.insert(params, args.block_reason)
    end
    
    -- 规则名称过滤
    if args.rule_name and args.rule_name ~= "" then
        table.insert(where_clauses, "rule_name LIKE ?")
        table.insert(params, "%" .. args.rule_name .. "%")
    end
    
    -- 时间范围过滤
    if args.start_time and args.start_time ~= "" then
        table.insert(where_clauses, "block_time >= ?")
        table.insert(params, args.start_time)
    end
    
    if args.end_time and args.end_time ~= "" then
        table.insert(where_clauses, "block_time <= ?")
        table.insert(params, args.end_time)
    end
    
    -- 构建WHERE子句
    local where_sql = ""
    if #where_clauses > 0 then
        where_sql = "WHERE " .. table.concat(where_clauses, " AND ")
    end
    
    -- 查询总数
    local count_sql = "SELECT COUNT(*) as total FROM waf_block_logs " .. where_sql
    local count_res, count_err = mysql_pool.query(count_sql, unpack(params))
    
    if count_err then
        api_utils.json_response({
            error = "Internal Server Error",
            message = "查询日志总数失败: " .. (count_err or "unknown error")
        }, 500)
        return
    end
    
    local total = 0
    if count_res and #count_res > 0 then
        total = tonumber(count_res[1].total) or 0
    end
    
    -- 查询日志列表
    local sql = string.format([[
        SELECT 
            id, client_ip, rule_id, rule_name, block_reason,
            block_time, request_path, user_agent, created_at
        FROM waf_block_logs
        %s
        ORDER BY block_time DESC
        LIMIT ? OFFSET ?
    ]], where_sql)
    
    table.insert(params, page_size)
    table.insert(params, offset)
    
    local res, err = mysql_pool.query(sql, unpack(params))
    
    if err then
        api_utils.json_response({
            error = "Internal Server Error",
            message = "查询日志失败: " .. (err or "unknown error")
        }, 500)
        return
    end
    
    -- 确保 res 是数组类型（用于 JSON 序列化）
    local logs_array = {}
    if res then
        if type(res) == "table" then
            -- 检查是否是数组
            local is_array = false
            for i, _ in ipairs(res) do
                is_array = true
                logs_array[i] = res[i]
            end
            
            -- 如果不是数组，尝试转换
            if not is_array then
                local temp_array = {}
                for k, v in pairs(res) do
                    if type(k) == "number" and k > 0 then
                        table.insert(temp_array, {key = k, value = v})
                    end
                end
                table.sort(temp_array, function(a, b) return a.key < b.key end)
                for _, item in ipairs(temp_array) do
                    table.insert(logs_array, item.value)
                end
            end
        end
    end
    
    api_utils.json_response({
        success = true,
        data = logs_array,
        pagination = {
            page = page,
            page_size = page_size,
            total = total,
            total_pages = math.ceil(total / page_size)
        }
    }, 200)
end

-- 获取审计日志列表
function _M.get_audit_logs()
    local session = auth.require_auth()
    if not session then
        return
    end
    
    local args = api_utils.get_args()
    local page = tonumber(args.page) or 1
    local page_size = tonumber(args.page_size) or 50
    local offset = (page - 1) * page_size
    
    -- 查询条件
    local where_clauses = {}
    local params = {}
    
    -- 用户名过滤
    if args.username and args.username ~= "" then
        table.insert(where_clauses, "username = ?")
        table.insert(params, args.username)
    end
    
    -- 操作类型过滤
    if args.action_type and args.action_type ~= "" then
        table.insert(where_clauses, "action_type = ?")
        table.insert(params, args.action_type)
    end
    
    -- 资源类型过滤
    if args.resource_type and args.resource_type ~= "" then
        table.insert(where_clauses, "resource_type = ?")
        table.insert(params, args.resource_type)
    end
    
    -- 状态过滤
    if args.status and args.status ~= "" then
        table.insert(where_clauses, "status = ?")
        table.insert(params, args.status)
    end
    
    -- 时间范围过滤
    if args.start_time and args.start_time ~= "" then
        table.insert(where_clauses, "created_at >= ?")
        table.insert(params, args.start_time)
    end
    
    if args.end_time and args.end_time ~= "" then
        table.insert(where_clauses, "created_at <= ?")
        table.insert(params, args.end_time)
    end
    
    -- 构建WHERE子句
    local where_sql = ""
    if #where_clauses > 0 then
        where_sql = "WHERE " .. table.concat(where_clauses, " AND ")
    end
    
    -- 查询总数
    local count_sql = "SELECT COUNT(*) as total FROM waf_audit_logs " .. where_sql
    local count_res, count_err = mysql_pool.query(count_sql, unpack(params))
    
    if count_err then
        api_utils.json_response({
            error = "Internal Server Error",
            message = "查询日志总数失败: " .. (count_err or "unknown error")
        }, 500)
        return
    end
    
    local total = 0
    if count_res and #count_res > 0 then
        total = tonumber(count_res[1].total) or 0
    end
    
    -- 查询日志列表
    local sql = string.format([[
        SELECT 
            id, user_id, username, action_type, resource_type, resource_id,
            action_description, request_method, request_path, request_params,
            ip_address, user_agent, status, error_message, created_at
        FROM waf_audit_logs
        %s
        ORDER BY created_at DESC
        LIMIT ? OFFSET ?
    ]], where_sql)
    
    table.insert(params, page_size)
    table.insert(params, offset)
    
    local res, err = mysql_pool.query(sql, unpack(params))
    
    if err then
        api_utils.json_response({
            error = "Internal Server Error",
            message = "查询日志失败: " .. (err or "unknown error")
        }, 500)
        return
    end
    
    -- 确保 res 是数组类型（用于 JSON 序列化）
    local logs_array = {}
    if res then
        if type(res) == "table" then
            -- 检查是否是数组
            local is_array = false
            for i, _ in ipairs(res) do
                is_array = true
                logs_array[i] = res[i]
            end
            
            -- 如果不是数组，尝试转换
            if not is_array then
                local temp_array = {}
                for k, v in pairs(res) do
                    if type(k) == "number" and k > 0 then
                        table.insert(temp_array, {key = k, value = v})
                    end
                end
                table.sort(temp_array, function(a, b) return a.key < b.key end)
                for _, item in ipairs(temp_array) do
                    table.insert(logs_array, item.value)
                end
            end
        end
    end
    
    api_utils.json_response({
        success = true,
        data = logs_array,
        pagination = {
            page = page,
            page_size = page_size,
            total = total,
            total_pages = math.ceil(total / page_size)
        }
    }, 200)
end

-- 获取日志统计信息
function _M.get_log_stats()
    local session = auth.require_auth()
    if not session then
        return
    end
    
    local args = api_utils.get_args()
    local start_time = args.start_time or os.date("!%Y-%m-%d 00:00:00", ngx.time() - 86400)  -- 默认最近24小时
    local end_time = args.end_time or os.date("!%Y-%m-%d %H:%M:%S", ngx.time())
    
    -- 访问日志统计
    local access_stats_sql = [[
        SELECT 
            COUNT(*) as total_requests,
            COUNT(DISTINCT client_ip) as unique_ips,
            COUNT(DISTINCT request_domain) as unique_domains,
            AVG(response_time) as avg_response_time,
            SUM(CASE WHEN status_code >= 400 THEN 1 ELSE 0 END) as error_count
        FROM waf_access_logs
        WHERE request_time >= ? AND request_time <= ?
    ]]
    
    local access_stats, access_err = mysql_pool.query(access_stats_sql, start_time, end_time)
    
    -- 封控日志统计
    local block_stats_sql = [[
        SELECT 
            COUNT(*) as total_blocks,
            COUNT(DISTINCT client_ip) as unique_blocked_ips
        FROM waf_block_logs
        WHERE block_time >= ? AND block_time <= ?
    ]]
    
    local block_stats, block_err = mysql_pool.query(block_stats_sql, start_time, end_time)
    
    -- 审计日志统计
    local audit_stats_sql = [[
        SELECT 
            COUNT(*) as total_audits,
            COUNT(DISTINCT username) as unique_users
        FROM waf_audit_logs
        WHERE created_at >= ? AND created_at <= ?
    ]]
    
    local audit_stats, audit_err = mysql_pool.query(audit_stats_sql, start_time, end_time)
    
    api_utils.json_response({
        success = true,
        data = {
            access_logs = access_stats and access_stats[1] or {},
            block_logs = block_stats and block_stats[1] or {},
            audit_logs = audit_stats and audit_stats[1] or {},
            time_range = {
                start_time = start_time,
                end_time = end_time
            }
        }
    }, 200)
end

return _M

