-- TOTP (Time-based One-Time Password) 模块
-- 路径：项目目录下的 lua/waf/totp.lua（保持在项目目录，不复制到系统目录）
-- 功能：实现 Google Authenticator 兼容的 TOTP 双因素认证
-- 参考：RFC 6238 (TOTP)

local _M = {}

-- Base32 编码表
local BASE32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

-- Base32 解码表
local BASE32_DECODE = {}
for i = 1, #BASE32_ALPHABET do
    BASE32_DECODE[string.sub(BASE32_ALPHABET, i, i)] = i - 1
end

-- Base32 编码
local function base32_encode(data)
    if not data or #data == 0 then
        return ""
    end
    
    local result = {}
    local bits = 0
    local value = 0
    
    for i = 1, #data do
        value = (value << 8) | string.byte(data, i)
        bits = bits + 8
        
        while bits >= 5 do
            local index = (value >> (bits - 5)) & 0x1F
            table.insert(result, string.sub(BASE32_ALPHABET, index + 1, index + 1))
            bits = bits - 5
        end
    end
    
    if bits > 0 then
        local index = (value << (5 - bits)) & 0x1F
        table.insert(result, string.sub(BASE32_ALPHABET, index + 1, index + 1))
    end
    
    return table.concat(result)
end

-- Base32 解码
local function base32_decode(encoded)
    if not encoded or #encoded == 0 then
        return ""
    end
    
    encoded = string.upper(encoded)
    local result = {}
    local bits = 0
    local value = 0
    
    for i = 1, #encoded do
        local char = string.sub(encoded, i, i)
        local index = BASE32_DECODE[char]
        
        if not index then
            -- 跳过无效字符（如空格、等号）
            if char ~= " " and char ~= "=" then
                return nil, "Invalid Base32 character: " .. char
            end
        else
            value = (value << 5) | index
            bits = bits + 5
            
            if bits >= 8 then
                local byte = (value >> (bits - 8)) & 0xFF
                table.insert(result, string.char(byte))
                bits = bits - 8
            end
        end
    end
    
    return table.concat(result)
end

-- HMAC-SHA1 实现（使用 OpenResty 的 resty.sha1）
local function hmac_sha1(key, message)
    -- 尝试使用 OpenResty 的 resty.sha1 模块
    local ok, sha1 = pcall(require, "resty.sha1")
    if not ok then
        ngx.log(ngx.ERR, "resty.sha1 not available, TOTP requires SHA1 support")
        return nil, "SHA1 not available. Please install lua-resty-openssl or ensure resty.sha1 is available"
    end
    
    -- HMAC-SHA1 实现
    local block_size = 64
    local opad = {}
    local ipad = {}
    
    -- 如果密钥长度超过块大小，先哈希
    if #key > block_size then
        local sha = sha1:new()
        sha:update(key)
        key = sha:final()
    end
    
    -- 填充密钥到块大小
    local padded_key = key
    while #padded_key < block_size do
        padded_key = padded_key .. string.char(0)
    end
    
    -- 创建 ipad 和 opad
    for i = 1, block_size do
        local byte = string.byte(padded_key, i) or 0
        table.insert(ipad, string.char(byte ~ 0x36))
        table.insert(opad, string.char(byte ~ 0x5C))
    end
    
    local ipad_str = table.concat(ipad)
    local opad_str = table.concat(opad)
    
    -- 计算 HMAC
    local sha1_obj = sha1:new()
    sha1_obj:update(ipad_str)
    sha1_obj:update(message)
    local hash1 = sha1_obj:final()
    
    local sha2_obj = sha1:new()
    sha2_obj:update(opad_str)
    sha2_obj:update(hash1)
    local hash2 = sha2_obj:final()
    
    return hash2
end

-- 生成 TOTP 代码
function _M.generate_totp(secret_base32, time_step, digits)
    time_step = time_step or 30  -- 默认 30 秒
    digits = digits or 6  -- 默认 6 位数字
    
    -- 解码 Base32 密钥
    local secret, err = base32_decode(secret_base32)
    if not secret then
        return nil, err or "Failed to decode secret"
    end
    
    -- 计算时间步数
    local current_time = ngx.time()
    local time_counter = math.floor(current_time / time_step)
    
    -- 将时间计数器转换为 8 字节大端序
    local time_bytes = {}
    for i = 7, 0, -1 do
        table.insert(time_bytes, string.char((time_counter >> (i * 8)) & 0xFF))
    end
    local time_str = table.concat(time_bytes)
    
    -- 计算 HMAC-SHA1
    local hmac, err = hmac_sha1(secret, time_str)
    if not hmac then
        return nil, err or "Failed to compute HMAC"
    end
    
    -- 动态截取（RFC 6238）
    local offset = (string.byte(hmac, #hmac) & 0x0F) + 1
    local binary = ((string.byte(hmac, offset) & 0x7F) << 24) |
                   ((string.byte(hmac, offset + 1) & 0xFF) << 16) |
                   ((string.byte(hmac, offset + 2) & 0xFF) << 8) |
                   (string.byte(hmac, offset + 3) & 0xFF)
    
    local otp = binary % (10 ^ digits)
    
    -- 格式化为指定位数
    return string.format("%0" .. digits .. "d", otp)
end

-- 验证 TOTP 代码
function _M.verify_totp(secret_base32, code, time_step, window)
    time_step = time_step or 30
    window = window or 1  -- 默认允许前后 1 个时间窗口
    
    -- 生成当前时间窗口的代码
    local current_code = _M.generate_totp(secret_base32, time_step, 6)
    if not current_code then
        return false, "Failed to generate TOTP"
    end
    
    -- 检查当前代码
    if current_code == code then
        return true
    end
    
    -- 检查前后时间窗口（允许时钟偏差）
    for i = -window, window do
        if i ~= 0 then
            local test_time = ngx.time() + (i * time_step)
            local test_counter = math.floor(test_time / time_step)
            
            -- 解码密钥
            local secret, err = base32_decode(secret_base32)
            if not secret then
                break
            end
            
            -- 计算时间步数
            local time_bytes = {}
            for j = 7, 0, -1 do
                table.insert(time_bytes, string.char((test_counter >> (j * 8)) & 0xFF))
            end
            local time_str = table.concat(time_bytes)
            
            -- 计算 HMAC
            local hmac, err = hmac_sha1(secret, time_str)
            if hmac then
                local offset = (string.byte(hmac, #hmac) & 0x0F) + 1
                local binary = ((string.byte(hmac, offset) & 0x7F) << 24) |
                               ((string.byte(hmac, offset + 1) & 0xFF) << 16) |
                               ((string.byte(hmac, offset + 2) & 0xFF) << 8) |
                               (string.byte(hmac, offset + 3) & 0xFF)
                
                local test_code = string.format("%06d", binary % 1000000)
                if test_code == code then
                    return true
                end
            end
        end
    end
    
    return false, "Invalid TOTP code"
end

-- 生成随机密钥（Base32 编码）
function _M.generate_secret(length)
    length = length or 16  -- 默认 16 字节（Base32 编码后约 26 字符）
    
    local random_bytes = {}
    for i = 1, length do
        table.insert(random_bytes, string.char(math.random(0, 255)))
    end
    
    local secret = table.concat(random_bytes)
    return base32_encode(secret)
end

-- 生成 QR 码 URL（用于 Google Authenticator）
-- 注意：内网部署时，建议使用前端 JavaScript QR 码库生成，不依赖外部服务
function _M.generate_qr_url(secret, username, issuer)
    local config = require "config"
    issuer = issuer or "WAF Management"
    username = username or "user"
    
    -- 构建 otpauth URL
    local otpauth_url = string.format(
        "otpauth://totp/%s:%s?secret=%s&issuer=%s&algorithm=SHA1&digits=6&period=30",
        ngx.escape_uri(issuer),
        ngx.escape_uri(username),
        secret,
        ngx.escape_uri(issuer)
    )
    
    -- 根据配置选择 QR 码生成方式
    local qr_generator = config.totp and config.totp.qr_generator or "local"
    
    if qr_generator == "external" then
        -- 使用外部服务生成 QR 码（需要外网访问）
        local external_url = config.totp and config.totp.external_qr_url or 
                            "https://api.qrserver.com/v1/create-qr-code/?size=200x200&data="
        local qr_url = external_url .. ngx.escape_uri(otpauth_url)
        return qr_url, otpauth_url
    else
        -- 本地模式：返回 nil，表示需要前端 JavaScript 生成 QR 码
        -- 前端可以使用 qrcode.js 等库生成 QR 码，无需外网访问
        return nil, otpauth_url
    end
end

-- 生成 QR 码数据（用于前端 JavaScript 生成）
function _M.generate_qr_data(secret, username, issuer)
    issuer = issuer or "WAF Management"
    username = username or "user"
    
    -- 构建 otpauth URL
    local otpauth_url = string.format(
        "otpauth://totp/%s:%s?secret=%s&issuer=%s&algorithm=SHA1&digits=6&period=30",
        issuer,
        username,
        secret,
        issuer
    )
    
    return {
        otpauth_url = otpauth_url,
        secret = secret,
        username = username,
        issuer = issuer
    }
end

-- 导出 Base32 函数（供其他模块使用）
_M.base32_encode = base32_encode
_M.base32_decode = base32_decode

return _M

