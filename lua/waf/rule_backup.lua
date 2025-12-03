-- 规则本地备份模块
-- 路径：项目目录下的 lua/waf/rule_backup.lua（保持在项目目录，不复制到系统目录）
-- 功能：实现规则本地备份机制，用于数据库故障时的降级

local mysql_pool = require "waf.mysql_pool"
local config = require "config"
local path_utils = require "waf.path_utils"
local serializer = require "waf.serializer"
local cjson = require "cjson"

local _M = {}

-- 配置
-- 备份目录（优先使用配置，否则使用项目根目录下的backup目录）
local BACKUP_DIR = config.rule_backup and config.rule_backup.backup_dir or path_utils.get_backup_path()
local BACKUP_INTERVAL = config.rule_backup and config.rule_backup.backup_interval or 300  -- 备份间隔（秒，默认5分钟）
local MAX_BACKUP_FILES = config.rule_backup and config.rule_backup.max_backup_files or 10  -- 最大备份文件数
local ENABLE_BACKUP = config.rule_backup and config.rule_backup.enable or true

-- 确保备份目录存在
local function ensure_backup_dir()
    if not ENABLE_BACKUP then
        return true
    end
    
    -- 使用path_utils确保目录存在
    return path_utils.ensure_dir(BACKUP_DIR)
end

-- 备份规则到本地文件
function _M.backup_rules()
    if not ENABLE_BACKUP then
        return false, "backup disabled"
    end
    
    ensure_backup_dir()
    
    -- 查询所有启用的规则
    local sql = [[
        SELECT id, rule_type, rule_value, rule_name, description, 
               status, priority, start_time, end_time, rule_version
        FROM waf_block_rules
        WHERE status = 1
        ORDER BY id
    ]]
    
    local rules, err = mysql_pool.query(sql)
    if err then
        ngx.log(ngx.ERR, "backup rules query error: ", err)
        return false, err
    end
    
    -- 查询白名单规则
    local whitelist_sql = [[
        SELECT id, ip_type, ip_value, description, status
        FROM waf_whitelist
        WHERE status = 1
        ORDER BY id
    ]]
    
    local whitelist, err2 = mysql_pool.query(whitelist_sql)
    if err2 then
        ngx.log(ngx.ERR, "backup whitelist query error: ", err2)
        -- 继续备份，即使白名单查询失败
    end
    
    -- 构建备份数据
    local backup_data = {
        timestamp = ngx.time(),
        datetime = os.date("!%Y-%m-%d %H:%M:%S", ngx.time()),
        rules = rules or {},
        whitelist = whitelist or {}
    }
    
    -- 序列化数据
    local serialized, format = serializer.encode(backup_data)
    if not serialized then
        return false, "serialization failed"
    end
    
    -- 写入文件
    local timestamp = os.date("%Y%m%d_%H%M%S", ngx.time())
    local filename = BACKUP_DIR .. "/rules_backup_" .. timestamp .. "." .. format
    local file_handle = io.open(filename, "w")
    if not file_handle then
        return false, "failed to open backup file"
    end
    
    -- 如果是MessagePack，需要以二进制模式写入
    if format == "msgpack" then
        file_handle:write(serialized)
    else
        file_handle:write(serialized)
    end
    
    file_handle:close()
    
    -- 清理旧备份文件
    _M.cleanup_old_backups()
    
    ngx.log(ngx.INFO, "rules backed up to: ", filename)
    return true, filename
end

-- 从本地文件恢复规则
function _M.restore_rules(filename)
    if not filename then
        -- 查找最新的备份文件
        filename = _M.get_latest_backup()
        if not filename then
            return false, "no backup file found"
        end
    end
    
    local file_handle = io.open(filename, "r")
    if not file_handle then
        return false, "failed to open backup file"
    end
    
    local content = file_handle:read("*all")
    file_handle:close()
    
    -- 检测格式并反序列化
    local backup_data, format = serializer.decode(content)
    if not backup_data then
        return false, "deserialization failed"
    end
    
    -- 恢复规则（这里只是返回数据，实际恢复需要调用者处理）
    return backup_data, format
end

-- 获取最新的备份文件
function _M.get_latest_backup()
    ensure_backup_dir()
    
    -- 安全检查：防止路径注入攻击
    if BACKUP_DIR:match("[;&|`$(){}]") then
        ngx.log(ngx.ERR, "Invalid characters in BACKUP_DIR: ", BACKUP_DIR)
        return nil
    end
    
    -- 转义路径中的特殊字符（防止shell注入）
    local escaped_dir = BACKUP_DIR:gsub("'", "'\\''")
    
    -- 列出所有备份文件（使用安全转义）
    local cmd = "ls -t '" .. escaped_dir .. "/rules_backup_*.*' 2>/dev/null | head -1"
    local handle = io.popen(cmd)
    if not handle then
        return nil
    end
    
    local filename = handle:read("*line")
    handle:close()
    
    -- 验证文件名是否在备份目录内（防止路径遍历攻击）
    if filename and filename:match("^" .. BACKUP_DIR:gsub("%-", "%%-") .. "/") then
        return filename
    end
    
    return nil
end

-- 清理旧备份文件（只保留一个月的备份）
function _M.cleanup_old_backups()
    ensure_backup_dir()
    
    -- 安全检查：防止路径注入攻击
    if BACKUP_DIR:match("[;&|`$(){}]") then
        ngx.log(ngx.ERR, "Invalid characters in BACKUP_DIR: ", BACKUP_DIR)
        return
    end
    
    -- 转义路径中的特殊字符（防止shell注入）
    local escaped_dir = BACKUP_DIR:gsub("'", "'\\''")
    
    -- 列出所有备份文件（使用安全转义）
    local cmd = "ls '" .. escaped_dir .. "/rules_backup_*.*' 2>/dev/null"
    local handle = io.popen(cmd)
    if not handle then
        return
    end
    
    local current_time = ngx.time()
    -- 计算一个月前的时间戳（30天 = 30 * 24 * 60 * 60 秒）
    local one_month_ago = current_time - (30 * 24 * 60 * 60)
    
    for line in handle:lines() do
        -- 验证文件名是否在备份目录内（防止路径遍历攻击）
        if line:match("^" .. BACKUP_DIR:gsub("%-", "%%-") .. "/") then
            -- 从文件名中提取时间戳
            -- 文件名格式：rules_backup_YYYYMMDD_HHMMSS.json 或 rules_backup_YYYYMMDD_HHMMSS.msgpack
            local timestamp_str = line:match("rules_backup_(%d%d%d%d%d%d%d%d_%d%d%d%d%d%d)")
            if timestamp_str then
                -- 解析时间戳：YYYYMMDD_HHMMSS
                local year = tonumber(timestamp_str:sub(1, 4))
                local month = tonumber(timestamp_str:sub(5, 6))
                local day = tonumber(timestamp_str:sub(7, 8))
                local hour = tonumber(timestamp_str:sub(10, 11))
                local minute = tonumber(timestamp_str:sub(12, 13))
                local second = tonumber(timestamp_str:sub(14, 15))
                
                if year and month and day and hour and minute and second then
                    -- 使用os.time构建时间戳
                    -- 注意：备份文件名使用os.date("%Y%m%d_%H%M%S", ngx.time())生成，使用本地时区
                    -- os.time也使用本地时区，所以可以直接使用
                    local file_time = os.time({
                        year = year,
                        month = month,
                        day = day,
                        hour = hour,
                        min = minute,
                        sec = second
                    })
                    
                    -- 如果文件时间早于一个月前，删除该文件
                    if file_time and file_time < one_month_ago then
                        -- 再次验证文件路径（双重检查，防止路径遍历攻击）
                        if line:match("^" .. BACKUP_DIR:gsub("%-", "%%-") .. "/") then
                            local ok, err = os.remove(line)
                            if ok then
                                ngx.log(ngx.INFO, "removed old backup file (older than 1 month): ", line, 
                                        " (file_time: ", os.date("%Y-%m-%d %H:%M:%S", file_time), 
                                        ", threshold: ", os.date("%Y-%m-%d %H:%M:%S", one_month_ago), ")")
                            else
                                ngx.log(ngx.WARN, "failed to remove old backup file: ", line, ", error: ", err or "unknown")
                            end
                        end
                    end
                else
                    -- 如果无法解析时间戳，记录警告但不删除（可能是旧格式或其他文件）
                    ngx.log(ngx.WARN, "cannot parse timestamp from backup file: ", line)
                end
            else
                -- 如果文件名格式不匹配，记录警告但不删除（可能是其他文件）
                ngx.log(ngx.WARN, "backup file name format not recognized: ", line)
            end
        end
    end
    handle:close()
end

-- 从备份加载规则到缓存（降级模式）
function _M.load_rules_from_backup()
    local backup_data, format = _M.restore_rules()
    if not backup_data then
        return false, "failed to restore from backup"
    end
    
    local cache = ngx.shared.waf_cache
    local cjson = require "cjson"
    
    -- 加载封控规则
    if backup_data.rules and #backup_data.rules > 0 then
        -- 过滤IP段规则
        local ip_range_rules = {}
        for _, rule in ipairs(backup_data.rules) do
            if rule.rule_type == "ip_range" then
                table.insert(ip_range_rules, rule)
            end
        end
        
        if #ip_range_rules > 0 then
            cache:set("rule_list:ip_range:block", cjson.encode(ip_range_rules), 3600)
            ngx.log(ngx.INFO, "loaded ", #ip_range_rules, " IP range rules from backup")
        end
    end
    
    -- 加载白名单规则
    if backup_data.whitelist and #backup_data.whitelist > 0 then
        local ip_range_whitelist = {}
        for _, rule in ipairs(backup_data.whitelist) do
            if rule.ip_type == "ip_range" then
                table.insert(ip_range_whitelist, rule)
            end
        end
        
        if #ip_range_whitelist > 0 then
            cache:set("rule_list:ip_range:whitelist", cjson.encode(ip_range_whitelist), 3600)
            ngx.log(ngx.INFO, "loaded ", #ip_range_whitelist, " whitelist rules from backup")
        end
    end
    
    return true, "rules loaded from backup"
end

-- 检查备份文件是否存在
function _M.has_backup()
    local latest = _M.get_latest_backup()
    return latest ~= nil
end

return _M

