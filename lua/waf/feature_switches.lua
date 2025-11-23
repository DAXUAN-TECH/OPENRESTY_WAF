-- 功能开关管理模块
-- 路径：项目目录下的 lua/waf/feature_switches.lua（保持在项目目录，不复制到系统目录）
-- 功能：从数据库读取功能开关配置，支持动态更新

local mysql_pool = require "waf.mysql_pool"
local config = require "config"
local cjson = require "cjson"

local _M = {}

-- 功能开关缓存（使用ngx.shared缓存）
local cache = ngx.shared.waf_cache
local CACHE_KEY_PREFIX = "feature_switch:"
local CACHE_TTL = 300  -- 缓存5分钟

-- 从数据库加载所有功能开关
local function load_from_database()
    local sql = [[
        SELECT feature_key, feature_name, description, enable, config_source
        FROM waf_feature_switches
        WHERE config_source = 'database'
    ]]
    
    local results, err = mysql_pool.query(sql)
    if err then
        ngx.log(ngx.ERR, "failed to load feature switches from database: ", err)
        return nil, err
    end
    
    local switches = {}
    if results then
        for _, row in ipairs(results) do
            switches[row.feature_key] = {
                feature_key = row.feature_key,
                feature_name = row.feature_name,
                description = row.description,
                enable = row.enable == 1,
                config_source = row.config_source
            }
            -- 更新缓存
            local cache_key = CACHE_KEY_PREFIX .. row.feature_key
            cache:set(cache_key, row.enable == 1 and "1" or "0", CACHE_TTL)
        end
    end
    
    return switches, nil
end

-- 从配置文件加载功能开关（作为默认值）
local function load_from_config()
    local switches = {}
    
    if config.features then
        for key, feature in pairs(config.features) do
            switches[key] = {
                feature_key = key,
                feature_name = key,
                description = feature.description or "",
                enable = feature.enable == true,
                config_source = "file"
            }
        end
    end
    
    return switches
end

-- 合并配置（数据库优先，配置文件作为默认值）
local function merge_switches(db_switches, config_switches)
    local merged = {}
    
    -- 先使用配置文件中的默认值
    for key, feature in pairs(config_switches) do
        merged[key] = feature
    end
    
    -- 用数据库中的配置覆盖（如果存在）
    if db_switches then
        for key, feature in pairs(db_switches) do
            merged[key] = feature
        end
    end
    
    return merged
end

-- 获取所有功能开关
function _M.get_all()
    -- 先从缓存获取
    local cache_key = CACHE_KEY_PREFIX .. "_all"
    local cached = cache:get(cache_key)
    if cached then
        local ok, switches = pcall(cjson.decode, cached)
        if ok and switches then
            return switches, nil
        end
    end
    
    -- 从数据库加载
    local db_switches, err = load_from_database()
    if err then
        -- 如果数据库加载失败，使用配置文件
        ngx.log(ngx.WARN, "failed to load from database, using config file: ", err)
        local config_switches = load_from_config()
        return config_switches, nil
    end
    
    -- 合并配置
    local config_switches = load_from_config()
    local merged = merge_switches(db_switches, config_switches)
    
    -- 更新缓存
    cache:set(cache_key, cjson.encode(merged), CACHE_TTL)
    
    return merged, nil
end

-- 获取单个功能开关状态
function _M.get(feature_key)
    if not feature_key then
        return nil, "feature_key is required"
    end
    
    -- 先从缓存获取
    local cache_key = CACHE_KEY_PREFIX .. feature_key
    local cached = cache:get(cache_key)
    if cached then
        return cached == "1", nil
    end
    
    -- 从数据库查询
    local sql = [[
        SELECT enable, config_source
        FROM waf_feature_switches
        WHERE feature_key = ? AND config_source = 'database'
        LIMIT 1
    ]]
    
    local results, err = mysql_pool.query(sql, feature_key)
    if err then
        ngx.log(ngx.ERR, "failed to get feature switch: ", err)
        -- 如果数据库查询失败，尝试从配置文件获取
        if config.features and config.features[feature_key] then
            local enable = config.features[feature_key].enable == true
            cache:set(cache_key, enable and "1" or "0", CACHE_TTL)
            return enable, nil
        end
        return nil, err
    end
    
    local enable = false
    if results and #results > 0 then
        enable = results[1].enable == 1
    else
        -- 如果数据库中没有，尝试从配置文件获取
        if config.features and config.features[feature_key] then
            enable = config.features[feature_key].enable == true
        end
    end
    
    -- 更新缓存
    cache:set(cache_key, enable and "1" or "0", CACHE_TTL)
    
    return enable, nil
end

-- 更新功能开关状态（写入数据库）
function _M.update(feature_key, enable)
    if not feature_key then
        return nil, "feature_key is required"
    end
    
    local enable_value = enable and 1 or 0
    
    -- 先检查是否存在
    local sql_check = [[
        SELECT id FROM waf_feature_switches WHERE feature_key = ? AND config_source = 'database'
    ]]
    local results, err = mysql_pool.query(sql_check, feature_key)
    if err then
        return nil, err
    end
    
    if results and #results > 0 then
        -- 更新
        local sql_update = [[
            UPDATE waf_feature_switches 
            SET enable = ?, updated_at = NOW()
            WHERE feature_key = ? AND config_source = 'database'
        ]]
        local ok, err = mysql_pool.query(sql_update, enable_value, feature_key)
        if err then
            return nil, err
        end
    else
        -- 插入（需要先获取功能名称和描述）
        local feature_name = feature_key
        local description = ""
        if config.features and config.features[feature_key] then
            feature_name = config.features[feature_key].feature_name or feature_key
            description = config.features[feature_key].description or ""
        end
        
        local sql_insert = [[
            INSERT INTO waf_feature_switches 
            (feature_key, feature_name, description, enable, config_source)
            VALUES (?, ?, ?, ?, 'database')
        ]]
        local ok, err = mysql_pool.query(sql_insert, feature_key, feature_name, description, enable_value)
        if err then
            return nil, err
        end
    end
    
    -- 清除缓存
    local cache_key = CACHE_KEY_PREFIX .. feature_key
    cache:delete(cache_key)
    cache:delete(CACHE_KEY_PREFIX .. "_all")
    
    return true, nil
end

-- 批量更新功能开关
function _M.batch_update(switches)
    if not switches or type(switches) ~= "table" then
        return nil, "switches array is required"
    end
    
    local updated = {}
    local errors = {}
    
    for _, switch in ipairs(switches) do
        local feature_key = switch.key or switch.feature_key
        local enable = switch.enable
        
        if not feature_key then
            table.insert(errors, "feature_key is required")
        else
            local ok, err = _M.update(feature_key, enable)
            if err then
                table.insert(errors, feature_key .. ": " .. err)
            else
                table.insert(updated, feature_key)
            end
        end
    end
    
    return {
        updated = updated,
        errors = #errors > 0 and errors or nil
    }, #errors > 0 and table.concat(errors, "; ") or nil
end

-- 检查功能是否启用（便捷函数）
function _M.is_enabled(feature_key)
    local enable, err = _M.get(feature_key)
    if err then
        ngx.log(ngx.WARN, "failed to check feature switch: ", feature_key, ", error: ", err)
        -- 出错时默认返回false（安全起见）
        return false
    end
    return enable == true
end

return _M

