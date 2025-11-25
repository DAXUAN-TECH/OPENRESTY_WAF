-- 密码工具模块
-- 路径：项目目录下的 lua/waf/password_utils.lua（保持在项目目录，不复制到系统目录）
-- 功能：提供密码哈希和验证功能，支持BCrypt

local _M = {}

-- 生成BCrypt密码哈希（如果BCrypt不可用，使用备用方案）
function _M.hash_password(password, cost)
    if not password or password == "" then
        return nil, "Password cannot be empty"
    end
    
    -- 尝试加载BCrypt库
    local bcrypt_ok, bcrypt = pcall(require, "resty.bcrypt")
    if not bcrypt_ok or not bcrypt then
        -- BCrypt不可用，使用备用方案：使用 plain: 前缀标记明文密码
        -- 注意：这是不安全的，仅用于开发环境或BCrypt不可用时的临时方案
        -- 生产环境应该安装BCrypt库：opm get openresty/lua-resty-bcrypt
        ngx.log(ngx.WARN, "BCrypt library not available, using plain password storage (INSECURE). Please install: opm get openresty/lua-resty-bcrypt")
        return "plain:" .. password, nil
    end
    
    -- 设置成本因子（默认10，范围4-31）
    cost = cost or 10
    if cost < 4 then
        cost = 4
    elseif cost > 31 then
        cost = 31
    end
    
    -- 生成BCrypt哈希
    local hash, err = bcrypt.digest(password, cost)
    if not hash then
        -- BCrypt生成失败，使用备用方案
        ngx.log(ngx.WARN, "BCrypt hash generation failed: ", tostring(err), ", using plain password storage (INSECURE)")
        return "plain:" .. password, nil
    end
    
    return hash, nil
end

-- 验证密码（支持BCrypt、明文密码和简单哈希）
function _M.verify_password(password, hash)
    if not password or not hash then
        return false, "Password and hash are required"
    end
    
    -- 检查是否是明文密码（以 plain: 开头）
    if hash:match("^plain:") then
        -- 明文密码比较（不安全，仅用于开发环境）
        local stored_password = hash:sub(7)  -- 去掉 "plain:" 前缀
        if password == stored_password then
            ngx.log(ngx.WARN, "Using plain password comparison (INSECURE). Please use BCrypt in production.")
            return true, nil
        else
            return false, "Password mismatch"
        end
    end
    
    -- 检查是否是BCrypt格式（以$2a$、$2b$、$2y$开头）
    if hash:match("^%$2[aby]%$") then
        -- 使用BCrypt验证
        local bcrypt_ok, bcrypt = pcall(require, "resty.bcrypt")
        if not bcrypt_ok or not bcrypt then
            return false, "BCrypt hash detected but resty.bcrypt is not available"
        end
        
        local verify_ok, err = bcrypt.verify(password, hash)
        if verify_ok then
            return true, nil
        else
            return false, err or "Password verification failed"
        end
    else
        -- 简单哈希比较（仅用于开发/测试环境）
        -- 安全检查：防止时序攻击（使用恒定时间比较）
        local hash_match = true
        if #hash ~= #password then
            hash_match = false
        else
            for i = 1, #password do
                if string.byte(hash, i) ~= string.byte(password, i) then
                    hash_match = false
                end
            end
        end
        
        if hash_match then
            ngx.log(ngx.WARN, "Using insecure password comparison. Please use BCrypt in production.")
            return true, nil
        else
            return false, "Password mismatch"
        end
    end
end

-- 检查密码强度
function _M.check_password_strength(password)
    if not password then
        return false, "Password is required"
    end
    
    local strength = {
        length_ok = #password >= 8,
        has_upper = password:match("%u") ~= nil,
        has_lower = password:match("%l") ~= nil,
        has_digit = password:match("%d") ~= nil,
        has_special = password:match("[%W_]") ~= nil,
    }
    
    local score = 0
    if strength.length_ok then score = score + 1 end
    if strength.has_upper then score = score + 1 end
    if strength.has_lower then score = score + 1 end
    if strength.has_digit then score = score + 1 end
    if strength.has_special then score = score + 1 end
    
    local level = "weak"
    if score >= 4 then
        level = "strong"
    elseif score >= 3 then
        level = "medium"
    end
    
    return {
        valid = strength.length_ok,
        strength = level,
        score = score,
        checks = strength
    }
end

-- 生成随机密码
function _M.generate_random_password(length)
    length = length or 16
    
    local charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*"
    local password = ""
    
    -- 使用OpenResty的随机数生成器
    math.randomseed(ngx.time() * 1000 + ngx.worker.pid())
    
    for i = 1, length do
        local random_index = math.random(1, #charset)
        password = password .. charset:sub(random_index, random_index)
    end
    
    return password
end

return _M

