-- API工具函数模块
-- 路径：项目目录下的 lua/api/utils.lua（保持在项目目录，不复制到系统目录）
-- 功能：提供API处理中常用的工具函数

local cjson = require "cjson"

local _M = {}

-- 设置JSON响应
function _M.json_response(data, status_code)
    status_code = status_code or 200
    ngx.status = status_code
    ngx.header.content_type = "application/json; charset=utf-8"
    
    -- 确保空表序列化为数组而不是对象
    -- 注意：encode_empty_table_as_object 是一个函数，需要安全调用
    local old_value = nil
    local ok_get, current_value = pcall(function()
        -- 尝试获取当前值（某些版本可能不支持无参数调用）
        return cjson.encode_empty_table_as_object()
    end)
    if ok_get and current_value ~= nil then
        old_value = current_value
    end
    
    -- 设置新值
    local ok_set = pcall(function()
        cjson.encode_empty_table_as_object(false)
    end)
    if not ok_set then
        ngx.log(ngx.WARN, "无法设置 encode_empty_table_as_object，可能不支持此功能")
    end
    
    -- 序列化数据
    local json_str = cjson.encode(data)
    
    -- 恢复原始设置（如果之前成功获取了旧值）
    if old_value ~= nil then
        pcall(function()
            cjson.encode_empty_table_as_object(old_value)
        end)
    end
    
    ngx.say(json_str)
    ngx.exit(status_code)
end

-- 设置CSV响应
function _M.csv_response(data, filename)
    filename = filename or "export.csv"
    ngx.status = 200
    ngx.header.content_type = "text/csv; charset=utf-8"
    ngx.header["Content-Disposition"] = 'attachment; filename="' .. filename .. '"'
    ngx.say(data)
    ngx.exit(200)
end

-- 获取请求参数（包括URL参数和Body参数）
function _M.get_args()
    local args = ngx.req.get_uri_args()
    local method = ngx.req.get_method()
    
    if method == "POST" or method == "PUT" or method == "PATCH" then
        ngx.req.read_body()
        local body = ngx.req.get_body_data()
        if body then
            -- 检查 Content-Type
            local content_type = ngx.req.get_headers()["Content-Type"] or ""
            
            -- 如果是 JSON 格式
            if content_type:match("application/json") then
                local ok, json_data = pcall(cjson.decode, body)
                if ok and json_data then
                    for k, v in pairs(json_data) do
                        args[k] = v
                    end
                end
            -- 如果是 form-urlencoded 格式
            elseif content_type:match("application/x-www-form-urlencoded") then
                local ok, post_args = pcall(ngx.req.get_post_args)
                if ok and post_args then
                    for k, v in pairs(post_args) do
                        -- post_args 的值可能是数组（同名参数），取第一个
                        if type(v) == "table" then
                            args[k] = v[1]
                        else
                            args[k] = v
                        end
                    end
                end
            else
                -- 尝试先解析 JSON，如果失败则尝试 form-urlencoded
                local ok, json_data = pcall(cjson.decode, body)
                if ok and json_data then
                    for k, v in pairs(json_data) do
                        args[k] = v
                    end
                else
                    -- 尝试解析 form-urlencoded
                    local ok2, post_args = pcall(ngx.req.get_post_args)
                    if ok2 and post_args then
                        for k, v in pairs(post_args) do
                            if type(v) == "table" then
                                args[k] = v[1]
                            else
                                args[k] = v
                            end
                        end
                    end
                end
            end
        end
    end
    
    return args
end

-- 从URI路径提取ID
function _M.extract_id_from_uri(pattern)
    local uri = ngx.var.request_uri
    local id_match = uri:match(pattern)
    if id_match then
        return tonumber(id_match)
    end
    return nil
end

-- 验证必填参数
function _M.validate_required(params, required_fields)
    for _, field in ipairs(required_fields) do
        if not params[field] or params[field] == "" then
            return false, "参数 " .. field .. " 不能为空"
        end
    end
    return true, nil
end

-- 解析分页参数
function _M.parse_pagination(args)
    return {
        page = args.page and tonumber(args.page) or 1,
        page_size = args.page_size and tonumber(args.page_size) or 20
    }
end

return _M

