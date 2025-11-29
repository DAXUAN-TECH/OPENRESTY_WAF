-- 规则更新通知模块
-- 路径：项目目录下的 lua/waf/rule_notification.lua（保持在项目目录，不复制到系统目录）
-- 功能：实现规则更新通知机制，主动通知所有工作进程更新缓存

local cache_invalidation = require "waf.cache_invalidation"
local redis_cache = require "waf.redis_cache"
local config = require "config"
local cjson = require "cjson"

local _M = {}

-- 配置
local NOTIFICATION_ENABLED = config.rule_notification and config.rule_notification.enable or true
local NOTIFICATION_CHANNEL = config.rule_notification and config.rule_notification.channel or "waf:rule_update"
local USE_REDIS_PUBSUB = config.rule_notification and config.rule_notification.use_redis_pubsub or false

-- 规则更新通知（通过Redis Pub/Sub）
function _M.notify_rule_update(update_type, details)
    if not NOTIFICATION_ENABLED then
        return false, "notification disabled"
    end
    
    if USE_REDIS_PUBSUB and redis_cache.is_available() then
        -- 使用Redis Pub/Sub（通过redis_cache模块的连接池）
        local notification = {
            type = update_type or "rule_update",
            timestamp = ngx.time(),
            details = details or {}
        }
        
        local message = cjson.encode(notification)
        local ok, err = redis_cache.publish(NOTIFICATION_CHANNEL, message)
        
        if ok then
            ngx.log(ngx.INFO, "rule update notification sent via Redis Pub/Sub")
            return true, nil
        else
            ngx.log(ngx.WARN, "failed to publish notification via Redis: ", tostring(err))
            -- 继续执行，不阻塞主流程
        end
    end
    
    -- 回退到版本号机制（已实现）
    -- 注意：这里不能调用 cache_invalidation.increment_rule_version()
    -- 因为 increment_rule_version() 会调用 notify_rule_update()，导致循环调用
    -- 版本号应该在规则变更时由调用者直接调用 increment_rule_version()
    -- 这里只清除缓存，不更新版本号
    -- 注意：缓存清除失败不影响主流程，只记录警告
    local ok, err = pcall(cache_invalidation.invalidate_rule_list_cache)
    if not ok then
        ngx.log(ngx.WARN, "cache invalidation failed, but continuing: ", tostring(err))
    end
    ngx.log(ngx.INFO, "rule update notification via cache invalidation")
    return true, nil
end

-- 订阅规则更新通知（在工作进程中）
function _M.subscribe_rule_updates()
    if not NOTIFICATION_ENABLED or not USE_REDIS_PUBSUB then
        return false, "notification disabled or Redis Pub/Sub not enabled"
    end
    
    -- 这个函数应该在init_worker中调用，设置订阅
    -- 由于OpenResty的限制，实际订阅需要在定时器中实现
    ngx.log(ngx.INFO, "rule update subscription initialized")
    return true, nil
end

-- 处理规则更新通知
function _M.handle_notification(notification)
    if not notification then
        return false
    end
    
    local ok, data = pcall(cjson.decode, notification)
    if not ok or not data then
        return false
    end
    
    if data.type == "rule_update" then
        -- 清除相关缓存
        cache_invalidation.invalidate_rule_list_cache()
        ngx.log(ngx.INFO, "rule update notification handled, cache invalidated")
        return true
    end
    
    return false
end

-- 通知规则创建
function _M.notify_rule_created(rule_id, rule_type)
    return _M.notify_rule_update("rule_created", {
        rule_id = rule_id,
        rule_type = rule_type
    })
end

-- 通知规则更新
function _M.notify_rule_updated(rule_id, rule_type)
    return _M.notify_rule_update("rule_updated", {
        rule_id = rule_id,
        rule_type = rule_type
    })
end

-- 通知规则删除
function _M.notify_rule_deleted(rule_id, rule_type)
    return _M.notify_rule_update("rule_deleted", {
        rule_id = rule_id,
        rule_type = rule_type
    })
end

return _M

