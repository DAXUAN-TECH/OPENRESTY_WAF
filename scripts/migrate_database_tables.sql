-- ============================================
-- 数据库表结构迁移脚本
-- 功能：将 waf_system_access_whitelist_config 和 waf_cache_versions 表的数据迁移到 waf_system_config 表
-- 使用说明：
--   1. 在执行此脚本前，请先备份数据库
--   2. 确保已执行最新的 init.sql 文件
--   3. 在 MySQL 命令行中执行：mysql -u waf -p waf_db < migrate_database_tables.sql
-- ============================================

USE waf_db;

-- ============================================
-- 1. 迁移系统访问白名单开关配置
-- ============================================
-- 检查是否存在旧表
SET @table_exists = (
    SELECT COUNT(*) 
    FROM information_schema.tables 
    WHERE table_schema = 'waf_db' 
    AND table_name = 'waf_system_access_whitelist_config'
);

-- 如果旧表存在，迁移数据
SET @migration_sql = IF(@table_exists > 0,
    CONCAT('
        -- 迁移系统访问白名单开关配置
        INSERT INTO waf_system_config (config_key, config_value, description)
        SELECT 
            ''system_access_whitelist_enabled'' AS config_key,
            CAST(enabled AS CHAR) AS config_value,
            ''是否启用系统访问白名单（1-启用，0-禁用，开启时只有白名单内的IP才能访问管理系统）'' AS description
        FROM waf_system_access_whitelist_config
        WHERE id = 1
        ON DUPLICATE KEY UPDATE
            config_value = VALUES(config_value),
            updated_at = CURRENT_TIMESTAMP;
    '),
    'SELECT "waf_system_access_whitelist_config 表不存在，跳过迁移" AS message;'
);

PREPARE stmt FROM @migration_sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- ============================================
-- 2. 迁移缓存版本控制配置
-- ============================================
-- 检查是否存在旧表
SET @table_exists = (
    SELECT COUNT(*) 
    FROM information_schema.tables 
    WHERE table_schema = 'waf_db' 
    AND table_name = 'waf_cache_versions'
);

-- 如果旧表存在，迁移数据
SET @migration_sql = IF(@table_exists > 0,
    CONCAT('
        -- 迁移缓存版本控制配置
        INSERT INTO waf_system_config (config_key, config_value, description)
        SELECT 
            CONCAT(''cache_version_'', cache_type) AS config_key,
            CAST(version AS CHAR) AS config_value,
            CONCAT(''缓存版本号（'', cache_type, ''类型，用于缓存失效）'') AS description
        FROM waf_cache_versions
        ON DUPLICATE KEY UPDATE
            config_value = VALUES(config_value),
            updated_at = CURRENT_TIMESTAMP;
    '),
    'SELECT "waf_cache_versions 表不存在，跳过迁移" AS message;'
);

PREPARE stmt FROM @migration_sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- ============================================
-- 3. 确保新配置项存在（如果迁移失败，手动创建）
-- ============================================
-- 确保系统访问白名单开关配置存在
INSERT INTO waf_system_config (config_key, config_value, description)
VALUES ('system_access_whitelist_enabled', '0', '是否启用系统访问白名单（1-启用，0-禁用，开启时只有白名单内的IP才能访问管理系统）')
ON DUPLICATE KEY UPDATE
    description = VALUES(description);

-- 确保缓存版本控制配置存在
INSERT INTO waf_system_config (config_key, config_value, description) VALUES
('cache_version_rules', '1', '规则缓存版本号（用于缓存失效）'),
('cache_version_whitelist', '1', '白名单缓存版本号（用于缓存失效）'),
('cache_version_geo', '1', '地域缓存版本号（用于缓存失效）'),
('cache_version_frequency', '1', '频率统计缓存版本号（用于缓存失效）')
ON DUPLICATE KEY UPDATE
    description = VALUES(description);

-- ============================================
-- 4. 删除旧表（可选，建议先验证数据迁移成功后再执行）
-- ============================================
-- 注意：以下语句会删除旧表，请确保数据已成功迁移后再执行
-- 建议：先注释掉以下语句，验证系统运行正常后再执行

-- DROP TABLE IF EXISTS waf_system_access_whitelist_config;
-- DROP TABLE IF EXISTS waf_cache_versions;

-- ============================================
-- 5. 验证迁移结果
-- ============================================
SELECT 
    '迁移完成，请检查以下配置项是否正确：' AS message
UNION ALL
SELECT CONCAT('system_access_whitelist_enabled = ', config_value) 
FROM waf_system_config 
WHERE config_key = 'system_access_whitelist_enabled'
UNION ALL
SELECT CONCAT('cache_version_rules = ', config_value) 
FROM waf_system_config 
WHERE config_key = 'cache_version_rules'
UNION ALL
SELECT CONCAT('cache_version_whitelist = ', config_value) 
FROM waf_system_config 
WHERE config_key = 'cache_version_whitelist'
UNION ALL
SELECT CONCAT('cache_version_geo = ', config_value) 
FROM waf_system_config 
WHERE config_key = 'cache_version_geo'
UNION ALL
SELECT CONCAT('cache_version_frequency = ', config_value) 
FROM waf_system_config 
WHERE config_key = 'cache_version_frequency';

