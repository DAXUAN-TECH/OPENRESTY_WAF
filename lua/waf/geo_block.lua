-- 地域封控模块
-- 路径：项目目录下的 lua/waf/geo_block.lua（保持在项目目录，不复制到系统目录）
-- 需要安装：opm get anjia0532/lua-resty-maxminddb
-- 支持：国家级别封控（国外）和省市级别封控（国内）

local config = require "config"
local ip_utils = require "waf.ip_utils"
local mysql_pool = require "waf.mysql_pool"

local _M = {}
local maxminddb = nil
local cache = ngx.shared.waf_cache
local CACHE_KEY_PREFIX = "geo_block:"
local CACHE_TTL = config.cache.ttl

-- 初始化 GeoIP2 数据库
local function init_geoip()
    if not config.geo.enable then
        return false
    end

    -- 检查是否已初始化
    if maxminddb then
        return true
    end

    -- 尝试加载 lua-resty-maxminddb
    local ok, mmdb = pcall(require, "resty.maxminddb")
    if not ok then
        ngx.log(ngx.ERR, "failed to load lua-resty-maxminddb, please install: opm get anjia0532/lua-resty-maxminddb")
        return false
    end

    -- 打开数据库文件
    local db, err = mmdb.new(config.geo.geoip_db_path)
    if not db then
        ngx.log(ngx.ERR, "failed to open GeoIP2 database: ", err)
        return false
    end

    maxminddb = db
    ngx.log(ngx.INFO, "GeoIP2 database loaded: ", config.geo.geoip_db_path)
    return true
end

-- 获取 IP 的地理位置信息（国家、省份、城市）
local function get_geo_info(ip)
    if not maxminddb then
        if not init_geoip() then
            return nil
        end
    end

    -- 从缓存获取
    local cache_key = CACHE_KEY_PREFIX .. "geo:" .. ip
    local cached = cache:get(cache_key)
    if cached then
        if cached == "" then
            return nil  -- 缓存空值表示未找到
        end
        local cjson = require "cjson"
        return cjson.decode(cached)
    end

    -- 查询数据库
    local res, err = maxminddb:lookup(ip)
    if not res or err then
        cache:set(cache_key, "", CACHE_TTL)  -- 缓存空值
        return nil
    end

    -- 提取地理位置信息
    local geo_info = {}
    
    -- 国家代码和名称
    if res.country then
        geo_info.country_code = res.country.iso_code
        geo_info.country_name = res.country.names and (res.country.names["zh-CN"] or res.country.names.en) or nil
    end
    
    -- 省份/州（subdivisions）
    if res.subdivisions and #res.subdivisions > 0 then
        local subdivision = res.subdivisions[1]  -- 取第一个（通常是省份）
        geo_info.region_code = subdivision.iso_code
        geo_info.region_name = subdivision.names and (subdivision.names["zh-CN"] or subdivision.names.en) or nil
    end
    
    -- 城市
    if res.city then
        geo_info.city_name = res.city.names and (res.city.names["zh-CN"] or res.city.names.en) or nil
    end

    -- 缓存结果
    if geo_info.country_code then
        local cjson = require "cjson"
        cache:set(cache_key, cjson.encode(geo_info), CACHE_TTL)
    else
        cache:set(cache_key, "", CACHE_TTL)  -- 缓存空值
    end

    return geo_info
end

-- 构建地域匹配值
-- 格式：国家代码（如 CN, US）或 国家代码:省份名称（如 CN:Beijing, CN:Shanghai）
local function build_geo_value(geo_info)
    if not geo_info or not geo_info.country_code then
        return nil
    end
    
    local country_code = geo_info.country_code
    
    -- 如果是中国，且有关键信息，构建省市格式
    if country_code == "CN" and geo_info.region_name then
        -- 格式：CN:省份名称 或 CN:省份名称:城市名称
        local value = country_code .. ":" .. geo_info.region_name
        if geo_info.city_name then
            value = value .. ":" .. geo_info.city_name
        end
        return value
    end
    
    -- 其他国家只返回国家代码
    return country_code
end

-- 检查地域封控
-- 支持匹配规则：
-- 1. 国家级别：CN, US, JP 等
-- 2. 国内省市：CN:Beijing, CN:Shanghai, CN:Guangdong 等
-- 3. 国内城市：CN:Beijing:Beijing, CN:Shanghai:Shanghai 等（精确到城市）
function _M.check(client_ip)
    if not config.geo.enable then
        return false, nil
    end

    -- 初始化数据库（如果未初始化）
    if not maxminddb then
        if not init_geoip() then
            return false, nil
        end
    end

    -- 获取 IP 的地理位置信息
    local geo_info = get_geo_info(client_ip)
    if not geo_info or not geo_info.country_code then
        return false, nil
    end

    local country_code = geo_info.country_code
    
    -- 构建匹配值列表（从精确到模糊）
    local match_values = {}
    
    -- 如果是中国，构建省市匹配值
    if country_code == "CN" then
        -- 1. 最精确：国家:省份:城市（如 CN:Beijing:Beijing）
        if geo_info.region_name and geo_info.city_name then
            table.insert(match_values, country_code .. ":" .. geo_info.region_name .. ":" .. geo_info.city_name)
        end
        
        -- 2. 省份级别：国家:省份（如 CN:Beijing）
        if geo_info.region_name then
            table.insert(match_values, country_code .. ":" .. geo_info.region_name)
        end
        
        -- 3. 国家级别：CN
        table.insert(match_values, country_code)
    else
        -- 其他国家只匹配国家代码
        table.insert(match_values, country_code)
    end

    -- 按优先级查询匹配规则（从精确到模糊）
    for _, match_value in ipairs(match_values) do
        local cache_key = CACHE_KEY_PREFIX .. "rule:" .. match_value
        local cached = cache:get(cache_key)
        
        if cached ~= nil then
            if cached == "1" then
                -- 从另一个缓存获取规则信息
                local rule_cache_key = cache_key .. ":data"
                local rule_data = cache:get(rule_cache_key)
                if rule_data then
                    local cjson = require "cjson"
                    return true, cjson.decode(rule_data)
                end
                -- 如果规则数据不存在，继续查询数据库获取规则信息
            elseif cached == "0" then
                -- 已确认无匹配，继续下一个
            end
        else
            -- 查询数据库
            local sql = [[
                SELECT id, rule_name, rule_value, priority FROM waf_block_rules 
                WHERE status = 1 
                AND rule_type = 'geo'
                AND rule_value = ?
                AND (start_time IS NULL OR start_time <= NOW())
                AND (end_time IS NULL OR end_time >= NOW())
                ORDER BY priority DESC
                LIMIT 1
            ]]

            local res, err = mysql_pool.query(sql, match_value)
            if err then
                ngx.log(ngx.ERR, "geo block query error: ", err)
                -- 继续下一个匹配值
            elseif res and #res > 0 then
                -- 匹配到规则
                local rule = res[1]
                cache:set(cache_key, "1", CACHE_TTL)
                local cjson = require "cjson"
                cache:set(cache_key .. ":data", cjson.encode({id = rule.id, rule_name = rule.rule_name}), CACHE_TTL)
                
                return true, rule
            else
                -- 无匹配，缓存结果
                cache:set(cache_key, "0", CACHE_TTL)
            end
        end
    end

    -- 所有匹配值都未匹配到规则
    return false, nil
end

-- 获取 IP 的地理位置信息（用于调试和查询）
function _M.get_geo_info(ip)
    return get_geo_info(ip)
end

-- 获取 IP 的完整地理位置信息（包含更多字段）
function _M.get_full_geo_info(ip)
    if not config.geo.enable then
        return nil
    end

    if not maxminddb then
        if not init_geoip() then
            return nil
        end
    end

    local res, err = maxminddb:lookup(ip)
    if not res or err then
        return nil
    end

    local geo_info = {}
    
    -- 国家信息
    if res.country then
        geo_info.country_code = res.country.iso_code
        geo_info.country_name = res.country.names and (res.country.names["zh-CN"] or res.country.names.en) or nil
    end
    
    -- 省份/州信息
    if res.subdivisions and #res.subdivisions > 0 then
        local subdivision = res.subdivisions[1]
        geo_info.region_code = subdivision.iso_code
        geo_info.region_name = subdivision.names and (subdivision.names["zh-CN"] or subdivision.names.en) or nil
    end
    
    -- 城市信息
    if res.city then
        geo_info.city_name = res.city.names and (res.city.names["zh-CN"] or res.city.names.en) or nil
    end
    
    -- 大洲信息
    if res.continent then
        geo_info.continent_code = res.continent.code
        geo_info.continent_name = res.continent.names and (res.continent.names["zh-CN"] or res.continent.names.en) or nil
    end
    
    -- 经纬度（如果可用）
    if res.location then
        geo_info.latitude = res.location.latitude
        geo_info.longitude = res.location.longitude
    end

    return geo_info
end

return _M

