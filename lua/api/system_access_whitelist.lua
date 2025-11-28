-- 系统访问白名单API模块
-- 路径：项目目录下的 lua/api/system_access_whitelist.lua
-- 功能：处理系统访问白名单的CRUD操作和开关控制

local mysql_pool = require "waf.mysql_pool"
local api_utils = require "api.utils"
local cjson = require "cjson"
local audit_log = require "waf.audit_log"
local ip_utils = require "waf.ip_utils"
local system_api = require "api.system"
local config_manager = require "waf.config_manager"

local _M = {}

-- 获取白名单开关状态
function _M.get_config()
    local ok, res, err = pcall(function()
        local sql = "SELECT config_value, updated_at FROM waf_system_config WHERE config_key = 'system_access_whitelist_enabled' LIMIT 1"
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
    
    local enabled = 0
    local updated_at = nil
    
    if res and #res > 0 then
        enabled = tonumber(res[1].config_value) or 0
        updated_at = res[1].updated_at
    else
        -- 如果配置不存在，创建默认配置（关闭状态）
        -- 使用INSERT IGNORE或ON DUPLICATE KEY UPDATE避免并发问题
        local insert_ok, insert_err = pcall(function()
            local insert_sql = [[
                INSERT INTO waf_system_config (config_key, config_value, description) 
                VALUES ('system_access_whitelist_enabled', '0', '是否启用系统访问白名单（1-启用，0-禁用，开启时只有白名单内的IP才能访问管理系统）')
                ON DUPLICATE KEY UPDATE config_value = VALUES(config_value)
            ]]
            return mysql_pool.query(insert_sql)
        end)
        
        if not insert_ok or insert_err then
            ngx.log(ngx.ERR, "get_config: failed to create default config: ", tostring(insert_err))
            api_utils.json_response({error = "创建默认配置失败: " .. tostring(insert_err)}, 500)
            return
        end
        
        -- 重新查询获取创建后的值
        local retry_ok, retry_res, retry_err = pcall(function()
            local retry_sql = "SELECT config_value, updated_at FROM waf_system_config WHERE config_key = 'system_access_whitelist_enabled' LIMIT 1"
            return mysql_pool.query(retry_sql)
        end)
        
        if retry_ok and retry_res and #retry_res > 0 then
            enabled = tonumber(retry_res[1].config_value) or 0
            updated_at = retry_res[1].updated_at
        end
    end
    
    api_utils.json_response({
        success = true,
        data = {
            enabled = enabled,
            updated_at = updated_at,
            updated_by = nil  -- 不再存储updated_by，因为waf_system_config表没有此字段
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
    
    local ok, res, err = pcall(function()
        local sql = [[
            UPDATE waf_system_config 
            SET config_value = ?
            WHERE config_key = 'system_access_whitelist_enabled'
        ]]
        return mysql_pool.query(sql, tostring(enabled))
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
    audit_log.log("update", "system_config", "system_access_whitelist_enabled", 
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
    local status = 1  -- 默认启用
    
    if not ip_address or ip_address == "" then
        api_utils.json_response({error = "IP地址不能为空"}, 400)
        return
    end
    
    -- 验证IP地址格式（支持单个IP、多个IP、CIDR、IP范围）
    local is_valid, error_msg = _M.validate_ip_value(ip_address)
    if not is_valid then
        api_utils.json_response({error = error_msg or "IP地址格式不正确"}, 400)
        return
    end
    
    -- status默认为1（启用），但创建时不需要验证，因为已经设置为1
    
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
    
    -- 检查当前白名单条目数量（在插入前）
    local count_ok, count_res, count_err = pcall(function()
        local count_sql = "SELECT COUNT(*) as total FROM waf_system_access_whitelist"
        return mysql_pool.query(count_sql)
    end)
    
    local is_first_entry = false
    if count_ok and not count_err and count_res and count_res[1] then
        local current_count = tonumber(count_res[1].total) or 0
        is_first_entry = (current_count == 0)
    end
    
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
    
    -- 如果是第一条白名单条目，自动开启系统白名单
    if is_first_entry then
        local update_config_ok, update_config_res, update_config_err = pcall(function()
            local update_sql = [[
                UPDATE waf_system_config 
                SET config_value = '1'
                WHERE config_key = 'system_access_whitelist_enabled'
            ]]
            return mysql_pool.query(update_sql)
        end)
        
        if update_config_ok and not update_config_err then
            ngx.log(ngx.INFO, "create: 第一条白名单条目已创建，自动开启系统白名单")
            audit_log.log("update", "system_config", "system_access_whitelist_enabled", 
                "添加第一条白名单条目，自动开启系统白名单", "success")
        else
            ngx.log(ngx.WARN, "create: 第一条白名单条目已创建，但自动开启系统白名单失败: ", tostring(update_config_err))
        end
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
    
    local message = "创建成功，nginx配置正在重新加载"
    if is_first_entry then
        message = "创建成功，系统白名单已自动开启，nginx配置正在重新加载"
    end
    
    api_utils.json_response({
        success = true,
        message = message,
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
        -- 验证IP地址格式（支持单个IP、多个IP、CIDR、IP范围）
        local is_valid, error_msg = _M.validate_ip_value(ip_address)
        if not is_valid then
            api_utils.json_response({error = error_msg or "IP地址格式不正确"}, 400)
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
    
    -- 如果传入了status参数，则更新状态（用于启用/禁用功能）
    local status = nil
    if args.status ~= nil then
        status = tonumber(args.status)
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
    
    -- 先查询要删除的条目信息（检查状态）
    local entry_ok, entry_res, entry_err = pcall(function()
        local entry_sql = "SELECT id, ip_address, status FROM waf_system_access_whitelist WHERE id = ? LIMIT 1"
        return mysql_pool.query(entry_sql, id)
    end)
    
    if not entry_ok or entry_err or not entry_res or #entry_res == 0 then
        ngx.log(ngx.ERR, "delete: failed to query entry or entry not found: ", tostring(entry_err))
        api_utils.json_response({error = "白名单条目不存在"}, 404)
        return
    end
    
    local entry_status = tonumber(entry_res[1].status) or 0
    local is_enabled_entry = (entry_status == 1)  -- 要删除的条目是否是启用的
    
    -- 删除前检查当前启用的白名单条目数量（只统计status=1的条目）
    -- 因为系统白名单检查时只检查status=1的启用条目
    local count_before_ok, count_before_res, count_before_err = pcall(function()
        local count_sql = "SELECT COUNT(*) as total FROM waf_system_access_whitelist WHERE status = 1"
        return mysql_pool.query(count_sql)
    end)
    
    local is_last_enabled_entry = false
    if count_before_ok and not count_before_err and count_before_res and count_before_res[1] then
        local count_before = tonumber(count_before_res[1].total) or 0
        -- 如果删除前只有1条启用的条目，且要删除的这条也是启用的，删除后就没有启用的条目了
        is_last_enabled_entry = (count_before == 1 and is_enabled_entry)
        ngx.log(ngx.DEBUG, "delete: count_before=", count_before, ", is_enabled_entry=", is_enabled_entry, ", is_last_enabled_entry=", is_last_enabled_entry)
    end
    
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
    
    -- 如果删除的是最后一条启用的白名单条目，自动关闭系统白名单
    if is_last_enabled_entry then
        local update_config_ok, update_config_res, update_config_err = pcall(function()
            local update_sql = [[
                UPDATE waf_system_config 
                SET config_value = '0'
                WHERE config_key = 'system_access_whitelist_enabled'
            ]]
            return mysql_pool.query(update_sql)
        end)
        
        if update_config_ok and not update_config_err then
            ngx.log(ngx.INFO, "delete: 最后一条启用的白名单条目已删除，自动关闭系统白名单")
            audit_log.log("update", "system_config", "system_access_whitelist_enabled", 
                "删除最后一条启用的白名单条目，自动关闭系统白名单", "success")
        else
            ngx.log(ngx.WARN, "delete: 最后一条启用的白名单条目已删除，但自动关闭系统白名单失败: ", tostring(update_config_err))
        end
    end
    
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
    
    local message = "删除成功，nginx配置正在重新加载"
    if is_last_enabled_entry then
        message = "删除成功，系统白名单已自动关闭（已无启用的白名单条目），nginx配置正在重新加载"
    end
    
    api_utils.json_response({
        success = true,
        message = message
    })
end

-- 验证IP值格式（支持单个IP、多个IP、CIDR、IP范围）
function _M.validate_ip_value(ip_value)
    if not ip_value or ip_value == "" then
        return false, "IP地址不能为空"
    end
    
    -- 检查是否包含逗号（多个IP）
    if ip_value:match(",") then
        -- 多个IP，逐个验证
        local ip_list = {}
        for ip_str in ip_value:gmatch("([^,]+)") do
            local ip = ip_str:match("^%s*(.-)%s*$")  -- 去除首尾空格
            if ip and ip ~= "" then
                table.insert(ip_list, ip)
            end
        end
        
        if #ip_list == 0 then
            return false, "未找到有效的IP地址"
        end
        
        -- 验证每个IP
        for _, ip in ipairs(ip_list) do
            local is_valid = false
            -- 检查是否为单个IP
            if ip_utils.is_valid_ip(ip) then
                is_valid = true
            -- 检查是否为CIDR格式
            elseif ip_utils.is_valid_cidr(ip) then
                is_valid = true
            -- 检查是否为IP范围格式
            else
                local start_ip, end_ip = ip_utils.parse_ip_range(ip)
                if start_ip and end_ip then
                    is_valid = true
                end
            end
            
            if not is_valid then
                return false, "无效的IP格式: " .. ip .. "（应为单个IP如192.168.1.100、多个IP如192.168.1.1,192.168.1.2、CIDR格式如192.168.1.0/24或IP范围如192.168.1.1-192.168.1.100）"
            end
        end
        
        return true
    else
        -- 单个IP或IP段
        local is_valid = false
        -- 检查是否为单个IP
        if ip_utils.is_valid_ip(ip_value) then
            is_valid = true
        -- 检查是否为CIDR格式
        elseif ip_utils.is_valid_cidr(ip_value) then
            is_valid = true
        -- 检查是否为IP范围格式
        else
            local start_ip, end_ip = ip_utils.parse_ip_range(ip_value)
            if start_ip and end_ip then
                is_valid = true
            end
        end
        
        if not is_valid then
            return false, "无效的IP格式（应为单个IP如192.168.1.100、多个IP如192.168.1.1,192.168.1.2、CIDR格式如192.168.1.0/24或IP范围如192.168.1.1-192.168.1.100）"
        end
        
        return true
    end
end

-- 检查IP是否在白名单中（用于认证中间件）
function _M.check_ip_allowed(ip_address)
    if not ip_address then
        ngx.log(ngx.ERR, "check_ip_allowed: ip_address is nil")
        return false
    end
    
    ngx.log(ngx.DEBUG, "check_ip_allowed: checking IP: ", ip_address)
    
    -- 先检查开关是否启用（使用config_manager，带缓存）
    -- 如果配置不存在，config_manager会返回默认值0（未启用）
    local enabled = config_manager.get_config("system_access_whitelist_enabled", 0, "number")
    
    ngx.log(ngx.DEBUG, "check_ip_allowed: system_access_whitelist_enabled=", enabled)
    
    -- 如果配置不存在，尝试创建默认配置（异步，不阻塞）
    if enabled == nil then
        ngx.log(ngx.WARN, "check_ip_allowed: config not found, creating default config")
        ngx.timer.at(0, function()
            local ok, err = pcall(function()
                local insert_sql = [[
                    INSERT INTO waf_system_config (config_key, config_value, description) 
                    VALUES ('system_access_whitelist_enabled', '0', '是否启用系统访问白名单（1-启用，0-禁用，开启时只有白名单内的IP才能访问管理系统）')
                    ON DUPLICATE KEY UPDATE config_value = VALUES(config_value)
                ]]
                return mysql_pool.query(insert_sql)
            end)
            if not ok or err then
                ngx.log(ngx.ERR, "check_ip_allowed: failed to create default config: ", tostring(err))
            end
        end)
        enabled = 0  -- 默认未启用
    end
    
    if enabled == 0 then
        -- 白名单未启用，允许所有IP访问
        ngx.log(ngx.DEBUG, "check_ip_allowed: whitelist disabled (enabled=0), allowing access for IP: ", ip_address)
        return true
    end
    
    -- 白名单已启用，检查IP是否在白名单中
    ngx.log(ngx.INFO, "check_ip_allowed: whitelist enabled (enabled=1), checking IP: ", ip_address)
    local ok, res, err = pcall(function()
        local sql = "SELECT ip_address FROM waf_system_access_whitelist WHERE status = 1"
        return mysql_pool.query(sql)
    end)
    
    if not ok or err then
        ngx.log(ngx.ERR, "check_ip_allowed: failed to query whitelist: ", tostring(err))
        -- 查询失败时，为了安全，拒绝访问
        return false
    end
    
    -- 严格检查：res必须是非nil的表，且长度大于0
    -- 使用type检查确保res是table类型，使用#res检查数组长度
    -- 如果res不是table，或者res是空数组，都视为白名单为空
    if not res or type(res) ~= "table" or #res == 0 then
        -- 白名单为空，拒绝所有访问
        ngx.log(ngx.WARN, "check_ip_allowed: whitelist enabled but empty, denying access for IP: ", ip_address, 
            " (res type: ", type(res), ", res length: ", res and #res or "nil", ")")
        return false
    end
    
    ngx.log(ngx.INFO, "check_ip_allowed: found ", #res, " whitelist entries, checking IP: ", ip_address)
    
    -- 检查IP是否匹配任何白名单条目
    for _, row in ipairs(res) do
        local whitelist_ip = row.ip_address
        
        -- 检查是否包含逗号（多个IP）
        if whitelist_ip:match(",") then
            -- 多个IP，逐个检查
            for ip_str in whitelist_ip:gmatch("([^,]+)") do
                local ip = ip_str:match("^%s*(.-)%s*$")  -- 去除首尾空格
                if ip and ip ~= "" then
                    -- 检查是否为CIDR格式
                    if ip:match("/") then
                        if ip_utils.match_cidr(ip_address, ip) then
                            return true
                        end
                    -- 检查是否为IP范围格式
                    elseif ip:match("-") then
                        local start_ip, end_ip = ip_utils.parse_ip_range(ip)
                        if start_ip and end_ip and ip_utils.match_ip_range(ip_address, start_ip, end_ip) then
                            return true
                        end
                    -- 单个IP，直接比较
                    elseif ip_address == ip then
                        ngx.log(ngx.DEBUG, "check_ip_allowed: IP matched in comma-separated list: ", ip_address)
                        return true
                    end
                end
            end
        else
            -- 单个IP或IP段
            -- 检查是否为CIDR格式
            if whitelist_ip:match("/") then
                if ip_utils.match_cidr(ip_address, whitelist_ip) then
                    ngx.log(ngx.DEBUG, "check_ip_allowed: IP matched CIDR: ", ip_address, " in ", whitelist_ip)
                    return true
                end
            -- 检查是否为IP范围格式
            elseif whitelist_ip:match("-") then
                local start_ip, end_ip = ip_utils.parse_ip_range(whitelist_ip)
                if start_ip and end_ip and ip_utils.match_ip_range(ip_address, start_ip, end_ip) then
                    ngx.log(ngx.DEBUG, "check_ip_allowed: IP matched range: ", ip_address, " in ", whitelist_ip)
                    return true
                end
            -- 单个IP，直接比较
            elseif ip_address == whitelist_ip then
                ngx.log(ngx.DEBUG, "check_ip_allowed: IP matched exactly: ", ip_address)
                return true
            end
        end
    end
    
    ngx.log(ngx.WARN, "check_ip_allowed: IP ", ip_address, " not found in whitelist (checked ", #res, " entries)")
    return false
end

return _M

