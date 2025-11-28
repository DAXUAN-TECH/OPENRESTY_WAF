-- 告警模块
-- 路径：项目目录下的 lua/waf/alert.lua（保持在项目目录，不复制到系统目录）
-- 功能：实现告警机制，监控关键指标并发送告警

local config = require "config"
local metrics = require "waf.metrics"
local health_check = require "waf.health_check"
local pool_monitor = require "waf.pool_monitor"
local cjson = require "cjson"

local _M = {}

-- 配置
local ALERT_ENABLED = config.alert and config.alert.enable or true
local ALERT_THRESHOLDS = config.alert and config.alert.thresholds or {
    block_rate = 100,  -- 每分钟封控次数阈值
    cache_miss_rate = 0.5,  -- 缓存未命中率阈值（50%）
    db_failure_count = 3,  -- 数据库连续失败次数阈值
    pool_usage = 0.9,  -- 连接池使用率阈值（90%）
    error_rate = 0.1  -- 错误率阈值（10%）
}

-- 告警历史记录（防止重复告警）
local alert_history = {}
local ALERT_COOLDOWN = config.alert and config.alert.cooldown or 300  -- 告警冷却时间（秒，默认5分钟）

-- 检查是否在冷却期内
local function is_in_cooldown(alert_key)
    local last_alert = alert_history[alert_key]
    if not last_alert then
        return false
    end
    
    return (ngx.time() - last_alert) < ALERT_COOLDOWN
end

-- 记录告警
local function record_alert(alert_key)
    alert_history[alert_key] = ngx.time()
end

-- 发送告警（日志方式，可扩展为邮件/短信等）
local function send_alert(level, title, message, details)
    if not ALERT_ENABLED then
        return
    end
    
    local alert_key = level .. ":" .. title
    if is_in_cooldown(alert_key) then
        return  -- 在冷却期内，不重复发送
    end
    
    local alert_data = {
        level = level,
        title = title,
        message = message,
        details = details or {},
        timestamp = ngx.time(),
        datetime = os.date("!%Y-%m-%d %H:%M:%S", ngx.time())
    }
    
    -- 记录告警日志
    if level == "critical" then
        ngx.log(ngx.CRIT, "[ALERT] ", title, ": ", message, " | Details: ", cjson.encode(details))
    elseif level == "warning" then
        ngx.log(ngx.WARN, "[ALERT] ", title, ": ", message, " | Details: ", cjson.encode(details))
    else
        ngx.log(ngx.INFO, "[ALERT] ", title, ": ", message, " | Details: ", cjson.encode(details))
    end
    
    -- 可以扩展为发送邮件、短信、Webhook等
    if config.alert and config.alert.webhook_url then
        -- 发送Webhook通知
        local http = require "resty.http"
        local httpc = http.new()
        httpc:set_timeout(1000)
        
        local res, err = httpc:request_uri(config.alert.webhook_url, {
            method = "POST",
            body = cjson.encode(alert_data),
            headers = {
                ["Content-Type"] = "application/json"
            }
        })
        
        if err then
            ngx.log(ngx.ERR, "failed to send alert webhook: ", err)
        end
    end
    
    record_alert(alert_key)
end

-- 检查封控率告警
function _M.check_block_rate()
    -- 获取最近1分钟的封控次数
    local block_count = metrics.get_counter("waf_blocks_total") or 0
    
    if block_count >= ALERT_THRESHOLDS.block_rate then
        send_alert("warning", "High Block Rate", 
            string.format("Block rate exceeded threshold: %d blocks/min (threshold: %d)", 
                block_count, ALERT_THRESHOLDS.block_rate),
            {block_count = block_count, threshold = ALERT_THRESHOLDS.block_rate})
    end
end

-- 检查缓存未命中率告警
function _M.check_cache_miss_rate()
    local cache_hits = metrics.get_counter("waf_cache_hits_total") or 0
    local cache_misses = metrics.get_counter("waf_cache_misses_total") or 0
    
    local total = cache_hits + cache_misses
    if total == 0 then
        return
    end
    
    local miss_rate = cache_misses / total
    if miss_rate >= ALERT_THRESHOLDS.cache_miss_rate then
        send_alert("warning", "High Cache Miss Rate",
            string.format("Cache miss rate exceeded threshold: %.2f%% (threshold: %.2f%%)",
                miss_rate * 100, ALERT_THRESHOLDS.cache_miss_rate * 100),
            {miss_rate = miss_rate, hits = cache_hits, misses = cache_misses})
    end
end

-- 检查数据库健康状态告警
function _M.check_database_health()
    local is_healthy, status = health_check.get_status()
    
    if not is_healthy then
        send_alert("critical", "Database Unhealthy",
            "Database health check failed: " .. (status or "unknown"),
            {status = status})
    end
end

-- 检查连接池使用率告警
function _M.check_pool_usage()
    local usage = pool_monitor.get_pool_usage()
    
    if usage >= ALERT_THRESHOLDS.pool_usage then
        send_alert("warning", "High Pool Usage",
            string.format("Connection pool usage exceeded threshold: %.2f%% (threshold: %.2f%%)",
                usage * 100, ALERT_THRESHOLDS.pool_usage * 100),
            {usage = usage, threshold = ALERT_THRESHOLDS.pool_usage})
    end
end

-- 检查错误率告警
function _M.check_error_rate()
    local total_requests = metrics.get_counter("waf_requests_total") or 0
    local error_requests = metrics.get_counter("waf_errors_total") or 0
    
    if total_requests == 0 then
        return
    end
    
    local error_rate = error_requests / total_requests
    if error_rate >= ALERT_THRESHOLDS.error_rate then
        send_alert("warning", "High Error Rate",
            string.format("Error rate exceeded threshold: %.2f%% (threshold: %.2f%%)",
                error_rate * 100, ALERT_THRESHOLDS.error_rate * 100),
            {error_rate = error_rate, total = total_requests, errors = error_requests})
    end
end

-- 执行所有告警检查
function _M.check_all()
    if not ALERT_ENABLED then
        return
    end
    
    _M.check_block_rate()
    _M.check_cache_miss_rate()
    _M.check_database_health()
    _M.check_pool_usage()
    _M.check_error_rate()
end

return _M

