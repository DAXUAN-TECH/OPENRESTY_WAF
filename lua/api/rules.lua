-- 规则管理API模块
-- 路径：项目目录下的 lua/api/rules.lua（保持在项目目录，不复制到系统目录）
-- 功能：处理规则管理的CRUD操作API请求

local rule_management = require "waf.rule_management"
local api_utils = require "api.utils"
local cjson = require "cjson"
local config = require "config"
local feature_switches = require "waf.feature_switches"
local audit_log = require "waf.audit_log"
local system_api = require "api.system"

local _M = {}

-- 检查规则管理界面功能是否启用（优先从数据库读取）
local function check_feature_enabled()
    -- 优先从数据库读取功能开关
    local enabled = feature_switches.is_enabled("rule_management_ui")
    if not enabled then
        api_utils.json_response({
            success = false,
            error = "规则管理界面功能已禁用"
        }, 403)
        return false
    end
    return true
end

-- 创建规则
function _M.create()
    if not check_feature_enabled() then
        return
    end
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        api_utils.json_response({error = "request body is required"}, 400)
        return
    end
    
    local ok, rule_data = pcall(cjson.decode, body)
    if not ok then
        api_utils.json_response({error = "invalid JSON format"}, 400)
        return
    end
    
    local result, err = rule_management.create_rule(rule_data)
    if err then
        -- 记录审计日志（失败）
        audit_log.log_rule_action("create", result and result.id or nil, rule_data.rule_name, false, err)
        api_utils.json_response({error = err}, 400)
        return
    end
    
    -- 记录审计日志（成功）
    audit_log.log_rule_action("create", result.id, rule_data.rule_name, true, nil)
    
    api_utils.json_response({
        success = true,
        rule = result
    })
end

-- 查询规则列表
function _M.list()
    if not check_feature_enabled() then
        return
    end
    local args = api_utils.get_args()
    local params = {
        rule_type = args.rule_type,
        status = args.status and tonumber(args.status) or nil,
        rule_group = args.rule_group,  -- 支持按分组筛选
        page = args.page and tonumber(args.page) or 1,
        page_size = args.page_size and tonumber(args.page_size) or 20
    }
    
    local result, err = rule_management.list_rules(params)
    if err then
        api_utils.json_response({error = err}, 500)
        return
    end
    
    -- 确保 result 存在且包含 rules 数组
    if not result then
        ngx.log(ngx.WARN, "list_rules returned nil result")
        result = {
            rules = {},
            total = 0,
            page = params.page,
            page_size = params.page_size,
            total_pages = 0
        }
    end
    
    -- 确保 rules 是数组类型（用于 JSON 序列化）
    if not result.rules then
        ngx.log(ngx.WARN, "result.rules is nil, setting to empty array")
        result.rules = {}
    elseif type(result.rules) ~= "table" then
        ngx.log(ngx.ERR, "result.rules is not a table, type: ", type(result.rules), ", value: ", tostring(result.rules))
        result.rules = {}
    else
        -- 检查是否是数组（使用 # 和 ipairs 判断）
        local is_array = false
        local array_length = 0
        
        -- 尝试使用 ipairs 遍历
        for i, _ in ipairs(result.rules) do
            array_length = i
            is_array = true
        end
        
        -- 如果 ipairs 没有遍历到任何元素，检查是否是空数组
        if array_length == 0 then
            if next(result.rules) == nil then
                -- 空数组，保持原样
                is_array = true
                ngx.log(ngx.DEBUG, "result.rules is empty array")
            else
                -- 非空但不是数组，需要转换
                ngx.log(ngx.WARN, "result.rules is not an array, converting...")
                is_array = false
            end
        end
        
        -- 如果不是数组，转换为数组
        if not is_array then
            local rules_array = {}
            local temp_array = {}
            
            -- 收集所有数字键的值
            for k, v in pairs(result.rules) do
                if type(k) == "number" and k > 0 then
                    table.insert(temp_array, {key = k, value = v})
                end
            end
            
            -- 按 key 排序
            table.sort(temp_array, function(a, b) return a.key < b.key end)
            
            -- 转换为数组
            for _, item in ipairs(temp_array) do
                table.insert(rules_array, item.value)
            end
            
            result.rules = rules_array
            ngx.log(ngx.INFO, "converted rules to array, length: ", #result.rules)
        else
            ngx.log(ngx.DEBUG, "result.rules is already an array, length: ", array_length)
        end
    end
    
    -- 最终验证：确保 rules 是数组
    if type(result.rules) ~= "table" then
        ngx.log(ngx.ERR, "FATAL: result.rules is still not a table after conversion!")
        result.rules = {}
    end
    
    -- 强制转换为标准数组（确保 JSON 序列化时是数组）
    -- 创建一个新的数组，只包含数字索引的元素
    local final_rules = {}
    if #result.rules > 0 then
        -- 使用 ipairs 确保只复制数组部分
        for i = 1, #result.rules do
            final_rules[i] = result.rules[i]
        end
    end
    result.rules = final_rules
    
    -- 测试 JSON 序列化，确保 rules 是数组格式
    local cjson = require "cjson"
    local test_json = cjson.encode(result.rules)
    ngx.log(ngx.INFO, "Rules JSON serialization test: ", test_json:sub(1, 200))
    
    -- 检查 JSON 字符串是否以 [ 开头（数组）而不是 { 开头（对象）
    if not test_json:match("^%[") then
        ngx.log(ngx.ERR, "WARNING: rules JSON does not start with [, it starts with: ", test_json:sub(1, 1))
        -- 强制设置为空数组
        result.rules = {}
    end
    
    api_utils.json_response({
        success = true,
        data = result
    })
end

-- 查询规则详情
function _M.get()
    if not check_feature_enabled() then
        return
    end
    local args = api_utils.get_args()
    local rule_id = args.id or args.rule_id
    
    if not rule_id then
        rule_id = api_utils.extract_id_from_uri("/api/rules/(%d+)")
    end
    
    if not rule_id then
        api_utils.json_response({error = "rule_id is required"}, 400)
        return
    end
    
    local rule, err = rule_management.get_rule(rule_id)
    if err then
        api_utils.json_response({error = err}, 404)
        return
    end
    
    api_utils.json_response({
        success = true,
        rule = rule
    })
end

-- 更新规则
function _M.update()
    if not check_feature_enabled() then
        return
    end
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        api_utils.json_response({error = "request body is required"}, 400)
        return
    end
    
    local args = api_utils.get_args()
    local rule_id = args.id or args.rule_id
    
    if not rule_id then
        rule_id = api_utils.extract_id_from_uri("/api/rules/(%d+)")
    end
    
    if not rule_id then
        api_utils.json_response({error = "rule_id is required"}, 400)
        return
    end
    
    local ok, rule_data = pcall(cjson.decode, body)
    if not ok then
        api_utils.json_response({error = "invalid JSON format"}, 400)
        return
    end
    
    -- 获取规则信息用于审计日志
    local old_rule = rule_management.get_rule(rule_id)
    local rule_name = old_rule and old_rule.rule_name or rule_data.rule_name or ""
    
    local result, err = rule_management.update_rule(rule_id, rule_data)
    if err then
        -- 记录审计日志（失败）
        audit_log.log_rule_action("update", rule_id, rule_name, false, err)
        api_utils.json_response({error = err}, 400)
        return
    end
    
    -- 记录审计日志（成功）
    audit_log.log_rule_action("update", rule_id, rule_name, true, nil)
    
    -- 触发nginx重载（异步，不阻塞响应）
    -- 注意：规则更新后需要reload使新规则生效
    ngx.timer.at(0, function()
        local ok, result = system_api.reload_nginx_internal()
        if not ok then
            ngx.log(ngx.WARN, "更新规则后自动触发nginx重载失败: ", result or "unknown error")
        else
            ngx.log(ngx.INFO, "更新规则后自动触发nginx重载成功")
        end
    end)
    
    api_utils.json_response({
        success = true,
        rule = result,
        message = "规则已更新，nginx配置正在重新加载"
    })
end

-- 删除规则
function _M.delete()
    if not check_feature_enabled() then
        return
    end
    local args = api_utils.get_args()
    local rule_id = args.id or args.rule_id
    
    if not rule_id then
        rule_id = api_utils.extract_id_from_uri("/api/rules/(%d+)")
    end
    
    if not rule_id then
        api_utils.json_response({error = "rule_id is required"}, 400)
        return
    end
    
    -- 获取规则信息用于审计日志
    local old_rule = rule_management.get_rule(rule_id)
    local rule_name = old_rule and old_rule.rule_name or ""
    
    local result, err = rule_management.delete_rule(rule_id)
    if err then
        -- 记录审计日志（失败）
        audit_log.log_rule_action("delete", rule_id, rule_name, false, err)
        api_utils.json_response({error = err}, 400)
        return
    end
    
    -- 记录审计日志（成功）
    audit_log.log_rule_action("delete", rule_id, rule_name, true, nil)
    
    api_utils.json_response({
        success = true,
        message = "规则已删除"
    })
end

-- 启用规则
function _M.enable()
    if not check_feature_enabled() then
        return
    end
    local rule_id = api_utils.extract_id_from_uri("/api/rules/(%d+)/enable")
    
    if not rule_id then
        api_utils.json_response({error = "rule_id is required"}, 400)
        return
    end
    
    -- 获取规则信息用于审计日志
    local rule = rule_management.get_rule(rule_id)
    local rule_name = rule and rule.rule_name or ""
    
    local result, err = rule_management.enable_rule(rule_id)
    if err then
        -- 记录审计日志（失败）
        audit_log.log_rule_action("enable", rule_id, rule_name, false, err)
        api_utils.json_response({error = err}, 400)
        return
    end
    
    -- 记录审计日志（成功）
    audit_log.log_rule_action("enable", rule_id, rule_name, true, nil)
    
    api_utils.json_response({
        success = true,
        message = "规则已启用"
    })
end

-- 禁用规则
function _M.disable()
    if not check_feature_enabled() then
        return
    end
    local rule_id = api_utils.extract_id_from_uri("/api/rules/(%d+)/disable")
    
    if not rule_id then
        api_utils.json_response({error = "rule_id is required"}, 400)
        return
    end
    
    -- 获取规则信息用于审计日志
    local rule = rule_management.get_rule(rule_id)
    local rule_name = rule and rule.rule_name or ""
    
    local result, err = rule_management.disable_rule(rule_id)
    if err then
        -- 记录审计日志（失败）
        audit_log.log_rule_action("disable", rule_id, rule_name, false, err)
        api_utils.json_response({error = err}, 400)
        return
    end
    
    -- 记录审计日志（成功）
    audit_log.log_rule_action("disable", rule_id, rule_name, true, nil)
    
    api_utils.json_response({
        success = true,
        message = "规则已禁用"
    })
end

-- 获取规则分组列表
function _M.list_groups()
    if not check_feature_enabled() then
        return
    end
    
    local result, err = rule_management.list_rule_groups()
    if err then
        api_utils.json_response({error = err}, 500)
        return
    end
    
    -- 确保 result 是数组类型（用于 JSON 序列化）
    local groups_array = {}
    if result then
        if type(result) == "table" then
            -- 检查是否是数组（有数字索引）
            local is_array = false
            local array_length = 0
            for i, _ in ipairs(result) do
                is_array = true
                array_length = i
                groups_array[i] = result[i]
            end
            
            -- 如果 ipairs 没有遍历到任何元素，检查是否是空数组
            if array_length == 0 then
                if next(result) == nil then
                    -- 空数组，保持为空数组
                    is_array = true
                else
                    -- 非空但不是数组，需要转换
                    is_array = false
                end
            end
            
            -- 如果不是数组，尝试转换
            if not is_array then
                -- 检查是否有数字键
                local has_numeric_keys = false
                for k, v in pairs(result) do
                    if type(k) == "number" and k > 0 then
                        has_numeric_keys = true
                        table.insert(groups_array, v)
                    end
                end
                
                -- 如果有数字键，对结果进行排序
                if has_numeric_keys then
                    table.sort(groups_array, function(a, b)
                        -- 如果group_name存在，按group_name排序
                        if a and a.group_name and b and b.group_name then
                            return a.group_name < b.group_name
                        end
                        return false
                    end)
                end
            end
        end
    end
    -- 如果result为nil，groups_array已经是空数组[]，直接使用
    
    -- 强制转换为标准数组（确保 JSON 序列化时是数组）
    -- 创建一个新的数组，只包含数字索引的元素
    local final_groups = {}
    if #groups_array > 0 then
        -- 使用 ipairs 确保只复制数组部分
        for i = 1, #groups_array do
            final_groups[i] = groups_array[i]
        end
    end
    
    -- 测试 JSON 序列化，确保 groups 是数组格式
    local cjson = require "cjson"
    local test_json = cjson.encode(final_groups)
    ngx.log(ngx.DEBUG, "Groups JSON serialization test: ", test_json:sub(1, 100))
    
    -- 检查 JSON 字符串是否以 [ 开头（数组）而不是 { 开头（对象）
    if not test_json:match("^%[") then
        ngx.log(ngx.WARN, "WARNING: groups JSON does not start with [, it starts with: ", test_json:sub(1, 1))
        -- 强制设置为空数组
        final_groups = {}
    end
    
    api_utils.json_response({
        success = true,
        data = final_groups
    })
end

-- 获取分组统计信息
function _M.group_stats()
    if not check_feature_enabled() then
        return
    end
    
    local result, err = rule_management.get_group_stats()
    if err then
        api_utils.json_response({error = err}, 500)
        return
    end
    
    api_utils.json_response({
        success = true,
        data = result
    })
end

return _M

