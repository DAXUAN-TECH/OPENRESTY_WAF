-- 配置验证模块
-- 路径：项目目录下的 lua/waf/config_validator.lua（保持在项目目录，不复制到系统目录）
-- 功能：验证配置文件的有效性，启动时检查配置

local config = require "config"
local ip_utils = require "waf.ip_utils"

local _M = {}

-- 验证结果
local ValidationResult = {
    SUCCESS = "success",
    WARNING = "warning",
    ERROR = "error"
}

-- 验证结果列表
local validation_results = {}

-- 添加验证结果
local function add_result(level, section, field, message)
    table.insert(validation_results, {
        level = level,
        section = section,
        field = field,
        message = message
    })
end

-- 验证MySQL配置
local function validate_mysql()
    if not config.mysql then
        add_result(ValidationResult.ERROR, "mysql", nil, "MySQL配置缺失")
        return false
    end
    
    local mysql = config.mysql
    
    -- 验证必填字段
    if not mysql.host or mysql.host == "" then
        add_result(ValidationResult.ERROR, "mysql", "host", "MySQL主机地址不能为空")
    end
    
    if not mysql.port or mysql.port <= 0 or mysql.port > 65535 then
        add_result(ValidationResult.ERROR, "mysql", "port", "MySQL端口无效（范围：1-65535）")
    end
    
    if not mysql.database or mysql.database == "" then
        add_result(ValidationResult.ERROR, "mysql", "database", "MySQL数据库名不能为空")
    end
    
    if not mysql.user or mysql.user == "" then
        add_result(ValidationResult.ERROR, "mysql", "user", "MySQL用户名不能为空")
    end
    
    if not mysql.password then
        add_result(ValidationResult.WARNING, "mysql", "password", "MySQL密码未设置（可能使用空密码）")
    end
    
    -- 验证连接池配置
    if mysql.pool_size and (mysql.pool_size < 1 or mysql.pool_size > 1000) then
        add_result(ValidationResult.WARNING, "mysql", "pool_size", "连接池大小建议在1-1000之间，当前值：" .. mysql.pool_size)
    end
    
    if mysql.pool_timeout and mysql.pool_timeout < 1000 then
        add_result(ValidationResult.WARNING, "mysql", "pool_timeout", "连接池超时时间建议至少1000毫秒")
    end
    
    return true
end

-- 验证Redis配置（可选）
local function validate_redis()
    if not config.redis then
        return true  -- Redis是可选的
    end
    
    local redis = config.redis
    
    if redis.host and redis.host ~= "" then
        if not redis.port or redis.port <= 0 or redis.port > 65535 then
            add_result(ValidationResult.ERROR, "redis", "port", "Redis端口无效（范围：1-65535）")
        end
    end
    
    return true
end

-- 验证缓存配置
local function validate_cache()
    if not config.cache then
        add_result(ValidationResult.ERROR, "cache", nil, "缓存配置缺失")
        return false
    end
    
    local cache = config.cache
    
    if cache.ttl and cache.ttl < 1 then
        add_result(ValidationResult.WARNING, "cache", "ttl", "缓存TTL建议至少1秒")
    end
    
    if cache.max_items and cache.max_items < 100 then
        add_result(ValidationResult.WARNING, "cache", "max_items", "最大缓存项数建议至少100")
    end
    
    if cache.rule_list_ttl and cache.rule_list_ttl < 60 then
        add_result(ValidationResult.WARNING, "cache", "rule_list_ttl", "规则列表缓存时间建议至少60秒")
    end
    
    return true
end

-- 验证日志配置
local function validate_log()
    if not config.log then
        add_result(ValidationResult.ERROR, "log", nil, "日志配置缺失")
        return false
    end
    
    local log = config.log
    
    if log.batch_size and (log.batch_size < 1 or log.batch_size > 10000) then
        add_result(ValidationResult.WARNING, "log", "batch_size", "批量写入大小建议在1-10000之间")
    end
    
    if log.batch_interval and log.batch_interval < 0.1 then
        add_result(ValidationResult.WARNING, "log", "batch_interval", "批量写入间隔建议至少0.1秒")
    end
    
    if log.max_retry and log.max_retry < 0 then
        add_result(ValidationResult.WARNING, "log", "max_retry", "最大重试次数不能为负数")
    end
    
    if log.buffer_warn_threshold and (log.buffer_warn_threshold < 0 or log.buffer_warn_threshold > 1) then
        add_result(ValidationResult.WARNING, "log", "buffer_warn_threshold", "缓冲区警告阈值应在0-1之间")
    end
    
    return true
end

-- 验证封控配置
local function validate_block()
    if not config.block then
        add_result(ValidationResult.ERROR, "block", nil, "封控配置缺失")
        return false
    end
    
    if config.block.enable == nil then
        add_result(ValidationResult.WARNING, "block", "enable", "封控启用状态未设置，将使用默认值")
    end
    
    return true
end

-- 验证自动封控配置
local function validate_auto_block()
    if not config.auto_block then
        return true  -- 可选配置
    end
    
    local auto_block = config.auto_block
    
    if auto_block.enable and auto_block.frequency_threshold then
        if auto_block.frequency_threshold < 1 then
            add_result(ValidationResult.WARNING, "auto_block", "frequency_threshold", "频率阈值建议至少1")
        end
    end
    
    if auto_block.error_rate_threshold then
        if auto_block.error_rate_threshold < 0 or auto_block.error_rate_threshold > 1 then
            add_result(ValidationResult.ERROR, "auto_block", "error_rate_threshold", "错误率阈值应在0-1之间")
        end
    end
    
    if auto_block.block_duration and auto_block.block_duration < 60 then
        add_result(ValidationResult.WARNING, "auto_block", "block_duration", "自动封控时长建议至少60秒")
    end
    
    return true
end

-- 验证GeoIP配置
local function validate_geo()
    if not config.geo then
        return true  -- 可选配置
    end
    
    if config.geo.enable then
        -- 如果启用了GeoIP，检查数据库路径
        if not config.geo.geoip_db_path or config.geo.geoip_db_path == "" then
            -- 路径会在init中动态设置，这里只警告
            add_result(ValidationResult.WARNING, "geo", "geoip_db_path", "GeoIP数据库路径未设置，将在初始化时自动检测")
        else
            -- 验证路径格式（不能是绝对路径，应该是相对路径或动态路径）
            if config.geo.geoip_db_path:match("^/") then
                add_result(ValidationResult.WARNING, "geo", "geoip_db_path", "建议使用相对路径以保证可移植性")
            end
        end
    end
    
    return true
end

-- 验证告警配置
local function validate_alert()
    if not config.alert then
        return true  -- 可选配置
    end
    
    local alert = config.alert
    
    if alert.enable and alert.thresholds then
        local thresholds = alert.thresholds
        
        if thresholds.block_rate and thresholds.block_rate < 1 then
            add_result(ValidationResult.WARNING, "alert", "thresholds.block_rate", "封控率阈值建议至少1")
        end
        
        if thresholds.cache_miss_rate and (thresholds.cache_miss_rate < 0 or thresholds.cache_miss_rate > 1) then
            add_result(ValidationResult.ERROR, "alert", "thresholds.cache_miss_rate", "缓存未命中率阈值应在0-1之间")
        end
        
        if thresholds.pool_usage and (thresholds.pool_usage < 0 or thresholds.pool_usage > 1) then
            add_result(ValidationResult.ERROR, "alert", "thresholds.pool_usage", "连接池使用率阈值应在0-1之间")
        end
        
        if thresholds.error_rate and (thresholds.error_rate < 0 or thresholds.error_rate > 1) then
            add_result(ValidationResult.ERROR, "alert", "thresholds.error_rate", "错误率阈值应在0-1之间")
        end
    end
    
    return true
end

-- 验证规则备份配置
local function validate_rule_backup()
    if not config.rule_backup then
        return true  -- 可选配置
    end
    
    local rule_backup = config.rule_backup
    
    if rule_backup.enable then
        if rule_backup.backup_dir then
            -- 检查备份目录路径（不能使用绝对路径）
            if rule_backup.backup_dir:match("^/") and not rule_backup.backup_dir:match("^/tmp/") then
                add_result(ValidationResult.WARNING, "rule_backup", "backup_dir", "备份目录建议使用相对路径或/tmp目录以保证可移植性")
            end
        end
        
        if rule_backup.backup_interval and rule_backup.backup_interval < 60 then
            add_result(ValidationResult.WARNING, "rule_backup", "backup_interval", "备份间隔建议至少60秒")
        end
        
        if rule_backup.max_backup_files and rule_backup.max_backup_files < 1 then
            add_result(ValidationResult.WARNING, "rule_backup", "max_backup_files", "最大备份文件数建议至少1")
        end
    end
    
    return true
end

-- 执行所有验证
function _M.validate_all()
    validation_results = {}
    
    local all_valid = true
    
    -- 执行各项验证
    if not validate_mysql() then all_valid = false end
    validate_redis()  -- Redis是可选的，不强制
    if not validate_cache() then all_valid = false end
    if not validate_log() then all_valid = false end
    if not validate_block() then all_valid = false end
    validate_auto_block()  -- 可选
    validate_geo()  -- 可选
    validate_alert()  -- 可选
    validate_rule_backup()  -- 可选
    
    return all_valid, validation_results
end

-- 获取验证结果
function _M.get_results()
    return validation_results
end

-- 检查是否有错误
function _M.has_errors()
    for _, result in ipairs(validation_results) do
        if result.level == ValidationResult.ERROR then
            return true
        end
    end
    return false
end

-- 检查是否有警告
function _M.has_warnings()
    for _, result in ipairs(validation_results) do
        if result.level == ValidationResult.WARNING then
            return true
        end
    end
    return false
end

-- 格式化验证结果（用于日志输出）
function _M.format_results()
    local output = {}
    
    local errors = {}
    local warnings = {}
    
    for _, result in ipairs(validation_results) do
        local msg = string.format("[%s.%s] %s", result.section, result.field or "general", result.message)
        if result.level == ValidationResult.ERROR then
            table.insert(errors, msg)
        elseif result.level == ValidationResult.WARNING then
            table.insert(warnings, msg)
        end
    end
    
    if #errors > 0 then
        table.insert(output, "配置错误：")
        for _, err in ipairs(errors) do
            table.insert(output, "  ✗ " .. err)
        end
    end
    
    if #warnings > 0 then
        table.insert(output, "配置警告：")
        for _, warn in ipairs(warnings) do
            table.insert(output, "  ⚠ " .. warn)
        end
    end
    
    if #errors == 0 and #warnings == 0 then
        table.insert(output, "✓ 配置验证通过")
    end
    
    return table.concat(output, "\n")
end

-- 验证特定配置项
function _M.validate_field(section, field, value)
    -- 可以根据需要实现特定字段的验证逻辑
    return true, nil
end

return _M

