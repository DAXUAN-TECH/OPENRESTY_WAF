-- 配置检查API模块
-- 路径：项目目录下的 lua/api/config_check.lua（保持在项目目录，不复制到系统目录）
-- 功能：提供配置检查工具API端点

local config_validator = require "waf.config_validator"
local api_utils = require "api.utils"
local cjson = require "cjson"
local config = require "config"
local feature_switches = require "waf.feature_switches"

local _M = {}

-- 检查配置检查API功能是否启用（优先从数据库读取）
local function check_feature_enabled()
    -- 优先从数据库读取功能开关
    local enabled = feature_switches.is_enabled("config_check_api")
    if not enabled then
        api_utils.json_response({
            success = false,
            error = "配置检查API功能已禁用"
        }, 403)
        return false
    end
    return true
end

-- 执行配置检查
function _M.check()
    if not check_feature_enabled() then
        return
    end
    -- 执行验证
    local valid, results = config_validator.validate_all()
    
    -- 组织返回数据
    local response = {
        success = true,
        valid = valid,
        has_errors = config_validator.has_errors(),
        has_warnings = config_validator.has_warnings(),
        results = results,
        formatted = config_validator.format_results()
    }
    
    -- 如果有错误，返回400状态码
    local status_code = 200
    if config_validator.has_errors() then
        status_code = 400
        response.success = false
    end
    
    api_utils.json_response(response, status_code)
end

-- 获取验证结果
function _M.get_results()
    if not check_feature_enabled() then
        return
    end
    local results = config_validator.get_results()
    
    api_utils.json_response({
        success = true,
        results = results,
        has_errors = config_validator.has_errors(),
        has_warnings = config_validator.has_warnings()
    })
end

-- 获取格式化的验证结果
function _M.get_formatted()
    if not check_feature_enabled() then
        return
    end
    local formatted = config_validator.format_results()
    
    api_utils.json_response({
        success = true,
        formatted = formatted,
        has_errors = config_validator.has_errors(),
        has_warnings = config_validator.has_warnings()
    })
end

return _M

