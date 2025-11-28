-- 缓存失效工具模块
-- 路径：项目目录下的 lua/waf/cache_invalidation.lua（保持在项目目录，不复制到系统目录）

local mysql_pool = require "waf.mysql_pool"
-- 注意：rule_notification 使用延迟加载，避免循环依赖
-- local rule_notification = require "waf.rule_notification"  -- 移到函数内部
local redis_cache = require "waf.redis_cache"
local config = require "config"

local _M = {}
local cache = ngx.shared.waf_cache

-- 增加规则版本号（触发缓存失效）
function _M.increment_rule_version()
    local sql = [[
        UPDATE waf_system_config
        SET config_value = CAST(config_value AS UNSIGNED) + 1
        WHERE config_key = 'rule_version'
    ]]

    local res, err = mysql_pool.query(sql)
    if err then
        ngx.log(ngx.ERR, "increment rule version error: ", err)
        return false, err
    end

    -- 清除版本号缓存
    cache:delete("rule_version:current")
    
    -- 注意：不在这里调用 rule_notification.notify_rule_update()
    -- 因为 rule_notification.notify_rule_update() 会调用 increment_rule_version()
    -- 这会导致循环调用和栈溢出
    -- 规则更新通知应该在调用 increment_rule_version() 之后由调用者处理
    
    ngx.log(ngx.INFO, "rule version incremented")
    return true, nil
end

-- 清除指定IP的所有缓存
function _M.invalidate_ip_cache(client_ip)
    if not client_ip then
        return false, "client_ip is required"
    end

    -- 清除封控规则缓存
    cache:delete("block_rules:single:" .. client_ip)
    cache:delete("block_rules:single:" .. client_ip .. ":rule")
    cache:delete("block_rules:range:" .. client_ip)
    cache:delete("block_rules:range:" .. client_ip .. ":rule")
    cache:delete("whitelist:" .. client_ip)
    cache:delete("freq_stats:" .. client_ip)
    cache:delete("auto_block:" .. client_ip)
    cache:delete("auto_block:" .. client_ip .. ":info")
    cache:delete("geo_block:geo:" .. client_ip)

    ngx.log(ngx.INFO, "cache invalidated for IP: ", client_ip)
    return true, nil
end

-- 清除规则列表缓存
function _M.invalidate_rule_list_cache()
    cache:delete("rule_list:ip_range:block")
    cache:delete("rule_list:ip_range:whitelist")
    
    -- 清除Redis缓存（失败不影响主流程）
    if redis_cache.is_available() then
        local ok1 = redis_cache.delete("rule_list:ip_range:block")
        local ok2 = redis_cache.delete("rule_list:ip_range:whitelist")
        if not ok1 or not ok2 then
            ngx.log(ngx.WARN, "Redis cache delete failed, but continuing with operation")
        end
    end
    
    ngx.log(ngx.INFO, "rule list cache invalidated")
    return true, nil
end

-- 清除所有缓存（谨慎使用）
function _M.invalidate_all_cache()
    -- 清除规则列表缓存
    _M.invalidate_rule_list_cache()
    
    -- 清除版本号缓存
    cache:delete("rule_version:current")
    
    -- 注意：无法清除所有IP的缓存（需要遍历），这里只清除关键缓存
    ngx.log(ngx.WARN, "all cache invalidated (partial)")
    return true, nil
end

return _M

