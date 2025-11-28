-- 性能监控API模块
-- 路径：项目目录下的 lua/api/performance.lua（保持在项目目录，不复制到系统目录）
-- 功能：提供性能监控和缓存调优相关的API接口

local performance_monitor = require "waf.performance_monitor"
local cache_tuner = require "waf.cache_tuner"
local api_utils = require "api.utils"
local cjson = require "cjson"

local _M = {}

-- 获取慢查询列表
function _M.get_slow_queries()
    local args = api_utils.get_args()
    local limit = args.limit and tonumber(args.limit) or 100
    
    local queries = performance_monitor.get_slow_queries(limit)
    
    api_utils.json_response({
        success = true,
        data = queries,
        total = #queries
    })
end

-- 获取性能统计
function _M.get_stats()
    local stats = performance_monitor.get_performance_stats()
    
    api_utils.json_response({
        success = true,
        data = stats
    })
end

-- 分析慢查询
function _M.analyze_slow_queries()
    local analysis = performance_monitor.analyze_slow_queries()
    
    api_utils.json_response({
        success = true,
        data = analysis
    })
end

-- 获取缓存使用情况
function _M.get_cache_usage()
    local usage = cache_tuner.analyze_cache_usage()
    
    api_utils.json_response({
        success = true,
        data = usage
    })
end

-- 获取缓存调优历史
function _M.get_cache_tuning_history()
    local args = api_utils.get_args()
    local limit = args.limit and tonumber(args.limit) or 50
    
    local history = cache_tuner.get_tuning_history(limit)
    
    api_utils.json_response({
        success = true,
        data = history,
        total = #history
    })
end

-- 获取缓存调优建议
function _M.get_cache_recommendations()
    local recommendations = cache_tuner.get_cache_recommendations()
    
    api_utils.json_response({
        success = true,
        data = recommendations,
        total = #recommendations
    })
end

return _M

