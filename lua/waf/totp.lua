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
        local hashed_key = sha:final()
        -- resty.sha1 的 final() 通常返回二进制字符串（20字节），但也可能返回十六进制字符串（40字符）
        -- 检查是否是十六进制字符串（长度为40，只包含0-9a-fA-F）
        if type(hashed_key) == "string" and #hashed_key == 40 and string.match(hashed_key, "^[0-9a-fA-F]+$") then
            -- 转换为二进制字符串
            local binary_key = ""
            for i = 1, 40, 2 do
                local hex_byte = string.sub(hashed_key, i, i + 1)
                local byte_value = tonumber(hex_byte, 16)
                if byte_value then
                    binary_key = binary_key .. string.char(byte_value)
                end
            end
            key = binary_key
        elseif type(hashed_key) == "string" and #hashed_key == 20 then
            -- 已经是二进制字符串（20字节），直接使用
            key = hashed_key
        else
            -- 其他情况，直接使用（可能是其他格式）
            key = hashed_key
        end
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
    ngx.log(ngx.DEBUG, "hmac_sha1: hash1 type: ", type(hash1), ", length: ", hash1 and #hash1 or 0)
    
    -- resty.sha1 的 final() 通常返回二进制字符串（20字节），但也可能返回十六进制字符串（40字符）
    -- 检查是否是十六进制字符串（长度为40，只包含0-9a-fA-F）
    if type(hash1) == "string" and #hash1 == 40 and string.match(hash1, "^[0-9a-fA-F]+$") then
        -- 转换为二进制字符串
        local binary_hash1 = ""
        for i = 1, 40, 2 do
            local hex_byte = string.sub(hash1, i, i + 1)
            local byte_value = tonumber(hex_byte, 16)
            if byte_value then
                binary_hash1 = binary_hash1 .. string.char(byte_value)
            end
        end
        hash1 = binary_hash1
    elseif type(hash1) == "string" and #hash1 ~= 20 then
        -- 如果不是20字节，记录警告
        ngx.log(ngx.WARN, "hmac_sha1: hash1 length is ", #hash1, ", expected 20 bytes (binary) or 40 chars (hex)")
    end
    
    local sha2_obj = sha1:new()
    sha2_obj:update(opad_str)
    sha2_obj:update(hash1)
    local hash2 = sha2_obj:final()
    ngx.log(ngx.DEBUG, "hmac_sha1: hash2 type: ", type(hash2), ", length: ", hash2 and #hash2 or 0, ", before conversion")
    
    -- 同样检查 hash2 是否是十六进制字符串
    if type(hash2) == "string" and #hash2 == 40 and string.match(hash2, "^[0-9a-fA-F]+$") then
        -- 转换为二进制字符串
        local binary_hash2 = ""
        for i = 1, 40, 2 do
            local hex_byte = string.sub(hash2, i, i + 1)
            local byte_value = tonumber(hex_byte, 16)
            if byte_value then
                binary_hash2 = binary_hash2 .. string.char(byte_value)
            end
        end
        hash2 = binary_hash2
    elseif type(hash2) == "string" and #hash2 ~= 20 then
        -- 如果不是20字节，记录警告
        ngx.log(ngx.WARN, "hmac_sha1: hash2 length is ", #hash2, ", expected 20 bytes (binary) or 40 chars (hex)")
    end
    
    -- 验证最终结果长度
    if type(hash2) ~= "string" or (#hash2 ~= 20 and #hash2 ~= 40) then
        ngx.log(ngx.ERR, "hmac_sha1: invalid hash2 format, type: ", type(hash2), ", length: ", hash2 and #hash2 or 0)
        return nil, "Invalid HMAC result format"
    end
    
    ngx.log(ngx.DEBUG, "hmac_sha1: final hash2 length: ", #hash2, " bytes")
    return hash2
end

-- 生成 TOTP 代码
function _M.generate_totp(secret_base32, time_step, digits)
    time_step = time_step or 30  -- 默认 30 秒
    digits = digits or 6  -- 默认 6 位数字
    
    -- 解码 Base32 密钥
    local secret, err = base32_decode(secret_base32)
    if not secret then
        ngx.log(ngx.WARN, "totp.generate_totp: failed to decode secret_base32, error: ", tostring(err), ", secret_base32: ", string.sub(secret_base32, 1, 20), "...")
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
    ngx.log(ngx.INFO, "totp.verify_totp: decoding secret_base32, length: ", #secret_base32, ", prefix: ", string.sub(secret_base32, 1, 12), "...")
    local secret, err = base32_decode(secret_base32)
    if not secret then
        ngx.log(ngx.WARN, "totp.verify_totp: failed to decode secret, error: ", tostring(err), ", secret_base32: ", string.sub(secret_base32, 1, 20), "...")
        return false, "Invalid secret format"
    end
    ngx.log(ngx.INFO, "totp.verify_totp: secret decoded successfully, decoded length: ", #secret, " bytes")
    
    -- 计算当前时间计数器
    local current_time = ngx.time()
    local current_counter = math.floor(current_time / time_step)
    
    ngx.log(ngx.INFO, "totp.verify_totp: current_time: ", current_time, ", time_step: ", time_step, ", current_counter: ", current_counter, ", window: ", window, ", input_code: ", code)
    
    -- 收集所有窗口的代码用于调试
    local all_codes = {}
    
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
            table.insert(all_codes, string.format("counter[%d]=ERROR", test_counter))
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
            
            -- 记录每个窗口的代码
            table.insert(all_codes, string.format("counter[%d]=%s", test_counter, test_code))
            ngx.log(ngx.INFO, "totp.verify_totp: window[", i, "] counter: ", test_counter, ", generated_code: ", test_code, ", input_code: ", code, ", match: ", test_code == code)
            
            if test_code == code then
                ngx.log(ngx.INFO, "totp.verify_totp: TOTP code verified successfully, counter: ", test_counter, ", window offset: ", i)
                return true
            end
        end
    end
    
    -- 输出所有窗口的代码用于调试
    ngx.log(ngx.WARN, "totp.verify_totp: TOTP code verification failed, input_code: ", code, ", checked windows: ", -window, " to ", window, ", all_codes: ", table.concat(all_codes, ", "))
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

