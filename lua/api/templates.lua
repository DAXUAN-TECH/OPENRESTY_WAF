-- 模板管理API模块
-- 路径：项目目录下的 lua/api/templates.lua（保持在项目目录，不复制到系统目录）
-- 功能：处理规则模板管理的API请求

local rule_templates = require "waf.rule_templates"
local api_utils = require "api.utils"

local _M = {}

-- 获取模板列表
function _M.list()
    local templates = rule_templates.list_templates()
    api_utils.json_response({
        success = true,
        count = #templates,
        templates = templates
    })
end

-- 获取模板详情
function _M.get()
    local args = api_utils.get_args()
    local template_name = args.template_name
    
    if not template_name then
        api_utils.json_response({error = "template_name is required"}, 400)
        return
    end
    
    local template = rule_templates.get_template(template_name)
    if not template then
        api_utils.json_response({error = "template not found"}, 404)
        return
    end
    
    api_utils.json_response({
        success = true,
        template = template
    })
end

-- 应用模板
function _M.apply()
    local args = api_utils.get_args()
    local template_name = args.template_name
    
    if not template_name then
        api_utils.json_response({error = "template_name is required"}, 400)
        return
    end
    
    local options = {
        update_existing = args.update_existing == "true" or args.update_existing == "1",
        enable_rules = args.enable_rules == "true" or args.enable_rules == "1"
    }
    
    local result, err = rule_templates.apply_template(template_name, options)
    if err then
        api_utils.json_response({error = err}, 400)
        return
    end
    
    api_utils.json_response({
        success = true,
        result = result
    })
end

-- 从数据库获取模板列表
function _M.list_from_db()
    local templates, err = rule_templates.list_templates_from_db()
    if err then
        api_utils.json_response({error = err}, 500)
        return
    end
    
    api_utils.json_response({
        success = true,
        count = #templates,
        templates = templates
    })
end

-- 从数据库获取模板详情
function _M.get_from_db()
    local args = api_utils.get_args()
    local template_id = args.template_id and tonumber(args.template_id) or nil
    
    if not template_id then
        api_utils.json_response({error = "template_id is required"}, 400)
        return
    end
    
    local template, err = rule_templates.get_template_from_db(template_id)
    if err then
        api_utils.json_response({error = err}, 404)
        return
    end
    
    api_utils.json_response({
        success = true,
        template = template
    })
end

-- 应用数据库中的模板
function _M.apply_from_db()
    local args = api_utils.get_args()
    local template_id = args.template_id and tonumber(args.template_id) or nil
    
    if not template_id then
        api_utils.json_response({error = "template_id is required"}, 400)
        return
    end
    
    local options = {
        update_existing = args.update_existing == "true" or args.update_existing == "1",
        enable_rules = args.enable_rules == "true" or args.enable_rules == "1"
    }
    
    local result, err = rule_templates.apply_template_from_db(template_id, options)
    if err then
        api_utils.json_response({error = err}, 400)
        return
    end
    
    api_utils.json_response({
        success = true,
        result = result
    })
end

return _M

