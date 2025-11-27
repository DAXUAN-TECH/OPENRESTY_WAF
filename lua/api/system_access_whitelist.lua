-- 系统访问白名单API模块
-- 路径：项目目录下的 lua/api/system_access_whitelist.lua
-- 功能：处理系统访问白名单的CRUD操作和开关控制

local mysql_pool = require "waf.mysql_pool"
local api_utils = require "api.utils"
local cjson = require "cjson"
local audit_log = require "waf.audit_log"
local ip_utils = require "waf.ip_utils"
local system_api = require "api.system"

local _M = {}

-- 获取白名单开关状态
function _M.get_config()
    local ok, res, err = pcall(function()
        local sql = "SELECT enabled, updated_at, updated_by FROM waf_system_access_whitelist_config WHERE id = 1 LIMIT 1"
        return mysql_pool.query(sql)
    end)
    
    if not ok then
        ngx.log(ngx.ERR, "get_config: database query failed: ", tostring(res))
        api_utils.json_response({error = "数据库查询失败"}, 500)
        return
    end
    
    if err then
        ngx.log(ngx.ERR, "get_config: database error: ", tostring(err))
        api_utils.json_response({error = "数据库错误"}, 500)
        return
    end
    
    if not res or #res == 0 then
        -- 如果配置不存在，创建默认配置（关闭状态）
        local insert_ok, insert_err = pcall(function()
            local insert_sql = "INSERT INTO waf_system_access_whitelist_config (id, enabled) VALUES (1, 0)"
            return mysql_pool.query(insert_sql)
        end)
        
        if not insert_ok or insert_err then
            ngx.log(ngx.ERR, "get_config: failed to create default config")
            api_utils.json_response({error = "创建默认配置失败"}, 500)
            return
        end
        
        api_utils.json_response({
            success = true,
            data = {
                enabled = 0,
                updated_at = nil,
                updated_by = nil
            }
        })
        return
    end
    
    api_utils.json_response({
        success = true,
        data = {
            enabled = res[1].enabled,
            updated_at = res[1].updated_at,
            updated_by = res[1].updated_by
        }
    })
end

-- 更新白名单开关状态
function _M.update_config()
    if ngx.req.get_method() ~= "POST" then
        api_utils.json_response({error = "Method not allowed"}, 405)
        return
    end
    
    local args = api_utils.get_args()
    local enabled = args.enabled
    
    if enabled == nil then
        api_utils.json_response({error = "enabled参数不能为空"}, 400)
        return
    end
    
    enabled = tonumber(enabled)
    if enabled ~= 0 and enabled ~= 1 then
        api_utils.json_response({error = "enabled参数必须是0或1"}, 400)
        return
    end
    
    -- 获取当前用户信息（从session）
    local auth = require "waf.auth"
    local authenticated, session = auth.is_authenticated()
    local updated_by = authenticated and session.username or "system"
    
    local ok, res, err = pcall(function()
        local sql = [[
            UPDATE waf_system_access_whitelist_config 
            SET enabled = ?, updated_by = ?
            WHERE id = 1
        ]]
        return mysql_pool.query(sql, enabled, updated_by)
    end)
    
    if not ok then
        ngx.log(ngx.ERR, "update_config: database query failed: ", tostring(res))
        api_utils.json_response({error = "数据库查询失败"}, 500)
        return
    end
    
    if err then
        ngx.log(ngx.ERR, "update_config: database error: ", tostring(err))
        api_utils.json_response({error = "数据库错误"}, 500)
        return
    end
    
    -- 记录审计日志
    audit_log.log("update", "system_access_whitelist_config", "1", 
        "更新系统访问白名单开关: " .. (enabled == 1 and "启用" or "禁用"), "success")
    
    -- 触发nginx重载（异步，不阻塞响应）
    ngx.timer.at(0, function()
        local ok, result = system_api.reload_nginx_internal()
        if not ok then
            ngx.log(ngx.WARN, "系统访问白名单开关更新后自动触发nginx重载失败: ", result or "unknown error")
        else
            ngx.log(ngx.INFO, "系统访问白名单开关更新后自动触发nginx重载成功")
        end
    end)
    
    api_utils.json_response({
        success = true,
        message = enabled == 1 and "白名单已启用，nginx配置正在重新加载" or "白名单已禁用，nginx配置正在重新加载"
    })
end

-- 获取白名单列表
function _M.list()
    local args = api_utils.get_args()
    local page = tonumber(args.page) or 1
    local page_size = tonumber(args.page_size) or 50
    local status = args.status
    
    local offset = (page - 1) * page_size
    
    local where_clause = ""
    local params = {}
    
    if status ~= nil and status ~= "" then
        where_clause = "WHERE status = ?"
        table.insert(params, tonumber(status))
    end
    
    -- 获取总数
    local count_sql = "SELECT COUNT(*) as total FROM waf_system_access_whitelist " .. where_clause
    local ok, count_res, err = pcall(function()
        return mysql_pool.query(count_sql, unpack(params))
    end)
    
    if not ok or err then
        ngx.log(ngx.ERR, "list: failed to get count: ", tostring(err))
        api_utils.json_response({error = "查询失败"}, 500)
        return
    end
    
    local total = count_res and count_res[1] and tonumber(count_res[1].total) or 0
    
    -- 获取列表
    local sql = string.format([[
        SELECT id, ip_address, description, status, created_at, updated_at
        FROM waf_system_access_whitelist
        %s
        ORDER BY id DESC
        LIMIT ? OFFSET ?
    ]], where_clause)
    
    table.insert(params, page_size)
    table.insert(params, offset)
    
    local ok, res, err = pcall(function()
        return mysql_pool.query(sql, unpack(params))
    end)
    
    if not ok or err then
        ngx.log(ngx.ERR, "list: failed to get list: ", tostring(err))
        api_utils.json_response({error = "查询失败"}, 500)
        return
    end
    
    -- 确保返回的数据是数组类型（用于 JSON 序列化）
    local data_array = {}
    if res then
        if type(res) == "table" then
            -- 检查是否是数组
            local is_array = false
            for i, _ in ipairs(res) do
                is_array = true
                data_array[i] = res[i]
            end
            
            -- 如果不是数组，尝试转换
            if not is_array then
                local temp_array = {}
                for k, v in pairs(res) do
                    if type(k) == "number" and k > 0 then
                        table.insert(temp_array, {key = k, value = v})
                    end
                end
                table.sort(temp_array, function(a, b) return a.key < b.key end)
                for _, item in ipairs(temp_array) do
                    table.insert(data_array, item.value)
                end
            end
        end
    end
    
    api_utils.json_response({
        success = true,
        data = data_array,
        pagination = {
            page = page,
            page_size = page_size,
            total = total,
            total_pages = math.ceil(total / page_size)
        }
    })
end

-- 创建白名单
function _M.create()
    if ngx.req.get_method() ~= "POST" then
        api_utils.json_response({error = "Method not allowed"}, 405)
        return
    end
    
    local args = api_utils.get_args()
    local ip_address = args.ip_address
    local description = args.description or ""
    local status = tonumber(args.status) or 1
    
    if not ip_address or ip_address == "" then
        api_utils.json_response({error = "IP地址不能为空"}, 400)
        return
    end
    
    -- 验证IP地址格式（支持CIDR）
    local is_valid = ip_utils.is_valid_ip(ip_address) or ip_utils.is_valid_cidr(ip_address)
    if not is_valid then
        api_utils.json_response({error = "IP地址格式不正确"}, 400)
        return
    end
    
    if status ~= 0 and status ~= 1 then
        api_utils.json_response({error = "状态必须是0或1"}, 400)
        return
    end
    
    -- 检查是否已存在
    local check_ok, check_res, check_err = pcall(function()
        local check_sql = "SELECT id FROM waf_system_access_whitelist WHERE ip_address = ? LIMIT 1"
        return mysql_pool.query(check_sql, ip_address)
    end)
    
    if check_ok and not check_err and check_res and #check_res > 0 then
        api_utils.json_response({error = "该IP地址已存在"}, 400)
        return
    end
    
    -- 获取当前用户信息
    local auth = require "waf.auth"
    local authenticated, session = auth.is_authenticated()
    local username = authenticated and session.username or "system"
    
    local ok, res, err = pcall(function()
        local sql = [[
            INSERT INTO waf_system_access_whitelist (ip_address, description, status)
            VALUES (?, ?, ?)
        ]]
        return mysql_pool.insert(sql, ip_address, description, status)
    end)
    
    if not ok or err then
        ngx.log(ngx.ERR, "create: failed to insert: ", tostring(err))
        api_utils.json_response({error = "创建失败"}, 500)
        return
    end
    
    -- 记录审计日志
    audit_log.log("create", "system_access_whitelist", tostring(res), 
        "创建系统访问白名单: " .. ip_address, "success")
    
    -- 触发nginx重载（异步，不阻塞响应）
    ngx.timer.at(0, function()
        local ok, result = system_api.reload_nginx_internal()
        if not ok then
            ngx.log(ngx.WARN, "创建系统访问白名单后自动触发nginx重载失败: ", result or "unknown error")
        else
            ngx.log(ngx.INFO, "创建系统访问白名单后自动触发nginx重载成功")
        end
    end)
    
    api_utils.json_response({
        success = true,
        message = "创建成功，nginx配置正在重新加载",
        data = {id = res}
    })
end

-- 更新白名单
function _M.update()
    if ngx.req.get_method() ~= "POST" and ngx.req.get_method() ~= "PUT" then
        api_utils.json_response({error = "Method not allowed"}, 405)
        return
    end
    
    local uri = ngx.var.request_uri
    local id_match = uri:match("^/api/system/access/whitelist/(%d+)$")
    if not id_match then
        api_utils.json_response({error = "无效的ID"}, 400)
        return
    end
    
    local id = tonumber(id_match)
    local args = api_utils.get_args()
    local ip_address = args.ip_address
    local description = args.description
    local status = args.status
    
    if ip_address and ip_address ~= "" then
        -- 验证IP地址格式
        local is_valid = ip_utils.is_valid_ip(ip_address) or ip_utils.is_valid_cidr(ip_address)
        if not is_valid then
            api_utils.json_response({error = "IP地址格式不正确"}, 400)
            return
        end
        
        -- 检查是否已存在（排除自己）
        local check_ok, check_res, check_err = pcall(function()
            local check_sql = "SELECT id FROM waf_system_access_whitelist WHERE ip_address = ? AND id != ? LIMIT 1"
            return mysql_pool.query(check_sql, ip_address, id)
        end)
        
        if check_ok and not check_err and check_res and #check_res > 0 then
            api_utils.json_response({error = "该IP地址已存在"}, 400)
            return
        end
    end
    
    if status ~= nil then
        status = tonumber(status)
        if status ~= 0 and status ~= 1 then
            api_utils.json_response({error = "状态必须是0或1"}, 400)
            return
        end
    end
    
    -- 构建更新SQL
    local update_fields = {}
    local params = {}
    
    if ip_address then
        table.insert(update_fields, "ip_address = ?")
        table.insert(params, ip_address)
    end
    
    if description ~= nil then
        table.insert(update_fields, "description = ?")
        table.insert(params, description)
    end
    
    if status ~= nil then
        table.insert(update_fields, "status = ?")
        table.insert(params, status)
    end
    
    if #update_fields == 0 then
        api_utils.json_response({error = "没有需要更新的字段"}, 400)
        return
    end
    
    table.insert(params, id)
    
    local sql = string.format([[
        UPDATE waf_system_access_whitelist
        SET %s
        WHERE id = ?
    ]], table.concat(update_fields, ", "))
    
    local ok, res, err = pcall(function()
        return mysql_pool.query(sql, unpack(params))
    end)
    
    if not ok or err then
        ngx.log(ngx.ERR, "update: failed to update: ", tostring(err))
        api_utils.json_response({error = "更新失败"}, 500)
        return
    end
    
    -- 获取当前用户信息
    local auth = require "waf.auth"
    local authenticated, session = auth.is_authenticated()
    local username = authenticated and session.username or "system"
    
    -- 记录审计日志
    audit_log.log("update", "system_access_whitelist", tostring(id), 
        "更新系统访问白名单", "success")
    
    -- 触发nginx重载（异步，不阻塞响应）
    -- 注意：如果IP地址改变，需要reload使新的IP生效
    ngx.timer.at(0, function()
        local ok, result = system_api.reload_nginx_internal()
        if not ok then
            ngx.log(ngx.WARN, "更新系统访问白名单后自动触发nginx重载失败: ", result or "unknown error")
        else
            ngx.log(ngx.INFO, "更新系统访问白名单后自动触发nginx重载成功")
        end
    end)
    
    api_utils.json_response({
        success = true,
        message = "更新成功，nginx配置正在重新加载"
    })
end

-- 删除白名单
function _M.delete()
    if ngx.req.get_method() ~= "DELETE" and ngx.req.get_method() ~= "POST" then
        api_utils.json_response({error = "Method not allowed"}, 405)
        return
    end
    
    local uri = ngx.var.request_uri
    local id_match = uri:match("^/api/system/access/whitelist/(%d+)$")
    if not id_match then
        api_utils.json_response({error = "无效的ID"}, 400)
        return
    end
    
    local id = tonumber(id_match)
    
    local ok, res, err = pcall(function()
        local sql = "DELETE FROM waf_system_access_whitelist WHERE id = ?"
        return mysql_pool.query(sql, id)
    end)
    
    if not ok or err then
        ngx.log(ngx.ERR, "delete: failed to delete: ", tostring(err))
        api_utils.json_response({error = "删除失败"}, 500)
        return
    end
    
    -- 获取当前用户信息
    local auth = require "waf.auth"
    local authenticated, session = auth.is_authenticated()
    local username = authenticated and session.username or "system"
    
    -- 记录审计日志
    audit_log.log("delete", "system_access_whitelist", tostring(id), 
        "删除系统访问白名单", "success")
    
    -- 触发nginx重载（异步，不阻塞响应）
    -- 注意：删除IP后需要reload使变更生效
    ngx.timer.at(0, function()
        local ok, result = system_api.reload_nginx_internal()
        if not ok then
            ngx.log(ngx.WARN, "删除系统访问白名单后自动触发nginx重载失败: ", result or "unknown error")
        else
            ngx.log(ngx.INFO, "删除系统访问白名单后自动触发nginx重载成功")
        end
    end)
    
    api_utils.json_response({
        success = true,
        message = "删除成功，nginx配置正在重新加载"
    })
end

-- 检查IP是否在白名单中（用于认证中间件）
function _M.check_ip_allowed(ip_address)
    if not ip_address then
        return false
    end
    
    -- 先检查开关是否启用
    local ok, res, err = pcall(function()
        local sql = "SELECT enabled FROM waf_system_access_whitelist_config WHERE id = 1 LIMIT 1"
        return mysql_pool.query(sql)
    end)
    
    if not ok or err or not res or #res == 0 then
        -- 如果查询失败或配置不存在，默认允许访问（安全起见，不启用白名单）
        return true
    end
    
    local enabled = res[1].enabled
    if enabled == 0 then
        -- 白名单未启用，允许所有IP访问
        return true
    end
    
    -- 白名单已启用，检查IP是否在白名单中
    ok, res, err = pcall(function()
        local sql = "SELECT ip_address FROM waf_system_access_whitelist WHERE status = 1"
        return mysql_pool.query(sql)
    end)
    
    if not ok or err then
        ngx.log(ngx.ERR, "check_ip_allowed: failed to query whitelist: ", tostring(err))
        -- 查询失败时，为了安全，拒绝访问
        return false
    end
    
    if not res or #res == 0 then
        -- 白名单为空，拒绝所有访问
        return false
    end
    
    -- 检查IP是否匹配任何白名单条目
    for _, row in ipairs(res) do
        local whitelist_ip = row.ip_address
        -- 检查是否为CIDR格式
        if whitelist_ip:match("/") then
            -- CIDR格式，使用match_cidr
            if ip_utils.match_cidr(ip_address, whitelist_ip) then
                return true
            end
        else
            -- 单个IP，直接比较
            if ip_address == whitelist_ip then
                return true
            end
        end
    end
    
    return false
end

return _M

