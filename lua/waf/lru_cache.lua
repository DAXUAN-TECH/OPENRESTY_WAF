-- LRU缓存策略模块
-- 路径：项目目录下的 lua/waf/lru_cache.lua（保持在项目目录，不复制到系统目录）
-- 功能：实现LRU缓存策略，限制缓存项数量，对不活跃IP使用更短的TTL

local config = require "config"
local cjson = require "cjson"

local _M = {}
local cache = ngx.shared.waf_cache

-- 配置
local MAX_CACHE_ITEMS = config.cache.max_items or 10000
local ACTIVE_TTL = config.cache.ttl or 60  -- 活跃IP缓存时间
local INACTIVE_TTL = config.cache.inactive_ttl or 30  -- 不活跃IP缓存时间（更短）
local ACCESS_COUNT_THRESHOLD = config.cache.access_count_threshold or 3  -- 活跃访问次数阈值

-- LRU链表键
local LRU_LIST_KEY = "lru_list"
local ACCESS_COUNT_PREFIX = "access_count:"

-- 获取LRU列表
local function get_lru_list()
    local list_data = cache:get(LRU_LIST_KEY)
    if list_data then
        return cjson.decode(list_data)
    end
    return {}
end

-- 保存LRU列表
local function save_lru_list(list)
    cache:set(LRU_LIST_KEY, cjson.encode(list), 0)  -- 不过期
end

-- 更新LRU列表（将key移到最前面）
local function update_lru(key)
    local list = get_lru_list()
    
    -- 移除旧位置
    for i, v in ipairs(list) do
        if v == key then
            table.remove(list, i)
            break
        end
    end
    
    -- 添加到最前面
    table.insert(list, 1, key)
    
    -- 如果超过最大数量，移除最旧的
    while #list > MAX_CACHE_ITEMS do
        local oldest_key = table.remove(list)
        cache:delete(oldest_key)
        cache:delete(ACCESS_COUNT_PREFIX .. oldest_key)
    end
    
    save_lru_list(list)
end

-- 记录访问次数
local function record_access(key)
    local count_key = ACCESS_COUNT_PREFIX .. key
    local count = cache:get(count_key) or 0
    cache:incr(count_key, 1)
    cache:expire(count_key, ACTIVE_TTL * 2)  -- 过期时间稍长
end

-- 获取访问次数
local function get_access_count(key)
    local count_key = ACCESS_COUNT_PREFIX .. key
    return cache:get(count_key) or 0
end

-- 判断是否活跃
local function is_active(key)
    return get_access_count(key) >= ACCESS_COUNT_THRESHOLD
end

-- 设置缓存值（带LRU管理）
function _M.set(key, value, ttl)
    ttl = ttl or ACTIVE_TTL
    
    -- 检查是否活跃，决定TTL
    if not is_active(key) then
        ttl = INACTIVE_TTL
    end
    
    -- 设置缓存值
    cache:set(key, value, ttl)
    
    -- 更新LRU列表
    update_lru(key)
    
    -- 记录访问
    record_access(key)
end

-- 获取缓存值（带LRU管理）
function _M.get(key)
    local value = cache:get(key)
    
    if value then
        -- 更新LRU列表
        update_lru(key)
        
        -- 记录访问
        record_access(key)
    end
    
    return value
end

-- 删除缓存值
function _M.delete(key)
    cache:delete(key)
    cache:delete(ACCESS_COUNT_PREFIX .. key)
    
    -- 从LRU列表移除
    local list = get_lru_list()
    for i, v in ipairs(list) do
        if v == key then
            table.remove(list, i)
            save_lru_list(list)
            break
        end
    end
end

-- 清理过期缓存
function _M.cleanup()
    local list = get_lru_list()
    local cleaned = 0
    
    for i = #list, 1, -1 do
        local key = list[i]
        if not cache:get(key) then
            -- 缓存已过期，从列表移除
            table.remove(list, i)
            cache:delete(ACCESS_COUNT_PREFIX .. key)
            cleaned = cleaned + 1
        end
    end
    
    if cleaned > 0 then
        save_lru_list(list)
    end
    
    return cleaned
end

-- 获取缓存统计信息
function _M.get_stats()
    local list = get_lru_list()
    local active_count = 0
    local inactive_count = 0
    
    for _, key in ipairs(list) do
        if is_active(key) then
            active_count = active_count + 1
        else
            inactive_count = inactive_count + 1
        end
    end
    
    return {
        total_items = #list,
        active_items = active_count,
        inactive_items = inactive_count,
        max_items = MAX_CACHE_ITEMS
    }
end

return _M

