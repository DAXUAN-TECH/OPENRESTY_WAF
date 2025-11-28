-- 序列化工具模块
-- 路径：项目目录下的 lua/waf/serializer.lua（保持在项目目录，不复制到系统目录）
-- 功能：支持JSON和MessagePack序列化格式

local config = require "config"
local cjson = require "cjson"

local _M = {}

-- 检查是否启用MessagePack
local USE_MSGPACK = config.serializer and config.serializer.use_msgpack or false
local msgpack = nil

-- 尝试加载MessagePack
if USE_MSGPACK then
    local ok, mp = pcall(require, "resty.msgpack")
    if ok then
        msgpack = mp
        ngx.log(ngx.INFO, "MessagePack serializer enabled")
    else
        ngx.log(ngx.WARN, "MessagePack not available, falling back to JSON")
        USE_MSGPACK = false
    end
end

-- 序列化数据
function _M.encode(data)
    if USE_MSGPACK and msgpack then
        local ok, result = pcall(msgpack.pack, data)
        if ok then
            return result, "msgpack"
        else
            ngx.log(ngx.WARN, "MessagePack encode failed, falling back to JSON: ", result)
        end
    end
    
    -- 回退到JSON
    local ok, result = pcall(cjson.encode, data)
    if ok then
        return result, "json"
    else
        return nil, result
    end
end

-- 反序列化数据
function _M.decode(data, format)
    -- 如果指定了格式，使用指定格式
    if format == "msgpack" and USE_MSGPACK and msgpack then
        local ok, result = pcall(msgpack.unpack, data)
        if ok then
            return result, "msgpack"
        else
            ngx.log(ngx.WARN, "MessagePack decode failed, falling back to JSON: ", result)
        end
    end
    
    -- 尝试自动检测格式
    if USE_MSGPACK and msgpack then
        -- MessagePack数据通常以特定字节开头
        local first_byte = string.byte(data, 1)
        if first_byte >= 0x80 and first_byte <= 0xff then
            -- 可能是MessagePack格式
            local ok, result = pcall(msgpack.unpack, data)
            if ok then
                return result, "msgpack"
            end
        end
    end
    
    -- 回退到JSON
    local ok, result = pcall(cjson.decode, data)
    if ok then
        return result, "json"
    else
        return nil, result
    end
end

-- 获取当前使用的序列化格式
function _M.get_format()
    if USE_MSGPACK and msgpack then
        return "msgpack"
    end
    return "json"
end

-- 检查是否支持MessagePack
function _M.supports_msgpack()
    return USE_MSGPACK and msgpack ~= nil
end

return _M

