-- 缓存策略优化模块
-- 路径：项目目录下的 lua/waf/cache_optimizer.lua（保持在项目目录，不复制到系统目录）
-- 功能：实现动态TTL调整、热点数据识别和预加载
-- 优化说明：
-- 1. 动态TTL：根据数据访问频率自动调整缓存过期时间
-- 2. 热点数据识别：识别高频访问的数据，延长其缓存时间
-- 3. 预加载：提前加载热点数据，减少缓存未命中

local config_manager = require "waf.config_manager"
local cjson = require "cjson"

local _M = {}
local cache = ngx.shared.waf_cache

-- 配置键（从数据库读取）
local CACHE_OPTIMIZER_ENABLE = "cache_optimizer_enable"
local DYNAMIC_TTL_ENABLE = "cache_dynamic_ttl_enable"
local HOTSPOT_DETECTION_ENABLE = "cache_hotspot_detection_enable"
local HOTSPOT_PRELOAD_ENABLE = "cache_hotspot_preload_enable"

-- 缓存键前缀
local ACCESS_COUNT_PREFIX = "cache_access_count:"
local ACCESS_TIME_PREFIX = "cache_access_time:"
local HOTSPOT_PREFIX = "cache_hotspot:"
local DYNAMIC_TTL_PREFIX = "cache_dynamic_ttl:"

-- 热点数据阈值（从数据库读取，默认值）
local HOTSPOT_THRESHOLD = 100  -- 访问次数阈值
local HOTSPOT_WINDOW = 300  -- 时间窗口（秒）
local MIN_TTL = 30  -- 最小TTL（秒）
local MAX_TTL = 3600  -- 最大TTL（秒）
local BASE_TTL = 60  -- 基础TTL（秒）

-- 检查功能是否启用
local function is_enabled()
    return config_manager.get_config(CACHE_OPTIMIZER_ENABLE, false, "boolean")
end

local function is_dynamic_ttl_enabled()
    return is_enabled() and config_manager.get_config(DYNAMIC_TTL_ENABLE, true, "boolean")
end

local function is_hotspot_detection_enabled()
    return is_enabled() and config_manager.get_config(HOTSPOT_DETECTION_ENABLE, true, "boolean")
end

local function is_hotspot_preload_enabled()
    return is_enabled() and config_manager.get_config(HOTSPOT_PRELOAD_ENABLE, false, "boolean")
end

-- 记录访问（用于热点数据识别）
function _M.record_access(key)
    if not is_hotspot_detection_enabled() then
        return
    end
    
    local now = ngx.time()
    local count_key = ACCESS_COUNT_PREFIX .. key
    local time_key = ACCESS_TIME_PREFIX .. key
    
    -- 获取当前访问次数
    local count = cache:get(count_key) or 0
    count = count + 1
    
    -- 更新访问次数和时间
    cache:set(count_key, tostring(count), HOTSPOT_WINDOW)
    cache:set(time_key, tostring(now), HOTSPOT_WINDOW)
    
    -- 检查是否为热点数据
    local threshold = tonumber(config_manager.get_config("cache_hotspot_threshold", HOTSPOT_THRESHOLD, "number")) or HOTSPOT_THRESHOLD
    if count >= threshold then
        cache:set(HOTSPOT_PREFIX .. key, "1", HOTSPOT_WINDOW)
    end
end

-- 计算动态TTL（根据访问频率）
function _M.calculate_dynamic_ttl(key, base_ttl)
    if not is_dynamic_ttl_enabled() then
        return base_ttl
    end
    
    base_ttl = base_ttl or BASE_TTL
    
    -- 获取访问次数
    local count_key = ACCESS_COUNT_PREFIX .. key
    local count = tonumber(cache:get(count_key) or 0) or 0
    
    -- 根据访问频率计算TTL
    -- 访问次数越多，TTL越长（但不超过最大值）
    local min_ttl = tonumber(config_manager.get_config("cache_min_ttl", MIN_TTL, "number")) or MIN_TTL
    local max_ttl = tonumber(config_manager.get_config("cache_max_ttl", MAX_TTL, "number")) or MAX_TTL
    
    -- 线性增长：每10次访问增加10%的TTL
    local ttl = base_ttl * (1 + (count / 10) * 0.1)
    
    -- 限制在最小值和最大值之间
    if ttl < min_ttl then
        ttl = min_ttl
    elseif ttl > max_ttl then
        ttl = max_ttl
    end
    
    -- 缓存计算出的TTL（避免重复计算）
    cache:set(DYNAMIC_TTL_PREFIX .. key, tostring(ttl), base_ttl)
    
    return math.floor(ttl)
end

-- 检查是否为热点数据
function _M.is_hotspot(key)
    if not is_hotspot_detection_enabled() then
        return false
    end
    
    return cache:get(HOTSPOT_PREFIX .. key) == "1"
end

-- 获取热点数据列表
function _M.get_hotspot_keys(limit)
    if not is_hotspot_detection_enabled() then
        return {}
    end
    
    limit = limit or 100
    local hotspots = {}
    local count = 0
    
    -- 注意：ngx.shared 不支持遍历，这里只能通过已知的键来查找
    -- 实际应用中，热点数据列表应该存储在Redis或数据库中
    -- 这里提供一个简化的实现
    
    return hotspots
end

-- 预加载热点数据（异步执行）
function _M.preload_hotspots()
    if not is_hotspot_preload_enabled() then
        return
    end
    
    -- 在定时器中异步执行预加载
    -- 这里只提供接口，具体预加载逻辑由调用者实现
    ngx.log(ngx.INFO, "Hotspot preload triggered")
end

-- 获取缓存统计信息
function _M.get_stats()
    if not is_enabled() then
        return {
            enabled = false
        }
    end
    
    return {
        enabled = true,
        dynamic_ttl_enabled = is_dynamic_ttl_enabled(),
        hotspot_detection_enabled = is_hotspot_detection_enabled(),
        hotspot_preload_enabled = is_hotspot_preload_enabled(),
        hotspot_threshold = tonumber(config_manager.get_config("cache_hotspot_threshold", HOTSPOT_THRESHOLD, "number")) or HOTSPOT_THRESHOLD,
        min_ttl = tonumber(config_manager.get_config("cache_min_ttl", MIN_TTL, "number")) or MIN_TTL,
        max_ttl = tonumber(config_manager.get_config("cache_max_ttl", MAX_TTL, "number")) or MAX_TTL
    }
end

return _M

