-- 监控指标模块（Prometheus格式）
-- 路径：项目目录下的 lua/waf/metrics.lua（保持在项目目录，不复制到系统目录）

local config = require "config"
local health_check = require "waf.health_check"

local _M = {}
-- 安全获取共享内存（兼容Stream块）
local function get_cache()
    local ok, cache = pcall(function()
        return ngx.shared.waf_cache
    end)
    if ok and cache then
        return cache
    end
    return nil
end
local cache = get_cache()

-- 指标键前缀
local METRICS_PREFIX = "metrics:"
local METRICS_TTL = 300  -- 指标缓存5分钟

-- 增加计数器指标
function _M.increment_counter(name, labels)
    if not cache then
        return  -- 如果缓存不可用，跳过指标记录
    end
    
    local key = METRICS_PREFIX .. "counter:" .. name
    if labels then
        key = key .. ":" .. table.concat(labels, ":")
    end
    
    local current = cache:get(key) or 0
    cache:incr(key, 1)
    cache:expire(key, METRICS_TTL)
end

-- 设置仪表盘指标
function _M.set_gauge(name, value, labels)
    if not cache then
        return  -- 如果缓存不可用，跳过指标记录
    end
    
    local key = METRICS_PREFIX .. "gauge:" .. name
    if labels then
        key = key .. ":" .. table.concat(labels, ":")
    end
    
    cache:set(key, value, METRICS_TTL)
end

-- 记录直方图指标
function _M.observe_histogram(name, value, labels)
    if not cache then
        return  -- 如果缓存不可用，跳过指标记录
    end
    
    local key = METRICS_PREFIX .. "histogram:" .. name
    if labels then
        key = key .. ":" .. table.concat(labels, ":")
    end
    
    -- 简化实现：记录平均值和计数
    local avg_key = key .. ":avg"
    local count_key = key .. ":count"
    
    local current_avg = cache:get(avg_key) or 0
    local current_count = cache:get(count_key) or 0
    
    local new_count = current_count + 1
    local new_avg = (current_avg * current_count + value) / new_count
    
    cache:set(avg_key, new_avg, METRICS_TTL)
    cache:set(count_key, new_count, METRICS_TTL)
end

-- 获取Prometheus格式的指标
function _M.get_prometheus_metrics()
    local metrics = {}
    
    -- WAF封控相关指标
    _M.collect_block_metrics(metrics)
    
    -- 性能相关指标
    _M.collect_performance_metrics(metrics)
    
    -- 健康检查指标
    _M.collect_health_metrics(metrics)
    
    return table.concat(metrics, "\n")
end

-- 收集封控相关指标
function _M.collect_block_metrics(metrics)
    -- 封控总数（从缓存获取，实际应该从数据库统计）
    local block_count = 0
    if cache then
        block_count = cache:get(METRICS_PREFIX .. "counter:waf_blocks_total") or 0
    end
    table.insert(metrics, string.format("# HELP waf_blocks_total Total number of blocked requests"))
    table.insert(metrics, string.format("# TYPE waf_blocks_total counter"))
    table.insert(metrics, string.format("waf_blocks_total %d", block_count))
    
    -- 自动封控数量
    local auto_block_count = 0
    if cache then
        auto_block_count = cache:get(METRICS_PREFIX .. "counter:waf_auto_blocks_total") or 0
    end
    table.insert(metrics, string.format("# HELP waf_auto_blocks_total Total number of auto-blocked IPs"))
    table.insert(metrics, string.format("# TYPE waf_auto_blocks_total counter"))
    table.insert(metrics, string.format("waf_auto_blocks_total %d", auto_block_count))
    
    -- 当前被封控的IP数
    local blocked_ips = 0
    if cache then
        blocked_ips = cache:get(METRICS_PREFIX .. "gauge:waf_blocked_ips") or 0
    end
    table.insert(metrics, string.format("# HELP waf_blocked_ips Current number of blocked IPs"))
    table.insert(metrics, string.format("# TYPE waf_blocked_ips gauge"))
    table.insert(metrics, string.format("waf_blocked_ips %d", blocked_ips))
end

-- 收集性能相关指标
function _M.collect_performance_metrics(metrics)
    -- 缓存命中率（简化实现）
    local cache_hits = 0
    local cache_misses = 0
    if cache then
        cache_hits = cache:get(METRICS_PREFIX .. "counter:waf_cache_hits_total") or 0
        cache_misses = cache:get(METRICS_PREFIX .. "counter:waf_cache_misses_total") or 0
    end
    local cache_hit_rate = 0
    if cache_hits + cache_misses > 0 then
        cache_hit_rate = cache_hits / (cache_hits + cache_misses)
    end
    
    table.insert(metrics, string.format("# HELP waf_cache_hit_rate Cache hit rate"))
    table.insert(metrics, string.format("# TYPE waf_cache_hit_rate gauge"))
    table.insert(metrics, string.format("waf_cache_hit_rate %.4f", cache_hit_rate))
    
    -- 规则匹配耗时（平均值）
    local match_time_avg = 0
    if cache then
        match_time_avg = cache:get(METRICS_PREFIX .. "histogram:waf_rule_match_duration_seconds:avg") or 0
    end
    table.insert(metrics, string.format("# HELP waf_rule_match_duration_seconds Average rule matching duration in seconds"))
    table.insert(metrics, string.format("# TYPE waf_rule_match_duration_seconds gauge"))
    table.insert(metrics, string.format("waf_rule_match_duration_seconds %.6f", match_time_avg))
end

-- 收集健康检查指标
function _M.collect_health_metrics(metrics)
    local is_healthy, status = health_check.get_status()
    local health_value = is_healthy and 1 or 0
    
    table.insert(metrics, string.format("# HELP waf_database_health Database health status (1=healthy, 0=unhealthy)"))
    table.insert(metrics, string.format("# TYPE waf_database_health gauge"))
    table.insert(metrics, string.format("waf_database_health %d", health_value))
    
    -- 降级模式状态
    local fallback_enabled = config.fallback and config.fallback.enable or false
    local fallback_value = fallback_enabled and 1 or 0
    table.insert(metrics, string.format("# HELP waf_fallback_enabled Fallback mode enabled (1=enabled, 0=disabled)"))
    table.insert(metrics, string.format("# TYPE waf_fallback_enabled gauge"))
    table.insert(metrics, string.format("waf_fallback_enabled %d", fallback_value))
end

-- 记录封控事件
function _M.record_block(reason)
    _M.increment_counter("waf_blocks_total")
    if reason and string.find(reason, "auto_") then
        _M.increment_counter("waf_auto_blocks_total")
    end
end

-- 记录缓存命中/未命中
function _M.record_cache_hit()
    _M.increment_counter("waf_cache_hits_total")
end

function _M.record_cache_miss()
    _M.increment_counter("waf_cache_misses_total")
end

-- 记录规则匹配耗时
function _M.record_match_duration(duration_seconds)
    _M.observe_histogram("waf_rule_match_duration_seconds", duration_seconds)
end

-- 获取计数器值
function _M.get_counter(name, labels)
    if not cache then
        return 0
    end
    
    local key = METRICS_PREFIX .. "counter:" .. name
    if labels then
        key = key .. ":" .. table.concat(labels, ":")
    end
    return cache:get(key) or 0
end

-- 获取仪表盘值
function _M.get_gauge(name, labels)
    if not cache then
        return 0
    end
    
    local key = METRICS_PREFIX .. "gauge:" .. name
    if labels then
        key = key .. ":" .. table.concat(labels, ":")
    end
    return cache:get(key) or 0
end

return _M

