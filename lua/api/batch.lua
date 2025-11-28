-- 批量操作API模块
-- 路径：项目目录下的 lua/api/batch.lua（保持在项目目录，不复制到系统目录）
-- 功能：处理批量导入/导出规则的API请求

local batch_operations = require "waf.batch_operations"
local api_utils = require "api.utils"
local audit_log = require "waf.audit_log"

local _M = {}

-- 导出规则（JSON格式）
function _M.export_json()
    local args = api_utils.get_args()
    local rule_type = args.rule_type
    local status = args.status and tonumber(args.status) or nil
    
    local rules, err = batch_operations.export_rules_json(rule_type, status)
    if err then
        -- 记录审计日志（失败）
        audit_log.log_rule_action("export_json", nil, "批量导出规则(JSON)", false, err)
        api_utils.json_response({error = err}, 500)
        return
    end
    
    -- 记录审计日志（成功）
    audit_log.log_rule_action("export_json", nil, "批量导出规则(JSON)", true, nil)
    
    api_utils.json_response({
        success = true,
        count = #rules,
        rules = rules
    })
end

-- 导出规则（CSV格式）
function _M.export_csv()
    local args = api_utils.get_args()
    local rule_type = args.rule_type
    local status = args.status and tonumber(args.status) or nil
    
    local csv_data, err = batch_operations.export_rules_csv(rule_type, status)
    if err then
        -- 记录审计日志（失败）
        audit_log.log_rule_action("export_csv", nil, "批量导出规则(CSV)", false, err)
        api_utils.json_response({error = err}, 500)
        return
    end
    
    -- 记录审计日志（成功）
    audit_log.log_rule_action("export_csv", nil, "批量导出规则(CSV)", true, nil)
    
    local filename = "rules_export_" .. os.date("%Y%m%d_%H%M%S") .. ".csv"
    api_utils.csv_response(csv_data, filename)
end

-- 导入规则（JSON格式）
function _M.import_json()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        api_utils.json_response({error = "request body is required"}, 400)
        return
    end
    
    local args = api_utils.get_args()
    local options = {
        skip_invalid = args.skip_invalid == "true" or args.skip_invalid == "1",
        update_existing = args.update_existing == "true" or args.update_existing == "1"
    }
    
    local results, err = batch_operations.import_rules_json(body, options)
    if err then
        -- 记录审计日志（失败）
        audit_log.log_rule_action("import_json", nil, "批量导入规则(JSON)", false, err)
        api_utils.json_response({error = err}, 400)
        return
    end
    
    -- 记录审计日志（成功）
    local imported_count = results and results.imported and #results.imported or 0
    local failed_count = results and results.failed and #results.failed or 0
    local description = string.format("批量导入规则(JSON): 成功%d条, 失败%d条", imported_count, failed_count)
    audit_log.log_rule_action("import_json", nil, description, true, nil)
    
    api_utils.json_response({
        success = true,
        results = results
    })
end

-- 导入规则（CSV格式）
function _M.import_csv()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        api_utils.json_response({error = "request body is required"}, 400)
        return
    end
    
    local args = api_utils.get_args()
    local options = {
        skip_header = args.skip_header ~= "false",
        skip_invalid = args.skip_invalid == "true" or args.skip_invalid == "1",
        update_existing = args.update_existing == "true" or args.update_existing == "1"
    }
    
    local results, err = batch_operations.import_rules_csv(body, options)
    if err then
        -- 记录审计日志（失败）
        audit_log.log_rule_action("import_csv", nil, "批量导入规则(CSV)", false, err)
        api_utils.json_response({error = err}, 400)
        return
    end
    
    -- 记录审计日志（成功）
    local imported_count = results and results.imported and #results.imported or 0
    local failed_count = results and results.failed and #results.failed or 0
    local description = string.format("批量导入规则(CSV): 成功%d条, 失败%d条", imported_count, failed_count)
    audit_log.log_rule_action("import_csv", nil, description, true, nil)
    
    api_utils.json_response({
        success = true,
        results = results
    })
end

return _M

