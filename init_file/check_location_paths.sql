-- ============================================
-- 检查 location_paths 和 location_path 字段是否存在
-- ============================================
-- 用途：快速检查数据库表结构是否包含新字段
-- 执行方式：mysql -u用户名 -p数据库名 < check_location_paths.sql

USE waf_db;

-- 检查 waf_proxy_configs.location_paths 字段
SELECT 
    'waf_proxy_configs.location_paths' AS field_name,
    CASE 
        WHEN COUNT(*) > 0 THEN 'EXISTS (字段已存在)'
        ELSE 'NOT EXISTS (字段不存在，需要执行迁移脚本)'
    END AS status,
    CASE 
        WHEN COUNT(*) > 0 THEN 'OK'
        ELSE 'ERROR: 需要执行 migration_add_location_paths_simple.sql'
    END AS action
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'waf_proxy_configs'
  AND COLUMN_NAME = 'location_paths'

UNION ALL

-- 检查 waf_proxy_backends.location_path 字段
SELECT 
    'waf_proxy_backends.location_path' AS field_name,
    CASE 
        WHEN COUNT(*) > 0 THEN 'EXISTS (字段已存在)'
        ELSE 'NOT EXISTS (字段不存在，需要执行迁移脚本)'
    END AS status,
    CASE 
        WHEN COUNT(*) > 0 THEN 'OK'
        ELSE 'ERROR: 需要执行 migration_add_location_paths_simple.sql'
    END AS action
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'waf_proxy_backends'
  AND COLUMN_NAME = 'location_path';

