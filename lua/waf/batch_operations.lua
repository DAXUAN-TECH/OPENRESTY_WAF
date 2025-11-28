-- 批量操作模块
-- 路径：项目目录下的 lua/waf/batch_operations.lua（保持在项目目录，不复制到系统目录）
-- 功能：支持批量导入/导出封控规则（CSV/JSON格式）

local mysql_pool = require "waf.mysql_pool"
local ip_utils = require "waf.ip_utils"
local cache_invalidation = require "waf.cache_invalidation"
local cjson = require "cjson"

local _M = {}

-- 导出规则为JSON格式
function _M.export_rules_json(rule_type, status)
    local sql = [[
        SELECT id, rule_type, rule_value, rule_name, description, 
               status, priority, start_time, end_time, created_at, updated_at
        FROM waf_block_rules
        WHERE 1=1
    ]]
    
    local conditions = {}
    local params = {}
    
    if rule_type then
        table.insert(conditions, "AND rule_type = ?")
        table.insert(params, rule_type)
    end
    
    if status ~= nil then
        table.insert(conditions, "AND status = ?")
        table.insert(params, status)
    end
    
    sql = sql .. " " .. table.concat(conditions, " ") .. " ORDER BY id DESC"
    
    local res, err = mysql_pool.query(sql, unpack(params))
    if err then
        ngx.log(ngx.ERR, "export rules query error: ", err)
        return nil, err
    end
    
    return res or {}, nil
end

-- 导出规则为CSV格式
function _M.export_rules_csv(rule_type, status)
    local rules, err = _M.export_rules_json(rule_type, status)
    if err then
        return nil, err
    end
    
    -- CSV头部
    local csv_lines = {
        "id,rule_type,rule_value,rule_name,description,status,priority,start_time,end_time,created_at,updated_at"
    }
    
    -- 转换每条规则为CSV行
    for _, rule in ipairs(rules) do
        local row = {
            rule.id or "",
            rule.rule_type or "",
            '"' .. (rule.rule_value or ""):gsub('"', '""') .. '"',
            '"' .. (rule.rule_name or ""):gsub('"', '""') .. '"',
            '"' .. (rule.description or ""):gsub('"', '""') .. '"',
            rule.status or "",
            rule.priority or "",
            rule.start_time or "",
            rule.end_time or "",
            rule.created_at or "",
            rule.updated_at or ""
        }
        table.insert(csv_lines, table.concat(row, ","))
    end
    
    return table.concat(csv_lines, "\n"), nil
end

-- 验证规则数据
local function validate_rule(rule)
    if not rule.rule_type then
        return false, "rule_type is required"
    end
    
    if not rule.rule_value then
        return false, "rule_value is required"
    end
    
    if not rule.rule_name then
        return false, "rule_name is required"
    end
    
    -- 验证规则类型
    local valid_types = {single_ip = true, ip_range = true, geo = true}
    if not valid_types[rule.rule_type] then
        return false, "invalid rule_type: " .. rule.rule_type
    end
    
    -- 验证IP格式（如果是single_ip或ip_range）
    if rule.rule_type == "single_ip" then
        if not ip_utils.is_valid_ip(rule.rule_value) then
            return false, "invalid IP address: " .. rule.rule_value
        end
    elseif rule.rule_type == "ip_range" then
        -- 检查CIDR格式或IP范围格式
        local is_cidr = rule.rule_value:match("^([^/]+)/(%d+)$")
        local is_range = rule.rule_value:match("^([^%-]+)%-(.+)$")
        
        if is_cidr then
            if not ip_utils.is_valid_cidr(rule.rule_value) then
                return false, "invalid CIDR format: " .. rule.rule_value
            end
        elseif is_range then
            local start_ip, end_ip = ip_utils.parse_ip_range(rule.rule_value)
            if not start_ip or not end_ip then
                return false, "invalid IP range format: " .. rule.rule_value
            end
            if not ip_utils.is_valid_ip(start_ip) or not ip_utils.is_valid_ip(end_ip) then
                return false, "invalid IP address in range: " .. rule.rule_value
            end
        else
            return false, "invalid ip_range format (should be CIDR or IP range): " .. rule.rule_value
        end
    end
    
    -- 验证状态
    if rule.status ~= nil and rule.status ~= 0 and rule.status ~= 1 then
        return false, "invalid status (should be 0 or 1): " .. tostring(rule.status)
    end
    
    -- 验证优先级
    if rule.priority ~= nil then
        local priority = tonumber(rule.priority)
        if not priority or priority < 0 or priority > 1000 then
            return false, "invalid priority (should be 0-1000): " .. tostring(rule.priority)
        end
    end
    
    return true, nil
end

-- 导入规则（JSON格式）
function _M.import_rules_json(rules_data, options)
    options = options or {}
    local skip_invalid = options.skip_invalid or false
    local update_existing = options.update_existing or false
    
    if type(rules_data) == "string" then
        local ok, decoded = pcall(cjson.decode, rules_data)
        if not ok then
            return nil, "invalid JSON format: " .. decoded
        end
        rules_data = decoded
    end
    
    if type(rules_data) ~= "table" then
        return nil, "rules_data must be a table or JSON string"
    end
    
    -- 如果rules_data是对象，尝试获取rules数组
    if rules_data.rules then
        rules_data = rules_data.rules
    end
    
    local results = {
        success = 0,
        failed = 0,
        skipped = 0,
        errors = {}
    }
    
    -- 第一步：验证所有规则
    local valid_rules = {}
    local invalid_rules = {}
    
    for i, rule in ipairs(rules_data) do
        local valid, err_msg = validate_rule(rule)
        if not valid then
            if skip_invalid then
                results.skipped = results.skipped + 1
                table.insert(results.errors, {
                    index = i,
                    rule_name = rule.rule_name or "unknown",
                    error = err_msg
                })
                table.insert(invalid_rules, {index = i, rule = rule})
            else
                return nil, string.format("rule[%d] validation failed: %s", i, err_msg)
            end
        else
            table.insert(valid_rules, {index = i, rule = rule})
        end
    end
    
    -- 第二步：批量查询所有有效规则是否已存在（性能优化）
    local existing_rules_map = {}
    if #valid_rules > 0 then
        -- 构建批量查询SQL（使用IN子句）
        local rule_types = {}
        local rule_values = {}
        local rule_keys = {}  -- 用于映射回原始规则
        
        for _, item in ipairs(valid_rules) do
            local rule = item.rule
            local key = rule.rule_type .. ":" .. rule.rule_value
            if not existing_rules_map[key] then
                table.insert(rule_types, rule.rule_type)
                table.insert(rule_values, rule.rule_value)
                table.insert(rule_keys, key)
            end
        end
        
        if #rule_values > 0 then
            -- 构建批量查询SQL（分批查询，每批最多1000条）
            local batch_size = 1000
            for batch_start = 1, #rule_values, batch_size do
                local batch_end = math.min(batch_start + batch_size - 1, #rule_values)
                local batch_types = {}
                local batch_values = {}
                local batch_keys = {}
                
                for i = batch_start, batch_end do
                    table.insert(batch_types, rule_types[i])
                    table.insert(batch_values, rule_values[i])
                    table.insert(batch_keys, rule_keys[i])
                end
                
                -- 构建SQL（使用IN子句和组合条件）
                local conditions = {}
                local params = {}
                for i = 1, #batch_values do
                    table.insert(conditions, "(rule_type = ? AND rule_value = ?)")
                    table.insert(params, batch_types[i])
                    table.insert(params, batch_values[i])
                end
                
                local sql_batch = [[
                    SELECT id, rule_type, rule_value FROM waf_block_rules
                    WHERE ]] .. table.concat(conditions, " OR ")
                
                local existing_batch, err = mysql_pool.query(sql_batch, unpack(params))
                if err then
                    ngx.log(ngx.ERR, "batch check existing rules error: ", err)
                    -- 如果批量查询失败，回退到逐个查询
                    for i = batch_start, batch_end do
                        local key = batch_keys[i - batch_start + 1]
                        local rule_type = batch_types[i - batch_start + 1]
                        local rule_value = batch_values[i - batch_start + 1]
                        
                        local sql_check = [[
                            SELECT id FROM waf_block_rules
                            WHERE rule_type = ?
                            AND rule_value = ?
                            LIMIT 1
                        ]]
                        
                        local existing, err2 = mysql_pool.query(sql_check, rule_type, rule_value)
                        if not err2 and existing and #existing > 0 then
                            existing_rules_map[key] = existing[1].id
                        end
                    end
                else
                    -- 构建映射表
                    if existing_batch then
                        for _, row in ipairs(existing_batch) do
                            local key = row.rule_type .. ":" .. row.rule_value
                            existing_rules_map[key] = row.id
                        end
                    end
                end
            end
        end
    end
    
    -- 第三步：处理所有有效规则（插入或更新）
    for _, item in ipairs(valid_rules) do
        local i = item.index
        local rule = item.rule
        local key = rule.rule_type .. ":" .. rule.rule_value
        local existing_id = existing_rules_map[key]
        
        if existing_id then
            -- 规则已存在
            if update_existing then
                -- 更新现有规则
                local sql_update = [[
                    UPDATE waf_block_rules
                    SET rule_name = ?, description = ?, status = ?, 
                        priority = ?, start_time = ?, end_time = ?
                    WHERE id = ?
                ]]
                
                local ok, err = mysql_pool.update(sql_update,
                    rule.rule_name,
                    rule.description or "",
                    rule.status or 1,
                    rule.priority or 0,
                    rule.start_time or nil,
                    rule.end_time or nil,
                    existing_id
                )
                
                if err then
                    ngx.log(ngx.ERR, "update rule error: ", err)
                    results.failed = results.failed + 1
                    table.insert(results.errors, {
                        index = i,
                        rule_name = rule.rule_name or "unknown",
                        error = "update error: " .. err
                    })
                else
                    results.success = results.success + 1
                end
            else
                -- 跳过已存在的规则
                results.skipped = results.skipped + 1
            end
        else
            -- 插入新规则（批量插入优化）
            -- 收集所有需要插入的规则，最后批量插入
            if not results.insert_batch then
                results.insert_batch = {}
            end
            table.insert(results.insert_batch, {
                index = i,
                rule = rule
            })
        end
    end
    
    -- 第四步：批量插入新规则（性能优化）
    if results.insert_batch and #results.insert_batch > 0 then
        local insert_fields = {"rule_type", "rule_value", "rule_name", "description", "status", "priority", "start_time", "end_time", "rule_version"}
        local insert_values = {}
        
        for _, item in ipairs(results.insert_batch) do
            local rule = item.rule
            table.insert(insert_values, {
                rule.rule_type,
                rule.rule_value,
                rule.rule_name,
                rule.description or "",
                rule.status or 1,
                rule.priority or 0,
                rule.start_time or nil,
                rule.end_time or nil,
                1  -- rule_version
            })
        end
        
        -- 分批插入（每批最多1000条）
        local batch_size = 1000
        for batch_start = 1, #insert_values, batch_size do
            local batch_end = math.min(batch_start + batch_size - 1, #insert_values)
            local batch_values = {}
            
            for i = batch_start, batch_end do
                table.insert(batch_values, insert_values[i])
            end
            
            local res, err = mysql_pool.batch_insert("waf_block_rules", insert_fields, batch_values)
            if err then
                ngx.log(ngx.ERR, "batch insert rules error: ", err)
                -- 批量插入失败，回退到逐个插入
                for i = batch_start, batch_end do
                    local item = results.insert_batch[i]
                    local rule = item.rule
                    local sql_insert = [[
                        INSERT INTO waf_block_rules
                        (rule_type, rule_value, rule_name, description, status, priority, start_time, end_time, rule_version)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)
                    ]]
                    
                    local insert_id, err2 = mysql_pool.insert(sql_insert,
                        rule.rule_type,
                        rule.rule_value,
                        rule.rule_name,
                        rule.description or "",
                        rule.status or 1,
                        rule.priority or 0,
                        rule.start_time or nil,
                        rule.end_time or nil
                    )
                    
                    if err2 then
                        results.failed = results.failed + 1
                        table.insert(results.errors, {
                            index = item.index,
                            rule_name = rule.rule_name or "unknown",
                            error = "insert error: " .. err2
                        })
                    else
                        results.success = results.success + 1
                    end
                end
            else
                -- 批量插入成功
                results.success = results.success + #batch_values
            end
        end
        
        -- 清理临时数据
        results.insert_batch = nil
    end
    
    -- 清除缓存
    if results.success > 0 then
        cache_invalidation.invalidate_all()
    end
    
    return results, nil
end

-- 解析CSV行
local function parse_csv_line(line)
    local fields = {}
    local current_field = ""
    local in_quotes = false
    
    for i = 1, #line do
        local char = line:sub(i, i)
        
        if char == '"' then
            if in_quotes and line:sub(i + 1, i + 1) == '"' then
                -- 转义的双引号
                current_field = current_field .. '"'
                i = i + 1
            else
                -- 切换引号状态
                in_quotes = not in_quotes
            end
        elseif char == ',' and not in_quotes then
            -- 字段分隔符
            table.insert(fields, current_field)
            current_field = ""
        else
            current_field = current_field .. char
        end
    end
    
    -- 添加最后一个字段
    table.insert(fields, current_field)
    
    return fields
end

-- 导入规则（CSV格式）
function _M.import_rules_csv(csv_data, options)
    options = options or {}
    local skip_header = options.skip_header or true
    local skip_invalid = options.skip_invalid or false
    local update_existing = options.update_existing or false
    
    local lines = {}
    for line in csv_data:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    
    if #lines == 0 then
        return nil, "empty CSV data"
    end
    
    -- 跳过头部
    local start_index = 1
    if skip_header then
        start_index = 2
    end
    
    local rules = {}
    for i = start_index, #lines do
        local fields = parse_csv_line(lines[i])
        if #fields >= 3 then
            local rule = {
                rule_type = fields[2] or "",
                rule_value = fields[3] or "",
                rule_name = fields[4] or "",
                description = fields[5] or "",
                status = tonumber(fields[6]) or 1,
                priority = tonumber(fields[7]) or 0,
                start_time = fields[8] ~= "" and fields[8] or nil,
                end_time = fields[9] ~= "" and fields[9] or nil
            }
            table.insert(rules, rule)
        end
    end
    
    return _M.import_rules_json(rules, options)
end

return _M

