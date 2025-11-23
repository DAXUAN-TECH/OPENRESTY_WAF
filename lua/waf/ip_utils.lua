-- IP 工具函数
-- 路径：项目目录下的 lua/waf/ip_utils.lua（保持在项目目录，不复制到系统目录）

local _M = {}

-- 检查 bit 库是否可用（LuaJIT 内置）
local bit = bit
if not bit then
    -- 如果 bit 库不可用，尝试加载（OpenResty 中通常已内置）
    local ok, bit_module = pcall(require, "bit")
    if ok then
        bit = bit_module
    else
        error("bit library is required for CIDR matching")
    end
end

-- 检查IP是否为受信任代理
local function is_trusted_proxy(ip)
    local config = require "config"
    if not config.proxy or not config.proxy.enable_trusted_proxy_check then
        return true  -- 如果未启用检查，默认信任
    end

    local cache = ngx.shared.waf_cache
    local cache_key = "trusted_proxy:" .. ip
    local cached = cache:get(cache_key)
    if cached ~= nil then
        return cached == "1"
    end

    -- 查询数据库
    local mysql_pool = require "waf.mysql_pool"
    local sql = [[
        SELECT proxy_ip FROM waf_trusted_proxies 
        WHERE status = 1
    ]]
    
    local res, err = mysql_pool.query(sql)
    if err then
        ngx.log(ngx.ERR, "trusted proxy query error: ", err)
        return false
    end

    if res and #res > 0 then
        -- 检查IP是否匹配受信任代理列表
        for _, proxy in ipairs(res) do
            local proxy_ip = proxy.proxy_ip
            -- 检查CIDR格式
            if _M.match_cidr(ip, proxy_ip) then
                cache:set(cache_key, "1", config.proxy.trusted_proxies_cache_ttl or 300)
                return true
            end
            -- 检查精确匹配
            if ip == proxy_ip then
                cache:set(cache_key, "1", config.proxy.trusted_proxies_cache_ttl or 300)
                return true
            end
        end
    end

    cache:set(cache_key, "0", config.proxy.trusted_proxies_cache_ttl or 300)
    return false
end

-- 获取客户端真实 IP（增强安全性）
function _M.get_real_ip()
    local headers = ngx.req.get_headers()
    local config = require "config"
    
    -- 获取直接连接的客户端IP
    local direct_client_ip = ngx.var.remote_addr
    
    -- 如果启用了受信任代理检查，验证直接连接的IP是否为受信任代理
    local is_proxy = false
    if config.proxy and config.proxy.enable_trusted_proxy_check then
        is_proxy = is_trusted_proxy(direct_client_ip)
    else
        -- 如果未启用检查，检查是否为私有IP（可能是代理）
        local ip_version = _M.get_ip_version(direct_client_ip)
        if ip_version == 4 then
            local ip_int = _M.ipv4_to_int(direct_client_ip)
            if ip_int then
                -- 检查是否为私有IP（10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16）
                local a = math.floor(ip_int / (256^3))
                is_proxy = (a == 10) or 
                          (a == 172 and math.floor((ip_int % (256^3)) / (256^2)) >= 16 and math.floor((ip_int % (256^3)) / (256^2)) <= 31) or
                          (a == 192 and math.floor((ip_int % (256^3)) / (256^2)) == 168)
            end
        elseif ip_version == 6 then
            -- IPv6私有地址检查（fc00::/7 和 fe80::/10）
            local normalized = _M.normalize_ipv6(direct_client_ip)
            if normalized then
                local high, _ = _M.ipv6_to_int128(direct_client_ip)
                if high then
                    -- fc00::/7: 0xfc00 到 0xfdff
                    -- fe80::/10: 0xfe80 到 0xfebf
                    local first_word = math.floor(high / (65536^3))
                    is_proxy = (first_word >= 0xfc00 and first_word <= 0xfdff) or
                              (first_word >= 0xfe80 and first_word <= 0xfebf)
                end
            end
        end
    end
    
    -- 如果直接连接的IP是受信任代理，从X-Forwarded-For获取真实IP
    if is_proxy then
        local x_forwarded_for = headers["X-Forwarded-For"]
        if x_forwarded_for then
            -- X-Forwarded-For 安全性增强：
            -- 1. 只从最后一个受信任代理获取真实IP
            -- 2. 验证IP格式
            -- 3. 记录IP获取过程（调试模式）
            local ips = {}
            for ip in x_forwarded_for:gmatch("([^,]+)") do
                ip = ip:match("^%s*(.-)%s*$")  -- 去除首尾空格
                -- 验证IP格式（防止注入）
                if ip and ip ~= "" and _M.is_valid_ip(ip) then
                    -- 检查IP是否包含非法字符（额外安全检查）
                    if not ip:match("[^%d%.%:a-fA-F]") then
                        table.insert(ips, ip)
                    else
                        ngx.log(ngx.WARN, "X-Forwarded-For contains invalid characters: ", ip)
                    end
                end
            end
            
            if #ips > 0 then
                -- X-Forwarded-For安全性增强：
                -- 1. 如果启用了受信任代理检查，从后往前遍历IP列表
                -- 2. 找到最后一个受信任代理，取它后面的IP作为真实IP
                -- 3. 如果所有IP都来自受信任代理，取最后一个IP（最接近客户端）
                -- 4. 限制IP列表长度，防止DoS攻击
                local MAX_FORWARDED_IPS = 10  -- 最多处理10个IP
                if #ips > MAX_FORWARDED_IPS then
                    ngx.log(ngx.WARN, "X-Forwarded-For contains too many IPs (", #ips, "), truncating to ", MAX_FORWARDED_IPS)
                    -- 只保留最后MAX_FORWARDED_IPS个IP（最接近客户端的）
                    local truncated_ips = {}
                    for i = #ips - MAX_FORWARDED_IPS + 1, #ips do
                        table.insert(truncated_ips, ips[i])
                    end
                    ips = truncated_ips
                end
                
                local real_ip = nil
                if config.proxy and config.proxy.enable_trusted_proxy_check then
                    -- 从后往前遍历，找到最后一个受信任代理
                    local last_trusted_index = 0
                    local trusted_proxies_found = {}
                    
                    for i = #ips, 1, -1 do
                        if is_trusted_proxy(ips[i]) then
                            last_trusted_index = i
                            table.insert(trusted_proxies_found, 1, ips[i])
                            -- 找到第一个受信任代理后继续检查前面的IP
                            -- 如果前面的IP也是受信任代理，说明代理链还在继续
                        end
                    end
                    
                    if last_trusted_index > 0 and last_trusted_index < #ips then
                        -- 取最后一个受信任代理后面的IP（真实客户端IP）
                        real_ip = ips[last_trusted_index + 1]
                        
                        -- 记录详细的IP解析过程（调试模式）
                        if config.proxy and config.proxy.log_ip_resolution then
                            ngx.log(ngx.INFO, "X-Forwarded-For IP resolution: found ", #trusted_proxies_found, 
                                    " trusted proxy(ies), real IP: ", real_ip, 
                                    " (last trusted proxy: ", ips[last_trusted_index], 
                                    ", direct connection: ", direct_client_ip, ")")
                        end
                    elseif last_trusted_index == #ips then
                        -- 所有IP都来自受信任代理，取最后一个（最接近客户端）
                        real_ip = ips[#ips]
                        
                        if config.proxy and config.proxy.log_ip_resolution then
                            ngx.log(ngx.WARN, "X-Forwarded-For: all IPs are trusted proxies, using last IP: ", real_ip)
                        end
                    else
                        -- 没有找到受信任代理，但直接连接的IP是代理
                        -- 这可能表示X-Forwarded-For被伪造，使用直接连接的IP
                        ngx.log(ngx.WARN, "X-Forwarded-For: no trusted proxy found in IP list, but direct connection is proxy. Possible spoofing attempt.")
                        real_ip = nil  -- 返回nil，将使用直接连接的IP
                    end
                else
                    -- 未启用检查时，取第一个IP（最原始的客户端IP）
                    real_ip = ips[1]
                    
                    if config.proxy and config.proxy.log_ip_resolution then
                        ngx.log(ngx.INFO, "X-Forwarded-For IP resolution (trusted proxy check disabled): using first IP: ", real_ip)
                    end
                end
                
                -- 再次验证IP格式和安全性
                if real_ip then
                    -- 严格验证IP格式
                    if not _M.is_valid_ip(real_ip) then
                        ngx.log(ngx.WARN, "X-Forwarded-For: resolved IP failed validation: ", real_ip)
                        real_ip = nil
                    else
                        -- 检查是否为保留IP（可能被伪造）
                        local ip_version = _M.get_ip_version(real_ip)
                        if ip_version == 4 then
                            local ip_int = _M.ipv4_to_int(real_ip)
                            if ip_int then
                                -- 检查是否为回环地址、多播地址等
                                local a = math.floor(ip_int / (256^3))
                                if a == 127 or a == 224 or (a >= 240 and a <= 255) then
                                    ngx.log(ngx.WARN, "X-Forwarded-For: resolved IP is reserved address: ", real_ip)
                                end
                            end
                        end
                        
                        -- 记录IP获取过程（调试模式）
                        if config.proxy and config.proxy.log_ip_resolution then
                            ngx.log(ngx.INFO, "Resolved real IP from X-Forwarded-For: ", real_ip, 
                                    " (from proxy: ", direct_client_ip, ", total IPs: ", #ips, 
                                    ", trusted proxy check: ", (config.proxy and config.proxy.enable_trusted_proxy_check) and "enabled" or "disabled", ")")
                        end
                        return real_ip
                    end
                end
            end
        end
        
        -- 检查 X-Real-IP（优先级低于 X-Forwarded-For）
        local x_real_ip = headers["X-Real-IP"]
        if x_real_ip then
            -- 验证IP格式
            x_real_ip = x_real_ip:match("^%s*(.-)%s*$")  -- 去除首尾空格
            if x_real_ip and _M.is_valid_ip(x_real_ip) and not x_real_ip:match("[^%d%.%:a-fA-F]") then
                if config.proxy and config.proxy.log_ip_resolution then
                    ngx.log(ngx.INFO, "Resolved real IP from X-Real-IP: ", x_real_ip, 
                            " (from proxy: ", direct_client_ip, ")")
                end
                return x_real_ip
            end
        end
    end
    
    -- 如果直接连接的IP不是代理，或未找到代理头，使用直接连接的IP
    if _M.is_valid_ip(direct_client_ip) then
        return direct_client_ip
    end
    
    -- 如果都不合法，返回nil
    ngx.log(ngx.WARN, "invalid client IP: ", direct_client_ip)
    return nil
end

-- IPv4 转整数
function _M.ipv4_to_int(ip)
    local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then
        return nil
    end
    a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
    if a > 255 or b > 255 or c > 255 or d > 255 then
        return nil
    end
    return a * 256^3 + b * 256^2 + c * 256 + d
end

-- 整数转 IPv4
function _M.int_to_ipv4(int)
    local d = int % 256
    int = math.floor(int / 256)
    local c = int % 256
    int = math.floor(int / 256)
    local b = int % 256
    int = math.floor(int / 256)
    local a = int % 256
    return string.format("%d.%d.%d.%d", a, b, c, d)
end

-- 注意：match_cidr、match_ip_range 和 parse_ip_range 函数在文件后面定义（支持IPv4和IPv6）

-- IPv6 地址规范化（展开压缩格式）
-- 将压缩的IPv6地址展开为完整格式
function _M.normalize_ipv6(ip)
    if not ip or ip == "" then
        return nil
    end
    
    -- 处理IPv4映射的IPv6地址（::ffff:192.168.1.1 或 ::ffff:0:192.168.1.1）
    local ipv4_part = ip:match(":(%d+%.%d+%.%d+%.%d+)$")
    if ipv4_part then
        local ipv4_int = _M.ipv4_to_int(ipv4_part)
        if ipv4_int then
            -- 提取IPv6前缀部分
            local prefix = ip:match("^(.+):" .. ipv4_part:gsub("%.", "%%.") .. "$")
            if prefix then
                -- 将IPv4部分转换为两个16位十六进制数
                local high16 = math.floor(ipv4_int / 65536)
                local low16 = ipv4_int % 65536
                
                -- 处理前缀中的双冒号
                if prefix:match("::$") then
                    -- 前缀以::结尾
                    prefix = prefix:gsub("::$", "")
                    local prefix_parts = {}
                    if prefix ~= "" then
                        for part in prefix:gmatch("([^:]+)") do
                            table.insert(prefix_parts, part)
                        end
                    end
                    
                    -- 计算需要填充的零组数量
                    local zero_groups = 6 - #prefix_parts
                    local parts = {}
                    for _, part in ipairs(prefix_parts) do
                        table.insert(parts, part)
                    end
                    for i = 1, zero_groups do
                        table.insert(parts, "0")
                    end
                    table.insert(parts, string.format("%04x", high16))
                    table.insert(parts, string.format("%04x", low16))
                    
                    -- 规范化每个部分
                    local normalized_parts = {}
                    for _, part in ipairs(parts) do
                        local num = tonumber(part, 16)
                        if not num or num < 0 or num > 65535 then
                            return nil
                        end
                        table.insert(normalized_parts, string.format("%04x", num))
                    end
                    return table.concat(normalized_parts, ":")
                else
                    -- 前缀中没有双冒号，直接拼接
                    local parts = {}
                    for part in prefix:gmatch("([^:]+)") do
                        table.insert(parts, part)
                    end
                    table.insert(parts, string.format("%04x", high16))
                    table.insert(parts, string.format("%04x", low16))
                    
                    -- 规范化每个部分
                    local normalized_parts = {}
                    for _, part in ipairs(parts) do
                        local num = tonumber(part, 16)
                        if not num or num < 0 or num > 65535 then
                            return nil
                        end
                        table.insert(normalized_parts, string.format("%04x", num))
                    end
                    return table.concat(normalized_parts, ":")
                end
            end
        end
    end
    
    -- 处理双冒号（::）压缩
    if ip:match("::") then
        local before, after = ip:match("^(.*)::(.*)$")
        
        if before == "" and after == "" then
            -- 全零地址 ::
            local parts = {}
            for i = 1, 8 do
                table.insert(parts, "0000")
            end
            return table.concat(parts, ":")
        end
        
        local before_parts = {}
        if before and before ~= "" then
            for part in before:gmatch("([^:]+)") do
                table.insert(before_parts, part)
            end
        end
        
        local after_parts = {}
        if after and after ~= "" then
            for part in after:gmatch("([^:]+)") do
                table.insert(after_parts, part)
            end
        end
        
        -- 计算需要填充的零组数量
        local total_parts = #before_parts + #after_parts
        if total_parts >= 8 then
            return nil  -- 无效的IPv6地址
        end
        
        local zero_groups = 8 - total_parts
        
        -- 构建完整部分列表
        local parts = {}
        for _, part in ipairs(before_parts) do
            table.insert(parts, part)
        end
        
        for i = 1, zero_groups do
            table.insert(parts, "0")
        end
        
        for _, part in ipairs(after_parts) do
            table.insert(parts, part)
        end
        
        -- 规范化每个部分
        local normalized_parts = {}
        for _, part in ipairs(parts) do
            if part == "" then
                part = "0"
            end
            local num = tonumber(part, 16)
            if not num or num < 0 or num > 65535 then
                return nil
            end
            table.insert(normalized_parts, string.format("%04x", num))
        end
        
        return table.concat(normalized_parts, ":")
    else
        -- 没有双冒号，直接分割
        local parts = {}
        for part in ip:gmatch("([^:]+)") do
            table.insert(parts, part)
        end
        
        if #parts ~= 8 then
            return nil
        end
        
        -- 规范化每个部分
        local normalized_parts = {}
        for _, part in ipairs(parts) do
            if part == "" then
                part = "0"
            end
            local num = tonumber(part, 16)
            if not num or num < 0 or num > 65535 then
                return nil
            end
            table.insert(normalized_parts, string.format("%04x", num))
        end
        
        return table.concat(normalized_parts, ":")
    end
end

-- IPv6 转128位整数（返回两个64位整数：高64位和低64位）
function _M.ipv6_to_int128(ip)
    local normalized = _M.normalize_ipv6(ip)
    if not normalized then
        return nil, nil
    end
    
    local parts = {}
    for part in normalized:gmatch("([^:]+)") do
        table.insert(parts, tonumber(part, 16))
    end
    
    if #parts ~= 8 then
        return nil, nil
    end
    
    -- 计算高64位
    local high = 0
    for i = 1, 4 do
        high = high * 65536 + (parts[i] or 0)
    end
    
    -- 计算低64位
    local low = 0
    for i = 5, 8 do
        low = low * 65536 + (parts[i] or 0)
    end
    
    return high, low
end

-- 128位整数转IPv6（从两个64位整数）
function _M.int128_to_ipv6(high, low)
    local parts = {}
    
    -- 从高64位提取4个16位部分
    for i = 1, 4 do
        local part = high % 65536
        high = math.floor(high / 65536)
        table.insert(parts, 1, string.format("%04x", part))
    end
    
    -- 从低64位提取4个16位部分
    for i = 1, 4 do
        local part = low % 65536
        low = math.floor(low / 65536)
        table.insert(parts, 5, string.format("%04x", part))
    end
    
    return table.concat(parts, ":")
end

-- 检查 IPv6 是否匹配 CIDR
function _M.match_ipv6_cidr(ip, cidr)
    local base_ip, mask_str = cidr:match("^([^/]+)/(%d+)$")
    if not base_ip then
        return false
    end
    
    local mask = tonumber(mask_str)
    if not mask or mask < 0 or mask > 128 then
        return false
    end
    
    local ip_high, ip_low = _M.ipv6_to_int128(ip)
    local base_high, base_low = _M.ipv6_to_int128(base_ip)
    
    if not ip_high or not base_high then
        return false
    end
    
    -- 计算掩码（128位）
    if mask == 0 then
        return true  -- 匹配所有
    elseif mask == 128 then
        return ip_high == base_high and ip_low == base_low
    elseif mask <= 64 then
        -- 掩码在高64位
        local shift = 64 - mask
        local mask_high = bit.lshift(0xFFFFFFFFFFFFFFFF, shift)
        return bit.band(ip_high, mask_high) == bit.band(base_high, mask_high)
    else
        -- 掩码跨越高低64位
        local high_mask_bits = 64
        local low_mask_bits = mask - 64
        local shift = 64 - low_mask_bits
        local mask_high = 0xFFFFFFFFFFFFFFFF
        local mask_low = bit.lshift(0xFFFFFFFFFFFFFFFF, shift)
        
        return bit.band(ip_high, mask_high) == bit.band(base_high, mask_high) and
               bit.band(ip_low, mask_low) == bit.band(base_low, mask_low)
    end
end

-- 检查 IPv6 是否在范围内
function _M.match_ipv6_range(ip, start_ip, end_ip)
    local ip_high, ip_low = _M.ipv6_to_int128(ip)
    local start_high, start_low = _M.ipv6_to_int128(start_ip)
    local end_high, end_low = _M.ipv6_to_int128(end_ip)
    
    if not ip_high or not start_high or not end_high then
        return false
    end
    
    -- 比较128位整数（先比较高64位，再比较低64位）
    if ip_high < start_high or ip_high > end_high then
        return false
    end
    
    if ip_high == start_high and ip_low < start_low then
        return false
    end
    
    if ip_high == end_high and ip_low > end_low then
        return false
    end
    
    return true
end

-- 解析 IPv6 范围（格式：2001:db8::1-2001:db8::100）
function _M.parse_ipv6_range(range_str)
    local start_ip, end_ip = range_str:match("^([^%-]+)%-(.+)$")
    if start_ip and end_ip then
        return start_ip:match("^%s*(.-)%s*$"), end_ip:match("^%s*(.-)%s*$")
    end
    return nil, nil
end

-- 判断IP地址类型（IPv4或IPv6）
function _M.get_ip_version(ip)
    if not ip then
        return nil
    end
    
    -- 先检查IPv4
    if _M.ipv4_to_int(ip) then
        return 4
    end
    
    -- 检查IPv6（包含冒号）
    if ip:match(":") then
        local normalized = _M.normalize_ipv6(ip)
        if normalized then
            return 6
        end
    end
    
    return nil
end

-- 验证 IP 地址格式（支持IPv4和IPv6）
function _M.is_valid_ip(ip)
    if not ip then
        return false
    end
    
    -- 检查IPv4
    if _M.ipv4_to_int(ip) then
        return true
    end
    
    -- 检查IPv6
    if ip:match(":") then
        local normalized = _M.normalize_ipv6(ip)
        return normalized ~= nil
    end
    
    return false
end

-- 验证 CIDR 格式（支持IPv4和IPv6）
function _M.is_valid_cidr(cidr)
    local base_ip, mask_str = cidr:match("^([^/]+)/(%d+)$")
    if not base_ip then
        return false
    end
    
    local mask = tonumber(mask_str)
    if not mask then
        return false
    end
    
    -- 检查IPv4 CIDR
    local ipv4_int = _M.ipv4_to_int(base_ip)
    if ipv4_int then
        return mask >= 0 and mask <= 32
    end
    
    -- 检查IPv6 CIDR
    local ipv6_normalized = _M.normalize_ipv6(base_ip)
    if ipv6_normalized then
        return mask >= 0 and mask <= 128
    end
    
    return false
end

-- 检查 IP 是否匹配 CIDR（支持IPv4和IPv6）
function _M.match_cidr(ip, cidr)
    local base_ip, mask_str = cidr:match("^([^/]+)/(%d+)$")
    if not base_ip then
        return false
    end
    
    local mask = tonumber(mask_str)
    if not mask then
        return false
    end
    
    -- 判断IP版本
    local ip_version = _M.get_ip_version(ip)
    local base_version = _M.get_ip_version(base_ip)
    
    if not ip_version or not base_version or ip_version ~= base_version then
        return false
    end
    
    -- IPv4 CIDR匹配
    if ip_version == 4 then
        if mask < 0 or mask > 32 then
            return false
        end
        
        local ip_int = _M.ipv4_to_int(ip)
        local base_int = _M.ipv4_to_int(base_ip)
        
        if not ip_int or not base_int then
            return false
        end
        
        local mask_int = bit.lshift(0xFFFFFFFF, 32 - mask)
        return bit.band(ip_int, mask_int) == bit.band(base_int, mask_int)
    end
    
    -- IPv6 CIDR匹配
    if ip_version == 6 then
        return _M.match_ipv6_cidr(ip, cidr)
    end
    
    return false
end

-- 检查 IP 是否在范围内（支持IPv4和IPv6）
function _M.match_ip_range(ip, start_ip, end_ip)
    local ip_version = _M.get_ip_version(ip)
    local start_version = _M.get_ip_version(start_ip)
    local end_version = _M.get_ip_version(end_ip)
    
    if not ip_version or not start_version or not end_version then
        return false
    end
    
    if ip_version ~= start_version or ip_version ~= end_version then
        return false
    end
    
    -- IPv4范围匹配
    if ip_version == 4 then
        local ip_int = _M.ipv4_to_int(ip)
        local start_int = _M.ipv4_to_int(start_ip)
        local end_int = _M.ipv4_to_int(end_ip)
        
        if not ip_int or not start_int or not end_int then
            return false
        end
        
        return ip_int >= start_int and ip_int <= end_int
    end
    
    -- IPv6范围匹配
    if ip_version == 6 then
        return _M.match_ipv6_range(ip, start_ip, end_ip)
    end
    
    return false
end

-- 解析 IP 范围（支持IPv4和IPv6）
function _M.parse_ip_range(range_str)
    if not range_str then
        return nil, nil
    end
    
    local start_ip, end_ip = range_str:match("^([^%-]+)%-(.+)$")
    if start_ip and end_ip then
        start_ip = start_ip:match("^%s*(.-)%s*$")
        end_ip = end_ip:match("^%s*(.-)%s*$")
        
        -- 验证两个IP版本是否一致
        local start_version = _M.get_ip_version(start_ip)
        local end_version = _M.get_ip_version(end_ip)
        
        if start_version and end_version and start_version == end_version then
            return start_ip, end_ip
        end
    end
    
    return nil, nil
end

return _M

