-- TOTP (Time-based One-Time Password) 模块
-- 路径：项目目录下的 lua/waf/totp.lua（保持在项目目录，不复制到系统目录）
-- 功能：实现 Google Authenticator 兼容的 TOTP 双因素认证
-- 参考：RFC 6238 (TOTP)

-- 加载 bit 库（用于位运算）
local bit = bit
if not bit then
    local ok, bit_module = pcall(require, "bit")
    if ok and bit_module then
        bit = bit_module
    else
        -- 如果 bit 库不可用，使用数学运算替代
        bit = {
            lshift = function(x, n) return x * (2^n) end,
            rshift = function(x, n) return math.floor(x / (2^n)) end,
            band = function(x, y)
                -- 位与操作：使用数学运算实现
                local result = 0
                local power = 1
                local x_val = x
                local y_val = y
                for i = 1, 32 do
                    local x_bit = x_val % 2
                    local y_bit = y_val % 2
                    if x_bit == 1 and y_bit == 1 then
                        result = result + power
                    end
                    x_val = math.floor(x_val / 2)
                    y_val = math.floor(y_val / 2)
                    power = power * 2
                    if x_val == 0 and y_val == 0 then
                        break
                    end
                end
                return result
            end,
            bor = function(x, y)
                -- 位或操作：使用数学运算实现
                local result = 0
                local power = 1
                local x_val = x
                local y_val = y
                for i = 1, 32 do
                    local x_bit = x_val % 2
                    local y_bit = y_val % 2
                    if x_bit == 1 or y_bit == 1 then
                        result = result + power
                    end
                    x_val = math.floor(x_val / 2)
                    y_val = math.floor(y_val / 2)
                    power = power * 2
                    if x_val == 0 and y_val == 0 then
                        break
                    end
                end
                return result
            end,
            bxor = function(x, y)
                -- 异或操作：使用数学运算实现
                local result = 0
                local power = 1
                local x_val = x
                local y_val = y
                for i = 1, 32 do
                    local x_bit = x_val % 2
                    local y_bit = y_val % 2
                    if (x_bit == 1 and y_bit == 0) or (x_bit == 0 and y_bit == 1) then
                        result = result + power
                    end
                    x_val = math.floor(x_val / 2)
                    y_val = math.floor(y_val / 2)
                    power = power * 2
                    if x_val == 0 and y_val == 0 then
                        break
                    end
                end
                return result
            end
        }
    end
end

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
        value = bit.bor(bit.lshift(value, 8), string.byte(data, i))
        bits = bits + 8
        
        while bits >= 5 do
            local index = bit.band(bit.rshift(value, bits - 5), 0x1F)
            table.insert(result, string.sub(BASE32_ALPHABET, index + 1, index + 1))
            bits = bits - 5
        end
    end
    
    if bits > 0 then
        local index = bit.band(bit.lshift(value, 5 - bits), 0x1F)
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
            value = bit.bor(bit.lshift(value, 5), index)
            bits = bits + 5
            
            if bits >= 8 then
                local byte = bit.band(bit.rshift(value, bits - 8), 0xFF)
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
        table.insert(ipad, string.char(bit.bxor(byte, 0x36)))
        table.insert(opad, string.char(bit.bxor(byte, 0x5C)))
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
        table.insert(time_bytes, string.char(bit.band(bit.rshift(time_counter, i * 8), 0xFF)))
    end
    local time_str = table.concat(time_bytes)
    
    -- 计算 HMAC-SHA1
    local hmac, err = hmac_sha1(secret, time_str)
    if not hmac then
        return nil, err or "Failed to compute HMAC"
    end
    
    -- 动态截取（RFC 6238）
    local offset = bit.band(string.byte(hmac, #hmac), 0x0F) + 1
    local binary = bit.bor(
                   bit.lshift(bit.band(string.byte(hmac, offset), 0x7F), 24),
                   bit.lshift(bit.band(string.byte(hmac, offset + 1), 0xFF), 16),
                   bit.lshift(bit.band(string.byte(hmac, offset + 2), 0xFF), 8),
                   bit.band(string.byte(hmac, offset + 3), 0xFF))
    
    local otp = binary % (10 ^ digits)
    
    -- 格式化为指定位数
    return string.format("%0" .. digits .. "d", otp)
end

-- 验证 TOTP 代码
function _M.verify_totp(secret_base32, code, time_step, window)
    time_step = time_step or 30
    window = window or 1  -- 默认允许前后 1 个时间窗口
    
    -- 确保 code 是字符串类型
    if type(code) == "number" then
        code = tostring(code)
    end
    code = tostring(code)
    
    -- 清理验证码：只保留数字
    code = string.gsub(code, "%D", "")
    
    -- 验证验证码格式
    if not code or #code ~= 6 then
        ngx.log(ngx.WARN, "totp.verify_totp: invalid code format, code: ", code or "nil", ", length: ", code and #code or 0)
        return false, "Invalid code format"
    end
    
    -- 解码密钥（只解码一次，避免重复解码）
    local secret, err = base32_decode(secret_base32)
    if not secret then
        ngx.log(ngx.WARN, "totp.verify_totp: failed to decode secret, error: ", tostring(err))
        return false, "Invalid secret format"
    end
    
    -- 计算当前时间计数器
    local current_time = ngx.time()
    local current_counter = math.floor(current_time / time_step)
    
    ngx.log(ngx.DEBUG, "totp.verify_totp: current_time: ", current_time, ", time_step: ", time_step, ", current_counter: ", current_counter, ", window: ", window, ", code: ", code)
    
    -- 检查所有时间窗口（包括当前窗口和前后窗口）
    for i = -window, window do
        local test_counter = current_counter + i
        
        -- 计算时间步数
        local time_bytes = {}
        for j = 7, 0, -1 do
            table.insert(time_bytes, string.char(bit.band(bit.rshift(test_counter, j * 8), 0xFF)))
        end
        local time_str = table.concat(time_bytes)
        
        -- 计算 HMAC
        local hmac, hmac_err = hmac_sha1(secret, time_str)
        if not hmac then
            ngx.log(ngx.WARN, "totp.verify_totp: failed to compute HMAC for counter ", test_counter, ", error: ", tostring(hmac_err))
            -- 继续检查下一个窗口
        else
            -- 动态截取（RFC 6238）
            local offset = bit.band(string.byte(hmac, #hmac), 0x0F) + 1
            local binary = bit.bor(
                           bit.lshift(bit.band(string.byte(hmac, offset), 0x7F), 24),
                           bit.lshift(bit.band(string.byte(hmac, offset + 1), 0xFF), 16),
                           bit.lshift(bit.band(string.byte(hmac, offset + 2), 0xFF), 8),
                           bit.band(string.byte(hmac, offset + 3), 0xFF))
            
            local test_code = string.format("%06d", binary % 1000000)
            -- 确保 test_code 是字符串
            test_code = tostring(test_code)
            
            ngx.log(ngx.DEBUG, "totp.verify_totp: counter: ", test_counter, ", test_code: ", test_code, ", input_code: ", code, ", match: ", test_code == code)
            
            if test_code == code then
                ngx.log(ngx.INFO, "totp.verify_totp: TOTP code verified successfully, counter: ", test_counter, ", window offset: ", i)
                return true
            end
        end
    end
    
    ngx.log(ngx.WARN, "totp.verify_totp: TOTP code verification failed, code: ", code, ", checked windows: ", -window, " to ", window)
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

