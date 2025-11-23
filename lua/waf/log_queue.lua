-- 日志队列模块
-- 路径：项目目录下的 lua/waf/log_queue.lua（保持在项目目录，不复制到系统目录）
-- 功能：实现日志写入重试机制、本地日志文件备份、日志队列机制

local mysql_pool = require "waf.mysql_pool"
local config = require "config"
local path_utils = require "waf.path_utils"
local cjson = require "cjson"
local file = require "resty.file"

local _M = {}
local cache = ngx.shared.waf_log_buffer

-- 配置
local MAX_RETRY = config.log.max_retry or 3
local RETRY_DELAY = config.log.retry_delay or 0.1
local QUEUE_MAX_SIZE = config.log.queue_max_size or 10000  -- 队列最大大小
-- 本地日志文件路径（优先使用配置，否则使用项目根目录下的logs目录）
local LOCAL_LOG_PATH = config.log.local_log_path or path_utils.get_log_path()
local ENABLE_LOCAL_BACKUP = config.log.enable_local_backup or true  -- 是否启用本地备份

-- 队列键
local QUEUE_KEY = "log_queue"
local QUEUE_SIZE_KEY = "log_queue_size"
local RETRY_QUEUE_KEY = "log_retry_queue"

-- 确保本地日志目录存在
local function ensure_log_dir()
    if not ENABLE_LOCAL_BACKUP then
        return true
    end
    
    -- 使用path_utils确保目录存在
    return path_utils.ensure_dir(LOCAL_LOG_PATH)
end

-- 写入本地日志文件
local function write_local_log(log_data, log_type)
    if not ENABLE_LOCAL_BACKUP then
        return true
    end
    
    ensure_log_dir()
    
    local timestamp = os.date("%Y%m%d")
    local filename = LOCAL_LOG_PATH .. "/" .. log_type .. "_" .. timestamp .. ".log"
    
    -- 将日志数据转换为JSON字符串
    local log_line = cjson.encode(log_data) .. "\n"
    
    -- 使用文件追加模式写入
    local file_handle = io.open(filename, "a")
    if file_handle then
        file_handle:write(log_line)
        file_handle:close()
        return true
    end
    
    return false
end

-- 添加日志到队列
function _M.enqueue(log_data, log_type)
    log_type = log_type or "access"
    
    -- 检查队列大小
    local queue_size = cache:get(QUEUE_SIZE_KEY) or 0
    if queue_size >= QUEUE_MAX_SIZE then
        ngx.log(ngx.ERR, "log queue is full, dropping log")
        -- 写入本地备份
        write_local_log(log_data, log_type)
        return false
    end
    
    -- 添加到队列
    local queue_data = cache:get(QUEUE_KEY)
    local queue = {}
    if queue_data then
        queue = cjson.decode(queue_data)
    end
    
    table.insert(queue, {
        data = log_data,
        type = log_type,
        timestamp = ngx.time(),
        retry_count = 0
    })
    
    cache:set(QUEUE_KEY, cjson.encode(queue), 3600)  -- 1小时过期
    cache:incr(QUEUE_SIZE_KEY, 1)
    
    return true
end

-- 从队列获取日志
function _M.dequeue(count)
    count = count or 1
    
    local queue_data = cache:get(QUEUE_KEY)
    if not queue_data then
        return {}
    end
    
    local queue = cjson.decode(queue_data)
    local logs = {}
    
    for i = 1, math.min(count, #queue) do
        table.insert(logs, table.remove(queue, 1))
        cache:dec(QUEUE_SIZE_KEY, 1)
    end
    
    if #queue > 0 then
        cache:set(QUEUE_KEY, cjson.encode(queue), 3600)
    else
        cache:delete(QUEUE_KEY)
    end
    
    return logs
end

-- 写入访问日志
function _M.write_access_log(log_data)
    local sql = [[
        INSERT INTO waf_access_logs 
        (client_ip, request_path, request_method, status_code, user_agent, referer, request_time, response_time)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]]
    
    local request_time = log_data.request_time or ngx.time()
    local datetime_str = os.date("!%Y-%m-%d %H:%M:%S", request_time)
    
    local ok, err = mysql_pool.insert(
        sql,
        log_data.client_ip,
        log_data.request_path,
        log_data.request_method,
        log_data.status_code,
        log_data.user_agent,
        log_data.referer,
        datetime_str,
        log_data.response_time
    )
    
    if err then
        -- 写入失败，写入本地备份
        write_local_log(log_data, "access")
        return false, err
    end
    
    return true, nil
end

-- 写入封控日志
function _M.write_block_log(log_data)
    local sql = [[
        INSERT INTO waf_block_logs 
        (client_ip, rule_id, rule_name, block_time, request_path, user_agent, block_reason)
        VALUES (?, ?, ?, NOW(), ?, ?, ?)
    ]]
    
    local ok, err = mysql_pool.insert(
        sql,
        log_data.client_ip,
        log_data.rule_id,
        log_data.rule_name,
        log_data.request_path,
        log_data.user_agent,
        log_data.block_reason or "manual"
    )
    
    if err then
        -- 写入失败，写入本地备份
        write_local_log(log_data, "block")
        return false, err
    end
    
    return true, nil
end

-- 重试写入日志
function _M.retry_write(log_entry)
    log_entry.retry_count = (log_entry.retry_count or 0) + 1
    
    if log_entry.retry_count > MAX_RETRY then
        -- 超过最大重试次数，写入本地备份
        write_local_log(log_entry.data, log_entry.type)
        return false, "max_retry_exceeded"
    end
    
    -- 根据日志类型选择写入函数
    local ok, err
    if log_entry.type == "access" then
        ok, err = _M.write_access_log(log_entry.data)
    elseif log_entry.type == "block" then
        ok, err = _M.write_block_log(log_entry.data)
    else
        return false, "unknown_log_type"
    end
    
    if not ok then
        -- 写入失败，添加到重试队列
        local retry_queue_data = cache:get(RETRY_QUEUE_KEY)
        local retry_queue = {}
        if retry_queue_data then
            retry_queue = cjson.decode(retry_queue_data)
        end
        
        table.insert(retry_queue, log_entry)
        cache:set(RETRY_QUEUE_KEY, cjson.encode(retry_queue), 3600)
        
        return false, err
    end
    
    return true, nil
end

-- 处理重试队列
function _M.process_retry_queue()
    local retry_queue_data = cache:get(RETRY_QUEUE_KEY)
    if not retry_queue_data then
        return 0
    end
    
    local retry_queue = cjson.decode(retry_queue_data)
    local processed = 0
    
    for i = #retry_queue, 1, -1 do
        local log_entry = retry_queue[i]
        
        -- 检查是否应该重试（延迟重试）
        local delay = RETRY_DELAY * (2 ^ (log_entry.retry_count or 0))
        if ngx.time() - log_entry.timestamp < delay then
            -- 还没到重试时间
            goto continue
        end
        
        local ok, err = _M.retry_write(log_entry)
        if ok then
            table.remove(retry_queue, i)
            processed = processed + 1
        end
        
        ::continue::
    end
    
    if #retry_queue > 0 then
        cache:set(RETRY_QUEUE_KEY, cjson.encode(retry_queue), 3600)
    else
        cache:delete(RETRY_QUEUE_KEY)
    end
    
    return processed
end

-- 获取队列大小
function _M.get_queue_size()
    return cache:get(QUEUE_SIZE_KEY) or 0
end

-- 获取重试队列大小
function _M.get_retry_queue_size()
    local retry_queue_data = cache:get(RETRY_QUEUE_KEY)
    if retry_queue_data then
        local retry_queue = cjson.decode(retry_queue_data)
        return #retry_queue
    end
    return 0
end

return _M

