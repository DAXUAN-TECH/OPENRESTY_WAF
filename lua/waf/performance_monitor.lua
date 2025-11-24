-- 性能监控模块
-- 路径：项目目录下的 lua/waf/performance_monitor.lua（保持在项目目录，不复制到系统目录）
-- 功能：监控系统性能指标，包括慢查询日志、缓存命中率、响应时间等

local mysql_pool = require "waf.mysql_pool"
local config_manager = require "waf.config_manager"
local metrics = require "waf.metrics"
local cjson = require "cjson"

local _M = {}
local cache = ngx.shared.waf_cache

-- 配置项（从数据库读取）
local ENABLE_MONITORING = config_manager.get_config("performance_monitor_enable", true, "boolean")
local SLOW_QUERY_THRESHOLD = tonumber(config_manager.get_config("performance_slow_query_threshold", 100, "number")) or 100  -- 慢查询阈值（毫秒）
local MONITOR_INTERVAL = tonumber(config_manager.get_config("performance_monitor_interval", 60, "number")) or 60  -- 监控间隔（秒）
local MAX_SLOW_QUERIES = tonumber(config_manager.get_config("performance_max_slow_queries", 1000, "number")) or 1000  -- 最大慢查询记录数

-- 慢查询日志键
local SLOW_QUERY_PREFIX = "slow_query:"
local SLOW_QUERY_LIST_KEY = "slow_query_list"

-- 记录慢查询
function _M.record_slow_query(sql, duration_ms, params)
    if not ENABLE_MONITORING then
        return
    end
    
    if duration_ms < SLOW_QUERY_THRESHOLD then
        return
    end
    
    local query_id = ngx.md5(sql .. tostring(ngx.time()) .. tostring(math.random()))
    local query_data = {
        sql = sql,
        duration_ms = duration_ms,
        params = params,
        timestamp = ngx.time(),
        datetime = os.date("!%Y-%m-%d %H:%M:%S", ngx.time())
    }
    
    -- 存储慢查询记录
    local cache_key = SLOW_QUERY_PREFIX .. query_id
    cache:set(cache_key, cjson.encode(query_data), 3600)  -- 保存1小时
    
    -- 添加到慢查询列表（限制数量）
    local list_data = cache:get(SLOW_QUERY_LIST_KEY)
    local query_list = {}
    if list_data then
        local ok, decoded = pcall(cjson.decode, list_data)
        if ok and decoded then
            query_list = decoded
        end
    end
    
    table.insert(query_list, {
        id = query_id,
        sql = sql,
        duration_ms = duration_ms,
        timestamp = ngx.time()
    })
    
    -- 保持列表大小
    if #query_list > MAX_SLOW_QUERIES then
        table.sort(query_list, function(a, b)
            return a.timestamp > b.timestamp
        end)
        query_list = {unpack(query_list, 1, MAX_SLOW_QUERIES)}
    end
    
    cache:set(SLOW_QUERY_LIST_KEY, cjson.encode(query_list), 3600)
    
    -- 记录到指标
    metrics.observe_histogram("waf_slow_query_duration_ms", duration_ms)
    metrics.increment_counter("waf_slow_queries_total")
end

-- 获取慢查询列表
function _M.get_slow_queries(limit)
    limit = limit or 100
    
    local list_data = cache:get(SLOW_QUERY_LIST_KEY)
    if not list_data then
        return {}
    end
    
    local ok, query_list = pcall(cjson.decode, list_data)
    if not ok or not query_list then
        return {}
    end
    
    -- 按时间排序（最新的在前）
    table.sort(query_list, function(a, b)
        return a.timestamp > b.timestamp
    end)
    
    -- 限制返回数量
    if #query_list > limit then
        query_list = {unpack(query_list, 1, limit)}
    end
    
    -- 获取详细信息
    local results = {}
    for _, item in ipairs(query_list) do
        local cache_key = SLOW_QUERY_PREFIX .. item.id
        local detail_data = cache:get(cache_key)
        if detail_data then
            local ok2, detail = pcall(cjson.decode, detail_data)
            if ok2 and detail then
                table.insert(results, detail)
            else
                table.insert(results, {
                    sql = item.sql,
                    duration_ms = item.duration_ms,
                    timestamp = item.timestamp
                })
            end
        else
            table.insert(results, {
                sql = item.sql,
                duration_ms = item.duration_ms,
                timestamp = item.timestamp
            })
        end
    end
    
    return results
end

-- 获取性能统计
function _M.get_performance_stats()
    local stats = {
        cache_hit_rate = metrics.get_gauge("waf_cache_hit_rate") or 0,
        cache_hits = metrics.get_counter("waf_cache_hits_total") or 0,
        cache_misses = metrics.get_counter("waf_cache_misses_total") or 0,
        slow_query_count = metrics.get_counter("waf_slow_queries_total") or 0,
        avg_query_time = metrics.get_gauge("waf_query_duration_ms") or 0,
        avg_match_time = metrics.get_gauge("waf_rule_match_duration_seconds") or 0
    }
    
    return stats
end

-- 分析慢查询并生成报告
function _M.analyze_slow_queries()
    local slow_queries = _M.get_slow_queries(1000)
    
    if #slow_queries == 0 then
        return {
            total = 0,
            avg_duration = 0,
            max_duration = 0,
            top_queries = {}
        }
    end
    
    -- 统计信息
    local total_duration = 0
    local max_duration = 0
    local query_count = {}
    
    for _, query in ipairs(slow_queries) do
        local duration = query.duration_ms or 0
        total_duration = total_duration + duration
        if duration > max_duration then
            max_duration = duration
        end
        
        -- 统计SQL模式（去除参数）
        local sql_pattern = query.sql or ""
        -- 简化SQL模式（去除具体值）
        sql_pattern = sql_pattern:gsub("%?", "?")
        sql_pattern = sql_pattern:gsub("'[^']*'", "'?'")
        sql_pattern = sql_pattern:gsub("%d+", "?")
        
        if not query_count[sql_pattern] then
            query_count[sql_pattern] = {
                pattern = sql_pattern,
                count = 0,
                total_duration = 0,
                max_duration = 0
            }
        end
        
        query_count[sql_pattern].count = query_count[sql_pattern].count + 1
        query_count[sql_pattern].total_duration = query_count[sql_pattern].total_duration + duration
        if duration > query_count[sql_pattern].max_duration then
            query_count[sql_pattern].max_duration = duration
        end
    end
    
    -- 排序并获取Top查询
    local top_queries = {}
    for pattern, data in pairs(query_count) do
        table.insert(top_queries, {
            pattern = pattern,
            count = data.count,
            avg_duration = data.total_duration / data.count,
            max_duration = data.max_duration
        })
    end
    
    table.sort(top_queries, function(a, b)
        return a.avg_duration > b.avg_duration
    end)
    
    if #top_queries > 10 then
        top_queries = {unpack(top_queries, 1, 10)}
    end
    
    return {
        total = #slow_queries,
        avg_duration = total_duration / #slow_queries,
        max_duration = max_duration,
        top_queries = top_queries
    }
end

-- 清理过期慢查询记录
function _M.cleanup_old_queries()
    local list_data = cache:get(SLOW_QUERY_LIST_KEY)
    if not list_data then
        return
    end
    
    local ok, query_list = pcall(cjson.decode, list_data)
    if not ok or not query_list then
        return
    end
    
    local current_time = ngx.time()
    local expired_time = current_time - 3600  -- 1小时前的记录
    
    local valid_queries = {}
    for _, item in ipairs(query_list) do
        if item.timestamp and item.timestamp > expired_time then
            table.insert(valid_queries, item)
        else
            -- 删除过期的详细记录
            local cache_key = SLOW_QUERY_PREFIX .. item.id
            cache:delete(cache_key)
        end
    end
    
    if #valid_queries < #query_list then
        cache:set(SLOW_QUERY_LIST_KEY, cjson.encode(valid_queries), 3600)
    end
end

return _M

