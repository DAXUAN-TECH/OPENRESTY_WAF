-- 规则管理API模块
-- 路径：项目目录下的 lua/api/rules.lua（保持在项目目录，不复制到系统目录）
-- 功能：处理规则管理的CRUD操作API请求

local rule_management = require "waf.rule_management"
local api_utils = require "api.utils"
local cjson = require "cjson"
local config = require "config"
local feature_switches = require "waf.feature_switches"

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
        api_utils.json_response({error = err}, 400)
        return
    end
    
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
        result.rules = {}
    elseif type(result.rules) ~= "table" then
        ngx.log(ngx.WARN, "rules is not a table, type: ", type(result.rules), ", value: ", tostring(result.rules))
        result.rules = {}
    else
        -- 将 rules 转换为真正的数组（确保索引从 1 开始连续）
        -- 这是为了确保 JSON 序列化时是数组而不是对象
        local rules_array = {}
        local rules_count = 0
        
        -- 首先尝试使用 ipairs（适用于数组）
        for i, rule in ipairs(result.rules) do
            rules_count = rules_count + 1
            rules_array[rules_count] = rule
        end
        
        -- 如果 ipairs 没有遍历到任何元素，但 table 不为空，可能是非数组 table
        if rules_count == 0 and next(result.rules) ~= nil then
            -- 尝试从 pairs 转换（处理非数组 table）
            local temp_array = {}
            for k, v in pairs(result.rules) do
                if type(k) == "number" and k > 0 then
                    table.insert(temp_array, {key = k, value = v})
                end
            end
            -- 按 key 排序
            table.sort(temp_array, function(a, b) return a.key < b.key end)
            -- 转换为数组
            for _, item in ipairs(temp_array) do
                rules_count = rules_count + 1
                rules_array[rules_count] = item.value
            end
        end
        
        -- 如果转换后还是空的，确保是空数组
        if rules_count == 0 then
            rules_array = {}
        end
        
        result.rules = rules_array
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
    
    local result, err = rule_management.update_rule(rule_id, rule_data)
    if err then
        api_utils.json_response({error = err}, 400)
        return
    end
    
    api_utils.json_response({
        success = true,
        rule = result
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
    
    local result, err = rule_management.delete_rule(rule_id)
    if err then
        api_utils.json_response({error = err}, 400)
        return
    end
    
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
    
    local result, err = rule_management.enable_rule(rule_id)
    if err then
        api_utils.json_response({error = err}, 400)
        return
    end
    
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
    
    local result, err = rule_management.disable_rule(rule_id)
    if err then
        api_utils.json_response({error = err}, 400)
        return
    end
    
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
    
    api_utils.json_response({
        success = true,
        data = result
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

