-- IP 工具函数
-- 路径：/usr/local/openresty/nginx/lua/waf/ip_utils.lua

local _M = {}

-- 获取客户端真实 IP
function _M.get_real_ip()
    local headers = ngx.req.get_headers()
    
    -- 优先检查 X-Forwarded-For（处理代理情况）
    local x_forwarded_for = headers["X-Forwarded-For"]
    if x_forwarded_for then
        -- X-Forwarded-For 可能包含多个 IP，取第一个
        local ips = {}
        for ip in x_forwarded_for:gmatch("([^,]+)") do
            ip = ip:match("^%s*(.-)%s*$")  -- 去除首尾空格
            if ip and ip ~= "" then
                table.insert(ips, ip)
            end
        end
        if #ips > 0 then
            return ips[1]
        end
    end
    
    -- 检查 X-Real-IP
    local x_real_ip = headers["X-Real-IP"]
    if x_real_ip then
        return x_real_ip
    end
    
    -- 使用 remote_addr
    return ngx.var.remote_addr
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

-- 检查 IP 是否匹配 CIDR
function _M.match_cidr(ip, cidr)
    local base_ip, mask_str = cidr:match("^([^/]+)/(%d+)$")
    if not base_ip then
        return false
    end
    
    local mask = tonumber(mask_str)
    if not mask or mask < 0 or mask > 32 then
        return false
    end
    
    local ip_int = _M.ipv4_to_int(ip)
    local base_int = _M.ipv4_to_int(base_ip)
    
    if not ip_int or not base_int then
        return false
    end
    
    -- 计算掩码
    local mask_int = bit.lshift(0xFFFFFFFF, 32 - mask)
    
    -- 检查网络部分是否相同
    return bit.band(ip_int, mask_int) == bit.band(base_int, mask_int)
end

-- 检查 IP 是否在范围内
function _M.match_ip_range(ip, start_ip, end_ip)
    local ip_int = _M.ipv4_to_int(ip)
    local start_int = _M.ipv4_to_int(start_ip)
    local end_int = _M.ipv4_to_int(end_ip)
    
    if not ip_int or not start_int or not end_int then
        return false
    end
    
    return ip_int >= start_int and ip_int <= end_int
end

-- 解析 IP 范围（格式：192.168.1.1-192.168.1.100）
function _M.parse_ip_range(range_str)
    local start_ip, end_ip = range_str:match("^([^%-]+)%-(.+)$")
    if start_ip and end_ip then
        return start_ip:match("^%s*(.-)%s*$"), end_ip:match("^%s*(.-)%s*$")
    end
    return nil, nil
end

-- 验证 IP 地址格式
function _M.is_valid_ip(ip)
    return _M.ipv4_to_int(ip) ~= nil
end

-- 验证 CIDR 格式
function _M.is_valid_cidr(cidr)
    local base_ip, mask_str = cidr:match("^([^/]+)/(%d+)$")
    if not base_ip then
        return false
    end
    
    if not _M.is_valid_ip(base_ip) then
        return false
    end
    
    local mask = tonumber(mask_str)
    return mask ~= nil and mask >= 0 and mask <= 32
end

return _M

