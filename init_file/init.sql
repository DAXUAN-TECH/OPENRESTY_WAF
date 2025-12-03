-- ============================================
-- OpenResty WAF 数据库设计（优化版 v2.1）
-- ============================================
-- 数据库名：waf_db
-- 字符集：utf8mb4（支持完整的UTF-8字符集，包括emoji等特殊字符）
-- 排序规则：utf8mb4_general_ci（通用排序规则，适合大多数场景）
-- 存储引擎：InnoDB（支持事务和外键约束）
-- 
-- 优化说明：
-- 1. 兼容 MySQL 5.7 和 8.0
-- 2. 优化索引结构，去除冗余索引，添加覆盖索引
-- 3. 优化字段类型，提高查询性能
-- 4. 添加联合索引，减少回表查询
-- 5. 优化SQL语句，使用INSERT IGNORE提高性能
-- 6. 优化视图查询，使用子查询和索引提示
-- 7. 确保所有字段完整，支持location_paths等新功能
-- 8. 添加缺失的索引，优化常用查询路径
-- 
-- 数据库用途：
-- 1. 存储WAF封控规则、白名单规则
-- 2. 记录访问日志和封控日志
-- 3. 存储用户信息和会话信息
-- 4. 存储系统配置和功能开关
-- 5. 存储反向代理配置（支持多location路径）
-- 6. 存储IP频率统计和自动封控记录
-- 
-- 版本历史：
-- v2.1 (2025-12-03): 添加缺失索引，优化INSERT语句，完善表结构
-- v2.0 (2025-12-03): 优化索引结构，添加联合索引，优化视图查询
-- v1.0: 初始版本
-- ============================================

CREATE DATABASE IF NOT EXISTS waf_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

USE waf_db;

-- ============================================
-- 1. 访问日志表（高频写入表，优化索引）
-- ============================================
CREATE TABLE IF NOT EXISTS waf_access_logs (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    client_ip VARCHAR(45) NOT NULL COMMENT '客户端IP地址（支持IPv6）',
    request_domain VARCHAR(255) DEFAULT NULL COMMENT '请求域名（Host头，用于区分不同域名的访问）',
    request_path VARCHAR(512) NOT NULL COMMENT '请求路径',
    request_method VARCHAR(10) NOT NULL DEFAULT 'GET' COMMENT '请求方法',
    status_code SMALLINT UNSIGNED NOT NULL COMMENT 'HTTP响应状态码（使用SMALLINT节省空间）',
    user_agent VARCHAR(512) DEFAULT NULL COMMENT 'User-Agent',
    referer VARCHAR(512) DEFAULT NULL COMMENT 'Referer',
    request_time DATETIME NOT NULL COMMENT '请求时间',
    response_time MEDIUMINT UNSIGNED DEFAULT NULL COMMENT '响应时间（毫秒，使用MEDIUMINT节省空间）',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (id),
    -- 优化：去除冗余索引，使用联合索引覆盖常用查询
    KEY idx_client_ip_time (client_ip, request_time) COMMENT 'IP和时间联合索引，覆盖按IP和时间范围查询',
    KEY idx_request_time (request_time) COMMENT '请求时间索引，用于时间范围查询和清理',
    KEY idx_status_code_time (status_code, request_time) COMMENT '状态码和时间联合索引，用于错误统计',
    KEY idx_domain_time (request_domain, request_time) COMMENT '域名和时间联合索引，用于按域名统计',
    KEY idx_request_path (request_path(100)) COMMENT '请求路径前缀索引，用于路径统计',
    KEY idx_domain_path_time (request_domain, request_path(100), request_time) COMMENT '域名、路径和时间联合索引，用于按域名和路径统计'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci 
ROW_FORMAT=DYNAMIC COMMENT='访问日志表：记录所有访问日志，包含域名信息';

-- ============================================
-- 2. 封控规则表（高频查询表，优化索引顺序）
-- ============================================
CREATE TABLE IF NOT EXISTS waf_block_rules (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID，自增',
    rule_type VARCHAR(20) NOT NULL COMMENT '规则类型：ip_whitelist-IP白名单, ip_blacklist-IP黑名单, geo_whitelist-地域白名单, geo_blacklist-地域黑名单',
    rule_value VARCHAR(255) NOT NULL COMMENT '规则值',
    rule_name VARCHAR(100) NOT NULL COMMENT '规则名称，用于标识规则用途',
    description TEXT DEFAULT NULL COMMENT '规则描述，详细说明规则的用途和来源',
    rule_group VARCHAR(50) DEFAULT NULL COMMENT '规则分组，用于按业务、地区等维度分组管理规则',
    status TINYINT NOT NULL DEFAULT 1 COMMENT '状态：1-启用（规则生效），0-禁用（规则不生效）',
    priority INT NOT NULL DEFAULT 0 COMMENT '优先级（数字越大优先级越高），相同条件下优先级高的规则优先匹配',
    rule_version INT UNSIGNED NOT NULL DEFAULT 1 COMMENT '规则版本号（用于缓存失效），规则更新时自动递增',
    start_time DATETIME DEFAULT NULL COMMENT '生效开始时间（NULL表示立即生效），用于定时生效规则',
    end_time DATETIME DEFAULT NULL COMMENT '生效结束时间（NULL表示永久生效），用于临时规则',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '记录创建时间',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '记录最后更新时间',
    PRIMARY KEY (id),
    -- 优化：使用覆盖索引，索引顺序按查询频率排序
    KEY idx_status_priority_type (status, priority DESC, rule_type) COMMENT '状态、优先级、类型联合索引，覆盖最常用查询',
    KEY idx_status_type (status, rule_type) COMMENT '状态和类型联合索引，用于组合查询',
    KEY idx_rule_version (rule_version) COMMENT '版本号索引，用于缓存失效检查',
    KEY idx_start_end_time (start_time, end_time) COMMENT '时间范围索引，用于查询定时规则',
    KEY idx_rule_group (rule_group) COMMENT '规则分组索引，用于按分组查询和统计',
    KEY idx_rule_value (rule_value(50)) COMMENT '规则值前缀索引，用于快速匹配规则值'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci 
ROW_FORMAT=DYNAMIC COMMENT='封控规则表：存储所有封控规则，支持单个IP、IP段、地域封控，支持规则分组管理';

-- ============================================
-- 3. 白名单表（高频查询表，优化索引）
-- ============================================
CREATE TABLE IF NOT EXISTS waf_whitelist (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID，自增',
    ip_type VARCHAR(20) NOT NULL COMMENT 'IP类型：single_ip-单个IP地址, ip_range-IP段（CIDR格式）',
    ip_value VARCHAR(255) NOT NULL COMMENT 'IP值',
    description TEXT DEFAULT NULL COMMENT '白名单说明，用于记录添加白名单的原因或来源',
    status TINYINT NOT NULL DEFAULT 1 COMMENT '状态：1-启用（白名单生效），0-禁用（白名单不生效）',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '记录创建时间',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '记录最后更新时间',
    PRIMARY KEY (id),
    -- 优化：使用覆盖索引，覆盖常用查询
    KEY idx_status_type_value (status, ip_type, ip_value(20)) COMMENT '状态、类型、IP值联合索引，覆盖白名单查询',
    KEY idx_ip_value (ip_value(20)) COMMENT 'IP值索引，用于快速匹配IP'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci 
ROW_FORMAT=DYNAMIC COMMENT='白名单表：存储IP白名单规则，白名单优先级高于封控规则';

-- ============================================
-- 4. 封控日志表（高频写入表，优化索引）
-- ============================================
CREATE TABLE IF NOT EXISTS waf_block_logs (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID，自增',
    client_ip VARCHAR(45) NOT NULL COMMENT '被封控的客户端IP地址（支持IPv6）',
    rule_id BIGINT UNSIGNED DEFAULT NULL COMMENT '匹配的封控规则ID（关联waf_block_rules表）',
    rule_name VARCHAR(100) DEFAULT NULL COMMENT '规则名称（冗余字段，便于查询，避免关联查询）',
    block_reason VARCHAR(50) NOT NULL DEFAULT 'manual' COMMENT '封控原因：manual-手动封控, auto_frequency-自动频率封控, auto_error-自动错误率封控, auto_scan-自动扫描封控',
    block_time DATETIME NOT NULL COMMENT '封控发生时间（记录IP被封控的具体时间）',
    request_path VARCHAR(512) DEFAULT NULL COMMENT '触发封控的请求路径（记录触发封控的具体URL）',
    user_agent VARCHAR(512) DEFAULT NULL COMMENT 'User-Agent信息（记录客户端浏览器或工具信息）',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '记录创建时间',
    PRIMARY KEY (id),
    -- 优化：使用覆盖索引，减少回表查询
    KEY idx_client_ip_time (client_ip, block_time) COMMENT 'IP和时间联合索引，用于查询特定IP的时间序列',
    KEY idx_block_time (block_time) COMMENT '封控时间索引，用于按时间范围查询',
    KEY idx_rule_id_time (rule_id, block_time) COMMENT '规则和时间联合索引，用于查询特定规则的时间序列',
    KEY idx_block_reason_time (block_reason, block_time) COMMENT '封控原因和时间联合索引，用于按原因统计',
    -- 外键约束：规则删除时，保留日志记录但设置为NULL（SET NULL）
    FOREIGN KEY (rule_id) REFERENCES waf_block_rules(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci 
ROW_FORMAT=DYNAMIC COMMENT='封控日志表：记录所有被封控的IP访问记录，用于审计和统计分析';

-- ============================================
-- 5. 地域代码表（低频更新表）
-- ============================================
CREATE TABLE IF NOT EXISTS waf_geo_codes (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID，自增',
    country_code VARCHAR(2) NOT NULL COMMENT '国家代码（ISO 3166-1 alpha-2标准，如CN、US、JP等）',
    country_name VARCHAR(100) NOT NULL COMMENT '国家名称（中文或英文名称）',
    region_code VARCHAR(10) DEFAULT NULL COMMENT '省份/地区代码（可选，用于国内省份或国外州/省）',
    region_name VARCHAR(100) DEFAULT NULL COMMENT '省份/地区名称（可选，如Beijing、Shanghai等）',
    city_name VARCHAR(100) DEFAULT NULL COMMENT '城市名称（可选，用于精确到城市级别的地域封控）',
    PRIMARY KEY (id),
    UNIQUE KEY uk_country_code (country_code) COMMENT '国家代码唯一索引，确保每个国家代码只出现一次',
    KEY idx_country_region (country_code, region_code) COMMENT '国家和省份联合索引，用于按国家+省份查询'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci 
ROW_FORMAT=DYNAMIC COMMENT='地域代码表：存储地域代码映射关系，支持国家、省份、城市三级地域封控';

-- 插入一些常用的地域代码示例（使用INSERT IGNORE提高性能，避免重复检查）
INSERT IGNORE INTO waf_geo_codes (country_code, country_name) VALUES
('CN', '中国'),
('US', '美国'),
('JP', '日本'),
('KR', '韩国'),
('GB', '英国'),
('DE', '德国'),
('FR', '法国'),
('RU', '俄罗斯'),
('IN', '印度'),
('BR', '巴西');

-- ============================================
-- 6. 系统配置表（低频更新表）
-- ============================================
CREATE TABLE IF NOT EXISTS waf_system_config (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID，自增',
    config_key VARCHAR(100) NOT NULL COMMENT '配置键（唯一标识配置项，如cache_ttl、log_batch_size等）',
    config_value TEXT NOT NULL COMMENT '配置值（配置项的具体值，支持文本、数字、JSON等格式）',
    description VARCHAR(255) DEFAULT NULL COMMENT '配置说明（描述配置项的用途和取值范围）',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '配置最后更新时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_config_key (config_key) COMMENT '配置键唯一索引，确保每个配置项只出现一次'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci 
ROW_FORMAT=DYNAMIC COMMENT='系统配置表：存储系统运行时配置参数，支持动态修改';

-- 插入默认配置（所有配置项都可通过Web界面管理）
INSERT INTO waf_system_config (config_key, config_value, description) VALUES
-- 缓存配置
('cache_ttl', '60', '缓存过期时间（秒）'),
('cache_max_items', '10000', '最大缓存项数'),
('cache_rule_list_ttl', '300', 'IP段规则列表缓存时间（秒，5分钟）'),
('cache_inactive_ttl', '30', '不活跃IP缓存时间（秒）'),
('cache_access_count_threshold', '3', '活跃访问次数阈值'),
-- 缓存优化配置（动态TTL、热点数据识别）
('cache_optimizer_enable', '1', '是否启用缓存策略优化（1-启用，0-禁用）'),
('cache_dynamic_ttl_enable', '1', '是否启用动态TTL调整（1-启用，0-禁用）'),
('cache_hotspot_detection_enable', '1', '是否启用热点数据识别（1-启用，0-禁用）'),
('cache_hotspot_preload_enable', '0', '是否启用热点数据预加载（1-启用，0-禁用）'),
('cache_hotspot_threshold', '100', '热点数据访问次数阈值'),
('cache_min_ttl', '30', '动态TTL最小值（秒）'),
('cache_max_ttl', '3600', '动态TTL最大值（秒）'),
-- 日志配置
('log_batch_size', '100', '日志批量写入大小'),
('log_batch_interval', '1', '日志批量写入间隔（秒）'),
('log_enable_async', '1', '是否异步写入（1-启用，0-禁用）'),
('log_max_retry', '3', '最大重试次数'),
('log_retry_delay', '0.1', '重试延迟（秒）'),
('log_buffer_warn_threshold', '0.8', '缓冲区警告阈值（80%）'),
('log_enable_local_backup', '1', '是否启用本地日志备份（1-启用，0-禁用）'),
('log_queue_max_size', '10000', '日志队列最大大小'),
-- 封控配置
('block_enable', '1', '是否启用封控（1-启用，0-禁用）'),
('block_page', '<!DOCTYPE html>
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
</html>', '封控页面HTML内容（403错误时显示的页面，可通过Web界面修改）'),
-- 白名单配置
('whitelist_enable', '1', '是否启用白名单（1-启用，0-禁用）'),
-- 地域封控配置
('geo_enable', '0', '是否启用地域封控（1-启用，0-禁用）'),
('geo_cache_ttl', '3600', 'GeoIP查询结果缓存时间（秒，默认1小时）'),
-- 自动封控配置
('auto_block_enable', '1', '是否启用自动封控（1-启用，0-禁用）'),
('auto_block_frequency_threshold', '100', '频率阈值（每分钟访问次数）'),
('auto_block_error_rate_threshold', '0.5', '错误率阈值（0-1之间，如0.5表示50%）'),
('auto_block_scan_path_threshold', '20', '扫描行为阈值（短时间内访问的不同路径数）'),
('auto_block_window_size', '60', '统计窗口大小（秒）'),
('auto_block_duration', '3600', '自动封控时长（秒，默认1小时）'),
('auto_block_check_interval', '10', '检查间隔（秒）'),
-- 代理IP安全配置
('proxy_enable_trusted_proxy_check', '1', '是否启用受信任代理检查（1-启用，0-禁用）'),
('proxy_trusted_proxies_cache_ttl', '300', '受信任代理列表缓存时间（秒）'),
('proxy_log_ip_resolution', '0', '是否记录IP解析过程日志（1-启用，0-禁用，调试用）'),
-- 缓存失效配置
('cache_invalidation_enable_version_check', '1', '是否启用版本号检查（1-启用，0-禁用）'),
('cache_invalidation_version_check_interval', '30', '版本号检查间隔（秒）'),
-- 降级机制配置
('fallback_enable', '1', '是否启用降级机制（1-启用，0-禁用）'),
('fallback_health_check_interval', '10', '健康检查间隔（秒）'),
-- 监控指标配置
('metrics_enable', '1', '是否启用监控指标（1-启用，0-禁用）'),
('metrics_prometheus_endpoint', '/metrics', 'Prometheus指标导出端点'),
-- 缓存穿透防护配置
('cache_protection_enable', '1', '是否启用缓存穿透防护（1-启用，0-禁用）'),
('cache_protection_enable_bloom_filter', '1', '是否启用布隆过滤器（1-启用，0-禁用）'),
('cache_protection_enable_rate_limit', '1', '是否启用频率限制（1-启用，0-禁用）'),
('cache_protection_empty_result_ttl', '60', '空结果缓存时间（秒）'),
('cache_protection_bloom_filter_size', '100000', '布隆过滤器大小'),
('cache_protection_bloom_filter_hash_count', '3', '布隆过滤器哈希函数数量'),
('cache_protection_rate_limit_window', '60', '频率限制窗口（秒）'),
('cache_protection_rate_limit_threshold', '100', '频率限制阈值（每个窗口内的请求数）'),
-- 连接池监控配置
('pool_monitor_enable', '1', '是否启用连接池监控（1-启用，0-禁用）'),
('pool_monitor_check_interval', '10', '监控检查间隔（秒）'),
('pool_monitor_warn_threshold', '0.8', '连接池警告阈值（80%）'),
('pool_monitor_max_pool_size', '100', '最大连接池大小'),
('pool_monitor_min_pool_size', '10', '最小连接池大小'),
('pool_monitor_growth_step', '10', '连接池增长步长'),
-- 缓存预热配置
('cache_warmup_enable', '1', '是否启用缓存预热（1-启用，0-禁用）'),
('cache_warmup_interval', '300', '预热间隔（秒）'),
('cache_warmup_batch_size', '100', '预热批次大小'),
('cache_warmup_smooth_transition', '1', '是否启用平滑过渡（1-启用，0-禁用）'),
('cache_warmup_warmup_common_ips', '0', '是否预热常用IP（1-启用，0-禁用）'),
-- 规则备份配置
('rule_backup_enable', '1', '是否启用规则备份（1-启用，0-禁用）'),
('rule_backup_backup_interval', '300', '备份间隔（秒，默认5分钟）'),
('rule_backup_max_backup_files', '10', '最大备份文件数'),
-- Redis缓存配置
('redis_cache_enable', '1', '是否启用Redis二级缓存（1-启用，0-禁用）'),
('redis_cache_key_prefix', 'waf:', 'Redis键前缀'),
('redis_cache_ttl', '300', '默认TTL（秒）'),
-- 规则更新通知配置
('rule_notification_enable', '1', '是否启用规则更新通知（1-启用，0-禁用）'),
('rule_notification_use_redis_pubsub', '0', '是否使用Redis Pub/Sub（1-启用，0-禁用）'),
('rule_notification_channel', 'waf:rule_update', 'Redis Pub/Sub频道'),
-- 告警配置
('alert_enable', '1', '是否启用告警（1-启用，0-禁用）'),
('alert_cooldown', '300', '告警冷却时间（秒，防止重复告警）'),
('alert_webhook_url', '', 'Webhook URL（可选，用于发送告警到外部系统）'),
('alert_threshold_block_rate', '100', '每分钟封控次数阈值'),
('alert_threshold_cache_miss_rate', '0.5', '缓存未命中率阈值（50%）'),
('alert_threshold_db_failure_count', '3', '数据库连续失败次数阈值'),
('alert_threshold_pool_usage', '0.9', '连接池使用率阈值（90%）'),
('alert_threshold_error_rate', '0.1', '错误率阈值（10%）'),
-- 会话配置
('session_ttl', '86400', '会话过期时间（秒，默认24小时）'),
('session_cookie_name', 'waf_session', '会话Cookie名称'),
('session_enable_secure', '1', '是否启用Secure标志（HTTPS时，1-启用，0-禁用）'),
('session_enable_httponly', '1', '是否启用HttpOnly标志（1-启用，0-禁用）'),
-- CSRF配置
('csrf_enable', '1', '是否启用CSRF防护（1-启用，0-禁用）'),
('csrf_token_ttl', '3600', 'CSRF Token过期时间（秒）'),
-- 速率限制配置
('rate_limit_login_enable', '1', '是否启用登录接口速率限制（1-启用，0-禁用）'),
('rate_limit_login_rate', '5', '登录接口速率限制（每分钟请求数）'),
('rate_limit_api_enable', '1', '是否启用API速率限制（1-启用，0-禁用）'),
('rate_limit_api_rate', '100', 'API速率限制（每分钟请求数）'),
-- 规则版本号
('rule_version', '1', '规则版本号（用于缓存失效）'),
-- WAF配置文件自动生成配置
('waf_conf_version', '1', 'WAF配置文件版本号（用于触发配置文件自动更新）'),
('waf_listen_port', '80', 'WAF管理服务监听端口'),
('waf_server_name', 'localhost', 'WAF管理服务服务器名称'),
('waf_client_max_body_size', '10m', 'WAF管理服务客户端请求体最大大小'),
-- 性能监控配置
('performance_monitor_enable', '1', '是否启用性能监控（1-启用，0-禁用）'),
('performance_slow_query_threshold', '100', '慢查询阈值（毫秒，超过此时间的查询会被记录）'),
('performance_monitor_interval', '60', '性能监控检查间隔（秒）'),
('performance_max_slow_queries', '1000', '最大慢查询记录数'),
-- 缓存调优配置
('cache_tuner_enable', '1', '是否启用缓存自动调优（1-启用，0-禁用）'),
('cache_tuner_interval', '300', '缓存调优检查间隔（秒，默认5分钟）'),
('cache_base_ttl', '60', '缓存基础TTL（秒，用于自动调优的基准值）'),
-- 共享内存优化配置
('shared_memory_optimizer_enable', '1', '是否启用共享内存优化（使用Redis替代部分共享内存，1-启用，0-禁用）'),
('shared_memory_redis_fallback_enable', '1', '是否启用Redis回退机制（Redis失败时回退到共享内存，1-启用，0-禁用）'),
-- 系统访问白名单配置（从waf_system_access_whitelist_config表合并）
('system_access_whitelist_enabled', '0', '是否启用系统访问白名单（1-启用，0-禁用，开启时只有白名单内的IP才能访问管理系统）'),
-- 管理端 HTTPS 与域名配置
('admin_ssl_enable', '0', '是否为管理端启用HTTPS（1-启用，0-禁用，启用后监听443并加载管理端证书）'),
('admin_server_name', 'localhost', '管理端访问域名（例如：waf-admin.example.com，多域名请用空格分隔）'),
('admin_ssl_pem', '', '管理端SSL证书内容（PEM格式）'),
('admin_ssl_key', '', '管理端SSL私钥内容（KEY格式）'),
('admin_force_https', '0', '是否强制将管理端HTTP重定向到HTTPS（1-开启，0-关闭）'),
-- 缓存版本控制配置（从waf_cache_versions表合并）
('cache_version_rules', '1', '规则缓存版本号（用于缓存失效）'),
('cache_version_whitelist', '1', '白名单缓存版本号（用于缓存失效）'),
('cache_version_geo', '1', '地域缓存版本号（用于缓存失效）'),
('cache_version_frequency', '1', '频率统计缓存版本号（用于缓存失效）')
ON DUPLICATE KEY UPDATE config_value = VALUES(config_value);

-- ============================================
-- 7. IP频率统计表（高频更新表，优化索引）
-- ============================================
CREATE TABLE IF NOT EXISTS waf_ip_frequency (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID，自增',
    client_ip VARCHAR(45) NOT NULL COMMENT '客户端IP地址（支持IPv6）',
    window_start DATETIME NOT NULL COMMENT '统计窗口开始时间（时间窗口的起始时间）',
    window_end DATETIME NOT NULL COMMENT '统计窗口结束时间（时间窗口的结束时间）',
    access_count INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '访问次数（该时间窗口内的总访问次数）',
    error_count INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '错误次数（该时间窗口内4xx/5xx错误响应次数）',
    unique_path_count INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '唯一路径数量（该时间窗口内访问的不同URL路径数量，用于检测扫描行为）',
    total_bytes BIGINT UNSIGNED DEFAULT 0 COMMENT '总字节数（该时间窗口内的总传输字节数）',
    avg_response_time MEDIUMINT UNSIGNED DEFAULT 0 COMMENT '平均响应时间（毫秒，该时间窗口内的平均响应时间）',
    max_response_time MEDIUMINT UNSIGNED DEFAULT 0 COMMENT '最大响应时间（毫秒，该时间窗口内的最大响应时间）',
    last_access_time DATETIME NOT NULL COMMENT '最后访问时间（该IP最后一次访问的时间）',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '记录创建时间',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '记录最后更新时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_ip_window (client_ip, window_start) COMMENT 'IP和窗口开始时间唯一索引，确保每个IP在每个时间窗口只有一条记录',
    -- 优化：使用覆盖索引，优化查询性能
    KEY idx_window_end (window_end) COMMENT '窗口结束时间索引，用于清理过期数据',
    KEY idx_client_ip_window_end (client_ip, window_end) COMMENT 'IP和窗口结束时间联合索引，用于查询特定IP的最新统计',
    KEY idx_access_count (access_count) COMMENT '访问次数索引，用于查询高频访问IP',
    KEY idx_error_count (error_count) COMMENT '错误次数索引，用于查询高错误率IP',
    KEY idx_unique_path_count (unique_path_count) COMMENT '唯一路径数量索引，用于检测扫描行为',
    KEY idx_client_ip_last_access (client_ip, last_access_time) COMMENT 'IP和最后访问时间联合索引，用于查询特定IP的最新访问记录'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci 
ROW_FORMAT=DYNAMIC COMMENT='IP频率统计表：按时间窗口统计IP访问频率、错误率、扫描行为等指标';

-- ============================================
-- 8. 自动封控记录表（中频更新表）
-- ============================================
CREATE TABLE IF NOT EXISTS waf_auto_block_logs (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID，自增',
    client_ip VARCHAR(45) NOT NULL COMMENT '被封控的客户端IP地址（支持IPv6）',
    block_reason VARCHAR(50) NOT NULL COMMENT '封控原因：frequency-频率过高, error_rate-错误率过高, scan-扫描行为',
    block_threshold VARCHAR(100) DEFAULT NULL COMMENT '触发阈值（JSON格式，记录触发封控的具体阈值）',
    auto_unblock_time DATETIME DEFAULT NULL COMMENT '自动解封时间（NULL表示永久封控，否则在指定时间自动解封）',
    status TINYINT NOT NULL DEFAULT 1 COMMENT '状态：1-已封控（IP当前处于封控状态），0-已解封（IP已被解封）',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '记录创建时间（封控发生时间）',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '记录最后更新时间（解封时更新）',
    PRIMARY KEY (id),
    KEY idx_client_ip_status (client_ip, status) COMMENT 'IP和状态联合索引，用于查询特定IP的当前封控状态',
    KEY idx_status_unblock_time (status, auto_unblock_time) COMMENT '状态和解封时间联合索引，用于查询待解封的记录',
    KEY idx_block_reason (block_reason) COMMENT '封控原因索引，用于按原因统计',
    KEY idx_created_at (created_at) COMMENT '创建时间索引，用于按时间范围查询和清理'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci 
ROW_FORMAT=DYNAMIC COMMENT='自动封控记录表：记录由自动封控功能触发的封控记录，包含封控原因和触发阈值';

-- ============================================
-- 9. 受信任代理IP表（低频更新表）
-- ============================================
CREATE TABLE IF NOT EXISTS waf_trusted_proxies (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID，自增',
    proxy_ip VARCHAR(45) NOT NULL COMMENT '代理IP地址（支持CIDR格式，如192.168.1.0/24或单个IP）',
    description VARCHAR(255) DEFAULT NULL COMMENT '代理说明，用于标识代理的用途或位置',
    status TINYINT NOT NULL DEFAULT 1 COMMENT '状态：1-启用（信任此代理），0-禁用（不信任）',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '记录创建时间',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '记录最后更新时间',
    PRIMARY KEY (id),
    KEY idx_status (status) COMMENT '状态索引，用于快速查询启用的代理',
    KEY idx_proxy_ip (proxy_ip) COMMENT '代理IP索引，用于快速匹配',
    KEY idx_status_proxy_ip (status, proxy_ip) COMMENT '状态和代理IP联合索引，用于查询启用的代理IP'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci 
ROW_FORMAT=DYNAMIC COMMENT='受信任代理IP表：存储受信任的代理服务器IP，用于安全获取客户端真实IP';

-- 插入默认受信任代理IP（本地回环和私有网络，使用INSERT IGNORE提高性能）
-- 注意：waf_trusted_proxies表没有唯一索引，ON DUPLICATE KEY UPDATE不会生效，改为INSERT IGNORE
INSERT IGNORE INTO waf_trusted_proxies (proxy_ip, description, status) VALUES
('127.0.0.1/32', '本地回环', 1),
('::1/128', 'IPv6本地回环', 1),
('10.0.0.0/8', '私有网络A类', 1),
('172.16.0.0/12', '私有网络B类', 1),
('192.168.0.0/16', '私有网络C类', 1);

-- ============================================
-- 10. 规则模板表（低频更新表）
-- ============================================
CREATE TABLE IF NOT EXISTS waf_rule_templates (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    template_name VARCHAR(100) NOT NULL COMMENT '模板名称',
    template_description TEXT DEFAULT NULL COMMENT '模板描述',
    category VARCHAR(50) DEFAULT NULL COMMENT '模板分类：security-安全, testing-测试等',
    template_data TEXT NOT NULL COMMENT '模板数据（JSON格式，包含规则列表）',
    status TINYINT NOT NULL DEFAULT 1 COMMENT '状态：1-启用，0-禁用',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_template_name (template_name),
    KEY idx_category_status (category, status) COMMENT '分类和状态联合索引',
    KEY idx_status (status) COMMENT '状态索引，用于快速查询启用的模板'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci 
ROW_FORMAT=DYNAMIC COMMENT='规则模板表';

-- ============================================
-- 11. 功能开关表（低频更新表）
-- ============================================
CREATE TABLE IF NOT EXISTS waf_feature_switches (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    feature_key VARCHAR(100) NOT NULL COMMENT '功能键（唯一标识）',
    feature_name VARCHAR(100) NOT NULL COMMENT '功能名称',
    description TEXT DEFAULT NULL COMMENT '功能描述',
    enable TINYINT NOT NULL DEFAULT 1 COMMENT '是否启用：1-启用，0-禁用',
    config_source VARCHAR(20) NOT NULL DEFAULT 'database' COMMENT '配置来源：database-数据库, file-配置文件',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_feature_key (feature_key),
    KEY idx_enable_source (enable, config_source) COMMENT '启用状态和配置来源联合索引'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci 
ROW_FORMAT=DYNAMIC COMMENT='功能开关表';

-- 插入默认功能开关配置（统一管理所有功能）
INSERT INTO waf_feature_switches (feature_key, feature_name, description, enable, config_source) VALUES
-- 核心功能
('ip_block', 'IP封控', 'IP封控功能，包括单个IP、IP段封控', 1, 'database'),
('geo_block', '地域封控', '基于地理位置封控功能', 0, 'database'),
('auto_block', '自动封控', '基于频率和行为的自动封控功能', 1, 'database'),
('whitelist', '白名单', 'IP白名单功能', 1, 'database'),
('block_enable', '封控功能', '是否启用封控功能（1-启用，0-禁用）', 1, 'database'),
-- 日志和监控
('log_collect', '日志采集', '访问日志采集功能', 1, 'database'),
('metrics', '监控指标', 'Prometheus监控指标导出功能', 1, 'database'),
('alert', '告警功能', '系统告警功能', 1, 'database'),
('performance_monitor', '性能监控', '性能监控功能，监控慢查询和系统性能', 1, 'database'),
('pool_monitor', '连接池监控', '连接池监控功能，监控数据库连接池状态', 1, 'database'),
-- 缓存相关
('cache_warmup', '缓存预热', '缓存预热功能', 1, 'database'),
('cache_protection', '缓存穿透防护', '缓存穿透防护功能，防止缓存穿透攻击', 1, 'database'),
('cache_optimizer', '缓存策略优化', '缓存策略优化功能，动态TTL调整和热点数据识别', 1, 'database'),
('cache_tuner', '缓存自动调优', '缓存自动调优功能，根据实际业务场景动态调整缓存', 1, 'database'),
('redis_cache', 'Redis二级缓存', 'Redis二级缓存功能，使用Redis作为二级缓存', 1, 'database'),
('shared_memory_optimizer', '共享内存优化', '共享内存优化功能，使用Redis替代部分共享内存', 1, 'database'),
('cache_invalidation', '缓存失效', '缓存失效功能，版本号检查和缓存失效机制', 1, 'database'),
-- 规则相关
('rule_backup', '规则备份', '规则备份功能', 1, 'database'),
('rule_notification', '规则更新通知', '规则更新通知功能，通知所有工作进程更新缓存', 1, 'database'),
('rule_management_ui', '规则管理界面', '规则管理Web界面，提供规则的CRUD操作和审批流程', 1, 'database'),
-- 系统功能
('fallback', '降级机制', '降级机制功能，系统异常时自动降级', 1, 'database'),
('config_validation', '配置验证', '配置验证功能，启动时检查配置有效性', 1, 'database'),
('config_check_api', '配置检查API', '配置检查API端点，提供配置验证结果查询', 1, 'database'),
-- 安全功能
('csrf', 'CSRF防护', 'CSRF防护功能，防止跨站请求伪造攻击', 1, 'database'),
('rate_limit_login', '登录速率限制', '登录接口速率限制功能', 1, 'database'),
('rate_limit_api', 'API速率限制', 'API接口速率限制功能', 1, 'database'),
('proxy_trusted_check', '受信任代理检查', '受信任代理检查功能，安全获取客户端真实IP', 1, 'database'),
-- 注意：系统访问白名单功能已从功能管理中移除，保留在系统设置中管理
-- 界面功能
('stats', '统计报表', '封控统计报表功能，提供封控数据统计和分析', 1, 'database'),
('monitor', '监控面板', '实时监控面板功能，显示系统运行状态和关键指标', 1, 'database'),
('proxy_management', '反向代理管理', '反向代理配置管理功能，支持HTTP、TCP、UDP代理配置', 1, 'database')
ON DUPLICATE KEY UPDATE 
    feature_name = VALUES(feature_name),
    description = VALUES(description),
    config_source = 'database';

-- ============================================
-- 12. 用户表（中频更新表）
-- ============================================
CREATE TABLE IF NOT EXISTS waf_users (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID，自增',
    username VARCHAR(50) NOT NULL COMMENT '用户名（唯一标识，用于登录）',
    password_hash VARCHAR(255) NOT NULL COMMENT '密码哈希值（使用BCrypt算法加密存储，不存储明文密码）',
    role VARCHAR(20) NOT NULL DEFAULT 'user' COMMENT '用户角色：admin-管理员, user-普通用户',
    totp_secret VARCHAR(32) DEFAULT NULL COMMENT 'TOTP密钥（Base32编码的双因素认证密钥，NULL表示未启用双因素认证）',
    status TINYINT NOT NULL DEFAULT 1 COMMENT '用户状态：1-启用（用户可以登录），0-禁用（用户无法登录）',
    password_changed_at DATETIME DEFAULT NULL COMMENT '密码最后修改时间（用于密码过期策略）',
    password_must_change TINYINT NOT NULL DEFAULT 0 COMMENT '是否必须修改密码（1-是，0-否，首次登录或密码过期时设置为1）',
    last_login_time DATETIME DEFAULT NULL COMMENT '最后登录时间（记录用户最后一次成功登录的时间）',
    last_login_ip VARCHAR(45) DEFAULT NULL COMMENT '最后登录IP（记录用户最后一次登录的IP地址，支持IPv6）',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '用户创建时间',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '用户信息最后更新时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_username (username) COMMENT '用户名唯一索引，确保每个用户名只出现一次',
    KEY idx_status_role (status, role) COMMENT '状态和角色联合索引，用于权限查询',
    KEY idx_password_must_change (password_must_change) COMMENT '密码必须修改标识索引，用于查询需要修改密码的用户',
    KEY idx_last_login_time (last_login_time) COMMENT '最后登录时间索引，用于查询最近登录的用户'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci 
ROW_FORMAT=DYNAMIC COMMENT='用户表：存储系统用户信息，支持角色权限和双因素认证，不再使用硬编码的默认用户';

-- 注意：不再创建默认管理员用户，首次安装时需要通过以下方式之一创建：
-- 1. 使用安装脚本自动创建（推荐）
-- 2. 使用API创建：POST /api/auth/password/hash 生成密码哈希，然后手动插入数据库
-- 3. 使用MySQL命令行创建（需要先使用API生成密码哈希）
--
-- 示例SQL（需要先通过API生成密码哈希）：
-- INSERT INTO waf_users (username, password_hash, role, status, password_must_change)
-- VALUES ('admin', '$2b$10$...', 'admin', 1, 1);
-- 注意：password_hash 必须是通过 BCrypt 生成的哈希值，不能使用明文密码

-- ============================================
-- 13. 用户会话表（高频更新表，优化索引）
-- ============================================
CREATE TABLE IF NOT EXISTS waf_user_sessions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID，自增',
    user_id INT UNSIGNED NOT NULL COMMENT '用户ID（关联waf_users表，标识会话所属的用户）',
    session_id VARCHAR(64) NOT NULL COMMENT '会话ID（唯一标识，存储在Cookie中用于会话验证）',
    ip_address VARCHAR(45) DEFAULT NULL COMMENT '登录IP地址（记录用户登录时的IP地址，支持IPv6，用于安全审计）',
    user_agent VARCHAR(512) DEFAULT NULL COMMENT 'User-Agent信息（记录用户登录时的浏览器或客户端信息，用于安全审计）',
    expires_at DATETIME NOT NULL COMMENT '会话过期时间（会话在此时间后自动失效，需要重新登录）',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '会话创建时间（用户登录时间）',
    PRIMARY KEY (id),
    UNIQUE KEY uk_session_id (session_id) COMMENT '会话ID唯一索引，确保每个会话ID只出现一次',
    KEY idx_user_id_expires (user_id, expires_at) COMMENT '用户和过期时间联合索引，用于查询特定用户的活跃会话',
    KEY idx_expires_at (expires_at) COMMENT '过期时间索引，用于清理过期会话',
    -- 外键约束：用户删除时自动删除其所有会话
    FOREIGN KEY (user_id) REFERENCES waf_users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci 
ROW_FORMAT=DYNAMIC COMMENT='用户会话表：存储用户登录会话信息，用于会话管理和安全审计';

-- ============================================
-- 14. 自动解封任务表（中频更新表）
-- ============================================
CREATE TABLE IF NOT EXISTS waf_auto_unblock_tasks (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    rule_id BIGINT UNSIGNED DEFAULT NULL COMMENT '规则ID（如果是规则过期解封）',
    client_ip VARCHAR(45) DEFAULT NULL COMMENT 'IP地址（如果是IP自动解封）',
    unblock_type VARCHAR(20) NOT NULL COMMENT '解封类型：rule_expired-规则过期, auto_unblock-自动解封',
    scheduled_time DATETIME NOT NULL COMMENT '计划解封时间',
    status VARCHAR(20) NOT NULL DEFAULT 'pending' COMMENT '状态：pending-待处理, completed-已完成, failed-失败',
    executed_at DATETIME DEFAULT NULL COMMENT '执行时间',
    error_message TEXT DEFAULT NULL COMMENT '错误信息',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (id),
    KEY idx_status_scheduled (status, scheduled_time) COMMENT '状态和计划时间联合索引，用于查询待处理任务',
    KEY idx_rule_id (rule_id) COMMENT '规则ID索引',
    KEY idx_client_ip (client_ip) COMMENT 'IP地址索引',
    KEY idx_unblock_type (unblock_type) COMMENT '解封类型索引，用于按类型查询',
    -- 外键约束：规则删除时，保留任务记录但设置为NULL（SET NULL）
    FOREIGN KEY (rule_id) REFERENCES waf_block_rules(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci 
ROW_FORMAT=DYNAMIC COMMENT='自动解封任务表';

-- ============================================
-- 15. 缓存版本控制（已合并到waf_system_config表）
-- ============================================
-- 注意：缓存版本控制已合并到waf_system_config表中，使用config_key存储
-- 例如：cache_version_rules, cache_version_whitelist, cache_version_geo, cache_version_frequency

-- ============================================
-- 16. 反向代理配置表（低频更新表）
-- ============================================
CREATE TABLE IF NOT EXISTS waf_proxy_configs (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID，自增',
    proxy_name VARCHAR(100) NOT NULL COMMENT '代理配置名称（唯一标识，用于区分不同代理配置）',
    proxy_type VARCHAR(20) NOT NULL COMMENT '代理类型：http-HTTP/HTTPS代理, tcp-TCP代理, udp-UDP代理',
    listen_port INT UNSIGNED NOT NULL COMMENT '监听端口（代理服务器监听的端口）',
    listen_address VARCHAR(45) DEFAULT '0.0.0.0' COMMENT '监听地址（0.0.0.0表示监听所有接口，127.0.0.1表示仅本地）',
    server_name VARCHAR(255) DEFAULT NULL COMMENT '服务器名称（HTTP代理时使用，支持多个域名，用空格分隔）',
    location_paths JSON DEFAULT NULL COMMENT '路径匹配列表（HTTP代理时使用，JSON格式，存储多个location_path配置，格式：[{"location_path":"/api","backend_path":"/api"},{"location_path":"/v1","backend_path":"/v1"}]）',
    backend_type VARCHAR(20) NOT NULL DEFAULT 'upstream' COMMENT '后端类型：upstream-多个后端服务器（负载均衡，只支持此类型）',
    load_balance VARCHAR(20) DEFAULT 'round_robin' COMMENT '负载均衡算法：round_robin-轮询, least_conn-最少连接, ip_hash-IP哈希',
    health_check_enable TINYINT NOT NULL DEFAULT 1 COMMENT '是否启用健康检查：1-启用，0-禁用',
    health_check_interval INT DEFAULT 10 COMMENT '健康检查间隔（秒）',
    health_check_timeout INT DEFAULT 3 COMMENT '健康检查超时（秒）',
    max_fails INT DEFAULT 3 COMMENT '最大失败次数（超过此次数后标记为不可用）',
    fail_timeout INT DEFAULT 30 COMMENT '失败超时（秒，失败后在此时间内不再尝试）',
    proxy_timeout INT DEFAULT 60 COMMENT '代理超时（秒，连接后端超时时间）',
    proxy_connect_timeout INT DEFAULT 60 COMMENT '连接超时（秒，建立连接超时时间）',
    proxy_send_timeout INT DEFAULT 60 COMMENT '发送超时（秒，发送请求超时时间）',
    proxy_read_timeout INT DEFAULT 60 COMMENT '读取超时（秒，读取响应超时时间）',
    ssl_enable TINYINT NOT NULL DEFAULT 0 COMMENT '是否启用SSL：1-启用，0-禁用（HTTP代理时使用）',
    ssl_pem TEXT DEFAULT NULL COMMENT 'SSL证书内容（PEM格式，启用SSL时使用）',
    ssl_key TEXT DEFAULT NULL COMMENT 'SSL密钥内容（KEY格式，启用SSL时使用）',
    force_https_redirect TINYINT NOT NULL DEFAULT 0 COMMENT '是否强制将HTTP重定向到HTTPS（仅HTTP/HTTPS代理有效）',
    description TEXT DEFAULT NULL COMMENT '配置说明（描述代理配置的用途和来源）',
    ip_rule_ids JSON DEFAULT NULL COMMENT '防护规则ID数组（JSON格式，存储多个规则ID，支持IP白名单、IP黑名单、地域白名单、地域黑名单，但必须遵守互斥关系）',
    status TINYINT NOT NULL DEFAULT 1 COMMENT '状态：1-启用（代理生效），0-禁用（代理不生效）',
    priority INT NOT NULL DEFAULT 0 COMMENT '优先级（数字越大优先级越高，用于匹配顺序）',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '配置创建时间',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '配置最后更新时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_proxy_name (proxy_name) COMMENT '代理名称唯一索引，确保每个代理配置名称只出现一次',
    KEY idx_status_priority (status, priority DESC) COMMENT '状态和优先级联合索引，用于排序查询（降序）',
    KEY idx_proxy_type (proxy_type) COMMENT '代理类型索引，用于按类型查询',
    KEY idx_listen_port (listen_port) COMMENT '监听端口索引，用于快速查找端口配置',
    KEY idx_server_name (server_name(100)) COMMENT '服务器名称索引，用于HTTP代理匹配',
    KEY idx_listen_address_port (listen_address, listen_port) COMMENT '监听地址和端口联合索引，用于快速查找特定地址和端口的配置'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci 
ROW_FORMAT=DYNAMIC COMMENT='反向代理配置表：存储反向代理配置，支持HTTP、TCP、UDP代理';

-- ============================================
-- 17. 反向代理后端服务器表（低频更新表）
-- ============================================
CREATE TABLE IF NOT EXISTS waf_proxy_backends (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID，自增',
    proxy_id INT UNSIGNED NOT NULL COMMENT '代理配置ID（关联waf_proxy_configs表）',
    location_path VARCHAR(255) DEFAULT NULL COMMENT 'Location路径（HTTP/HTTPS代理时使用，标识该后端服务器属于哪个location，用于为每个location生成独立的upstream配置）',
    backend_address VARCHAR(255) NOT NULL COMMENT '后端服务器地址（IP地址或域名）',
    backend_port INT UNSIGNED NOT NULL COMMENT '后端服务器端口',
    backend_path VARCHAR(255) DEFAULT NULL COMMENT '后端路径（HTTP/HTTPS代理时使用，代理到后端的特定路径，如:/path，留空则代理到根路径）',
    weight INT UNSIGNED DEFAULT 1 COMMENT '权重（负载均衡时使用，数字越大权重越高）',
    max_fails INT DEFAULT 3 COMMENT '最大失败次数（超过此次数后标记为不可用）',
    fail_timeout INT DEFAULT 30 COMMENT '失败超时（秒，失败后在此时间内不再尝试）',
    backup TINYINT NOT NULL DEFAULT 0 COMMENT '是否为备用服务器：1-是，0-否（主服务器不可用时使用）',
    down TINYINT NOT NULL DEFAULT 0 COMMENT '是否手动下线：1-是，0-否（手动标记为不可用）',
    status TINYINT NOT NULL DEFAULT 1 COMMENT '状态：1-启用，0-禁用',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '记录创建时间',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '记录最后更新时间',
    PRIMARY KEY (id),
    KEY idx_proxy_id_status (proxy_id, status) COMMENT '代理ID和状态联合索引，用于查询特定代理的启用后端',
    KEY idx_proxy_id_location_path (proxy_id, location_path) COMMENT '代理ID和Location路径联合索引，用于查询特定location的后端服务器',
    KEY idx_location_path_weight (location_path, weight DESC) COMMENT 'Location路径和权重联合索引（降序），用于排序查询',
    -- 外键约束：代理配置删除时自动删除其所有后端服务器
    FOREIGN KEY (proxy_id) REFERENCES waf_proxy_configs(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci 
ROW_FORMAT=DYNAMIC COMMENT='反向代理后端服务器表：存储upstream类型的多个后端服务器配置，支持为每个location配置独立的后端服务器';

-- 插入反向代理功能开关
INSERT INTO waf_feature_switches (feature_key, feature_name, description, enable, config_source) VALUES
('proxy_management', '反向代理管理', '反向代理配置管理功能，支持HTTP、TCP、UDP代理配置', 1, 'database')
ON DUPLICATE KEY UPDATE 
    feature_name = VALUES(feature_name),
    description = VALUES(description),
    config_source = 'database';

-- ============================================
-- 18. 操作审计日志表（高频写入表，优化索引）
-- ============================================
CREATE TABLE IF NOT EXISTS waf_audit_logs (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID，自增',
    user_id INT UNSIGNED DEFAULT NULL COMMENT '用户ID（关联waf_users表，NULL表示系统操作）',
    username VARCHAR(50) DEFAULT NULL COMMENT '用户名（冗余字段，便于查询，避免关联查询）',
    action_type VARCHAR(50) NOT NULL COMMENT '操作类型：login-登录, logout-登出, create-创建, update-更新, delete-删除, enable-启用, disable-禁用等',
    resource_type VARCHAR(50) DEFAULT NULL COMMENT '资源类型：rule-规则, user-用户, config-配置, feature-功能开关等',
    resource_id VARCHAR(100) DEFAULT NULL COMMENT '资源ID（规则ID、用户ID等）',
    action_description TEXT DEFAULT NULL COMMENT '操作描述（详细说明操作内容和结果）',
    request_method VARCHAR(10) DEFAULT NULL COMMENT 'HTTP请求方法（GET、POST、PUT、DELETE等）',
    request_path VARCHAR(512) DEFAULT NULL COMMENT '请求路径（API端点或页面路径）',
    request_params TEXT DEFAULT NULL COMMENT '请求参数（JSON格式，记录请求的详细参数）',
    ip_address VARCHAR(45) DEFAULT NULL COMMENT '操作IP地址（记录操作来源IP，支持IPv6）',
    user_agent VARCHAR(512) DEFAULT NULL COMMENT 'User-Agent信息（记录操作时的浏览器或客户端信息）',
    status VARCHAR(20) NOT NULL DEFAULT 'success' COMMENT '操作状态：success-成功, failed-失败, error-错误',
    error_message TEXT DEFAULT NULL COMMENT '错误信息（操作失败时的错误详情）',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '操作时间（记录操作发生的具体时间）',
    PRIMARY KEY (id),
    -- 优化：使用覆盖索引，优化查询性能
    KEY idx_user_id_time (user_id, created_at) COMMENT '用户和时间联合索引，用于查询特定用户的操作历史',
    KEY idx_action_type_time (action_type, created_at) COMMENT '操作类型和时间联合索引，用于按操作类型统计',
    KEY idx_resource_type_id (resource_type, resource_id) COMMENT '资源类型和ID联合索引，用于查询特定资源的操作历史',
    KEY idx_created_at (created_at) COMMENT '操作时间索引，用于时间范围查询和清理',
    KEY idx_status_time (status, created_at) COMMENT '状态和时间联合索引，用于查询失败操作',
    KEY idx_ip_address_time (ip_address, created_at) COMMENT 'IP和时间联合索引，用于安全审计',
    -- 外键约束：用户删除时，保留审计日志但设置为NULL（SET NULL）
    FOREIGN KEY (user_id) REFERENCES waf_users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci 
ROW_FORMAT=DYNAMIC COMMENT='操作审计日志表：记录所有管理操作，包括登录、规则变更、配置修改等，用于安全审计和问题排查';

-- ============================================
-- 19. CSRF Token表（高频更新表，优化索引）
-- ============================================
CREATE TABLE IF NOT EXISTS waf_csrf_tokens (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID，自增',
    user_id INT UNSIGNED NOT NULL COMMENT '用户ID（关联waf_users表）',
    token VARCHAR(64) NOT NULL COMMENT 'CSRF Token值（唯一标识，存储在Cookie或Header中）',
    expires_at DATETIME NOT NULL COMMENT 'Token过期时间（Token在此时间后自动失效）',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Token创建时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_token (token) COMMENT 'Token唯一索引，确保每个Token只出现一次',
    KEY idx_user_id_expires (user_id, expires_at) COMMENT '用户和过期时间联合索引，用于查询特定用户的有效Token',
    KEY idx_expires_at (expires_at) COMMENT '过期时间索引，用于清理过期Token',
    -- 外键约束：用户删除时自动删除其所有Token
    FOREIGN KEY (user_id) REFERENCES waf_users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci 
ROW_FORMAT=DYNAMIC COMMENT='CSRF Token表：存储CSRF防护Token，防止跨站请求伪造攻击';

-- ============================================
-- 20. 用户会话增强字段（为waf_user_sessions表添加字段）
-- ============================================
-- 注意：如果字段已存在，此语句会失败，需要手动注释或删除
-- ALTER TABLE waf_user_sessions
-- ADD COLUMN csrf_token VARCHAR(64) DEFAULT NULL COMMENT 'CSRF Token（关联waf_csrf_tokens表）' AFTER session_id,
-- ADD COLUMN is_fixed TINYINT NOT NULL DEFAULT 0 COMMENT '是否固定会话（0-否，1-是，用于检测会话固定攻击）' AFTER user_agent,
-- ADD COLUMN concurrent_count INT UNSIGNED NOT NULL DEFAULT 1 COMMENT '并发会话数（同一用户的并发会话数量）' AFTER expires_at,
-- ADD KEY idx_csrf_token (csrf_token) COMMENT 'CSRF Token索引',
-- ADD KEY idx_is_fixed (is_fixed) COMMENT '会话固定标识索引';

-- ============================================
-- 视图定义（兼容MySQL 5.7和8.0）
-- ============================================

-- 删除视图（兼容MySQL 5.7和8.0）
-- 方法1：MySQL 8.0+ 支持 DROP VIEW IF EXISTS，直接使用
-- 方法2：MySQL 5.7 不支持 IF EXISTS，使用存储过程方式兼容
-- 注意：如果视图不存在，MySQL 5.7会报错，但可以安全忽略
DROP VIEW IF EXISTS waf_v_block_rule_stats;
DROP VIEW IF EXISTS waf_v_ip_access_stats;
DROP VIEW IF EXISTS waf_v_pending_unblock_tasks;

-- 创建视图：封控规则统计视图（优化：使用子查询提高性能）
CREATE VIEW waf_v_block_rule_stats AS
SELECT 
    br.id,
    br.rule_name,
    br.rule_type,
    br.status,
    COALESCE(bl_stats.block_count, 0) AS block_count,
    bl_stats.last_block_time
FROM waf_block_rules br
LEFT JOIN (
    SELECT 
        rule_id,
        COUNT(*) AS block_count,
        MAX(block_time) AS last_block_time
    FROM waf_block_logs
    GROUP BY rule_id
) bl_stats ON br.id = bl_stats.rule_id
WHERE br.status = 1;

-- 创建视图：IP 访问统计视图（最近24小时，优化：使用索引提示）
CREATE VIEW waf_v_ip_access_stats AS
SELECT 
    client_ip,
    COUNT(*) AS access_count,
    COUNT(DISTINCT request_path) AS path_count,
    SUM(CASE WHEN status_code >= 400 THEN 1 ELSE 0 END) AS error_count,
    MAX(request_time) AS last_access_time
FROM waf_access_logs USE INDEX (idx_request_time, idx_client_ip_time)
WHERE request_time >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
GROUP BY client_ip
ORDER BY access_count DESC;

-- 创建视图：待解封任务视图
CREATE VIEW waf_v_pending_unblock_tasks AS
SELECT 
    id,
    rule_id,
    client_ip,
    unblock_type,
    scheduled_time,
    status,
    TIMESTAMPDIFF(SECOND, NOW(), scheduled_time) AS seconds_until_unblock
FROM waf_auto_unblock_tasks
WHERE status = 'pending'
AND scheduled_time <= NOW()
ORDER BY scheduled_time ASC;

-- ============================================
-- 兼容性处理：为已存在的表添加缺失字段和索引
-- ============================================
-- 注意：MySQL 5.7 不支持 IF NOT EXISTS，使用存储过程或手动检查
-- 这里提供兼容的ALTER语句，如果字段已存在会报错，需要手动处理

-- 反向代理配置表：将backen字段重命名为backend_path（如果存在backen字段）
-- 注意：如果backen字段不存在或backend_path字段已存在，此语句会失败，需要手动注释或删除
-- ALTER TABLE waf_proxy_configs 
-- CHANGE COLUMN backen backend_path VARCHAR(255) DEFAULT NULL COMMENT '后端路径（HTTP代理时使用，代理到后端的特定路径，如/aaa，留空则代理到根路径，注意：后端服务器路径存储在waf_proxy_backends表中）';

-- 反向代理后端服务器表：添加location_path字段（如果不存在）
-- 注意：如果字段已存在，此语句会失败，需要手动注释或删除
-- ALTER TABLE waf_proxy_backends 
-- ADD COLUMN location_path VARCHAR(255) DEFAULT NULL COMMENT 'Location路径（HTTP/HTTPS代理时使用，标识该后端服务器属于哪个location，用于为每个location生成独立的upstream配置）' AFTER proxy_id,
-- ADD KEY idx_proxy_id_location_path (proxy_id, location_path) COMMENT '代理ID和Location路径联合索引，用于查询特定location的后端服务器';

-- 访问日志表：添加域名字段（如果不存在）
-- 注意：如果字段已存在，此语句会失败，需要手动注释或删除
-- ALTER TABLE waf_access_logs 
-- ADD COLUMN request_domain VARCHAR(255) DEFAULT NULL COMMENT '请求域名（Host头，用于区分不同域名的访问）' AFTER client_ip,
-- ADD KEY idx_request_domain (request_domain),
-- ADD KEY idx_domain_time (request_domain, request_time);

-- 封控日志表：添加封控原因字段（如果不存在）
-- ALTER TABLE waf_block_logs 
-- ADD COLUMN block_reason VARCHAR(50) NOT NULL DEFAULT 'manual' COMMENT '封控原因' AFTER rule_name,
-- ADD KEY idx_block_reason (block_reason),
-- ADD KEY idx_rule_id_time (rule_id, block_time);

-- 封控规则表：添加规则版本号和分组字段（如果不存在）
-- ALTER TABLE waf_block_rules
-- ADD COLUMN rule_version INT UNSIGNED NOT NULL DEFAULT 1 COMMENT '规则版本号（用于缓存失效）' AFTER priority,
-- ADD COLUMN rule_group VARCHAR(50) DEFAULT NULL COMMENT '规则分组' AFTER description,
-- ADD KEY idx_rule_version (rule_version),
-- ADD KEY idx_status_priority (status, priority),
-- ADD KEY idx_rule_group (rule_group);

-- ============================================
-- 21. 系统访问白名单表（中频更新表）
-- ============================================
CREATE TABLE IF NOT EXISTS waf_system_access_whitelist (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID，自增',
    ip_address VARCHAR(45) NOT NULL COMMENT 'IP地址（支持IPv4和IPv6，支持CIDR格式）',
    description TEXT DEFAULT NULL COMMENT '白名单说明（记录添加白名单的原因或来源）',
    status TINYINT NOT NULL DEFAULT 1 COMMENT '状态：1-启用（白名单生效），0-禁用（白名单不生效）',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '记录创建时间',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '记录最后更新时间',
    PRIMARY KEY (id),
    KEY idx_status_ip (status, ip_address(20)) COMMENT '状态和IP地址联合索引，用于快速查询启用的白名单',
    KEY idx_ip_address (ip_address(20)) COMMENT 'IP地址索引，用于快速匹配IP',
    KEY idx_created_at (created_at) COMMENT '创建时间索引，用于按时间范围查询'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci 
ROW_FORMAT=DYNAMIC COMMENT='系统访问白名单表：存储允许访问WAF管理系统的IP地址，开启时只有白名单内的IP才能访问';

-- ============================================
-- 22. 系统访问白名单开关配置（已合并到waf_system_config表）
-- ============================================
-- 注意：系统访问白名单开关配置已合并到waf_system_config表中，使用config_key='system_access_whitelist_enabled'存储

-- IP频率统计表：添加统计字段（如果不存在）
-- ALTER TABLE waf_ip_frequency
-- ADD COLUMN total_bytes BIGINT UNSIGNED DEFAULT 0 COMMENT '总字节数',
-- ADD COLUMN avg_response_time MEDIUMINT UNSIGNED DEFAULT 0 COMMENT '平均响应时间（毫秒）',
-- ADD COLUMN max_response_time MEDIUMINT UNSIGNED DEFAULT 0 COMMENT '最大响应时间（毫秒）',
-- ADD KEY idx_error_count (error_count),
-- ADD KEY idx_unique_path_count (unique_path_count);
