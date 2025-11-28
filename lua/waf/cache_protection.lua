-- 缓存穿透防护模块
-- 路径：项目目录下的 lua/waf/cache_protection.lua（保持在项目目录，不复制到系统目录）
-- 功能：防止缓存穿透攻击（空结果缓存、布隆过滤器、频率限制）

local config = require "config"
local cjson = require "cjson"

-- 加载 bit 库（用于位运算，兼容 LuaJIT/Lua 5.1）
local bit = bit
if not bit then
    local ok, bit_module = pcall(require, "bit")
    if ok and bit_module then
        bit = bit_module
    else
        -- 如果 bit 库不可用，使用数学运算替代
        bit = {
            bxor = function(x, y)
                -- 异或操作：使用数学运算实现
                local result = 0
                local power = 1
                local x_val = x
                local y_val = y
                for i = 1, 32 do
                    local x_bit = x_val % 2
                    local y_bit = y_val % 2
                    if (x_bit == 1 and y_bit == 0) or (x_bit == 0 and y_bit == 1) then
                        result = result + power
                    end
                    x_val = math.floor(x_val / 2)
                    y_val = math.floor(y_val / 2)
                    power = power * 2
                    if x_val == 0 and y_val == 0 then
                        break
                    end
                end
                return result
            end,
            band = function(x, y)
                -- 位与操作：使用数学运算实现
                local result = 0
                local power = 1
                local x_val = x
                local y_val = y
                for i = 1, 32 do
                    local x_bit = x_val % 2
                    local y_bit = y_val % 2
                    if x_bit == 1 and y_bit == 1 then
                        result = result + power
                    end
                    x_val = math.floor(x_val / 2)
                    y_val = math.floor(y_val / 2)
                    power = power * 2
                    if x_val == 0 and y_val == 0 then
                        break
                    end
                end
                return result
            end,
            bor = function(x, y)
                -- 位或操作：使用数学运算实现
                local result = 0
                local power = 1
                local x_val = x
                local y_val = y
                for i = 1, 32 do
                    local x_bit = x_val % 2
                    local y_bit = y_val % 2
                    if x_bit == 1 or y_bit == 1 then
                        result = result + power
                    end
                    x_val = math.floor(x_val / 2)
                    y_val = math.floor(y_val / 2)
                    power = power * 2
                    if x_val == 0 and y_val == 0 then
                        break
                    end
                end
                return result
            end,
            lshift = function(x, n)
                return x * (2^n)
            end
        }
    end
end

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

-- 配置
local EMPTY_RESULT_TTL = config.cache_protection and config.cache_protection.empty_result_ttl or 60  -- 空结果缓存时间（秒）
local BLOOM_FILTER_SIZE = config.cache_protection and config.cache_protection.bloom_filter_size or 100000  -- 布隆过滤器大小
local BLOOM_FILTER_HASH_COUNT = config.cache_protection and config.cache_protection.bloom_filter_hash_count or 3  -- 布隆过滤器哈希函数数量
local RATE_LIMIT_WINDOW = config.cache_protection and config.cache_protection.rate_limit_window or 60  -- 频率限制窗口（秒）
local RATE_LIMIT_THRESHOLD = config.cache_protection and config.cache_protection.rate_limit_threshold or 100  -- 频率限制阈值（每个窗口内的请求数）

-- 布隆过滤器键前缀
local BLOOM_FILTER_PREFIX = "bloom:"

-- 简单的哈希函数（FNV-1a，兼容 LuaJIT/Lua 5.1）
local function hash(str, seed)
    local hash = seed or 2166136261
    for i = 1, #str do
        local byte = string.byte(str, i)
        -- 使用 bit 库进行异或操作（兼容 LuaJIT）
        if bit and bit.bxor then
            hash = bit.bxor(hash, byte)
        else
            -- 回退：使用简化的哈希算法
            hash = hash + byte
        end
        hash = hash * 16777619
        -- 使用 bit 库进行位与操作（兼容 LuaJIT）
        if bit and bit.band then
            hash = bit.band(hash, 0xFFFFFFFF)  -- 限制为32位
        else
            -- 回退：使用取模限制为32位
            hash = hash % 4294967296  -- 2^32
        end
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
        
        -- 使用 bit 库进行位运算（兼容 LuaJIT）
        local bit_mask
        if bit and bit.lshift then
            bit_mask = bit.lshift(1, bit_index)
        else
            bit_mask = 2^bit_index
        end
        
        if bloom_data[byte_index] then
            if bit and bit.bor then
                bloom_data[byte_index] = bit.bor(bloom_data[byte_index], bit_mask)
            else
                bloom_data[byte_index] = bloom_data[byte_index] + bit_mask
            end
        else
            bloom_data[byte_index] = bit_mask
        end
    end
    
    -- 保存布隆过滤器
    if cache then
        cache:set(bloom_key, cjson.encode(bloom_data), 3600)  -- 1小时过期
    end
end

-- 布隆过滤器：检查元素是否存在
function _M.bloom_check(key, value)
    if not config.cache_protection or not config.cache_protection.enable_bloom_filter then
        return true  -- 如果未启用，返回true（允许查询）
    end
    
    local bloom_key = BLOOM_FILTER_PREFIX .. key
    local bloom_data = nil
    if cache then
        bloom_data = cache:get(bloom_key)
    end
    
    if not bloom_data then
        return false  -- 布隆过滤器不存在，可能不存在
    end
    
    bloom_data = cjson.decode(bloom_data)
    
    -- 检查所有哈希位
    for i = 1, BLOOM_FILTER_HASH_COUNT do
        local h = hash(value, i) % BLOOM_FILTER_SIZE
        local byte_index = math.floor(h / 8) + 1
        local bit_index = h % 8
        
        -- 使用 bit 库进行位运算（兼容 LuaJIT）
        local bit_mask
        if bit and bit.lshift then
            bit_mask = bit.lshift(1, bit_index)
        else
            bit_mask = 2^bit_index
        end
        
        local byte_value = bloom_data[byte_index] or 0
        local bit_value
        if bit and bit.band then
            bit_value = bit.band(byte_value, bit_mask)
        else
            -- 回退：使用取模检查
            bit_value = byte_value % (bit_mask * 2)
            if bit_value >= bit_mask then
                bit_value = bit_mask
            else
                bit_value = 0
            end
        end
        
        if bit_value == 0 then
            return false  -- 某个位为0，肯定不存在
        end
    end
    
    return true  -- 所有位都为1，可能存在（可能有误判）
end

-- 缓存空结果
function _M.cache_empty_result(cache_key, ttl)
    if not cache then
        return  -- 如果缓存不可用，跳过
    end
    ttl = ttl or EMPTY_RESULT_TTL
    cache:set(cache_key .. ":empty", "1", ttl)
end

-- 检查是否为空结果缓存
function _M.is_empty_result_cached(cache_key)
    if not cache then
        return false
    end
    return cache:get(cache_key .. ":empty") == "1"
end

-- 频率限制检查
function _M.check_rate_limit(ip, action)
    if not config.cache_protection or not config.cache_protection.enable_rate_limit then
        return true  -- 如果未启用，允许通过
    end
    
    if not cache then
        -- 如果缓存不可用，允许通过（避免在Stream块中阻塞）
        return true
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

