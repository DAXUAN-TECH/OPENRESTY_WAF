-- 配置管理API模块
-- 路径：项目目录下的 lua/api/config.lua（保持在项目目录，不复制到系统目录）
-- 功能：处理配置管理相关的API请求，支持通过Web界面管理配置

local api_utils = require "api.utils"
local config_manager = require "waf.config_manager"
local audit_log = require "waf.audit_log"

local _M = {}

-- 获取所有配置
function _M.list()
    local configs = config_manager.get_all_configs()
    api_utils.json_response({
        success = true,
        data = configs,
        count = #configs
    })
end

-- 获取单个配置
function _M.get()
    local args = api_utils.get_args()
    local config_key = args.config_key or args.key
    
    if not config_key then
        api_utils.json_response({
            success = false,
            error = "缺少参数: config_key"
        }, 400)
        return
    end
    
    local configs = config_manager.get_all_configs()
    for _, config in ipairs(configs) do
        if config.config_key == config_key then
            api_utils.json_response({
                success = true,
                data = config
            })
            return
        end
    end
    
    api_utils.json_response({
        success = false,
        error = "配置不存在: " .. config_key
    }, 404)
end

-- 更新配置
function _M.update()
    local args = api_utils.get_args()
    local config_key = args.config_key or args.key
    local config_value = args.config_value or args.value
    local description = args.description
    
    if not config_key or not config_value then
        api_utils.json_response({
            success = false,
            error = "缺少参数: config_key 或 config_value"
        }, 400)
        return
    end
    
    local ok, err = config_manager.set_config(config_key, config_value, description)
    if ok then
        audit_log.log_config_action("update", config_key, true, nil)
        api_utils.json_response({
            success = true,
            message = "配置更新成功"
        })
    else
        audit_log.log_config_action("update", config_key, false, err)
        api_utils.json_response({
            success = false,
            error = "配置更新失败: " .. (err or "unknown error")
        }, 500)
    end
end

-- 批量更新配置
function _M.batch_update()
    local args = api_utils.get_args()
    local configs = args.configs
    
    if not configs or type(configs) ~= "table" then
        api_utils.json_response({
            success = false,
            error = "缺少参数: configs (数组格式)"
        }, 400)
        return
    end
    
    local results = {}
    local success_count = 0
    local fail_count = 0
    
    for _, config in ipairs(configs) do
        if config.config_key and config.config_value ~= nil then
            local ok, err = config_manager.set_config(
                config.config_key,
                config.config_value,
                config.description
            )
            if ok then
                success_count = success_count + 1
                audit_log.log_config_action("update", config.config_key, true, nil)
            else
                fail_count = fail_count + 1
                audit_log.log_config_action("update", config.config_key, false, err)
            end
            table.insert(results, {
                config_key = config.config_key,
                success = ok,
                error = err
            })
        end
    end
    
    api_utils.json_response({
        success = true,
        message = string.format("批量更新完成: 成功 %d 个，失败 %d 个", success_count, fail_count),
        results = results,
        success_count = success_count,
        fail_count = fail_count
    })
end

-- 清除配置缓存
function _M.clear_cache()
    local args = api_utils.get_args()
    local config_key = args.config_key or args.key
    
    config_manager.clear_cache(config_key)
    
    api_utils.json_response({
        success = true,
        message = config_key and ("配置缓存已清除: " .. config_key) or "所有配置缓存已清除"
    })
end

return _M

