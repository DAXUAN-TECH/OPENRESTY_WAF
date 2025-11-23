-- 反向代理管理API模块
-- 路径：项目目录下的 lua/api/proxy.lua（保持在项目目录，不复制到系统目录）
-- 功能：处理反向代理配置的CRUD操作API请求

local proxy_management = require "waf.proxy_management"
local api_utils = require "api.utils"
local cjson = require "cjson"
local feature_switches = require "waf.feature_switches"
local system_api = require "api.system"

local _M = {}

-- 检查反向代理管理功能是否启用（优先从数据库读取）
local function check_feature_enabled()
    local enabled = feature_switches.is_enabled("proxy_management")
    if not enabled then
        api_utils.json_response({
            success = false,
            error = "反向代理管理功能已禁用"
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
        api_utils.json_response({error = err}, 400)
        return
    end
    
    -- 如果代理配置已启用，尝试触发nginx重载（异步，不阻塞响应）
    if proxy_data.status ~= 0 then
        ngx.timer.at(0, function()
            local ok, result = system_api.reload_nginx_internal()
            if not ok then
                ngx.log(ngx.WARN, "自动触发nginx重载失败: ", result or "unknown error")
            else
                ngx.log(ngx.INFO, "自动触发nginx重载成功")
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
    
    local result, err = proxy_management.update_proxy(proxy_id, proxy_data)
    if err then
        api_utils.json_response({error = err}, 400)
        return
    end
    
    -- 如果代理配置已启用或状态改变，尝试触发nginx重载（异步，不阻塞响应）
    if proxy_data.status == 1 or proxy_data.status == nil then
        ngx.timer.at(0, function()
            local ok, result = system_api.reload_nginx_internal()
            if not ok then
                ngx.log(ngx.WARN, "自动触发nginx重载失败: ", result or "unknown error")
            else
                ngx.log(ngx.INFO, "自动触发nginx重载成功")
            end
        end)
    end
    
    api_utils.json_response({
        success = true,
        proxy = result,
        message = "代理配置已更新" .. ((proxy_data.status == 1 or proxy_data.status == nil) and "，nginx配置正在重新加载" or "")
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
    
    local result, err = proxy_management.delete_proxy(proxy_id)
    if err then
        api_utils.json_response({error = err}, 400)
        return
    end
    
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
    
    local result, err = proxy_management.enable_proxy(proxy_id)
    if err then
        api_utils.json_response({error = err}, 400)
        return
    end
    
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
    
    local result, err = proxy_management.disable_proxy(proxy_id)
    if err then
        api_utils.json_response({error = err}, 400)
        return
    end
    
    -- 禁用代理后，尝试触发nginx重载（异步，不阻塞响应）
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
        message = "代理配置已禁用，nginx配置正在重新加载"
    })
end

return _M

