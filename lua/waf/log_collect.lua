-- 日志采集模块
-- 路径：项目目录下的 lua/waf/log_collect.lua（保持在项目目录，不复制到系统目录）

local ip_utils = require "waf.ip_utils"
local mysql_pool = require "waf.mysql_pool"
local config = require "config"
local cjson = require "cjson"

local _M = {}
local log_buffer = ngx.shared.waf_log_buffer
local BATCH_SIZE = config.log.batch_size
local BATCH_INTERVAL = config.log.batch_interval
local MAX_RETRY = config.log.max_retry or 3
local RETRY_DELAY = config.log.retry_delay or 0.1
local BUFFER_WARN_THRESHOLD = config.log.buffer_warn_threshold or 0.8
local BUFFER_KEY = "log_queue"
local TIMER_KEY = "log_timer"
local BUFFER_SIZE_KEY = "log_buffer_size"  -- 用于监控缓冲区大小

-- 直接写入日志（同步方式）
local function write_log_direct(log_data)
    local sql = [[
        INSERT INTO access_logs 
        (client_ip, request_path, request_method, status_code, user_agent, referer, request_time, response_time)
        VALUES (?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?), ?)
    ]]

    local ok, err = mysql_pool.insert(
        sql,
        log_data.client_ip,
        log_data.request_path,
        log_data.request_method,
        log_data.status_code,
        log_data.user_agent,
        log_data.referer,
        log_data.request_time,
        log_data.response_time
    )

    if err then
        ngx.log(ngx.ERR, "log insert error: ", err)
        return false
    end

    return true
end

-- 将日志添加到缓冲区
local function add_to_buffer(log_data)
    if not config.log.enable_async then
        -- 同步写入（不推荐，性能较差）
        return write_log_direct(log_data)
    end

    -- 异步写入：添加到共享内存缓冲区
    local queue_size = log_buffer:lpush(BUFFER_KEY, ngx.encode_base64(cjson.encode(log_data)))
    
    -- 更新缓冲区大小监控
    if queue_size then
        log_buffer:set(BUFFER_SIZE_KEY, queue_size, 0)  -- 0 表示不过期
        
        -- 检查缓冲区溢出警告（基于批量大小的阈值）
        -- 当队列大小超过批量大小的阈值倍数时，记录警告
        local warn_threshold_size = math.floor(BATCH_SIZE * (1 / BUFFER_WARN_THRESHOLD))
        if queue_size >= warn_threshold_size then
            ngx.log(ngx.WARN, "log buffer size high: ", queue_size, 
                    " (threshold: ", warn_threshold_size, ", batch_size: ", BATCH_SIZE, ")")
        end
    end
    
    -- 如果缓冲区达到批量大小，触发写入
    if queue_size and queue_size >= BATCH_SIZE then
        ngx.timer.at(0, flush_logs)
    end
end

-- 批量刷新日志到数据库（带重试机制）
local function flush_logs(premature, retry_count)
    if premature then
        return
    end
    
    retry_count = retry_count or 0

    local logs = {}
    local count = 0

    -- 从缓冲区取出日志
    while count < BATCH_SIZE do
        local log_str = log_buffer:rpop(BUFFER_KEY)
        if not log_str then
            break
        end

        local ok, log_data = pcall(function()
            return cjson.decode(ngx.decode_base64(log_str))
        end)

        if ok and log_data then
            table.insert(logs, log_data)
            count = count + 1
        end
    end

    if #logs == 0 then
        -- 更新缓冲区大小监控
        log_buffer:set(BUFFER_SIZE_KEY, 0, 0)
        return
    end

    -- 批量插入数据库
    local fields = {
        "client_ip", "request_path", "request_method", "status_code",
        "user_agent", "referer", "request_time", "response_time"
    }

    local values_list = {}
    for _, log_data in ipairs(logs) do
        local request_time = log_data.request_time or ngx.time()
        -- 将Unix时间戳转换为MySQL DATETIME格式
        local datetime_str = os.date("!%Y-%m-%d %H:%M:%S", request_time)
        
        table.insert(values_list, {
            log_data.client_ip or "",
            log_data.request_path or "",
            log_data.request_method or "GET",
            log_data.status_code or 200,
            log_data.user_agent or "",
            log_data.referer or "",
            datetime_str,  -- 使用格式化的日期时间字符串
            log_data.response_time or 0
        })
    end

    local res, err = mysql_pool.batch_insert("access_logs", fields, values_list)
    if err then
        ngx.log(ngx.ERR, "batch log insert error: ", err, " (retry: ", retry_count, "/", MAX_RETRY, ")")
        
        -- 重试机制：如果未达到最大重试次数，延迟后重试
        if retry_count < MAX_RETRY then
            -- 将日志重新放回缓冲区（从前往后放，保持顺序）
            -- 使用 lpush 将日志放回队列前面，因为队列是 lpush/rpop 的 FIFO 队列
            for i = 1, #logs do
                log_buffer:lpush(BUFFER_KEY, ngx.encode_base64(cjson.encode(logs[i])))
            end
            
            -- 延迟后重试
            local ok, timer_err = ngx.timer.at(RETRY_DELAY, flush_logs, retry_count + 1)
            if not ok then
                ngx.log(ngx.ERR, "failed to create retry timer: ", timer_err)
            end
        else
            -- 达到最大重试次数，记录错误但不再重试（避免无限循环）
            ngx.log(ngx.ERR, "batch log insert failed after ", MAX_RETRY, " retries, dropping ", #logs, " logs")
        end
    else
        ngx.log(ngx.DEBUG, "batch inserted ", #logs, " logs")
        -- 更新缓冲区大小监控
        local remaining = log_buffer:llen(BUFFER_KEY) or 0
        log_buffer:set(BUFFER_SIZE_KEY, remaining, 0)
    end
end

-- 初始化工作进程定时器
function _M.init_worker()
    -- 定期刷新日志（即使未达到批量大小）
    local function periodic_flush(premature)
        if premature then
            return
        end

        flush_logs(false, 0)

        -- 设置下一次定时器
        local ok, err = ngx.timer.at(BATCH_INTERVAL, periodic_flush)
        if not ok then
            ngx.log(ngx.ERR, "failed to create timer: ", err)
        end
    end

    -- 启动定时器
    local ok, err = ngx.timer.at(BATCH_INTERVAL, periodic_flush)
    if not ok then
        ngx.log(ngx.ERR, "failed to create initial timer: ", err)
    end
end

-- 采集日志（在 log_by_lua 阶段调用）
function _M.collect()
    -- 获取客户端真实 IP
    local client_ip = ip_utils.get_real_ip()
    if not client_ip then
        return
    end

    -- 获取请求信息
    local request_path = ngx.var.request_uri or ""
    local request_method = ngx.var.request_method or "GET"
    local status_code = ngx.status or 200
    local user_agent = ngx.var.http_user_agent or ""
    local referer = ngx.var.http_referer or ""
    
    -- 计算响应时间（毫秒）
    local response_time = 0
    if ngx.var.request_time then
        response_time = math.floor(tonumber(ngx.var.request_time) * 1000)
    end

    -- 获取请求时间（Unix 时间戳）
    local request_time = ngx.time()

    -- 构建日志数据
    local log_data = {
        client_ip = client_ip,
        request_path = request_path,
        request_method = request_method,
        status_code = status_code,
        user_agent = user_agent,
        referer = referer,
        request_time = request_time,
        response_time = response_time
    }

    -- 添加到缓冲区或直接写入
    add_to_buffer(log_data)
end

return _M

