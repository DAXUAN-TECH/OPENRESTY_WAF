-- 数据库连接池监控模块
-- 路径：项目目录下的 lua/waf/pool_monitor.lua（保持在项目目录，不复制到系统目录）
-- 功能：监控数据库连接池状态，实现动态扩容

local config = require "config"
local mysql = require "resty.mysql"
local cjson = require "cjson"

local _M = {}
local cache = ngx.shared.waf_cache

-- 配置
local MONITOR_INTERVAL = config.pool_monitor and config.pool_monitor.check_interval or 10  -- 监控检查间隔（秒）
local POOL_WARN_THRESHOLD = config.pool_monitor and config.pool_monitor.warn_threshold or 0.8  -- 连接池警告阈值（80%）
local POOL_MAX_SIZE = config.pool_monitor and config.pool_monitor.max_pool_size or 100  -- 最大连接池大小
local POOL_MIN_SIZE = config.pool_monitor and config.pool_monitor.min_pool_size or 10  -- 最小连接池大小
local POOL_GROWTH_STEP = config.pool_monitor and config.pool_monitor.growth_step or 10  -- 连接池增长步长

-- 连接池统计键
local POOL_STATS_KEY = "pool_stats"
local POOL_FAILURE_COUNT_KEY = "pool_failure_count"

-- 获取连接池统计信息
function _M.get_pool_stats()
    local stats_data = cache:get(POOL_STATS_KEY)
    if stats_data then
        return cjson.decode(stats_data)
    end
    
    return {
        total_connections = 0,
        active_connections = 0,
        idle_connections = 0,
        failed_connections = 0,
        last_check_time = 0
    }
end

-- 更新连接池统计信息
function _M.update_pool_stats(stats)
    cache:set(POOL_STATS_KEY, cjson.encode(stats), 300)  -- 缓存5分钟
end

-- 检查连接池健康状态
function _M.check_pool_health()
    local stats = _M.get_pool_stats()
    local current_time = ngx.time()
    
    -- 检查连接池使用率
    local usage_rate = 0
    if stats.total_connections > 0 then
        usage_rate = stats.active_connections / stats.total_connections
    end
    
    -- 检查是否需要扩容
    if usage_rate >= POOL_WARN_THRESHOLD and stats.total_connections < POOL_MAX_SIZE then
        ngx.log(ngx.WARN, "pool usage high: ", usage_rate * 100, "%, considering expansion")
        return "high_usage", usage_rate
    end
    
    -- 检查是否需要缩容
    if usage_rate < 0.3 and stats.total_connections > POOL_MIN_SIZE then
        ngx.log(ngx.INFO, "pool usage low: ", usage_rate * 100, "%, considering reduction")
        return "low_usage", usage_rate
    end
    
    return "normal", usage_rate
end

-- 测试数据库连接
function _M.test_connection()
    local db, err = mysql:new()
    if not db then
        return false, err
    end
    
    db:set_timeout(1000)  -- 1秒超时
    
    -- 使用 pcall 包装 connect 调用，避免在超时时出现 "attempt to send data on a closed socket" 错误
    local connect_ok, connect_result = pcall(function()
        return db:connect{
            host = config.mysql.host,
            port = config.mysql.port,
            database = config.mysql.database,
            user = config.mysql.user,
            password = config.mysql.password,
            charset = "utf8mb4",
        }
    end)
    
    local ok, err, errcode, sqlstate
    if connect_ok then
        -- pcall 成功，获取连接结果
        ok, err, errcode, sqlstate = connect_result
    else
        -- pcall 失败，说明 connect 过程中抛出了异常（可能是 socket 已关闭）
        ok = false
        err = connect_result or "connection failed with exception"
    end
    
    if not ok then
        -- 安全关闭失败的连接
        if db then
            pcall(function() db:close() end)
        end
        return false, err
    end
    
    -- 测试查询
    local res, err = db:query("SELECT 1")
    if not res then
        -- 安全关闭连接
        if db then
            pcall(function() db:close() end)
        end
        return false, err
    end
    
    -- 安全关闭连接
    if db then
        pcall(function() db:close() end)
    end
    return true, nil
end

-- 记录连接失败
function _M.record_failure()
    local count = cache:get(POOL_FAILURE_COUNT_KEY) or 0
    cache:incr(POOL_FAILURE_COUNT_KEY, 1)
    cache:expire(POOL_FAILURE_COUNT_KEY, 60)  -- 1分钟窗口
end

-- 获取连接失败次数
function _M.get_failure_count()
    return cache:get(POOL_FAILURE_COUNT_KEY) or 0
end

-- 重置连接失败计数
function _M.reset_failure_count()
    cache:delete(POOL_FAILURE_COUNT_KEY)
end

-- 获取连接池使用率
function _M.get_pool_usage()
    local stats = _M.get_pool_stats()
    if stats.total_connections == 0 then
        return 0
    end
    return stats.active_connections / stats.total_connections
end

-- 检查是否应该降级（连接池耗尽或数据库故障）
function _M.should_fallback()
    local failure_count = _M.get_failure_count()
    if failure_count >= 3 then
        return true, "too_many_failures"
    end
    
    local usage = _M.get_pool_usage()
    if usage >= 0.95 then
        return true, "pool_exhausted"
    end
    
    return false, nil
end

return _M

