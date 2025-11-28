-- WAF 配置文件
-- 路径：项目目录下的 lua/config.lua（保持在项目目录，不复制到系统目录）
-- 注意：所有功能模块的 enable 配置都从数据库读取，支持热更新

local config_manager = nil  -- 延迟加载，避免循环依赖

-- 延迟加载 config_manager
local function get_config_manager()
    if not config_manager then
        config_manager = require "waf.config_manager"
    end
    return config_manager
end

-- 获取配置值的辅助函数（从数据库读取，带默认值）
local function get_config_value(config_key, default_value, value_type)
    local cm = get_config_manager()
    if cm then
        return cm.get_config(config_key, default_value, value_type or "boolean")
    end
    return default_value
end

-- 创建配置表的元表，实现动态读取 enable 等字段
local function create_config_metatable(config_key_map)
    return {
        __index = function(t, k)
            -- 先检查表中是否已有该字段（避免覆盖已有字段）
            local raw_value = rawget(t, k)
            if raw_value ~= nil then
                return raw_value
            end
            -- 如果访问的是需要从数据库读取的字段，从数据库读取
            if config_key_map[k] then
                local config_key, default_value, value_type = config_key_map[k][1], config_key_map[k][2], config_key_map[k][3]
                return get_config_value(config_key, default_value, value_type or "boolean")
            end
            -- 其他字段返回 nil
            return nil
        end
    }
end

local _M = {}

-- MySQL 配置
_M.mysql = {
    host = "127.0.0.1",
    port = 3306,
    database = "waf_db",
    user = "waf",
    password = "123456",
    max_packet_size = 1024 * 1024,
    pool_size = 50,  -- 连接池大小
    pool_timeout = 10000,  -- 连接池超时（毫秒）
}

-- Redis 配置（可选）
_M.redis = {
    host = "127.0.0.1",
    port = 6379,
    password = 123456,
    db = 0,
    timeout = 1000,  -- 超时时间（毫秒）
    pool_size = 100,
}

-- 缓存配置
_M.cache = {
    ttl = 60,  -- 缓存过期时间（秒）
    max_items = 10000,  -- 最大缓存项数
    rule_list_ttl = 300,  -- IP 段规则列表缓存时间（秒，5分钟）
}

-- 日志配置
_M.log = {
    batch_size = 100,  -- 批量写入大小
    batch_interval = 1,  -- 批量写入间隔（秒）
    enable_async = true,  -- 是否异步写入
    max_retry = 3,  -- 最大重试次数
    retry_delay = 0.1,  -- 重试延迟（秒）
    buffer_warn_threshold = 0.8,  -- 缓冲区警告阈值（80%）
}

-- 封控配置（block_page 从数据库读取：block_page）
_M.block = setmetatable({
    -- block_page 从数据库读取，默认值为下面的 HTML
}, create_config_metatable({
    enable = {"block_enable", true, "boolean"},
    block_page = {"block_page", [[
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Access Denied</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #d32f2f; }
    </style>
</head>
<body>
    <h1>403 Forbidden</h1>
    <p>Your access has been denied.</p>
</body>
</html>
    ]], "string"}
}))

-- 白名单配置（enable 从数据库读取：whitelist_enable）
_M.whitelist = setmetatable({}, create_config_metatable({
    enable = {"whitelist_enable", true, "boolean"}
}))

-- 地域封控配置（enable 从数据库读取：geo_enable）
_M.geo = setmetatable({
    -- GeoIP2 数据库路径（相对于项目根目录）
    -- 使用 GeoLite2-City.mmdb 以支持省市级别查询
    -- 数据库文件需要放在项目目录的 lua/geoip/ 下
    -- 路径会在运行时动态获取
    geoip_db_path = nil,  -- 将在 init_by_lua 中动态设置
}, create_config_metatable({
    enable = {"geo_enable", false, "boolean"}
}))

-- 自动封控配置（enable 从数据库读取：auto_block_enable）
_M.auto_block = setmetatable({
    frequency_threshold = 100,  -- 频率阈值（每分钟访问次数）
    error_rate_threshold = 0.5,  -- 错误率阈值（0-1之间，如0.5表示50%）
    scan_path_threshold = 20,  -- 扫描行为阈值（短时间内访问的不同路径数）
    window_size = 60,  -- 统计窗口大小（秒）
    block_duration = 3600,  -- 自动封控时长（秒，默认1小时）
    check_interval = 10,  -- 检查间隔（秒）
}, create_config_metatable({
    enable = {"auto_block_enable", true, "boolean"}
}))

-- 代理IP安全配置（enable_trusted_proxy_check 从数据库读取：proxy_enable_trusted_proxy_check）
_M.proxy = setmetatable({
    trusted_proxies_cache_ttl = 300,  -- 受信任代理列表缓存时间（秒）
    log_ip_resolution = false,  -- 是否记录IP解析过程日志（调试用）
}, create_config_metatable({
    enable_trusted_proxy_check = {"proxy_enable_trusted_proxy_check", true, "boolean"}
}))

-- 缓存失效配置（enable_version_check 从数据库读取：cache_invalidation_enable_version_check）
_M.cache_invalidation = setmetatable({
    version_check_interval = 30,  -- 版本号检查间隔（秒）
}, create_config_metatable({
    enable_version_check = {"cache_invalidation_enable_version_check", true, "boolean"}
}))

-- 降级机制配置（enable 从数据库读取：fallback_enable）
_M.fallback = setmetatable({
    health_check_interval = 10,  -- 健康检查间隔（秒）
}, create_config_metatable({
    enable = {"fallback_enable", true, "boolean"}
}))

-- 监控指标配置（enable 从数据库读取：metrics_enable）
_M.metrics = setmetatable({
    prometheus_endpoint = "/metrics",  -- Prometheus指标导出端点
}, create_config_metatable({
    enable = {"metrics_enable", true, "boolean"}
}))

-- 缓存穿透防护配置（所有 enable 相关配置从数据库读取）
_M.cache_protection = setmetatable({
    empty_result_ttl = 60,  -- 空结果缓存时间（秒）
    bloom_filter_size = 100000,  -- 布隆过滤器大小
    bloom_filter_hash_count = 3,  -- 布隆过滤器哈希函数数量
    rate_limit_window = 60,  -- 频率限制窗口（秒）
    rate_limit_threshold = 100,  -- 频率限制阈值（每个窗口内的请求数）
}, create_config_metatable({
    enable = {"cache_protection_enable", true, "boolean"},
    enable_bloom_filter = {"cache_protection_enable_bloom_filter", true, "boolean"},
    enable_rate_limit = {"cache_protection_enable_rate_limit", true, "boolean"}
}))

-- 连接池监控配置（enable 从数据库读取：pool_monitor_enable）
_M.pool_monitor = setmetatable({
    check_interval = 10,  -- 监控检查间隔（秒）
    warn_threshold = 0.8,  -- 连接池警告阈值（80%）
    max_pool_size = 100,  -- 最大连接池大小
    min_pool_size = 10,  -- 最小连接池大小
    growth_step = 10,  -- 连接池增长步长
}, create_config_metatable({
    enable = {"pool_monitor_enable", true, "boolean"}
}))

-- 缓存配置增强
_M.cache.inactive_ttl = 30  -- 不活跃IP缓存时间（秒）
_M.cache.access_count_threshold = 3  -- 活跃访问次数阈值

-- 日志配置增强
_M.log.enable_local_backup = true  -- 是否启用本地日志备份
_M.log.local_log_path = nil  -- 本地日志文件路径（nil表示使用项目根目录下的logs目录，会在运行时动态设置）
_M.log.queue_max_size = 10000  -- 日志队列最大大小

-- 缓存预热配置（enable 从数据库读取：cache_warmup_enable）
_M.cache_warmup = setmetatable({
    interval = 300,  -- 预热间隔（秒）
    batch_size = 100,  -- 预热批次大小
    smooth_transition = true,  -- 是否启用平滑过渡
    warmup_common_ips = false,  -- 是否预热常用IP（可选）
}, create_config_metatable({
    enable = {"cache_warmup_enable", true, "boolean"}
}))

-- GeoIP配置增强
_M.geo.cache_ttl = 3600  -- GeoIP查询结果缓存时间（秒，默认1小时）

-- 序列化配置
_M.serializer = {
    use_msgpack = false,  -- 是否使用MessagePack（需要安装resty.msgpack）
}

-- 规则备份配置（enable 从数据库读取：rule_backup_enable）
_M.rule_backup = setmetatable({
    backup_dir = nil,  -- 备份目录（nil表示使用项目根目录下的backup目录，会在运行时动态设置）
    backup_interval = 300,  -- 备份间隔（秒，默认5分钟）
    max_backup_files = 10,  -- 最大备份文件数
}, create_config_metatable({
    enable = {"rule_backup_enable", true, "boolean"}
}))

-- Redis缓存配置（二级缓存，enable 从数据库读取：redis_cache_enable）
_M.redis_cache = setmetatable({
    key_prefix = "waf:",  -- Redis键前缀
    ttl = 300,  -- 默认TTL（秒）
}, create_config_metatable({
    enable = {"redis_cache_enable", true, "boolean"}
}))

-- 规则更新通知配置（enable 从数据库读取：rule_notification_enable）
_M.rule_notification = setmetatable({
    use_redis_pubsub = false,  -- 是否使用Redis Pub/Sub（需要Redis）
    channel = "waf:rule_update",  -- Redis Pub/Sub频道
}, create_config_metatable({
    enable = {"rule_notification_enable", true, "boolean"}
}))

-- 告警配置（enable 从数据库读取：alert_enable）
_M.alert = setmetatable({
    cooldown = 300,  -- 告警冷却时间（秒，防止重复告警）
    webhook_url = nil,  -- Webhook URL（可选，用于发送告警到外部系统）
    thresholds = {
        block_rate = 100,  -- 每分钟封控次数阈值
        cache_miss_rate = 0.5,  -- 缓存未命中率阈值（50%）
        db_failure_count = 3,  -- 数据库连续失败次数阈值
        pool_usage = 0.9,  -- 连接池使用率阈值（90%）
        error_rate = 0.1,  -- 错误率阈值（10%）
    }
}, create_config_metatable({
    enable = {"alert_enable", true, "boolean"}
}))

-- 功能开关配置（可通过Web界面控制）
_M.features = {
    -- 规则管理界面功能
    rule_management_ui = {
        enable = true,  -- 是否启用规则管理界面
        description = "规则管理Web界面，提供规则的CRUD操作"
    },
    -- 测试功能
    testing = {
        enable = true,  -- 是否启用测试功能
        description = "单元测试和集成测试功能"
    },
    -- 配置验证功能
    config_validation = {
        enable = true,  -- 是否启用配置验证
        description = "配置验证功能，启动时检查配置有效性"
    },
    -- 配置检查API
    config_check_api = {
        enable = true,  -- 是否启用配置检查API
        description = "配置检查API端点，提供配置验证结果查询"
    },
    -- 统计报表功能
    stats = {
        enable = true,  -- 是否启用统计报表
        description = "封控统计报表功能，提供封控数据统计和分析"
    },
    -- 监控面板功能
    monitor = {
        enable = true,  -- 是否启用监控面板
        description = "实时监控面板功能，显示系统运行状态和关键指标"
    }
}

-- TOTP 配置
_M.totp = {
    -- QR 码生成方式：local（本地SVG生成）或 external（使用外部服务）
    qr_generator = "local",  -- 内网部署建议使用 "local"
    -- 外部 QR 码服务 URL（当 qr_generator 为 "external" 时使用）
    external_qr_url = "https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=",
    -- 是否允许手动输入密钥（当无法扫描 QR 码时）
    allow_manual_entry = true
}

return _M

