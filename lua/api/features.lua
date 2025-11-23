-- 功能管理API模块
-- 路径：项目目录下的 lua/api/features.lua（保持在项目目录，不复制到系统目录）
-- 功能：提供功能开关的查询和更新API，支持从数据库读取和更新

local config = require "config"
local api_utils = require "api.utils"
local feature_switches = require "waf.feature_switches"
local cjson = require "cjson"

local _M = {}

-- 获取所有功能开关状态（优先从数据库读取）
function _M.list()
    local switches, err = feature_switches.get_all()
    if err then
        ngx.log(ngx.WARN, "failed to load feature switches from database, using config: ", err)
        -- 如果数据库加载失败，使用配置文件
        switches = {}
        if config.features then
            for key, feature in pairs(config.features) do
                switches[key] = {
                    feature_key = key,
                    feature_name = key,
                    description = feature.description or "",
                    enable = feature.enable == true,
                    config_source = "file"
                }
            end
        end
    end
    
    local features = {}
    for key, switch in pairs(switches) do
        table.insert(features, {
            key = switch.feature_key or key,
            name = switch.feature_name or key,
            enable = switch.enable == true,
            description = switch.description or "",
            config_source = switch.config_source or "file"
        })
    end
    
    api_utils.json_response({
        success = true,
        features = features
    })
end

-- 获取单个功能开关状态（优先从数据库读取）
function _M.get()
    local args = api_utils.get_args()
    local feature_key = args.key or args.feature_key
    
    if not feature_key then
        feature_key = api_utils.extract_id_from_uri("/api/features/([%w_]+)")
    end
    
    if not feature_key then
        api_utils.json_response({error = "feature_key is required"}, 400)
        return
    end
    
    -- 从数据库获取
    local enable, err = feature_switches.get(feature_key)
    if err then
        -- 如果数据库查询失败，尝试从配置文件获取
        if config.features and config.features[feature_key] then
            local feature = config.features[feature_key]
            api_utils.json_response({
                success = true,
                feature = {
                    key = feature_key,
                    name = feature_key,
                    enable = feature.enable == true,
                    description = feature.description or "",
                    config_source = "file"
                }
            })
            return
        else
            api_utils.json_response({error = "feature not found"}, 404)
            return
        end
    end
    
    -- 获取功能信息
    local feature_name = feature_key
    local description = ""
    if config.features and config.features[feature_key] then
        feature_name = config.features[feature_key].feature_name or feature_key
        description = config.features[feature_key].description or ""
    end
    
    api_utils.json_response({
        success = true,
        feature = {
            key = feature_key,
            name = feature_name,
            enable = enable == true,
            description = description,
            config_source = "database"
        }
    })
end

-- 更新功能开关状态（写入数据库）
function _M.update()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    
    if not body then
        api_utils.json_response({error = "request body is required"}, 400)
        return
    end
    
    local ok, data = pcall(cjson.decode, body)
    if not ok then
        api_utils.json_response({error = "invalid JSON format"}, 400)
        return
    end
    
    local feature_key = data.key or data.feature_key
    if not feature_key then
        api_utils.json_response({error = "feature_key is required"}, 400)
        return
    end
    
    -- 检查功能是否存在（在配置文件或数据库中）
    local enable, err = feature_switches.get(feature_key)
    if err and not (config.features and config.features[feature_key]) then
        api_utils.json_response({error = "feature not found"}, 404)
        return
    end
    
    -- 更新数据库中的开关状态
    local enable_value = data.enable == true or data.enable == "true" or data.enable == 1
    local ok, err = feature_switches.update(feature_key, enable_value)
    if err then
        api_utils.json_response({error = "failed to update feature switch: " .. err}, 500)
        return
    end
    
    -- 获取功能信息
    local feature_name = feature_key
    local description = ""
    if config.features and config.features[feature_key] then
        feature_name = config.features[feature_key].feature_name or feature_key
        description = config.features[feature_key].description or ""
    end
    
    ngx.log(ngx.INFO, "Feature ", feature_key, " updated to ", enable_value and "enabled" or "disabled")
    
    api_utils.json_response({
        success = true,
        message = "功能开关已更新",
        feature = {
            key = feature_key,
            name = feature_name,
            enable = enable_value,
            description = description,
            config_source = "database"
        }
    })
end

-- 批量更新功能开关状态（写入数据库）
function _M.batch_update()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    
    if not body then
        api_utils.json_response({error = "request body is required"}, 400)
        return
    end
    
    local ok, data = pcall(cjson.decode, body)
    if not ok then
        api_utils.json_response({error = "invalid JSON format"}, 400)
        return
    end
    
    if not data.features or type(data.features) ~= "table" then
        api_utils.json_response({error = "features array is required"}, 400)
        return
    end
    
    -- 使用feature_switches模块批量更新
    local result, err = feature_switches.batch_update(data.features)
    if err then
        api_utils.json_response({
            success = false,
            error = err,
            updated = result and result.updated or {},
            errors = result and result.errors or nil
        }, 500)
        return
    end
    
    api_utils.json_response({
        success = true,
        updated = result.updated,
        errors = result.errors,
        message = result.errors and #result.errors > 0 and "部分功能开关更新失败" or "所有功能开关已更新"
    })
end

return _M

