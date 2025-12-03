-- 代理管理API模块
-- 路径：项目目录下的 lua/api/proxy.lua（保持在项目目录，不复制到系统目录）
-- 功能：处理代理配置的CRUD操作API请求

local proxy_management = require "waf.proxy_management"
local api_utils = require "api.utils"
local cjson = require "cjson"
local feature_switches = require "waf.feature_switches"
local system_api = require "api.system"
local audit_log = require "waf.audit_log"

local _M = {}

-- 检查代理管理功能是否启用（优先从数据库读取）
local function check_feature_enabled()
    local enabled = feature_switches.is_enabled("proxy_management")
    if not enabled then
        api_utils.json_response({
            success = false,
            error = "代理管理功能已禁用"
        }, 403)
        return false
    end
    return true
end

-- 创建代理配置
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
    
    local ok, proxy_data = pcall(cjson.decode, body)
    if not ok then
        api_utils.json_response({error = "invalid JSON format"}, 400)
        return
    end
    
    local result, err = proxy_management.create_proxy(proxy_data)
    if err then
        -- 记录审计日志（失败）
        audit_log.log_proxy_action("create", nil, proxy_data.proxy_name, false, err)
        api_utils.json_response({error = err}, 400)
        return
    end
    
    -- 记录审计日志（成功）
    audit_log.log_proxy_action("create", result.id, proxy_data.proxy_name, true, nil)
    
    -- 如果代理配置已启用，尝试触发nginx重载（异步，不阻塞响应）
    -- 注意：create_proxy() 已经同步生成了nginx配置文件，这里只需要重载nginx
    -- 使用 ngx.timer.at(0, ...) 确保在当前请求处理完成后立即执行，但不会阻塞响应
    if proxy_data.status ~= 0 then
        ngx.timer.at(0, function()
            -- 先测试配置，再重载（由 reload_nginx_internal() 内部处理）
            local ok, result = system_api.reload_nginx_internal()
            if not ok then
                ngx.log(ngx.WARN, "创建代理后自动触发nginx重载失败: ", result or "unknown error")
            else
                ngx.log(ngx.INFO, "创建代理后自动触发nginx重载成功，配置已生效")
            end
        end)
    end
    
    api_utils.json_response({
        success = true,
        proxy = result,
        message = "代理配置已创建" .. (proxy_data.status ~= 0 and "，nginx配置正在重新加载" or "")
    })
end

-- 查询代理配置列表
function _M.list()
    if not check_feature_enabled() then
        return
    end
    local args = api_utils.get_args()
    local params = {
        proxy_type = args.proxy_type,
        status = args.status and tonumber(args.status) or nil,
        page = args.page and tonumber(args.page) or 1,
        page_size = args.page_size and tonumber(args.page_size) or 20
    }
    
    local result, err = proxy_management.list_proxies(params)
    if err then
        api_utils.json_response({error = err}, 500)
        return
    end
    
    -- 确保 result 存在且包含 proxies 数组
    if not result then
        ngx.log(ngx.WARN, "list_proxies returned nil result")
        result = {
            proxies = {},
            total = 0,
            page = params.page,
            page_size = params.page_size,
            total_pages = 0
        }
    end
    
    -- 确保 proxies 是数组类型（用于 JSON 序列化）
    if not result.proxies then
        ngx.log(ngx.WARN, "result.proxies is nil, setting to empty array")
        result.proxies = {}
    elseif type(result.proxies) ~= "table" then
        ngx.log(ngx.ERR, "result.proxies is not a table, type: ", type(result.proxies), ", value: ", tostring(result.proxies))
        result.proxies = {}
    else
        -- 检查是否是数组（使用 # 和 ipairs 判断）
        local is_array = false
        local array_length = 0
        
        -- 尝试使用 ipairs 遍历
        for i, _ in ipairs(result.proxies) do
            array_length = i
            is_array = true
        end
        
        -- 如果 ipairs 没有遍历到任何元素，检查是否是空数组
        if array_length == 0 then
            if next(result.proxies) == nil then
                -- 空数组，保持原样
                is_array = true
                ngx.log(ngx.DEBUG, "result.proxies is empty array")
            else
                -- 非空但不是数组，需要转换
                ngx.log(ngx.WARN, "result.proxies is not an array, converting...")
                is_array = false
            end
        end
        
        -- 如果不是数组，转换为数组
        if not is_array then
            local proxies_array = {}
            local temp_array = {}
            
            -- 收集所有数字键的值
            for k, v in pairs(result.proxies) do
                if type(k) == "number" and k > 0 then
                    table.insert(temp_array, {key = k, value = v})
                end
            end
            
            -- 按 key 排序
            table.sort(temp_array, function(a, b) return a.key < b.key end)
            
            -- 转换为数组
            for _, item in ipairs(temp_array) do
                table.insert(proxies_array, item.value)
            end
            
            result.proxies = proxies_array
            ngx.log(ngx.INFO, "converted proxies to array, length: ", #result.proxies)
        else
            ngx.log(ngx.DEBUG, "result.proxies is already an array, length: ", array_length)
        end
    end
    
    -- 最终验证：确保 proxies 是数组
    if type(result.proxies) ~= "table" then
        ngx.log(ngx.ERR, "FATAL: result.proxies is still not a table after conversion!")
        result.proxies = {}
    end
    
    -- 强制转换为标准数组（确保 JSON 序列化时是数组）
    local final_proxies = {}
    if #result.proxies > 0 then
        -- 使用 ipairs 确保只复制数组部分
        for i = 1, #result.proxies do
            local proxy = result.proxies[i]
            -- 确保每个proxy的rules字段是数组格式（如果存在）
            if proxy.rules and type(proxy.rules) == "table" then
                local rules_array = {}
                -- 检查是否是数组（使用ipairs可以遍历数组部分）
                -- 对于空数组 {}，ipairs 不会进入循环，但 #proxy.rules 会是 0，所以需要特殊处理
                local array_count = #proxy.rules
                local is_array = false
                
                -- 检查是否有非数字键（如果有，说明不是纯数组）
                local has_non_numeric_key = false
                for k, _ in pairs(proxy.rules) do
                    if type(k) ~= "number" or k < 1 or k > array_count then
                        has_non_numeric_key = true
                        break
                    end
                end
                
                -- 如果没有非数字键，且长度 >= 0，说明是数组（包括空数组）
                if not has_non_numeric_key and array_count >= 0 then
                    is_array = true
                    -- 是数组，直接复制
                    for j = 1, array_count do
                        local rule = proxy.rules[j]
                        -- 确保rule对象字段名正确
                        if rule then
                            rules_array[j] = {
                                id = rule.id or rule.ID,
                                rule_name = rule.rule_name or rule.RULE_NAME or rule.ruleName or "",
                                rule_type = rule.rule_type or rule.RULE_TYPE or rule.ruleType or ""
                            }
                        end
                    end
                    -- 测试 JSON 序列化，确保 rules 是数组格式
                    local cjson = require "cjson"
                    -- 设置 cjson 将空表序列化为数组而不是对象
                    local old_value = nil
                    local ok_get, current_value = pcall(function()
                        return cjson.encode_empty_table_as_object()
                    end)
                    if ok_get and current_value ~= nil then
                        old_value = current_value
                    end
                    
                    local ok_set = pcall(function()
                        cjson.encode_empty_table_as_object(false)
                    end)
                    if not ok_set then
                        ngx.log(ngx.WARN, "无法设置 encode_empty_table_as_object，可能不支持此功能")
                    end
                    
                    local test_json = cjson.encode(rules_array)
                    
                    -- 恢复原始设置
                    if old_value ~= nil then
                        pcall(function()
                            cjson.encode_empty_table_as_object(old_value)
                        end)
                    end
                    -- 检查 JSON 字符串是否以 [ 开头（数组）而不是 { 开头（对象）
                    if not test_json:match("^%[") then
                        ngx.log(ngx.ERR, "proxy_id=", proxy.id, ", WARNING: rules JSON does not start with [, it starts with: ", test_json:sub(1, 1), ", JSON: ", test_json:sub(1, 200))
                        -- 强制重新构建为数组（使用 table.insert 确保是数组）
                        rules_array = {}
                        for j = 1, array_count do
                            local rule = proxy.rules[j]
                            if rule then
                                table.insert(rules_array, {
                                    id = rule.id or rule.ID,
                                    rule_name = rule.rule_name or rule.RULE_NAME or rule.ruleName or "",
                                    rule_type = rule.rule_type or rule.RULE_TYPE or rule.ruleType or ""
                                })
                            end
                        end
                        -- 对于空数组，确保序列化为 []
                        if #rules_array == 0 then
                            -- 空数组，使用 encode_empty_table_as_object(false) 确保序列化为 []
                            pcall(function()
                                cjson.encode_empty_table_as_object(false)
                            end)
                        end
                    end
                    -- 调试日志：记录规则数量
                    if array_count > 0 then
                        ngx.log(ngx.INFO, "proxy_id=", proxy.id, ", rules_array length: ", #rules_array, ", JSON preview: ", test_json:sub(1, 200))
                    end
                else
                    -- 不是数组，尝试转换为数组
                    local idx = 1
                    for _, rule in pairs(proxy.rules) do
                        if rule then
                            rules_array[idx] = {
                                id = rule.id or rule.ID,
                                rule_name = rule.rule_name or rule.RULE_NAME or rule.ruleName or "",
                                rule_type = rule.rule_type or rule.RULE_TYPE or rule.ruleType or ""
                            }
                            idx = idx + 1
                        end
                    end
                    ngx.log(ngx.WARN, "proxy_id=", proxy.id, ", proxy.rules is not an array, converted to array, length: ", #rules_array)
                end
                proxy.rules = rules_array
            else
                -- 如果没有rules字段，记录日志
                if proxy.ip_rule_ids and type(proxy.ip_rule_ids) == "table" and #proxy.ip_rule_ids > 0 then
                    ngx.log(ngx.WARN, "proxy_id=", proxy.id, ", has ip_rule_ids but no rules field, ip_rule_ids: ", cjson.encode(proxy.ip_rule_ids))
                end
            end
            final_proxies[i] = proxy
        end
    end
    result.proxies = final_proxies
    
    api_utils.json_response({
        success = true,
        data = result
    })
end

-- 查询代理配置详情
function _M.get()
    if not check_feature_enabled() then
        return
    end
    local args = api_utils.get_args()
    local proxy_id = args.id or args.proxy_id
    
    if not proxy_id then
        proxy_id = api_utils.extract_id_from_uri("/api/proxy/(%d+)")
    end
    
    if not proxy_id then
        api_utils.json_response({error = "proxy_id is required"}, 400)
        return
    end
    
    local proxy, err = proxy_management.get_proxy(proxy_id)
    if err then
        api_utils.json_response({error = err}, 404)
        return
    end
    
    api_utils.json_response({
        success = true,
        proxy = proxy
    })
end

-- 更新代理配置
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
    local proxy_id = args.id or args.proxy_id
    
    if not proxy_id then
        proxy_id = api_utils.extract_id_from_uri("/api/proxy/(%d+)")
    end
    
    if not proxy_id then
        api_utils.json_response({error = "proxy_id is required"}, 400)
        return
    end
    
    local ok, proxy_data = pcall(cjson.decode, body)
    if not ok then
        api_utils.json_response({error = "invalid JSON format"}, 400)
        return
    end
    
    -- 获取代理信息用于审计日志
    local old_proxy = proxy_management.get_proxy(proxy_id)
    local proxy_name = old_proxy and old_proxy.proxy_name or proxy_data.proxy_name or ""
    
    -- 使用 xpcall 包裹 update_proxy，防止 Lua 运行时错误直接导致 500 HTML 错误页
    local ok_call, result_or_err, err = xpcall(function()
        return proxy_management.update_proxy(proxy_id, proxy_data)
    end, debug.traceback)
    
    if not ok_call then
        local trace = result_or_err or "unknown runtime error"
        ngx.log(ngx.ERR, "proxy_management.update_proxy runtime error: ", trace)
        -- 记录审计日志（失败）
        audit_log.log_proxy_action("update", proxy_id, proxy_name, false, trace)
        api_utils.json_response({error = "内部错误: " .. tostring(trace)}, 500)
        return
    end
    
    local result, err = result_or_err, err
    if err then
        -- 记录审计日志（失败）
        audit_log.log_proxy_action("update", proxy_id, proxy_name, false, err)
        api_utils.json_response({error = err}, 400)
        return
    end
    
    -- 记录审计日志（成功）
    audit_log.log_proxy_action("update", proxy_id, proxy_name, true, nil)
    
    -- 触发nginx重载（异步，不阻塞响应）
    -- 注意：代理配置更新后（无论状态如何）都需要reload使新配置生效
    ngx.timer.at(0, function()
        local ok, result = system_api.reload_nginx_internal()
        if not ok then
            ngx.log(ngx.WARN, "更新代理配置后自动触发nginx重载失败: ", result or "unknown error")
        else
            ngx.log(ngx.INFO, "更新代理配置后自动触发nginx重载成功")
        end
    end)
    
    api_utils.json_response({
        success = true,
        proxy = result,
        message = "代理配置已更新，nginx配置正在重新加载"
    })
end

-- 删除代理配置
function _M.delete()
    if not check_feature_enabled() then
        return
    end
    local args = api_utils.get_args()
    local proxy_id = args.id or args.proxy_id
    
    if not proxy_id then
        proxy_id = api_utils.extract_id_from_uri("/api/proxy/(%d+)")
    end
    
    if not proxy_id then
        api_utils.json_response({error = "proxy_id is required"}, 400)
        return
    end
    
    -- 获取代理信息用于审计日志
    local old_proxy = proxy_management.get_proxy(proxy_id)
    local proxy_name = old_proxy and old_proxy.proxy_name or ""
    
    local result, err = proxy_management.delete_proxy(proxy_id)
    if err then
        -- 记录审计日志（失败）
        audit_log.log_proxy_action("delete", proxy_id, proxy_name, false, err)
        api_utils.json_response({error = err}, 400)
        return
    end
    
    -- 记录审计日志（成功）
    audit_log.log_proxy_action("delete", proxy_id, proxy_name, true, nil)
    
    api_utils.json_response({
        success = true,
        message = "代理配置已删除"
    })
end

-- 启用代理配置
function _M.enable()
    if not check_feature_enabled() then
        return
    end
    local proxy_id = api_utils.extract_id_from_uri("/api/proxy/(%d+)/enable")
    
    if not proxy_id then
        api_utils.json_response({error = "proxy_id is required"}, 400)
        return
    end
    
    -- 获取代理信息用于审计日志
    local proxy = proxy_management.get_proxy(proxy_id)
    local proxy_name = proxy and proxy.proxy_name or ""
    
    local result, err = proxy_management.enable_proxy(proxy_id)
    if err then
        -- 记录审计日志（失败）
        audit_log.log_proxy_action("enable", proxy_id, proxy_name, false, err)
        api_utils.json_response({error = err}, 400)
        return
    end
    
    -- 记录审计日志（成功）
    audit_log.log_proxy_action("enable", proxy_id, proxy_name, true, nil)
    
    -- 启用代理后，尝试触发nginx重载（异步，不阻塞响应）
    ngx.timer.at(0, function()
        local ok, result = system_api.reload_nginx_internal()
        if not ok then
            ngx.log(ngx.WARN, "自动触发nginx重载失败: ", result or "unknown error")
        else
            ngx.log(ngx.INFO, "自动触发nginx重载成功")
        end
    end)
    
    api_utils.json_response({
        success = true,
        message = "代理配置已启用，nginx配置正在重新加载"
    })
end

-- 禁用代理配置
function _M.disable()
    if not check_feature_enabled() then
        return
    end
    local proxy_id = api_utils.extract_id_from_uri("/api/proxy/(%d+)/disable")
    
    if not proxy_id then
        api_utils.json_response({error = "proxy_id is required"}, 400)
        return
    end
    
    -- 获取代理信息用于审计日志
    local proxy = proxy_management.get_proxy(proxy_id)
    local proxy_name = proxy and proxy.proxy_name or ""
    
    local result, err = proxy_management.disable_proxy(proxy_id)
    if err then
        -- 记录审计日志（失败）
        audit_log.log_proxy_action("disable", proxy_id, proxy_name, false, err)
        api_utils.json_response({error = err}, 400)
        return
    end
    
    -- 记录审计日志（成功）
    audit_log.log_proxy_action("disable", proxy_id, proxy_name, true, nil)
    
    -- 禁用代理后，尝试触发nginx重载（异步，不阻塞响应）
    -- 注意：disable_proxy() 已经同步生成了nginx配置文件（清理了禁用的代理配置），这里只需要重载nginx
    -- 使用 ngx.timer.at(0, ...) 确保在当前请求处理完成后立即执行，但不会阻塞响应
    ngx.timer.at(0, function()
        -- 先测试配置，再重载（由 reload_nginx_internal() 内部处理）
        local ok, result = system_api.reload_nginx_internal()
        if not ok then
            ngx.log(ngx.WARN, "停用代理后自动触发nginx重载失败: ", result or "unknown error")
        else
            ngx.log(ngx.INFO, "停用代理后自动触发nginx重载成功，端口已停止监听")
        end
    end)
    
    api_utils.json_response({
        success = true,
        message = "代理配置已禁用，nginx配置正在重新加载"
    })
end

return _M

