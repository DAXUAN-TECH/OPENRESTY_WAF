-- 规则管理模块
-- 路径：项目目录下的 lua/waf/rule_management.lua（保持在项目目录，不复制到系统目录）
-- 功能：实现规则的CRUD操作

local mysql_pool = require "waf.mysql_pool"
local cache_invalidation = require "waf.cache_invalidation"
local rule_notification = require "waf.rule_notification"
local ip_utils = require "waf.ip_utils"
local cjson = require "cjson"

local _M = {}

-- 验证规则值格式
local function validate_rule_value(rule_type, rule_value)
    if not rule_value or rule_value == "" then
        return false, "规则值不能为空"
    end
    
    if rule_type == "single_ip" then
        if not ip_utils.is_valid_ip(rule_value) then
            return false, "无效的IP地址格式"
        end
    elseif rule_type == "ip_range" then
        -- 检查CIDR格式或IP范围格式
        if not ip_utils.is_valid_cidr(rule_value) then
            local start_ip, end_ip = ip_utils.parse_ip_range(rule_value)
            if not start_ip or not end_ip then
                return false, "无效的IP段格式（应为CIDR格式如192.168.1.0/24或IP范围如192.168.1.1-192.168.1.100）"
            end
        end
    elseif rule_type == "geo" then
        -- 验证地域代码格式（支持多选，用逗号分隔）
        -- 格式：国家代码（如CN、US）或 国家:省份代码（如CN:Beijing）或 国家:省份代码:城市名称（如CN:Beijing:北京）
        -- 支持多个值用逗号分隔，城市名称可以是中文
        local geo_values = {}
        for value in rule_value:gmatch("([^,]+)") do
            value = value:match("^%s*(.-)%s*$")  -- 去除首尾空格
            if value and value ~= "" then
                table.insert(geo_values, value)
            end
        end
        
        if #geo_values == 0 then
            return false, "地域代码不能为空"
        end
        
        -- 验证每个地域代码格式
        for _, geo_value in ipairs(geo_values) do
            -- 支持格式：
            -- 1. 国家代码：两个大写字母，如 CN, US, JP
            -- 2. 国家:省份代码：CN:Beijing, CN:Shanghai（省份代码可以是字母）
            -- 3. 国家:省份代码:城市名称：CN:Beijing:北京（城市名称可以是中文、字母、数字等）
            local pattern = "^[A-Z]{2}(:[A-Za-z0-9_%-]+(:[%w%u%l%p]+)?)?$"
            if not geo_value:match(pattern) then
                -- 更宽松的验证：支持中文字符
                local pattern2 = "^[A-Z]{2}(:[%w%u%l%p]+(:[%w%u%l%p]+)?)?$"
                if not geo_value:match(pattern2) then
                    return false, "无效的地域代码格式: " .. geo_value .. "（应为国家代码如CN、US或国家:省份如CN:Beijing或国家:省份:城市如CN:Beijing:北京）"
                end
            end
        end
    else
        return false, "无效的规则类型"
    end
    
    return true, nil
end

-- 创建规则
function _M.create_rule(rule_data)
    -- 验证必填字段
    if not rule_data.rule_type or not rule_data.rule_value or not rule_data.rule_name then
        return nil, "规则类型、规则值和规则名称不能为空"
    end
    
    -- 验证规则值格式
    local valid, err = validate_rule_value(rule_data.rule_type, rule_data.rule_value)
    if not valid then
        return nil, err
    end
    
    local status = rule_data.status or 1
    local priority = rule_data.priority or 0
    local description = rule_data.description
    local rule_group = rule_data.rule_group
    local start_time = rule_data.start_time
    local end_time = rule_data.end_time
    
    -- 处理空字符串：将空字符串转换为 nil（NULL）
    if description == "" then
        description = nil
    end
    if rule_group == "" then
        rule_group = nil
    end
    if start_time == "" then
        start_time = nil
    end
    if end_time == "" then
        end_time = nil
    end
    
    -- 验证分组名称（防止SQL注入，只允许字母、数字、下划线、中文字符和常见分隔符）
    if rule_group and rule_group ~= "" then
        if not rule_group:match("^[%w%u4e00-%u9fa5_%-%.%s]+$") then
            return nil, "分组名称包含非法字符，只允许字母、数字、下划线、中文字符和常见分隔符"
        end
        -- 限制分组名称长度
        if #rule_group > 50 then
            return nil, "分组名称长度不能超过50个字符"
        end
    end
    
    -- 构建SQL（支持规则分组和NULL值）
    -- 注意：rule_version 字段使用默认值 1，不需要在 VALUES 中指定
    local sql = [[
        INSERT INTO waf_block_rules 
        (rule_type, rule_value, rule_name, description, rule_group, status, priority, start_time, end_time, rule_version)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
    ]]
    
    -- 记录参数信息用于调试
    ngx.log(ngx.DEBUG, "create_rule SQL params: type=", rule_data.rule_type, 
        ", value=", rule_data.rule_value, ", name=", rule_data.rule_name,
        ", desc=", tostring(description), ", group=", tostring(rule_group),
        ", status=", status, ", priority=", priority,
        ", start=", tostring(start_time), ", end=", tostring(end_time))
    
    local insert_id, err = mysql_pool.insert(sql,
        rule_data.rule_type,
        rule_data.rule_value,
        rule_data.rule_name,
        description,
        rule_group,
        status,
        priority,
        start_time,
        end_time
    )
    
    if err then
        ngx.log(ngx.ERR, "create rule error: ", err)
        return nil, err
    end
    
    -- 如果规则已启用，触发缓存失效
    if status == 1 then
        cache_invalidation.increment_rule_version()
        rule_notification.notify_rule_created(insert_id, rule_data.rule_type)
    end
    
    ngx.log(ngx.INFO, "rule created: ", insert_id)
    return {id = insert_id}, nil
end

-- 查询规则列表
function _M.list_rules(params)
    params = params or {}
    local rule_type = params.rule_type
    local status = params.status
    local rule_group = params.rule_group
    local page = params.page or 1
    local page_size = params.page_size or 20
    
    -- 构建WHERE条件（使用参数化查询，防止SQL注入）
    local where_clauses = {}
    local query_params = {}
    
    if rule_type then
        table.insert(where_clauses, "rule_type = ?")
        table.insert(query_params, rule_type)
    end
    if status ~= nil then
        table.insert(where_clauses, "status = ?")
        table.insert(query_params, status)
    end
    if rule_group then
        if rule_group == "" then
            -- 查询未分组的规则
            table.insert(where_clauses, "(rule_group IS NULL OR rule_group = '')")
        else
            table.insert(where_clauses, "rule_group = ?")
            table.insert(query_params, rule_group)
        end
    end
    
    local where_sql = ""
    if #where_clauses > 0 then
        where_sql = "WHERE " .. table.concat(where_clauses, " AND ")
    end
    
    -- 查询总数
    local count_sql = "SELECT COUNT(*) as total FROM waf_block_rules " .. where_sql
    local count_res, err = mysql_pool.query(count_sql, unpack(query_params))
    if err then
        ngx.log(ngx.ERR, "count rules error: ", err)
        return nil, err
    end
    
    local total = count_res[1] and count_res[1].total or 0
    
    -- 查询列表（包含分组字段）
    local offset = (page - 1) * page_size
    local sql = string.format([[
        SELECT id, rule_type, rule_value, rule_name, description, rule_group, status, priority, 
               start_time, end_time, created_at, updated_at, rule_version
        FROM waf_block_rules
        %s
        ORDER BY priority DESC, created_at DESC
        LIMIT %d OFFSET %d
    ]], where_sql, page_size, offset)
    
    local rules, err = mysql_pool.query(sql, unpack(query_params))
    if err then
        ngx.log(ngx.ERR, "list rules error: ", err)
        return nil, err
    end
    
    -- 确保 rules 是数组类型
    if not rules then
        rules = {}
    elseif type(rules) ~= "table" then
        ngx.log(ngx.WARN, "list rules: rules is not a table, type: ", type(rules))
        rules = {}
    elseif #rules == 0 and next(rules) ~= nil then
        -- 如果是非数组的table（比如 {key = value}），转换为数组
        ngx.log(ngx.WARN, "list rules: rules is not an array table")
        rules = {}
    end
    
    return {
        rules = rules,
        total = total,
        page = page,
        page_size = page_size,
        total_pages = math.ceil(total / page_size)
    }, nil
end

-- 查询规则详情
function _M.get_rule(rule_id)
    if not rule_id then
        return nil, "规则ID不能为空"
    end
    
    local sql = [[
        SELECT id, rule_type, rule_value, rule_name, description, rule_group, status, priority, 
               start_time, end_time, created_at, updated_at, rule_version
        FROM waf_block_rules
        WHERE id = ?
        LIMIT 1
    ]]
    
    local rules, err = mysql_pool.query(sql, rule_id)
    if err then
        ngx.log(ngx.ERR, "get rule error: ", err)
        return nil, err
    end
    
    if not rules or #rules == 0 then
        return nil, "规则不存在"
    end
    
    return rules[1], nil
end

-- 更新规则
function _M.update_rule(rule_id, rule_data)
    if not rule_id then
        return nil, "规则ID不能为空"
    end
    
    -- 检查规则是否存在
    local rule, err = _M.get_rule(rule_id)
    if err then
        return nil, err
    end
    
    -- 构建更新字段
    local update_fields = {}
    
    if rule_data.rule_type then
        if rule_data.rule_type ~= rule.rule_type then
            return nil, "不允许修改规则类型"
        end
    end
    
    if rule_data.rule_value then
        local valid, err_msg = validate_rule_value(rule.rule_type, rule_data.rule_value)
        if not valid then
            return nil, err_msg
        end
        table.insert(update_fields, "rule_value = ?")
    end
    
    if rule_data.rule_name then
        table.insert(update_fields, "rule_name = ?")
    end
    
    if rule_data.description ~= nil then
        table.insert(update_fields, "description = ?")
    end
    
    if rule_data.rule_group ~= nil then
        -- 验证分组名称（防止SQL注入）
        if rule_data.rule_group ~= "" then
            if not rule_data.rule_group:match("^[%w%u4e00-%u9fa5_%-%.%s]+$") then
                return nil, "分组名称包含非法字符，只允许字母、数字、下划线、中文字符和常见分隔符"
            end
            if #rule_data.rule_group > 50 then
                return nil, "分组名称长度不能超过50个字符"
            end
        end
        if rule_data.rule_group == "" then
            table.insert(update_fields, "rule_group = NULL")
        else
            table.insert(update_fields, "rule_group = ?")
        end
    end
    
    if rule_data.priority ~= nil then
        table.insert(update_fields, "priority = ?")
    end
    
    if rule_data.start_time ~= nil then
        if rule_data.start_time == "" then
            table.insert(update_fields, "start_time = NULL")
        else
            table.insert(update_fields, "start_time = ?")
        end
    end
    
    if rule_data.end_time ~= nil then
        if rule_data.end_time == "" then
            table.insert(update_fields, "end_time = NULL")
        else
            table.insert(update_fields, "end_time = ?")
        end
    end
    
    -- 构建参数列表
    local update_params = {}
    if rule_data.rule_value then
        table.insert(update_params, rule_data.rule_value)
    end
    if rule_data.rule_name then
        table.insert(update_params, rule_data.rule_name)
    end
    if rule_data.description ~= nil then
        table.insert(update_params, rule_data.description)
    end
    if rule_data.rule_group ~= nil and rule_data.rule_group ~= "" then
        table.insert(update_params, rule_data.rule_group)
    end
    if rule_data.priority ~= nil then
        table.insert(update_params, rule_data.priority)
    end
    if rule_data.start_time ~= nil and rule_data.start_time ~= "" then
        table.insert(update_params, rule_data.start_time)
    end
    if rule_data.end_time ~= nil and rule_data.end_time ~= "" then
        table.insert(update_params, rule_data.end_time)
    end
    
    if rule_data.status ~= nil then
        local new_status = tonumber(rule_data.status)
        local old_status = rule.status
        
        table.insert(update_fields, "status = " .. new_status)
        
        -- 如果状态改变，更新规则版本号
        if old_status ~= new_status then
            table.insert(update_fields, "rule_version = rule_version + 1")
        end
    end
    
    if #update_fields == 0 then
        return nil, "没有需要更新的字段"
    end
    
    -- 添加状态更新参数
    if rule_data.status ~= nil then
        table.insert(update_params, rule_data.status)
    end
    
    -- 添加规则ID到参数列表
    table.insert(update_params, rule_id)
    
    -- 执行更新
    local sql = "UPDATE waf_block_rules SET " .. table.concat(update_fields, ", ") .. " WHERE id = ?"
    
    local res, err = mysql_pool.query(sql, unpack(update_params))
    if err then
        ngx.log(ngx.ERR, "update rule error: ", err)
        return nil, err
    end
    
    -- 如果规则状态改变，触发缓存失效
    if rule_data.status ~= nil and rule.status ~= tonumber(rule_data.status) then
        cache_invalidation.increment_rule_version()
        rule_notification.notify_rule_updated(rule_id, rule.rule_type)
    end
    
    ngx.log(ngx.INFO, "rule updated: ", rule_id)
    return {id = rule_id}, nil
end

-- 删除规则
function _M.delete_rule(rule_id)
    if not rule_id then
        return nil, "规则ID不能为空"
    end
    
    -- 检查规则是否存在
    local rule, err = _M.get_rule(rule_id)
    if err then
        return nil, err
    end
    
    -- 执行删除
    local sql = "DELETE FROM waf_block_rules WHERE id = ?"
    local res, err = mysql_pool.query(sql, rule_id)
    if err then
        ngx.log(ngx.ERR, "delete rule error: ", err)
        return nil, err
    end
    
    -- 触发缓存失效
    cache_invalidation.increment_rule_version()
    rule_notification.notify_rule_deleted(rule_id, rule.rule_type)
    
    ngx.log(ngx.INFO, "rule deleted: ", rule_id)
    return {id = rule_id}, nil
end

-- 启用规则
function _M.enable_rule(rule_id)
    return _M.update_rule(rule_id, {status = 1})
end

-- 禁用规则
function _M.disable_rule(rule_id)
    return _M.update_rule(rule_id, {status = 0})
end

-- 获取所有规则分组列表（用于下拉选择）
function _M.list_rule_groups()
    local sql = [[
        SELECT DISTINCT rule_group as group_name, COUNT(*) as rule_count
        FROM waf_block_rules
        WHERE rule_group IS NOT NULL AND rule_group != ''
        GROUP BY rule_group
        ORDER BY rule_group ASC
    ]]
    
    local groups, err = mysql_pool.query(sql)
    if err then
        ngx.log(ngx.ERR, "list rule groups error: ", err)
        return nil, err
    end
    
    return groups or {}, nil
end

-- 获取分组统计信息（每个分组的规则数量）
function _M.get_group_stats()
    local sql = [[
        SELECT 
            COALESCE(rule_group, '未分组') as group_name,
            COUNT(*) as total_count,
            SUM(CASE WHEN status = 1 THEN 1 ELSE 0 END) as enabled_count,
            SUM(CASE WHEN status = 0 THEN 1 ELSE 0 END) as disabled_count
        FROM waf_block_rules
        GROUP BY rule_group
        ORDER BY group_name ASC
    ]]
    
    local stats, err = mysql_pool.query(sql)
    if err then
        ngx.log(ngx.ERR, "get group stats error: ", err)
        return nil, err
    end
    
    return stats or {}, nil
end

return _M

