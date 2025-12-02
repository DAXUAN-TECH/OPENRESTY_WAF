-- ============================================
-- 数据库迁移脚本：添加 location_paths 和 location_path 字段（完整版）
-- 执行时间：2025-12-03
-- 说明：
--   1. 先检查字段是否存在
--   2. 如果不存在则添加字段和索引
--   3. 最后验证字段是否添加成功
--   4. 兼容MySQL 5.7+版本（不支持IF NOT EXISTS语法）
-- 使用方法：
--   mysql -u waf -p waf_db < migration_add_location_paths_complete.sql
-- ============================================

USE waf_db;

-- ============================================
-- 第一部分：检查字段是否存在
-- ============================================
SELECT '============================================' AS '';
SELECT '开始检查字段状态...' AS '';
SELECT '============================================' AS '';

-- 检查 waf_proxy_configs.location_paths 字段
SELECT 
    'waf_proxy_configs.location_paths' AS field_name,
    CASE 
        WHEN COUNT(*) > 0 THEN 'EXISTS (字段已存在)'
        ELSE 'NOT EXISTS (字段不存在，需要添加)'
    END AS status
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
        ELSE 'NOT EXISTS (字段不存在，需要添加)'
    END AS status
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'waf_proxy_backends'
  AND COLUMN_NAME = 'location_path';

-- ============================================
-- 第二部分：添加字段（如果不存在）
-- ============================================
SELECT '============================================' AS '';
SELECT '开始添加字段...' AS '';
SELECT '============================================' AS '';

-- 1. 为 waf_proxy_configs 表添加 location_paths 字段
SET @sql1 = (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE waf_proxy_configs ADD COLUMN location_paths JSON DEFAULT NULL COMMENT ''路径匹配列表（HTTP代理时使用，JSON格式，存储多个location_path配置，格式：[{"location_path":"/api","backend_path":"/api"},{"location_path":"/v1","backend_path":"/v1"}]，如果为空则使用location_path字段）'' AFTER location_path;',
        'SELECT ''Column location_paths already exists in waf_proxy_configs, skipping...'' AS message;'
    )
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'waf_proxy_configs'
      AND COLUMN_NAME = 'location_paths'
);
PREPARE stmt1 FROM @sql1;
EXECUTE stmt1;
DEALLOCATE PREPARE stmt1;

-- 2. 为 waf_proxy_backends 表添加 location_path 字段（如果不存在）
SET @sql2 = (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE waf_proxy_backends ADD COLUMN location_path VARCHAR(255) DEFAULT NULL COMMENT ''关联的Location路径（HTTP/HTTPS代理时使用，用于将后端服务器与特定location关联）'' AFTER proxy_id;',
        'SELECT ''Column location_path already exists in waf_proxy_backends, skipping...'' AS message;'
    )
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'waf_proxy_backends'
      AND COLUMN_NAME = 'location_path'
);
PREPARE stmt2 FROM @sql2;
EXECUTE stmt2;
DEALLOCATE PREPARE stmt2;

-- 3. 为 waf_proxy_backends 表添加 location_path 索引（如果不存在）
SET @sql3 = (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE waf_proxy_backends ADD INDEX idx_proxy_id_location_path (proxy_id, location_path);',
        'SELECT ''Index idx_proxy_id_location_path already exists in waf_proxy_backends, skipping...'' AS message;'
    )
    FROM INFORMATION_SCHEMA.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'waf_proxy_backends'
      AND INDEX_NAME = 'idx_proxy_id_location_path'
);
PREPARE stmt3 FROM @sql3;
EXECUTE stmt3;
DEALLOCATE PREPARE stmt3;

-- ============================================
-- 第三部分：验证字段是否添加成功
-- ============================================
SELECT '============================================' AS '';
SELECT '验证字段状态...' AS '';
SELECT '============================================' AS '';

SELECT 
    'waf_proxy_configs.location_paths' AS field_name,
    CASE 
        WHEN COUNT(*) > 0 THEN 'EXISTS ✓'
        ELSE 'NOT EXISTS ✗'
    END AS status,
    CASE 
        WHEN COUNT(*) > 0 THEN 'OK'
        ELSE 'ERROR: 字段添加失败，请检查错误信息'
    END AS action
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'waf_proxy_configs'
  AND COLUMN_NAME = 'location_paths'

UNION ALL

SELECT 
    'waf_proxy_backends.location_path' AS field_name,
    CASE 
        WHEN COUNT(*) > 0 THEN 'EXISTS ✓'
        ELSE 'NOT EXISTS ✗'
    END AS status,
    CASE 
        WHEN COUNT(*) > 0 THEN 'OK'
        ELSE 'ERROR: 字段添加失败，请检查错误信息'
    END AS action
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'waf_proxy_backends'
  AND COLUMN_NAME = 'location_path';

-- ============================================
-- 第四部分：显示表结构（可选）
-- ============================================
SELECT '============================================' AS '';
SELECT '字段详细信息：' AS '';
SELECT '============================================' AS '';

-- 显示 waf_proxy_configs 表的 location_paths 字段信息
SELECT 
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE,
    COLUMN_DEFAULT,
    COLUMN_COMMENT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'waf_proxy_configs'
  AND COLUMN_NAME = 'location_paths'

UNION ALL

-- 显示 waf_proxy_backends 表的 location_path 字段信息
SELECT 
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE,
    COLUMN_DEFAULT,
    COLUMN_COMMENT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'waf_proxy_backends'
  AND COLUMN_NAME = 'location_path';

SELECT '============================================' AS '';
SELECT '迁移完成！如果所有字段状态为 EXISTS ✓，则可以重启 OpenResty 服务。' AS '';
SELECT '重启命令: systemctl restart openresty' AS '';
SELECT '============================================' AS '';

