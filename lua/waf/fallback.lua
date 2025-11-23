-- 降级机制模块
-- 路径：项目目录下的 lua/waf/fallback.lua（保持在项目目录，不复制到系统目录）

local health_check = require "waf.health_check"
local rule_backup = require "waf.rule_backup"
local config = require "config"
local cjson = require "cjson"

local _M = {}
local cache = ngx.shared.waf_cache

-- 降级模式配置
local FALLBACK_MODE_KEY = "fallback_mode"
local FALLBACK_ENABLED = config.fallback and config.fallback.enable or true

-- 检查是否应该使用降级模式
function _M.should_fallback()
    if not FALLBACK_ENABLED then
        return false
    end

    local is_healthy, status = health_check.get_status()
    local should_fallback = not is_healthy
    
    -- 如果数据库故障且没有缓存规则，尝试从备份加载
    if should_fallback then
        local has_rules = cache:get("rule_list:ip_range:block")
        if not has_rules and rule_backup.has_backup() then
            ngx.log(ngx.WARN, "database unavailable, loading rules from backup")
            rule_backup.load_rules_from_backup()
        end
    end
    
    return should_fallback
end

-- 从缓存获取封控规则（降级模式）
function _M.get_block_rule_from_cache(client_ip, rule_type)
    if rule_type == "single_ip" then
        local cache_key = "block_rules:single:" .. client_ip
        local cached = cache:get(cache_key)
        if cached == "1" then
            local rule_cache_key = cache_key .. ":rule"
            local rule_data = cache:get(rule_cache_key)
            if rule_data then
                local ok, rule = pcall(function()
                    return cjson.decode(rule_data)
                end)
                if ok and rule then
                    return true, rule
                end
            end
        end
    elseif rule_type == "ip_range" then
        local cache_key = "block_rules:range:" .. client_ip
        local cached = cache:get(cache_key)
        if cached == "1" then
            local rule_cache_key = cache_key .. ":rule"
            local rule_data = cache:get(rule_cache_key)
            if rule_data then
                local ok, rule = pcall(function()
                    return cjson.decode(rule_data)
                end)
                if ok and rule then
                    return true, rule
                end
            end
        end
    end
    
    return false, nil
end

-- 从缓存获取白名单（降级模式）
function _M.get_whitelist_from_cache(client_ip)
    local cache_key = "whitelist:" .. client_ip
    local cached = cache:get(cache_key)
    if cached ~= nil then
        return cached == "1"
    end
    return false
end

-- 记录降级模式使用日志
function _M.log_fallback_usage(reason)
    ngx.log(ngx.WARN, "fallback mode activated: ", reason or "database unavailable")
end

return _M

