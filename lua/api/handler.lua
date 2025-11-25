-- API处理模块（路由分发器）
-- 路径：项目目录下的 lua/api/handler.lua（保持在项目目录，不复制到系统目录）
-- 功能：作为API路由分发器，根据请求路径和方法分发到相应的API模块

local rules_api = require "api.rules"
local templates_api = require "api.templates"
local batch_api = require "api.batch"
local config_check_api = require "api.config_check"
local config_api = require "api.config"
local features_api = require "api.features"
local auth_api = require "api.auth"
local stats_api = require "api.stats"
local proxy_api = require "api.proxy"
local system_api = require "api.system"
local api_utils = require "api.utils"
local auth = require "waf.auth"
local csrf = require "waf.csrf"
local rate_limit = require "waf.rate_limit"

local _M = {}

-- API 认证检查中间件（除了登录相关 API）
local function require_api_auth()
    local uri = ngx.var.request_uri
    local path = uri:match("^([^?]+)")
    local method = ngx.req.get_method()
    
    -- 登录相关 API 不需要认证，但需要速率限制
    if path == "/api/auth/login" or path == "/api/auth/check" then
        -- 登录接口速率限制
        if path == "/api/auth/login" then
            local username = nil
            ngx.req.read_body()
            local args = ngx.req.get_post_args()
            if args and args.username then
                username = args.username
            end
            
            local ok, remaining, limit = rate_limit.check_login_rate_limit(username, ngx.var.remote_addr)
            if not ok then
                ngx.header["X-RateLimit-Limit"] = tostring(limit)
                ngx.header["X-RateLimit-Remaining"] = "0"
                ngx.header["X-RateLimit-Reset"] = tostring(ngx.time() + remaining)
                api_utils.json_response({
                    error = "Too Many Requests",
                    message = "登录请求过于频繁，请稍后再试",
                    retry_after = remaining
                }, 429)
                return false
            end
            
            -- 设置速率限制响应头
            ngx.header["X-RateLimit-Limit"] = tostring(limit)
            ngx.header["X-RateLimit-Remaining"] = tostring(remaining)
        end
        
        return true
    end
    
    -- 其他所有 API 都需要认证
    local authenticated, session = auth.is_authenticated()
    if not authenticated then
        api_utils.json_response({
            error = "Unauthorized",
            message = "请先登录"
        }, 401)
        return false
    end
    
    -- API速率限制
    local ok, remaining, limit = rate_limit.check_api_rate_limit(
        session.username,
        ngx.var.remote_addr,
        path
    )
    if not ok then
        ngx.header["X-RateLimit-Limit"] = tostring(limit)
        ngx.header["X-RateLimit-Remaining"] = "0"
        ngx.header["X-RateLimit-Reset"] = tostring(ngx.time() + remaining)
        api_utils.json_response({
            error = "Too Many Requests",
            message = "请求过于频繁，请稍后再试",
            retry_after = remaining
        }, 429)
        return false
    end
    
    -- 设置速率限制响应头
    ngx.header["X-RateLimit-Limit"] = tostring(limit)
    ngx.header["X-RateLimit-Remaining"] = tostring(remaining)
    
    -- CSRF防护检查（POST、PUT、DELETE等需要）
    if csrf.requires_csrf(method) then
        local token = csrf.get_token_from_request()
        local verify_ok, err = csrf.verify_token(token, session.username)
        if not verify_ok then
            api_utils.json_response({
                error = "Forbidden",
                message = "CSRF token验证失败: " .. (err or "unknown error")
            }, 403)
            return false
        end
    end
    
    return true, session
end

-- 路由分发主函数
function _M.route()
    local uri = ngx.var.request_uri
    local method = ngx.req.get_method()
    
    -- 移除查询字符串
    local path = uri:match("^([^?]+)")
    
    -- 认证相关路由（不需要认证检查）
    if path:match("^/api/auth") then
        return _M.route_auth(path, method)
    end
    
    -- 其他所有 API 都需要认证
    local auth_ok, session = require_api_auth()
    if not auth_ok then
        return  -- 已返回 401
    end
    
    -- 规则管理相关路由
    if path:match("^/api/rules") then
        return _M.route_rules(path, method)
    end
    
    -- 功能管理相关路由
    if path:match("^/api/features") then
        return _M.route_features(path, method)
    end
    
    -- 配置检查相关路由
    if path:match("^/api/config") then
        return _M.route_config(path, method)
    end
    
    -- 模板管理相关路由
    if path:match("^/api/templates") then
        return _M.route_templates(path, method)
    end
    
    -- 统计报表相关路由
    if path:match("^/api/stats") then
        return _M.route_stats(path, method)
    end
    
    -- 反向代理管理相关路由
    if path:match("^/api/proxy") then
        return _M.route_proxy(path, method)
    end
    
    -- 系统管理相关路由
    if path:match("^/api/system") then
        return _M.route_system(path, method)
    end
    
    -- 性能监控相关路由
    if path:match("^/api/performance") then
        return _M.route_performance(path, method)
    end
    
    -- 未匹配的路由
    api_utils.json_response({
        error = "API endpoint not found",
        path = path,
        method = method
    }, 404)
end

-- 规则管理路由分发
function _M.route_rules(path, method)
    -- 批量操作：导出/导入
    if path == "/api/rules/export/json" then
        return batch_api.export_json()
    elseif path == "/api/rules/export/csv" then
        return batch_api.export_csv()
    elseif path == "/api/rules/import/json" then
        return batch_api.import_json()
    elseif path == "/api/rules/import/csv" then
        return batch_api.import_csv()
    end
    
    -- 规则列表（GET /api/rules 或 GET /api/rules/list）
    if path == "/api/rules" or path == "/api/rules/list" then
        if method == "GET" then
            return rules_api.list()
        elseif method == "POST" then
            return rules_api.create()
        end
    end
    
    -- 规则详情、更新、删除（/api/rules/{id}）
    local rule_id_match = path:match("^/api/rules/(%d+)$")
    if rule_id_match then
        local rule_id = tonumber(rule_id_match)
        if method == "GET" then
            return rules_api.get()
        elseif method == "PUT" then
            return rules_api.update()
        elseif method == "DELETE" then
            return rules_api.delete()
        end
    end
    
    -- 启用规则（/api/rules/{id}/enable）
    local enable_match = path:match("^/api/rules/(%d+)/enable$")
    if enable_match then
        return rules_api.enable()
    end
    
    -- 禁用规则（/api/rules/{id}/disable）
    local disable_match = path:match("^/api/rules/(%d+)/disable$")
    if disable_match then
        return rules_api.disable()
    end
    
    -- 获取规则分组列表
    if path == "/api/rules/groups" then
        return rules_api.list_groups()
    end
    
    -- 获取分组统计信息
    if path == "/api/rules/groups/stats" then
        return rules_api.group_stats()
    end
    
    -- 未匹配的规则路由
    api_utils.json_response({
        error = "Rules API endpoint not found",
        path = path,
        method = method
    }, 404)
end

-- 功能管理路由分发
function _M.route_features(path, method)
    -- 批量更新功能开关
    if path == "/api/features/batch" then
        return features_api.batch_update()
    end
    
    -- 单个功能开关（/api/features/{key}）
    local feature_key_match = path:match("^/api/features/([%w_]+)$")
    if feature_key_match then
        if method == "GET" then
            return features_api.get()
        elseif method == "PUT" or method == "POST" then
            return features_api.update()
        end
    end
    
    -- 所有功能开关（GET /api/features 或 POST /api/features）
    if path == "/api/features" then
        if method == "GET" then
            return features_api.list()
        elseif method == "POST" then
            return features_api.batch_update()
        end
    end
    
    -- 未匹配的功能路由
    api_utils.json_response({
        error = "Features API endpoint not found",
        path = path,
        method = method
    }, 404)
end

-- 配置管理路由分发
function _M.route_config(path, method)
    -- 配置检查相关API
    if path == "/api/config/check" then
        return config_check_api.check()
    elseif path == "/api/config/results" then
        return config_check_api.get_results()
    elseif path == "/api/config/formatted" then
        return config_check_api.get_formatted()
    end
    
    -- 配置管理相关API
    if path == "/api/config" then
        if method == "GET" then
            return config_api.list()
        elseif method == "POST" then
            return config_api.batch_update()
        end
    elseif path == "/api/config/get" then
        return config_api.get()
    elseif path == "/api/config/update" then
        return config_api.update()
    elseif path == "/api/config/batch" then
        return config_api.batch_update()
    elseif path == "/api/config/clear-cache" then
        return config_api.clear_cache()
    end
    
    -- 未匹配的配置路由
    api_utils.json_response({
        error = "Config API endpoint not found",
        path = path,
        method = method
    }, 404)
end

-- 模板管理路由分发
function _M.route_templates(path, method)
    if path == "/api/templates/list" then
        return templates_api.list()
    elseif path == "/api/templates/get" then
        return templates_api.get()
    elseif path == "/api/templates/apply" then
        return templates_api.apply()
    elseif path == "/api/templates/db/list" then
        return templates_api.list_from_db()
    elseif path == "/api/templates/db/get" then
        return templates_api.get_from_db()
    elseif path == "/api/templates/db/apply" then
        return templates_api.apply_from_db()
    end
    
    -- 未匹配的模板路由
    api_utils.json_response({
        error = "Templates API endpoint not found",
        path = path,
        method = method
    }, 404)
end

-- ============================================
-- 批量操作API（委托给 batch_api 模块）
-- ============================================

-- 导出规则（JSON格式）
function _M.export_rules_json()
    return batch_api.export_json()
end

-- 导出规则（CSV格式）
function _M.export_rules_csv()
    return batch_api.export_csv()
end

-- 导入规则（JSON格式）
function _M.import_rules_json()
    return batch_api.import_json()
end

-- 导入规则（CSV格式）
function _M.import_rules_csv()
    return batch_api.import_csv()
end

-- ============================================
-- 模板管理API（委托给 templates_api 模块）
-- ============================================

-- 获取模板列表
function _M.list_templates()
    return templates_api.list()
end

-- 获取模板详情
function _M.get_template()
    return templates_api.get()
end

-- 应用模板
function _M.apply_template()
    return templates_api.apply()
end

-- 从数据库获取模板列表
function _M.list_templates_from_db()
    return templates_api.list_from_db()
end

-- 从数据库获取模板详情
function _M.get_template_from_db()
    return templates_api.get_from_db()
end

-- 应用数据库中的模板
function _M.apply_template_from_db()
    return templates_api.apply_from_db()
end

-- ============================================
-- 规则管理API（委托给 rules_api 模块）
-- ============================================

-- 创建规则
function _M.create_rule()
    return rules_api.create()
end

-- 查询规则列表
function _M.list_rules()
    return rules_api.list()
end

-- 查询规则详情
function _M.get_rule()
    return rules_api.get()
end

-- 更新规则
function _M.update_rule()
    return rules_api.update()
end

-- 删除规则
function _M.delete_rule()
    return rules_api.delete()
end

-- 启用规则
function _M.enable_rule()
    return rules_api.enable()
end

-- 禁用规则
function _M.disable_rule()
    return rules_api.disable()
end

-- ============================================
-- 配置检查API（委托给 config_check_api 模块）
-- ============================================

-- 执行配置检查
function _M.check_config()
    return config_check_api.check()
end

-- 获取配置验证结果
function _M.get_config_results()
    return config_check_api.get_results()
end

-- 获取格式化的配置验证结果
function _M.get_config_formatted()
    return config_check_api.get_formatted()
end

-- ============================================
-- 功能管理API（委托给 features_api 模块）
-- ============================================

-- 获取所有功能开关
function _M.list_features()
    return features_api.list()
end

-- 获取单个功能开关
function _M.get_feature()
    return features_api.get()
end

-- 更新功能开关
function _M.update_feature()
    return features_api.update()
end

-- 批量更新功能开关
function _M.batch_update_features()
    return features_api.batch_update()
end

-- 统计报表路由分发
function _M.route_stats(path, method)
    if path == "/api/stats/overview" then
        return stats_api.overview()
    elseif path == "/api/stats/timeseries" then
        return stats_api.timeseries()
    elseif path == "/api/stats/ip" then
        return stats_api.ip_stats()
    elseif path == "/api/stats/rules" then
        return stats_api.rule_stats()
    else
        api_utils.json_response({
            error = "Stats API endpoint not found",
            path = path,
            method = method
        }, 404)
    end
end

-- 反向代理管理路由分发
function _M.route_proxy(path, method)
    -- 代理配置列表（GET /api/proxy 或 GET /api/proxy/list）
    if path == "/api/proxy" or path == "/api/proxy/list" then
        if method == "GET" then
            return proxy_api.list()
        elseif method == "POST" then
            return proxy_api.create()
        end
    end
    
    -- 代理配置详情、更新、删除（/api/proxy/{id}）
    local proxy_id_match = path:match("^/api/proxy/(%d+)$")
    if proxy_id_match then
        if method == "GET" then
            return proxy_api.get()
        elseif method == "PUT" then
            return proxy_api.update()
        elseif method == "DELETE" then
            return proxy_api.delete()
        end
    end
    
    -- 启用代理配置（/api/proxy/{id}/enable）
    local enable_match = path:match("^/api/proxy/(%d+)/enable$")
    if enable_match then
        return proxy_api.enable()
    end
    
    -- 禁用代理配置（/api/proxy/{id}/disable）
    local disable_match = path:match("^/api/proxy/(%d+)/disable$")
    if disable_match then
        return proxy_api.disable()
    end
    
    -- 未匹配的代理路由
    api_utils.json_response({
        error = "Proxy API endpoint not found",
        path = path,
        method = method
    }, 404)
end

-- 系统管理路由分发
function _M.route_system(path, method)
    -- 重新加载nginx配置
    if path == "/api/system/reload" then
        if method == "POST" then
            return system_api.reload_nginx()
        else
            api_utils.json_response({error = "Method not allowed"}, 405)
            return
        end
    end
    
    -- 测试nginx配置
    if path == "/api/system/test-config" then
        if method == "GET" or method == "POST" then
            return system_api.test_nginx_config()
        else
            api_utils.json_response({error = "Method not allowed"}, 405)
            return
        end
    end
    
    -- 获取系统状态
    if path == "/api/system/status" then
        if method == "GET" then
            return system_api.get_status()
        else
            api_utils.json_response({error = "Method not allowed"}, 405)
            return
        end
    end
    
    -- 未匹配的系统路由
    api_utils.json_response({
        error = "System API endpoint not found",
        path = path,
        method = method
    }, 404)
end

-- 性能监控路由分发
function _M.route_performance(path, method)
    local performance_api = require "api.performance"
    
    if path == "/api/performance/slow-queries" then
        return performance_api.get_slow_queries()
    elseif path == "/api/performance/stats" then
        return performance_api.get_stats()
    elseif path == "/api/performance/analyze" then
        return performance_api.analyze_slow_queries()
    elseif path == "/api/performance/cache/usage" then
        return performance_api.get_cache_usage()
    elseif path == "/api/performance/cache/tuning-history" then
        return performance_api.get_cache_tuning_history()
    elseif path == "/api/performance/cache/recommendations" then
        return performance_api.get_cache_recommendations()
    else
        api_utils.json_response({
            error = "API endpoint not found",
            path = path,
            method = method
        }, 404)
    end
end

-- ============================================
-- 认证API路由分发
-- ============================================

function _M.route_auth(path, method)
    if path == "/api/auth/login" then
        return auth_api.login()
    elseif path == "/api/auth/logout" then
        return auth_api.logout()
    elseif path == "/api/auth/check" then
        return auth_api.check()
    elseif path == "/api/auth/me" then
        return auth_api.me()
    elseif path == "/api/auth/totp/status" then
        return auth_api.get_totp_status()
    elseif path == "/api/auth/totp/setup" then
        return auth_api.setup_totp()
    elseif path == "/api/auth/totp/enable" then
        return auth_api.enable_totp()
    elseif path == "/api/auth/totp/disable" then
        return auth_api.disable_totp()
    elseif path == "/api/auth/password/hash" then
        return auth_api.hash_password()
    elseif path == "/api/auth/password/check" then
        return auth_api.check_password_strength()
    elseif path == "/api/auth/password/generate" then
        return auth_api.generate_password()
    else
        api_utils.json_response({error = "Not Found"}, 404)
    end
end

return _M

