-- 封控统计报表API模块
-- 路径：项目目录下的 lua/api/stats.lua（保持在项目目录，不复制到系统目录）
-- 功能：提供封控统计报表相关的API接口

local mysql_pool = require "waf.mysql_pool"
local api_utils = require "api.utils"
local cjson = require "cjson"
local feature_switches = require "waf.feature_switches"

local _M = {}

-- 检查统计功能是否启用
local function check_feature_enabled()
    local enabled = feature_switches.is_enabled("stats")
    if not enabled then
        api_utils.json_response({
            success = false,
            error = "统计功能已禁用"
        }, 403)
        return false
    end
    return true
end

-- 获取封控统计概览
function _M.overview()
    if not check_feature_enabled() then
        return
    end
    
    local args = api_utils.get_args()
    local start_time = args.start_time or os.date("!%Y-%m-%d 00:00:00", ngx.time() - 86400)  -- 默认最近24小时
    local end_time = args.end_time or os.date("!%Y-%m-%d %H:%M:%S", ngx.time())
    
    -- 总封控次数
    local sql_total = [[
        SELECT COUNT(*) as total_blocks
        FROM waf_block_logs
        WHERE block_time >= ? AND block_time <= ?
    ]]
    
    -- 按原因分类统计
    local sql_by_reason = [[
        SELECT block_reason, COUNT(*) as count
        FROM waf_block_logs
        WHERE block_time >= ? AND block_time <= ?
        GROUP BY block_reason
    ]]
    
    -- 被封控的IP数
    local sql_unique_ips = [[
        SELECT COUNT(DISTINCT client_ip) as unique_ips
        FROM waf_block_logs
        WHERE block_time >= ? AND block_time <= ?
    ]]
    
    -- 规则命中统计（TOP 10）
    local sql_top_rules = [[
        SELECT rule_id, rule_name, COUNT(*) as hit_count
        FROM waf_block_logs
        WHERE block_time >= ? AND block_time <= ?
        AND rule_id IS NOT NULL
        GROUP BY rule_id, rule_name
        ORDER BY hit_count DESC
        LIMIT 10
    ]]
    
    local total_res, err1 = mysql_pool.query(sql_total, start_time, end_time)
    local reason_res, err2 = mysql_pool.query(sql_by_reason, start_time, end_time)
    local ips_res, err3 = mysql_pool.query(sql_unique_ips, start_time, end_time)
    local top_rules_res, err4 = mysql_pool.query(sql_top_rules, start_time, end_time)
    
    if err1 or err2 or err3 or err4 then
        api_utils.json_response({
            error = "查询失败",
            message = err1 or err2 or err3 or err4
        }, 500)
        return
    end
    
    local overview = {
        total_blocks = (total_res and #total_res > 0) and total_res[1].total_blocks or 0,
        unique_blocked_ips = (ips_res and #ips_res > 0) and ips_res[1].unique_ips or 0,
        by_reason = {},
        top_rules = {}
    }
    
    -- 按原因分类统计
    if reason_res then
        for _, row in ipairs(reason_res) do
            overview.by_reason[row.block_reason] = row.count
        end
    end
    
    -- TOP规则
    if top_rules_res then
        for _, row in ipairs(top_rules_res) do
            table.insert(overview.top_rules, {
                rule_id = row.rule_id,
                rule_name = row.rule_name,
                hit_count = row.hit_count
            })
        end
    end
    
    api_utils.json_response({
        success = true,
        data = overview,
        time_range = {
            start_time = start_time,
            end_time = end_time
        }
    }, 200)
end

-- 获取时间序列统计（用于图表）
function _M.timeseries()
    if not check_feature_enabled() then
        return
    end
    
    local args = api_utils.get_args()
    local start_time = args.start_time or os.date("!%Y-%m-%d 00:00:00", ngx.time() - 86400)
    local end_time = args.end_time or os.date("!%Y-%m-%d %H:%M:%S", ngx.time())
    local interval = args.interval or "hour"  -- hour, day
    
    local time_format = interval == "hour" and "%Y-%m-%d %H:00:00" or "%Y-%m-%d 00:00:00"
    local group_format = interval == "hour" and "DATE_FORMAT(block_time, '%Y-%m-%d %H:00:00')" or "DATE_FORMAT(block_time, '%Y-%m-%d')"
    
    local sql = string.format([[
        SELECT 
            %s as time_point,
            COUNT(*) as block_count,
            COUNT(DISTINCT client_ip) as unique_ips
        FROM waf_block_logs
        WHERE block_time >= ? AND block_time <= ?
        GROUP BY time_point
        ORDER BY time_point ASC
    ]], group_format)
    
    local res, err = mysql_pool.query(sql, start_time, end_time)
    if err then
        api_utils.json_response({
            error = "查询失败",
            message = err
        }, 500)
        return
    end
    
    local timeseries = {}
    if res then
        -- 确保 res 是数组
        local res_array = {}
        if type(res) == "table" then
            -- 检查是否是数组
            local is_array = false
            for i, _ in ipairs(res) do
                is_array = true
                res_array[i] = res[i]
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
                    table.insert(res_array, item.value)
                end
            end
        end
        
        for _, row in ipairs(res_array) do
            table.insert(timeseries, {
                time = row.time_point,
                block_count = row.block_count,
                unique_ips = row.unique_ips
            })
        end
    end
    
    api_utils.json_response({
        success = true,
        data = timeseries,
        interval = interval
    }, 200)
end

-- 获取IP封控统计
function _M.ip_stats()
    if not check_feature_enabled() then
        return
    end
    
    local args = api_utils.get_args()
    local start_time = args.start_time or os.date("!%Y-%m-%d 00:00:00", ngx.time() - 86400)
    local end_time = args.end_time or os.date("!%Y-%m-%d %H:%M:%S", ngx.time())
    local limit = tonumber(args.limit) or 20
    
    local sql = [[
        SELECT 
            client_ip,
            COUNT(*) as block_count,
            MIN(block_time) as first_block_time,
            MAX(block_time) as last_block_time,
            COUNT(DISTINCT rule_id) as rule_count
        FROM waf_block_logs
        WHERE block_time >= ? AND block_time <= ?
        GROUP BY client_ip
        ORDER BY block_count DESC
        LIMIT ?
    ]]
    
    local res, err = mysql_pool.query(sql, start_time, end_time, limit)
    if err then
        api_utils.json_response({
            error = "查询失败",
            message = err
        }, 500)
        return
    end
    
    local ip_stats = {}
    if res then
        -- 确保 res 是数组
        local res_array = {}
        if type(res) == "table" then
            -- 检查是否是数组
            local is_array = false
            for i, _ in ipairs(res) do
                is_array = true
                res_array[i] = res[i]
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
                    table.insert(res_array, item.value)
                end
            end
        end
        
        for _, row in ipairs(res_array) do
            table.insert(ip_stats, {
                client_ip = row.client_ip,
                block_count = row.block_count,
                first_block_time = row.first_block_time,
                last_block_time = row.last_block_time,
                rule_count = row.rule_count
            })
        end
    end
    
    api_utils.json_response({
        success = true,
        data = ip_stats
    }, 200)
end

-- 获取规则命中统计
function _M.rule_stats()
    if not check_feature_enabled() then
        return
    end
    
    local args = api_utils.get_args()
    local start_time = args.start_time or os.date("!%Y-%m-%d 00:00:00", ngx.time() - 86400)
    local end_time = args.end_time or os.date("!%Y-%m-%d %H:%M:%S", ngx.time())
    local limit = tonumber(args.limit) or 20
    
    local sql = [[
        SELECT 
            br.id,
            br.rule_name,
            br.rule_type,
            br.rule_value,
            COUNT(bl.id) as hit_count,
            COUNT(DISTINCT bl.client_ip) as blocked_ips,
            MAX(bl.block_time) as last_hit_time
        FROM waf_block_rules br
        LEFT JOIN waf_block_logs bl ON br.id = bl.rule_id 
            AND bl.block_time >= ? AND bl.block_time <= ?
        WHERE br.status = 1
        GROUP BY br.id, br.rule_name, br.rule_type, br.rule_value
        ORDER BY hit_count DESC
        LIMIT ?
    ]]
    
    local res, err = mysql_pool.query(sql, start_time, end_time, limit)
    if err then
        api_utils.json_response({
            error = "查询失败",
            message = err
        }, 500)
        return
    end
    
    local rule_stats = {}
    if res then
        -- 确保 res 是数组
        local res_array = {}
        if type(res) == "table" then
            -- 检查是否是数组
            local is_array = false
            for i, _ in ipairs(res) do
                is_array = true
                res_array[i] = res[i]
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
                    table.insert(res_array, item.value)
                end
            end
        end
        
        for _, row in ipairs(res_array) do
            table.insert(rule_stats, {
                rule_id = row.id,
                rule_name = row.rule_name,
                rule_type = row.rule_type,
                rule_value = row.rule_value,
                hit_count = row.hit_count or 0,
                blocked_ips = row.blocked_ips or 0,
                last_hit_time = row.last_hit_time
            })
        end
    end
    
    api_utils.json_response({
        success = true,
        data = rule_stats
    }, 200)
end

return _M

