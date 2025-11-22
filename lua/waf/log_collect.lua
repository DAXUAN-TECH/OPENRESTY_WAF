-- 日志采集模块
-- 路径：/usr/local/openresty/nginx/lua/waf/log_collect.lua

local ip_utils = require "waf.ip_utils"
local mysql_pool = require "waf.mysql_pool"
local config = require "config"
local cjson = require "cjson"

local _M = {}
local log_buffer = ngx.shared.waf_log_buffer
local BATCH_SIZE = config.log.batch_size
local BATCH_INTERVAL = config.log.batch_interval
local BUFFER_KEY = "log_queue"
local TIMER_KEY = "log_timer"

-- 将日志添加到缓冲区
local function add_to_buffer(log_data)
    if not config.log.enable_async then
        -- 同步写入（不推荐，性能较差）
        return write_log_direct(log_data)
    end

    -- 异步写入：添加到共享内存缓冲区
    local queue_size = log_buffer:lpush(BUFFER_KEY, ngx.encode_base64(cjson.encode(log_data)))
    
    -- 如果缓冲区达到批量大小，触发写入
    if queue_size and queue_size >= BATCH_SIZE then
        ngx.timer.at(0, flush_logs)
    end
end

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

-- 批量刷新日志到数据库
local function flush_logs(premature)
    if premature then
        return
    end

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
        ngx.log(ngx.ERR, "batch log insert error: ", err)
        -- 失败时重新放回缓冲区（可选，避免日志丢失）
        -- 但要注意防止无限循环
    else
        ngx.log(ngx.DEBUG, "batch inserted ", #logs, " logs")
    end
end

-- 初始化工作进程定时器
function _M.init_worker()
    -- 定期刷新日志（即使未达到批量大小）
    local function periodic_flush(premature)
        if premature then
            return
        end

        flush_logs(false)

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

