-- 缓存调优模块
-- 路径：项目目录下的 lua/waf/cache_tuner.lua（保持在项目目录，不复制到系统目录）
-- 功能：根据实际业务场景动态调整缓存大小和TTL

local config_manager = require "waf.config_manager"
local metrics = require "waf.metrics"
local cache_optimizer = require "waf.cache_optimizer"
local cjson = require "cjson"

local _M = {}
local cache = ngx.shared.waf_cache

-- 配置项（从数据库读取）
local ENABLE_TUNING = config_manager.get_config("cache_tuner_enable", true, "boolean")
local TUNING_INTERVAL = tonumber(config_manager.get_config("cache_tuner_interval", 300, "number")) or 300  -- 调优间隔（秒，默认5分钟）
local MIN_TTL = tonumber(config_manager.get_config("cache_min_ttl", 30, "number")) or 30  -- 最小TTL（秒）
local MAX_TTL = tonumber(config_manager.get_config("cache_max_ttl", 3600, "number")) or 3600  -- 最大TTL（秒）
local BASE_TTL = tonumber(config_manager.get_config("cache_base_ttl", 60, "number")) or 60  -- 基础TTL（秒）

-- 缓存统计键
local CACHE_STATS_PREFIX = "cache_stats:"
local CACHE_TUNING_HISTORY_KEY = "cache_tuning_history"

-- 记录缓存访问统计
function _M.record_cache_access(key, hit, ttl)
    if not ENABLE_TUNING then
        return
    end
    
    local stats_key = CACHE_STATS_PREFIX .. key
    local stats_data = cache:get(stats_key)
    local stats = {}
    
    if stats_data then
        local ok, decoded = pcall(cjson.decode, stats_data)
        if ok and decoded then
            stats = decoded
        end
    end
    
    stats.access_count = (stats.access_count or 0) + 1
    stats.hit_count = (stats.hit_count or 0) + (hit and 1 or 0)
    stats.last_access = ngx.time()
    stats.current_ttl = ttl or BASE_TTL
    
    -- 计算命中率
    stats.hit_rate = stats.hit_count / stats.access_count
    
    cache:set(stats_key, cjson.encode(stats), 3600)  -- 保存1小时
end

-- 分析缓存使用情况
function _M.analyze_cache_usage()
    if not ENABLE_TUNING then
        return nil
    end
    
    -- 获取缓存命中率
    local cache_hits = metrics.get_counter("waf_cache_hits_total") or 0
    local cache_misses = metrics.get_counter("waf_cache_misses_total") or 0
    local total_requests = cache_hits + cache_misses
    local hit_rate = 0
    if total_requests > 0 then
        hit_rate = cache_hits / total_requests
    end
    
    -- 获取缓存使用情况（简化实现，实际需要遍历所有键）
    local cache_size = cache:capacity() or 0
    local cache_free = cache:free_space() or 0
    local cache_used = cache_size - cache_free
    local usage_rate = 0
    if cache_size > 0 then
        usage_rate = cache_used / cache_size
    end
    
    return {
        hit_rate = hit_rate,
        cache_hits = cache_hits,
        cache_misses = cache_misses,
        total_requests = total_requests,
        cache_size = cache_size,
        cache_used = cache_used,
        cache_free = cache_free,
        usage_rate = usage_rate
    }
end

-- 根据业务场景调整缓存TTL
function _M.tune_cache_ttl()
    if not ENABLE_TUNING then
        return
    end
    
    local usage = _M.analyze_cache_usage()
    if not usage then
        return
    end
    
    -- 根据命中率和使用率调整TTL
    local new_base_ttl = BASE_TTL
    
    -- 如果命中率高（>80%），可以适当增加TTL
    if usage.hit_rate > 0.8 then
        new_base_ttl = math.min(BASE_TTL * 1.5, MAX_TTL)
    -- 如果命中率低（<50%），减少TTL以更快刷新
    elseif usage.hit_rate < 0.5 then
        new_base_ttl = math.max(BASE_TTL * 0.7, MIN_TTL)
    end
    
    -- 如果缓存使用率高（>80%），减少TTL以释放空间
    if usage.usage_rate > 0.8 then
        new_base_ttl = math.max(new_base_ttl * 0.8, MIN_TTL)
    -- 如果缓存使用率低（<30%），可以增加TTL
    elseif usage.usage_rate < 0.3 then
        new_base_ttl = math.min(new_base_ttl * 1.2, MAX_TTL)
    end
    
    -- 如果TTL有变化，更新配置
    if math.abs(new_base_ttl - BASE_TTL) > 5 then
        -- 记录调优历史
        local history_data = cache:get(CACHE_TUNING_HISTORY_KEY)
        local history = {}
        if history_data then
            local ok, decoded = pcall(cjson.decode, history_data)
            if ok and decoded then
                history = decoded
            end
        end
        
        table.insert(history, {
            timestamp = ngx.time(),
            datetime = os.date("!%Y-%m-%d %H:%M:%S", ngx.time()),
            old_ttl = BASE_TTL,
            new_ttl = new_base_ttl,
            hit_rate = usage.hit_rate,
            usage_rate = usage.usage_rate,
            reason = string.format("hit_rate=%.2f, usage_rate=%.2f", usage.hit_rate, usage.usage_rate)
        })
        
        -- 保持历史记录数量（最多100条）
        if #history > 100 then
            table.sort(history, function(a, b)
                return a.timestamp > b.timestamp
            end)
            history = {unpack(history, 1, 100)}
        end
        
        cache:set(CACHE_TUNING_HISTORY_KEY, cjson.encode(history), 86400)  -- 保存24小时
        
        -- 更新配置（这里只是记录，实际更新需要通过config_manager）
        ngx.log(ngx.INFO, string.format(
            "Cache TTL tuned: %d -> %d (hit_rate=%.2f, usage_rate=%.2f)",
            BASE_TTL, new_base_ttl, usage.hit_rate, usage.usage_rate
        ))
        
        -- 注意：实际更新配置需要通过config_manager.set_config()，这里只是记录建议
        -- 可以通过API或定时任务来应用这些建议
    end
end

-- 获取调优历史
function _M.get_tuning_history(limit)
    limit = limit or 50
    
    local history_data = cache:get(CACHE_TUNING_HISTORY_KEY)
    if not history_data then
        return {}
    end
    
    local ok, history = pcall(cjson.decode, history_data)
    if not ok or not history then
        return {}
    end
    
    -- 按时间排序（最新的在前）
    table.sort(history, function(a, b)
        return a.timestamp > b.timestamp
    end)
    
    -- 限制返回数量
    if #history > limit then
        history = {unpack(history, 1, limit)}
    end
    
    return history
end

-- 获取缓存建议
function _M.get_cache_recommendations()
    local usage = _M.analyze_cache_usage()
    if not usage then
        return {}
    end
    
    local recommendations = {}
    
    -- 命中率建议
    if usage.hit_rate < 0.5 then
        table.insert(recommendations, {
            type = "hit_rate",
            level = "warning",
            message = string.format("缓存命中率较低（%.2f%%），建议增加缓存TTL或检查缓存键设计", usage.hit_rate * 100),
            suggestion = "考虑增加cache_base_ttl配置值"
        })
    elseif usage.hit_rate > 0.9 then
        table.insert(recommendations, {
            type = "hit_rate",
            level = "info",
            message = string.format("缓存命中率很高（%.2f%%），可以适当增加TTL以提高性能", usage.hit_rate * 100),
            suggestion = "考虑增加cache_max_ttl配置值"
        })
    end
    
    -- 使用率建议
    if usage.usage_rate > 0.8 then
        table.insert(recommendations, {
            type = "usage_rate",
            level = "warning",
            message = string.format("缓存使用率较高（%.2f%%），建议减少TTL或增加缓存大小", usage.usage_rate * 100),
            suggestion = "考虑减少cache_base_ttl或增加lua_shared_dict大小"
        })
    elseif usage.usage_rate < 0.2 then
        table.insert(recommendations, {
            type = "usage_rate",
            level = "info",
            message = string.format("缓存使用率较低（%.2f%%），可以适当增加TTL", usage.usage_rate * 100),
            suggestion = "考虑增加cache_base_ttl配置值"
        })
    end
    
    return recommendations
end

return _M

