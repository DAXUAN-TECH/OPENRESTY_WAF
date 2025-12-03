-- 规则管理模块
-- 路径：项目目录下的 lua/waf/rule_management.lua（保持在项目目录，不复制到系统目录）
-- 功能：实现规则的CRUD操作

local mysql_pool = require "waf.mysql_pool"
local cache_invalidation = require "waf.cache_invalidation"
local rule_notification = require "waf.rule_notification"
local ip_utils = require "waf.ip_utils"
local cjson = require "cjson"

local _M = {}

-- 计算规则有效期文本（基于 end_time 和当前时间）
local function compute_validity_text(rule)
    local end_time = rule.end_time

    -- 未设置结束时间：视为永久有效
    if not end_time or end_time == ngx.null then
        return "永久有效"
    end

    -- remaining_seconds 由SQL计算得到：TIMESTAMPDIFF(SECOND, NOW(), end_time)
    local remaining = rule.remaining_seconds
    if remaining == nil or remaining == ngx.null then
        return "未知"
    end

    local seconds = tonumber(remaining)
    if not seconds then
        return "未知"
    end

    if seconds <= 0 then
        return "已过期"
    end

    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60

    return string.format("%d天%d时%d分%d秒", days, hours, minutes, secs)
end

-- 验证规则值格式
local function validate_rule_value(rule_type, rule_value)
    if not rule_value or rule_value == "" then
        return false, "规则值不能为空"
    end
    
    -- IP白名单和IP黑名单：支持单个IP、多个IP（逗号分隔）、IP段（CIDR格式或IP范围格式）
    if rule_type == "ip_whitelist" or rule_type == "ip_blacklist" then
        -- 检查是否包含逗号（多个IP）
        if rule_value:match(",") then
            -- 多个IP，逐个验证
            local ip_list = {}
            for ip_str in rule_value:gmatch("([^,]+)") do
                local ip = ip_str:match("^%s*(.-)%s*$")  -- 去除首尾空格
                if ip and ip ~= "" then
                    table.insert(ip_list, ip)
                end
            end
            
            if #ip_list == 0 then
                return false, "IP列表不能为空"
            end
            
            -- 验证每个IP
            for _, ip in ipairs(ip_list) do
                local is_valid = false
                -- 检查是否为单个IP
                if ip_utils.is_valid_ip(ip) then
                    is_valid = true
                -- 检查是否为CIDR格式
                elseif ip_utils.is_valid_cidr(ip) then
                    is_valid = true
                -- 检查是否为IP范围格式
                else
                    local start_ip, end_ip = ip_utils.parse_ip_range(ip)
                    if start_ip and end_ip then
                        is_valid = true
                    end
                end
                
                if not is_valid then
                    return false, "无效的IP格式: " .. ip .. "（应为单个IP如192.168.1.100、CIDR格式如192.168.1.0/24或IP范围如192.168.1.1-192.168.1.100）"
                end
            end
        else
            -- 单个IP或IP段
            -- 先检查是否为单个IP
            if ip_utils.is_valid_ip(rule_value) then
                -- 单个IP，验证通过
            elseif ip_utils.is_valid_cidr(rule_value) then
                -- CIDR格式，验证通过
            else
                -- 检查是否为IP范围格式
                local start_ip, end_ip = ip_utils.parse_ip_range(rule_value)
                if not start_ip or not end_ip then
                    return false, "无效的IP格式（应为单个IP如192.168.1.100、多个IP如192.168.1.1,192.168.1.2、CIDR格式如192.168.1.0/24或IP范围如192.168.1.1-192.168.1.100）"
                end
            end
        end
    elseif rule_type == "geo_whitelist" or rule_type == "geo_blacklist" then
        -- 验证地域代码格式（支持多选，用逗号分隔）
        -- 格式：国家代码（如CN、US）或 国家:省份代码（如CN:Beijing）或 国家:省份代码:城市名称（如CN:Beijing:北京）
        -- 支持多个值用逗号分隔，城市名称可以是中文
        local geo_values = {}
        for value in rule_value:gmatch("([^,]+)") do
            -- 去除首尾空格
            value = value:gsub("^%s+", ""):gsub("%s+$", "")
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
            -- 1. 国家代码：两个大写字母，如 CN, US, JP, VN
            -- 2. 国家:省份代码：CN:Beijing, CN:Shanghai（省份代码可以是字母、数字、下划线、连字符）
            -- 3. 国家:省份代码:城市名称：CN:Beijing:北京（城市名称可以是中文、字母、数字等任意字符，但不能包含逗号）
            
            -- 检查是否包含冒号（省份或城市）
            if geo_value:match(":") then
                -- 包含冒号，检查格式：CN:xxx 或 CN:xxx:yyy
                local parts = {}
                for part in geo_value:gmatch("([^:]+)") do
                    table.insert(parts, part)
                end
                
                if #parts < 2 or #parts > 3 then
                    return false, "无效的地域代码格式: " .. geo_value .. "（应为国家代码如CN、US或国家:省份如CN:Beijing或国家:省份:城市如CN:Beijing:北京）"
                end
                
                -- 第一部分必须是两个大写字母（国家代码）
                if not parts[1]:match("^[A-Z]{2}$") then
                    return false, "无效的地域代码格式: " .. geo_value .. "（国家代码必须是两个大写字母）"
                end
                
                -- 第二部分（省份代码）不能为空
                if parts[2] == "" then
                    return false, "无效的地域代码格式: " .. geo_value .. "（省份代码不能为空）"
                end
                
                -- 第三部分（城市名称，如果存在）不能为空
                if #parts == 3 and parts[3] == "" then
                    return false, "无效的地域代码格式: " .. geo_value .. "（城市名称不能为空）"
                end
            else
                -- 不包含冒号，应该是纯国家代码（两个大写字母）
                -- 直接验证：必须是两个大写字母
                if not geo_value:match("^[A-Z][A-Z]$") then
                    return false, "无效的地域代码格式: " .. geo_value .. "（国家代码必须是两个大写字母，如CN、US、VN）"
                end
            end
            
            -- 检查是否包含逗号（不应该在单个值中出现，应该在分割时已经处理）
            if geo_value:match(",") then
                return false, "无效的地域代码格式: " .. geo_value .. "（单个地域代码不能包含逗号，多个值请用逗号分隔）"
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
    -- 同时确保类型正确（转换为字符串）
    -- 注意：如果值是 nil 或 cjson.null，直接保持为 nil，不转换
    local cjson = require "cjson"
    
    if description ~= nil and description ~= cjson.null then
        description = tostring(description)
        if description == "" or description == "null" or description == "nil" then
            description = nil
        end
    else
        description = nil
    end
    if rule_group ~= nil and rule_group ~= cjson.null then
        rule_group = tostring(rule_group)
        if rule_group == "" or rule_group == "null" or rule_group == "nil" then
            rule_group = nil
        end
    else
        rule_group = nil
    end
    if start_time ~= nil and start_time ~= cjson.null then
        start_time = tostring(start_time)
        if start_time == "" or start_time == "null" or start_time == "nil" then
            start_time = nil
        end
    else
        start_time = nil
    end
    if end_time ~= nil and end_time ~= cjson.null then
        end_time = tostring(end_time)
        if end_time == "" or end_time == "null" or end_time == "nil" then
            end_time = nil
        end
    else
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
    
    -- 如果规则已启用，触发缓存失效（使用pcall确保失败不影响主流程）
    if status == 1 then
        local ok1, err1 = pcall(function()
            cache_invalidation.increment_rule_version()
        end)
        if not ok1 then
            ngx.log(ngx.WARN, "Failed to increment rule version: ", tostring(err1))
        end
        
        local ok2, err2 = pcall(function()
            rule_notification.notify_rule_created(insert_id, rule_data.rule_type)
        end)
        if not ok2 then
            ngx.log(ngx.WARN, "Failed to notify rule creation: ", tostring(err2))
        end
    end
    
    -- 触发规则备份（异步执行，不阻塞响应）
    local rule_backup = require "waf.rule_backup"
    ngx.timer.at(0, function()
        local ok, result = pcall(rule_backup.backup_rules)
        if ok and result then
            ngx.log(ngx.INFO, "Rules backed up after creation: ", result)
        else
            ngx.log(ngx.WARN, "Rule backup failed after creation: ", tostring(result))
        end
    end)
    
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
               start_time, end_time, created_at, updated_at, rule_version,
               CASE 
                   WHEN end_time IS NULL THEN NULL
                   ELSE TIMESTAMPDIFF(SECOND, NOW(), end_time)
               END AS remaining_seconds
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
    else
        -- 为每条规则计算有效期文本（规则有效期列）
        for _, rule in ipairs(rules) do
            rule.validity_text = compute_validity_text(rule)
        end
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
        
        -- 使用参数化查询，避免SQL注入
        table.insert(update_fields, "status = ?")
        table.insert(update_params, new_status)
        
        -- 如果状态改变，更新规则版本号
        if old_status ~= new_status then
            table.insert(update_fields, "rule_version = rule_version + 1")
        end
    end
    
    if #update_fields == 0 then
        return nil, "没有需要更新的字段"
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
    
    -- 如果规则状态改变，立即清除缓存并触发缓存失效（使用pcall确保失败不影响主流程）
    if rule_data.status ~= nil and rule.status ~= tonumber(rule_data.status) then
        -- 立即清除规则列表缓存（确保立即生效）
        local ok0, err0 = pcall(function()
            cache_invalidation.invalidate_rule_list_cache()
        end)
        if not ok0 then
            ngx.log(ngx.WARN, "Failed to invalidate rule list cache: ", tostring(err0))
        end
        
        -- 更新规则版本号（触发其他工作进程的缓存失效）
        local ok1, err1 = pcall(function()
            cache_invalidation.increment_rule_version()
        end)
        if not ok1 then
            ngx.log(ngx.WARN, "Failed to increment rule version: ", tostring(err1))
        end
        
        -- 发送规则更新通知
        local ok2, err2 = pcall(function()
            rule_notification.notify_rule_updated(rule_id, rule.rule_type)
        end)
        if not ok2 then
            ngx.log(ngx.WARN, "Failed to notify rule update: ", tostring(err2))
        end
    end
    
    -- 触发规则备份（异步执行，不阻塞响应）
    local rule_backup = require "waf.rule_backup"
    ngx.timer.at(0, function()
        local ok, result = pcall(rule_backup.backup_rules)
        if ok and result then
            ngx.log(ngx.INFO, "Rules backed up after update: ", result)
        else
            ngx.log(ngx.WARN, "Rule backup failed after update: ", tostring(result))
        end
    end)
    
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
    
    -- 检查是否有代理引用该规则（从ip_rule_ids JSON字段中查找）
    local cjson = require "cjson"
    local check_proxy_sql = [[
        SELECT id, proxy_name, proxy_type, listen_port
        FROM waf_proxy_configs
        WHERE JSON_CONTAINS(ip_rule_ids, ?)
        ORDER BY id ASC
    ]]
    local rule_id_json = cjson.encode(rule_id)
    local proxies, err = mysql_pool.query(check_proxy_sql, rule_id_json)
    if err then
        ngx.log(ngx.ERR, "check proxy references error: ", err)
        return nil, "检查代理引用时出错: " .. (err or "unknown error")
    end
    
    -- 如果有代理引用，返回错误信息，包含引用的代理名称列表
    if proxies and #proxies > 0 then
        local proxy_names = {}
        for _, proxy in ipairs(proxies) do
            local proxy_info = proxy.proxy_name
            if proxy.proxy_type then
                proxy_info = proxy_info .. " (" .. proxy.proxy_type .. ":" .. (proxy.listen_port or "") .. ")"
            end
            table.insert(proxy_names, proxy_info)
        end
        local proxy_list = table.concat(proxy_names, "、")
        local error_msg = string.format("该规则被以下代理引用，无法删除：%s", proxy_list)
        ngx.log(ngx.WARN, "Cannot delete rule ", rule_id, ", referenced by proxies: ", proxy_list)
        return nil, error_msg
    end
    
    -- 执行删除
    local sql = "DELETE FROM waf_block_rules WHERE id = ?"
    local res, err = mysql_pool.query(sql, rule_id)
    if err then
        ngx.log(ngx.ERR, "delete rule error: ", err)
        return nil, err
    end
    
    -- 触发缓存失效（使用pcall确保失败不影响主流程）
    local ok1, err1 = pcall(function()
        cache_invalidation.increment_rule_version()
    end)
    if not ok1 then
        ngx.log(ngx.WARN, "Failed to increment rule version: ", tostring(err1))
    end
    
    local ok2, err2 = pcall(function()
        rule_notification.notify_rule_deleted(rule_id, rule.rule_type)
    end)
    if not ok2 then
        ngx.log(ngx.WARN, "Failed to notify rule deletion: ", tostring(err2))
    end
    
    -- 触发规则备份（异步执行，不阻塞响应）
    local rule_backup = require "waf.rule_backup"
    ngx.timer.at(0, function()
        local ok, result = pcall(rule_backup.backup_rules)
        if ok and result then
            ngx.log(ngx.INFO, "Rules backed up after deletion: ", result)
        else
            ngx.log(ngx.WARN, "Rule backup failed after deletion: ", tostring(result))
        end
    end)
    
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
    
    -- 确保返回数组格式（即使是空结果也返回空数组[]而不是空对象{}）
    if not groups then
        return {}, nil
    end
    
    -- 检查是否是数组格式（有数字索引）
    local is_array = false
    local array_length = 0
    for i, _ in ipairs(groups) do
        is_array = true
        array_length = i
    end
    
    -- 如果是数组且有数据，直接返回
    if is_array and array_length > 0 then
        return groups, nil
    end
    
    -- 检查是否有数字键（可能是稀疏数组或对象）
    local has_numeric_keys = false
    local max_index = 0
    for k, v in pairs(groups) do
        if type(k) == "number" and k > 0 then
            has_numeric_keys = true
            if k > max_index then
                max_index = k
            end
        end
    end
    
    -- 如果有数字键，转换为数组
    if has_numeric_keys then
        local groups_array = {}
        for i = 1, max_index do
            if groups[i] then
                groups_array[i] = groups[i]
            end
        end
        return groups_array, nil
    end
    
    -- 如果没有数字键（空对象{}或nil），返回空数组[]
    -- 使用明确的数组初始化，确保JSON序列化为[]
    return {}, nil
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

