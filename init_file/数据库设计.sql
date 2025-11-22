-- OpenResty WAF 数据库设计
-- 数据库名：waf_db
-- 字符集：utf8mb4
-- 排序规则：utf8mb4_unicode_ci

CREATE DATABASE IF NOT EXISTS waf_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE waf_db;

-- 1. 访问日志表
CREATE TABLE IF NOT EXISTS access_logs (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    client_ip VARCHAR(45) NOT NULL COMMENT '客户端IP地址（支持IPv6）',
    request_path VARCHAR(512) NOT NULL COMMENT '请求路径',
    request_method VARCHAR(10) NOT NULL DEFAULT 'GET' COMMENT '请求方法',
    status_code INT NOT NULL COMMENT 'HTTP响应状态码',
    user_agent VARCHAR(512) DEFAULT NULL COMMENT 'User-Agent',
    referer VARCHAR(512) DEFAULT NULL COMMENT 'Referer',
    request_time DATETIME NOT NULL COMMENT '请求时间',
    response_time INT DEFAULT NULL COMMENT '响应时间（毫秒）',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (id),
    KEY idx_client_ip (client_ip),
    KEY idx_request_time (request_time),
    KEY idx_status_code (status_code),
    KEY idx_client_ip_time (client_ip, request_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='访问日志表';

-- 2. 封控规则表
CREATE TABLE IF NOT EXISTS block_rules (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    rule_type VARCHAR(20) NOT NULL COMMENT '规则类型：single_ip-单个IP, ip_range-IP段, geo-地域',
    rule_value VARCHAR(255) NOT NULL COMMENT '规则值：
        - single_ip: IP地址，如 192.168.1.100
        - ip_range: CIDR格式（如 192.168.1.0/24）或IP范围（如 192.168.1.1-192.168.1.100）
        - geo: 地域代码
            * 国家级别：CN, US, JP 等（ISO 3166-1 alpha-2）
            * 国内省份：CN:Beijing, CN:Shanghai, CN:Guangdong 等
            * 国内城市：CN:Beijing:Beijing, CN:Shanghai:Shanghai 等（国家:省份:城市）',
    rule_name VARCHAR(100) NOT NULL COMMENT '规则名称',
    description TEXT DEFAULT NULL COMMENT '规则描述',
    status TINYINT NOT NULL DEFAULT 1 COMMENT '状态：1-启用，0-禁用',
    priority INT NOT NULL DEFAULT 0 COMMENT '优先级（数字越大优先级越高）',
    start_time DATETIME DEFAULT NULL COMMENT '生效开始时间（NULL表示立即生效）',
    end_time DATETIME DEFAULT NULL COMMENT '生效结束时间（NULL表示永久生效）',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (id),
    KEY idx_status (status),
    KEY idx_rule_type (rule_type),
    KEY idx_status_type (status, rule_type),
    KEY idx_start_end_time (start_time, end_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='封控规则表';

-- 插入地域封控规则示例
-- 注意：以下示例仅供参考，实际使用时请根据需求修改

-- 封控整个国家（国外）
-- INSERT INTO block_rules (rule_type, rule_value, rule_name, description, status, priority)
-- VALUES ('geo', 'US', '封控美国', '封控所有来自美国的访问', 0, 80);

-- 封控国内省份
-- INSERT INTO block_rules (rule_type, rule_value, rule_name, description, status, priority)
-- VALUES ('geo', 'CN:Beijing', '封控北京', '封控所有来自北京的访问', 0, 90);

-- 封控国内城市（精确到城市）
-- INSERT INTO block_rules (rule_type, rule_value, rule_name, description, status, priority)
-- VALUES ('geo', 'CN:Shanghai:Shanghai', '封控上海市', '封控所有来自上海市的访问', 0, 100);

-- 3. 白名单表
CREATE TABLE IF NOT EXISTS whitelist (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    ip_type VARCHAR(20) NOT NULL COMMENT '类型：single_ip-单个IP, ip_range-IP段',
    ip_value VARCHAR(255) NOT NULL COMMENT 'IP值：IP地址或CIDR',
    description TEXT DEFAULT NULL COMMENT '说明',
    status TINYINT NOT NULL DEFAULT 1 COMMENT '状态：1-启用，0-禁用',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (id),
    KEY idx_status (status),
    KEY idx_ip_type (ip_type),
    KEY idx_status_type (status, ip_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='白名单表';

-- 4. 封控日志表
CREATE TABLE IF NOT EXISTS block_logs (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    client_ip VARCHAR(45) NOT NULL COMMENT '被封控的IP地址',
    rule_id BIGINT UNSIGNED DEFAULT NULL COMMENT '匹配的规则ID',
    rule_name VARCHAR(100) DEFAULT NULL COMMENT '规则名称（冗余字段，便于查询）',
    block_time DATETIME NOT NULL COMMENT '封控时间',
    request_path VARCHAR(512) DEFAULT NULL COMMENT '请求路径',
    user_agent VARCHAR(512) DEFAULT NULL COMMENT 'User-Agent',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (id),
    KEY idx_client_ip (client_ip),
    KEY idx_block_time (block_time),
    KEY idx_rule_id (rule_id),
    KEY idx_client_ip_time (client_ip, block_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='封控日志表';

-- 5. 地域代码表（可选，用于地域封控）
CREATE TABLE IF NOT EXISTS geo_codes (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    country_code VARCHAR(2) NOT NULL COMMENT '国家代码（ISO 3166-1 alpha-2）',
    country_name VARCHAR(100) NOT NULL COMMENT '国家名称',
    region_code VARCHAR(10) DEFAULT NULL COMMENT '省份/地区代码',
    region_name VARCHAR(100) DEFAULT NULL COMMENT '省份/地区名称',
    city_name VARCHAR(100) DEFAULT NULL COMMENT '城市名称',
    PRIMARY KEY (id),
    UNIQUE KEY uk_country_code (country_code),
    KEY idx_country_region (country_code, region_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='地域代码表';

-- 插入一些常用的地域代码示例
INSERT INTO geo_codes (country_code, country_name) VALUES
('CN', '中国'),
('US', '美国'),
('JP', '日本'),
('KR', '韩国'),
('GB', '英国'),
('DE', '德国'),
('FR', '法国'),
('RU', '俄罗斯'),
('IN', '印度'),
('BR', '巴西')
ON DUPLICATE KEY UPDATE country_name = VALUES(country_name);

-- 6. 系统配置表（可选，用于系统参数配置）
CREATE TABLE IF NOT EXISTS system_config (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    config_key VARCHAR(100) NOT NULL COMMENT '配置键',
    config_value TEXT NOT NULL COMMENT '配置值',
    description VARCHAR(255) DEFAULT NULL COMMENT '配置说明',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_config_key (config_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='系统配置表';

-- 插入默认配置
INSERT INTO system_config (config_key, config_value, description) VALUES
('cache_ttl', '60', '缓存过期时间（秒）'),
('log_batch_size', '100', '日志批量写入大小'),
('log_batch_interval', '1', '日志批量写入间隔（秒）'),
('enable_geo_block', '0', '是否启用地域封控（1-启用，0-禁用）')
ON DUPLICATE KEY UPDATE config_value = VALUES(config_value);

-- 创建视图：封控规则统计视图
CREATE OR REPLACE VIEW v_block_rule_stats AS
SELECT 
    br.id,
    br.rule_name,
    br.rule_type,
    br.status,
    COUNT(bl.id) AS block_count,
    MAX(bl.block_time) AS last_block_time
FROM block_rules br
LEFT JOIN block_logs bl ON br.id = bl.rule_id
WHERE br.status = 1
GROUP BY br.id, br.rule_name, br.rule_type, br.status;

-- 创建视图：IP 访问统计视图（最近24小时）
CREATE OR REPLACE VIEW v_ip_access_stats AS
SELECT 
    client_ip,
    COUNT(*) AS access_count,
    COUNT(DISTINCT request_path) AS path_count,
    SUM(CASE WHEN status_code >= 400 THEN 1 ELSE 0 END) AS error_count,
    MAX(request_time) AS last_access_time
FROM access_logs
WHERE request_time >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
GROUP BY client_ip
ORDER BY access_count DESC;

