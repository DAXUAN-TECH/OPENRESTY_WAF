-- CSRF 防护模块
-- 路径：项目目录下的 lua/waf/csrf.lua（保持在项目目录，不复制到系统目录）
-- 功能：生成和验证CSRF Token，防止跨站请求伪造攻击

local cjson = require "cjson"
local mysql_pool = require "waf.mysql_pool"
local config_manager = require "waf.config_manager"
local auth = require "waf.auth"

local _M = {}
local cache = ngx.shared.waf_cache
local CSRF_CACHE_PREFIX = "csrf:"
local CSRF_CACHE_TTL = tonumber(config_manager.get_config("csrf_token_ttl", 3600, "number")) or 3600  -- Token过期时间（秒，默认1小时）
local CSRF_ENABLED = config_manager.get_config("csrf_enable", true, "boolean")

-- 生成CSRF Token
local function generate_csrf_token()
    -- 使用时间戳 + 随机数 + IP地址生成唯一Token
    local timestamp = ngx.time()
    local random_num1 = math.random(1000000, 9999999)
    local random_num2 = math.random(1000000, 9999999)
    local remote_addr = ngx.var.remote_addr or "0.0.0.0"
    
    -- 组合生成唯一字符串
    local raw_string = timestamp .. ":" .. random_num1 .. ":" .. random_num2 .. ":" .. remote_addr
    
    -- 使用MD5哈希
    local token = ngx.md5(raw_string)
    
    return token
end

-- 生成并保存CSRF Token
function _M.generate_token(user_id)
    if not CSRF_ENABLED then
        return nil
    end
    
    if not user_id then
        local authenticated, session = auth.is_authenticated()
        if not authenticated then
            ngx.log(ngx.DEBUG, "csrf.generate_token: user not authenticated")
            return nil
        end
        -- 从会话中获取用户ID（优先使用 user_id，如果没有则使用 username）
        user_id = session.user_id or session.username
        
        if not user_id then
            ngx.log(ngx.ERR, "csrf.generate_token: session has no user_id or username, session: ", cjson.encode(session))
            return nil
        end
        
        -- 如果 user_id 是字符串（可能是 username），需要转换为用户ID
        if type(user_id) == "string" then
            -- 从数据库查询用户ID
            local ok, user_res = pcall(function()
                local sql = [[
                    SELECT id FROM waf_users WHERE username = ? LIMIT 1
                ]]
                return mysql_pool.query(sql, user_id)
            end)
            if ok and user_res and #user_res > 0 then
                user_id = user_res[1].id
            else
                -- 如果查询失败，记录错误但不保存到数据库
                ngx.log(ngx.ERR, "csrf.generate_token: failed to get user_id for username: ", user_id)
                return nil
            end
        end
    end
    
    -- 确保 user_id 是数字
    if type(user_id) ~= "number" then
        user_id = tonumber(user_id)
        if not user_id then
            ngx.log(ngx.ERR, "csrf.generate_token: invalid user_id type: ", type(user_id), ", value: ", tostring(user_id))
            return nil
        end
    end
    
    local token = generate_csrf_token()
    local expires_at = ngx.time() + CSRF_CACHE_TTL
    
    -- 保存到缓存（快速访问）
    local cache_key = CSRF_CACHE_PREFIX .. token
    local token_data = {
        user_id = user_id,
        expires_at = expires_at
    }
    cache:set(cache_key, cjson.encode(token_data), CSRF_CACHE_TTL)
    
    -- 保存到数据库（持久化）
    -- 先验证user_id是否存在，防止外键约束失败
    pcall(function()
        -- 验证user_id是否存在
        local check_sql = "SELECT id FROM waf_users WHERE id = ? LIMIT 1"
        local check_res, check_err = mysql_pool.query(check_sql, user_id)
        if not check_res or #check_res == 0 then
            -- user_id不存在，记录警告但不保存到数据库
            ngx.log(ngx.WARN, "csrf.generate_token: user_id ", user_id, " not found in waf_users, skipping database save")
            return
        end
        
        local sql = [[
            INSERT INTO waf_csrf_tokens (user_id, token, expires_at)
            VALUES (?, ?, FROM_UNIXTIME(?))
            ON DUPLICATE KEY UPDATE
                expires_at = FROM_UNIXTIME(?),
                created_at = CURRENT_TIMESTAMP
        ]]
        mysql_pool.query(sql, user_id, token, expires_at, expires_at)
    end)
    
    return token
end

-- 验证CSRF Token
function _M.verify_token(token, user_id)
    if not CSRF_ENABLED then
        return true
    end
    
    if not token or token == "" then
        return false, "CSRF token missing"
    end
    
    -- 从缓存获取
    local cache_key = CSRF_CACHE_PREFIX .. token
    local cached_data = cache:get(cache_key)
    
    if cached_data then
        local ok, token_data = pcall(cjson.decode, cached_data)
        if ok and token_data then
            -- 检查是否过期
            if token_data.expires_at > ngx.time() then
                -- 验证用户ID（如果提供）
                if user_id and token_data.user_id ~= user_id then
                    return false, "CSRF token user mismatch"
                end
                return true
            end
        end
    end
    
    -- 从数据库获取
    local ok, res = pcall(function()
        local sql = [[
            SELECT user_id, UNIX_TIMESTAMP(expires_at) as expires_at_ts
            FROM waf_csrf_tokens
            WHERE token = ?
            AND expires_at > NOW()
            LIMIT 1
        ]]
        return mysql_pool.query(sql, token)
    end)
    
    if ok and res and #res > 0 then
        local token_data = res[1]
        -- 再次验证过期时间（双重检查）
        if token_data.expires_at_ts and token_data.expires_at_ts > ngx.time() then
            -- 验证用户ID（如果提供）
            if user_id and token_data.user_id ~= user_id then
                return false, "CSRF token user mismatch"
            end
            return true
        end
    end
    
    return false, "CSRF token invalid or expired"
end

-- 从请求中获取CSRF Token（支持Header和Form参数）
function _M.get_token_from_request()
    -- 优先从Header获取
    local token = ngx.req.get_headers()["X-CSRF-Token"]
    if token then
        return token
    end
    
    -- 从Form参数获取
    ngx.req.read_body()
    local args = ngx.req.get_post_args()
    if args and args.csrf_token then
        return args.csrf_token
    end
    
    return nil
end

-- 清理过期的Token（定时任务调用）
function _M.cleanup_expired_tokens()
    pcall(function()
        local sql = [[
            DELETE FROM waf_csrf_tokens
            WHERE expires_at < NOW()
        ]]
        mysql_pool.query(sql)
    end)
end

-- 检查是否需要CSRF验证（GET、HEAD、OPTIONS通常不需要）
function _M.requires_csrf(method)
    if not CSRF_ENABLED then
        return false
    end
    
    local safe_methods = {
        GET = true,
        HEAD = true,
        OPTIONS = true
    }
    
    return not safe_methods[method]
end

return _M

