-- IP频率统计模块
-- 路径：项目目录下的 lua/waf/frequency_stats.lua（保持在项目目录，不复制到系统目录）

local mysql_pool = require "waf.mysql_pool"
local config = require "config"
local feature_switches = require "waf.feature_switches"
local cjson = require "cjson"

local _M = {}
local cache = ngx.shared.waf_cache
local CACHE_KEY_PREFIX = "freq_stats:"
local CACHE_TTL = 60  -- 频率统计缓存时间（秒）

-- 更新IP频率统计
function _M.update_frequency(client_ip, status_code, request_path)
    -- 检查自动封控功能是否启用（优先从数据库读取）
    local auto_block_enabled = feature_switches.is_enabled("auto_block")
    if not auto_block_enabled or not config.auto_block.enable then
        return
    end

    local window_size = config.auto_block.window_size or 60
    local now = ngx.time()
    local window_start = math.floor(now / window_size) * window_size
    local window_start_str = os.date("!%Y-%m-%d %H:%M:%S", window_start)
    local window_end_str = os.date("!%Y-%m-%d %H:%M:%S", window_start + window_size)
    local now_str = os.date("!%Y-%m-%d %H:%M:%S", now)

    -- 使用INSERT ... ON DUPLICATE KEY UPDATE更新统计
    -- 注意：unique_path_count的更新需要单独查询，这里先更新基础统计
    local sql = [[
        INSERT INTO waf_ip_frequency 
        (client_ip, window_start, window_end, access_count, error_count, unique_path_count, last_access_time)
        VALUES (?, ?, ?, 1, ?, 1, ?)
        ON DUPLICATE KEY UPDATE
            access_count = access_count + 1,
            error_count = error_count + ?,
            last_access_time = ?
    ]]

    local is_error = (status_code >= 400) and 1 or 0
    
    -- 执行更新（使用异步方式，避免阻塞）
    local ok, err = pcall(function()
        mysql_pool.query(sql, 
            client_ip, window_start_str, window_end_str, is_error, now_str,
            is_error, now_str
        )
    end)
    
    if not ok then
        ngx.log(ngx.ERR, "frequency stats update error: ", err)
    end
    
    -- 定期更新unique_path_count（每10次访问更新一次，避免频繁查询）
    -- 这里简化处理，在获取统计时再计算unique_path_count
end

-- 获取IP频率统计
function _M.get_frequency(client_ip)
    -- 检查自动封控功能是否启用（优先从数据库读取）
    local auto_block_enabled = feature_switches.is_enabled("auto_block")
    if not auto_block_enabled or not config.auto_block.enable then
        return nil
    end

    local cache_key = CACHE_KEY_PREFIX .. client_ip
    local cached = cache:get(cache_key)
    if cached then
        local ok, data = pcall(function()
            return cjson.decode(cached)
        end)
        if ok and data then
            return data
        end
    end

    local window_size = config.auto_block.window_size or 60
    local now = ngx.time()
    local window_start = math.floor(now / window_size) * window_size
    local window_start_str = os.date("!%Y-%m-%d %H:%M:%S", window_start)
    local window_end_str = os.date("!%Y-%m-%d %H:%M:%S", window_start + window_size)

    local sql = [[
        SELECT 
            access_count,
            error_count,
            unique_path_count,
            last_access_time
        FROM waf_ip_frequency
        WHERE client_ip = ?
        AND window_start = ?
        LIMIT 1
    ]]

    local res, err = mysql_pool.query(sql, client_ip, window_start_str)
    if err then
        ngx.log(ngx.ERR, "frequency stats query error: ", err)
        return nil
    end

    local stats = nil
    if res and #res > 0 then
        stats = {
            access_count = res[1].access_count or 0,
            error_count = res[1].error_count or 0,
            unique_path_count = res[1].unique_path_count or 0,
            last_access_time = res[1].last_access_time
        }
        
        -- 如果unique_path_count为0或需要更新，从访问日志计算
        if stats.unique_path_count == 0 or stats.access_count % 10 == 0 then
            local sql_path_count = [[
                SELECT COUNT(DISTINCT request_path) as path_count
                FROM waf_access_logs
                WHERE client_ip = ?
                AND request_time >= ?
                AND request_time < ?
            ]]
            
            local res_path, err_path = mysql_pool.query(sql_path_count, 
                client_ip, window_start_str, window_end_str)
            if not err_path and res_path and #res_path > 0 then
                stats.unique_path_count = res_path[1].path_count or 0
                -- 更新数据库中的unique_path_count
                local sql_update = [[
                    UPDATE waf_ip_frequency
                    SET unique_path_count = ?
                    WHERE client_ip = ?
                    AND window_start = ?
                ]]
                mysql_pool.query(sql_update, stats.unique_path_count, client_ip, window_start_str)
            end
        end
        
        -- 计算错误率
        if stats.access_count > 0 then
            stats.error_rate = stats.error_count / stats.access_count
        else
            stats.error_rate = 0
        end
    else
        stats = {
            access_count = 0,
            error_count = 0,
            unique_path_count = 0,
            error_rate = 0
        }
    end

    -- 缓存结果
    cache:set(cache_key, cjson.encode(stats), CACHE_TTL)
    return stats
end

-- 检查是否需要自动封控
function _M.should_auto_block(client_ip)
    -- 检查自动封控功能是否启用（优先从数据库读取）
    local auto_block_enabled = feature_switches.is_enabled("auto_block")
    if not auto_block_enabled or not config.auto_block.enable then
        return false, nil
    end

    local stats = _M.get_frequency(client_ip)
    if not stats then
        return false, nil
    end

    local block_reason = nil
    local threshold_info = {}

    -- 检查频率阈值
    local frequency_threshold = config.auto_block.frequency_threshold or 100
    if stats.access_count >= frequency_threshold then
        block_reason = "auto_frequency"
        threshold_info = {
            type = "frequency",
            threshold = frequency_threshold,
            actual = stats.access_count
        }
    end

    -- 检查错误率阈值
    if not block_reason then
        local error_rate_threshold = config.auto_block.error_rate_threshold or 0.5
        if stats.error_rate >= error_rate_threshold and stats.access_count >= 10 then
            block_reason = "auto_error"
            threshold_info = {
                type = "error_rate",
                threshold = error_rate_threshold,
                actual = stats.error_rate,
                error_count = stats.error_count,
                access_count = stats.access_count
            }
        end
    end

    -- 检查扫描行为阈值
    if not block_reason then
        local scan_threshold = config.auto_block.scan_path_threshold or 20
        if stats.unique_path_count >= scan_threshold and stats.access_count >= scan_threshold then
            block_reason = "auto_scan"
            threshold_info = {
                type = "scan",
                threshold = scan_threshold,
                actual = stats.unique_path_count,
                access_count = stats.access_count
            }
        end
    end

    if block_reason then
        return true, {
            reason = block_reason,
            threshold = threshold_info,
            stats = stats
        }
    end

    return false, nil
end

return _M

