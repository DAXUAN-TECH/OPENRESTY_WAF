-- 数据库健康检查模块
-- 路径：项目目录下的 lua/waf/health_check.lua（保持在项目目录，不复制到系统目录）

local mysql_pool = require "waf.mysql_pool"
local config = require "config"
local cjson = require "cjson"

local _M = {}
local cache = ngx.shared.waf_cache
local HEALTH_CHECK_KEY = "db_health_status"
local HEALTH_CHECK_TTL = 10  -- 健康检查结果缓存10秒
local FAILURE_THRESHOLD = 3  -- 连续失败3次后标记为故障
local SUCCESS_THRESHOLD = 2  -- 连续成功2次后恢复

-- 检查数据库健康状态
function _M.check_health()
    local health_status = cache:get(HEALTH_CHECK_KEY)
    if health_status then
        local ok, status = pcall(function()
            return cjson.decode(health_status)
        end)
        if ok and status then
            -- 如果最近检查过且状态正常，直接返回
            if status.status == "healthy" and status.last_check_time then
                local now = ngx.time()
                if now - status.last_check_time < HEALTH_CHECK_TTL then
                    return true, status
                end
            end
        end
    end

    -- 执行健康检查
    local sql = "SELECT 1 as health_check"
    local res, err = mysql_pool.query(sql)
    
    local now = ngx.time()
    local status = {
        status = "healthy",
        last_check_time = now,
        failure_count = 0,
        success_count = 0
    }

    if err or not res then
        -- 查询失败
        local cached_status = cache:get(HEALTH_CHECK_KEY)
        if cached_status then
            local ok, old_status = pcall(function()
                return cjson.decode(cached_status)
            end)
            if ok and old_status then
                status.failure_count = (old_status.failure_count or 0) + 1
                status.success_count = 0
            else
                status.failure_count = 1
            end
        else
            status.failure_count = 1
        end

        if status.failure_count >= FAILURE_THRESHOLD then
            status.status = "unhealthy"
            ngx.log(ngx.WARN, "database health check failed, marking as unhealthy (failure_count: ", status.failure_count, ")")
        end
    else
        -- 查询成功
        local cached_status = cache:get(HEALTH_CHECK_KEY)
        if cached_status then
            local ok, old_status = pcall(function()
                return cjson.decode(cached_status)
            end)
            if ok and old_status then
                if old_status.status == "unhealthy" then
                    status.success_count = (old_status.success_count or 0) + 1
                    if status.success_count >= SUCCESS_THRESHOLD then
                        status.status = "healthy"
                        ngx.log(ngx.INFO, "database health check recovered, marking as healthy")
                    else
                        status.status = "unhealthy"
                    end
                else
                    status.success_count = 0
                    status.failure_count = 0
                end
            end
        end
    end

    -- 缓存健康状态
    cache:set(HEALTH_CHECK_KEY, cjson.encode(status), HEALTH_CHECK_TTL * 2)
    
    return status.status == "healthy", status
end

-- 获取当前健康状态（不执行检查）
function _M.get_status()
    local health_status = cache:get(HEALTH_CHECK_KEY)
    if health_status then
        local ok, status = pcall(function()
            return cjson.decode(health_status)
        end)
        if ok and status then
            return status.status == "healthy", status
        end
    end
    return true, {status = "unknown"}  -- 未知状态，默认认为健康
end

-- 强制标记为健康（用于手动恢复）
function _M.mark_healthy()
    local status = {
        status = "healthy",
        last_check_time = ngx.time(),
        failure_count = 0,
        success_count = 0
    }
    cache:set(HEALTH_CHECK_KEY, cjson.encode(status), HEALTH_CHECK_TTL * 2)
    return true
end

-- 强制标记为不健康（用于测试）
function _M.mark_unhealthy()
    local status = {
        status = "unhealthy",
        last_check_time = ngx.time(),
        failure_count = FAILURE_THRESHOLD,
        success_count = 0
    }
    cache:set(HEALTH_CHECK_KEY, cjson.encode(status), HEALTH_CHECK_TTL * 2)
    return true
end

return _M

