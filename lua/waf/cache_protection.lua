-- 缓存穿透防护模块
-- 路径：项目目录下的 lua/waf/cache_protection.lua（保持在项目目录，不复制到系统目录）
-- 功能：防止缓存穿透攻击（空结果缓存、布隆过滤器、频率限制）

local config = require "config"
local cjson = require "cjson"

local _M = {}
local cache = ngx.shared.waf_cache

-- 配置
local EMPTY_RESULT_TTL = config.cache_protection and config.cache_protection.empty_result_ttl or 60  -- 空结果缓存时间（秒）
local BLOOM_FILTER_SIZE = config.cache_protection and config.cache_protection.bloom_filter_size or 100000  -- 布隆过滤器大小
local BLOOM_FILTER_HASH_COUNT = config.cache_protection and config.cache_protection.bloom_filter_hash_count or 3  -- 布隆过滤器哈希函数数量
local RATE_LIMIT_WINDOW = config.cache_protection and config.cache_protection.rate_limit_window or 60  -- 频率限制窗口（秒）
local RATE_LIMIT_THRESHOLD = config.cache_protection and config.cache_protection.rate_limit_threshold or 100  -- 频率限制阈值（每个窗口内的请求数）

-- 布隆过滤器键前缀
local BLOOM_FILTER_PREFIX = "bloom:"

-- 简单的哈希函数（FNV-1a）
local function hash(str, seed)
    local hash = seed or 2166136261
    for i = 1, #str do
        hash = hash ~ string.byte(str, i)
        hash = hash * 16777619
        hash = hash & 0xFFFFFFFF  -- 限制为32位
    end
    return hash
end

-- 布隆过滤器：添加元素
function _M.bloom_add(key, value)
    if not config.cache_protection or not config.cache_protection.enable_bloom_filter then
        return
    end
    
    local bloom_key = BLOOM_FILTER_PREFIX .. key
    local bloom_data = cache:get(bloom_key)
    
    if not bloom_data then
        -- 初始化布隆过滤器（使用位数组）
        bloom_data = {}
        for i = 1, math.ceil(BLOOM_FILTER_SIZE / 8) do
            bloom_data[i] = 0
        end
    else
        bloom_data = cjson.decode(bloom_data)
    end
    
    -- 计算多个哈希值
    for i = 1, BLOOM_FILTER_HASH_COUNT do
        local h = hash(value, i) % BLOOM_FILTER_SIZE
        local byte_index = math.floor(h / 8) + 1
        local bit_index = h % 8
        
        if bloom_data[byte_index] then
            bloom_data[byte_index] = bloom_data[byte_index] | (1 << bit_index)
        else
            bloom_data[byte_index] = 1 << bit_index
        end
    end
    
    -- 保存布隆过滤器
    cache:set(bloom_key, cjson.encode(bloom_data), 3600)  -- 1小时过期
end

-- 布隆过滤器：检查元素是否存在
function _M.bloom_check(key, value)
    if not config.cache_protection or not config.cache_protection.enable_bloom_filter then
        return true  -- 如果未启用，返回true（允许查询）
    end
    
    local bloom_key = BLOOM_FILTER_PREFIX .. key
    local bloom_data = cache:get(bloom_key)
    
    if not bloom_data then
        return false  -- 布隆过滤器不存在，可能不存在
    end
    
    bloom_data = cjson.decode(bloom_data)
    
    -- 检查所有哈希位
    for i = 1, BLOOM_FILTER_HASH_COUNT do
        local h = hash(value, i) % BLOOM_FILTER_SIZE
        local byte_index = math.floor(h / 8) + 1
        local bit_index = h % 8
        
        if not bloom_data[byte_index] or (bloom_data[byte_index] & (1 << bit_index)) == 0 then
            return false  -- 某个位为0，肯定不存在
        end
    end
    
    return true  -- 所有位都为1，可能存在（可能有误判）
end

-- 缓存空结果
function _M.cache_empty_result(cache_key, ttl)
    ttl = ttl or EMPTY_RESULT_TTL
    cache:set(cache_key .. ":empty", "1", ttl)
end

-- 检查是否为空结果缓存
function _M.is_empty_result_cached(cache_key)
    return cache:get(cache_key .. ":empty") == "1"
end

-- 频率限制检查
function _M.check_rate_limit(ip, action)
    if not config.cache_protection or not config.cache_protection.enable_rate_limit then
        return true  -- 如果未启用，允许通过
    end
    
    local rate_key = "rate_limit:" .. action .. ":" .. ip
    local current = cache:get(rate_key)
    
    if not current then
        -- 第一次请求
        cache:set(rate_key, "1", RATE_LIMIT_WINDOW)
        return true
    end
    
    local count = tonumber(current) or 0
    if count >= RATE_LIMIT_THRESHOLD then
        -- 超过阈值
        ngx.log(ngx.WARN, "rate limit exceeded for IP: ", ip, ", action: ", action)
        return false
    end
    
    -- 增加计数
    cache:incr(rate_key, 1)
    return true
end

-- 综合防护检查（结合布隆过滤器和频率限制）
function _M.should_allow_query(cache_key, value, ip, action)
    -- 检查频率限制
    if not _M.check_rate_limit(ip, action) then
        return false, "rate_limit_exceeded"
    end
    
    -- 检查空结果缓存
    if _M.is_empty_result_cached(cache_key) then
        return false, "empty_result_cached"
    end
    
    -- 检查布隆过滤器（如果启用）
    if config.cache_protection and config.cache_protection.enable_bloom_filter then
        if not _M.bloom_check(cache_key, value) then
            -- 布隆过滤器显示不存在，缓存空结果
            _M.cache_empty_result(cache_key, EMPTY_RESULT_TTL)
            return false, "bloom_filter_miss"
        end
    end
    
    return true, nil
end

-- 记录查询结果到布隆过滤器
function _M.record_query_result(cache_key, value, found)
    if found then
        -- 如果找到了，添加到布隆过滤器
        _M.bloom_add(cache_key, value)
    else
        -- 如果没找到，缓存空结果
        _M.cache_empty_result(cache_key, EMPTY_RESULT_TTL)
    end
end

return _M

