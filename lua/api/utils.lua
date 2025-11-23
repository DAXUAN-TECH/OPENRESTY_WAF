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
    ngx.say(cjson.encode(data))
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
            local ok, json_data = pcall(cjson.decode, body)
            if ok and json_data then
                for k, v in pairs(json_data) do
                    args[k] = v
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

