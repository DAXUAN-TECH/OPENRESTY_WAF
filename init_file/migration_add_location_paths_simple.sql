-- ============================================
-- 数据库迁移脚本：添加 location_paths 和 location_path 字段（兼容版）
-- 执行时间：2025-12-03
-- 说明：
--   1. 为 waf_proxy_configs 表添加 location_paths 字段
--   2. 为 waf_proxy_backends 表添加 location_path 字段（如果不存在）
--   3. 兼容MySQL 5.7+版本（不支持IF NOT EXISTS语法）
-- ============================================

-- 检查并添加字段（使用存储过程方式，兼容旧版本MySQL）

-- 1. 为 waf_proxy_configs 表添加 location_paths 字段
-- 如果字段已存在，会报错但可以忽略
SET @sql1 = (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE waf_proxy_configs ADD COLUMN location_paths JSON DEFAULT NULL COMMENT ''路径匹配列表（HTTP代理时使用，JSON格式，存储多个location_path配置，格式：[{"location_path":"/api","backend_path":"/api"},{"location_path":"/v1","backend_path":"/v1"}]）'' AFTER server_name;',
        'SELECT ''Column location_paths already exists in waf_proxy_configs'' AS message;'
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
        'SELECT ''Column location_path already exists in waf_proxy_backends'' AS message;'
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
        'SELECT ''Index idx_proxy_id_location_path already exists in waf_proxy_backends'' AS message;'
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
-- 验证：检查字段是否添加成功
-- ============================================
SELECT 
    'waf_proxy_configs.location_paths' AS field_name,
    CASE 
        WHEN COUNT(*) > 0 THEN 'EXISTS'
        ELSE 'NOT EXISTS'
    END AS status
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'waf_proxy_configs'
  AND COLUMN_NAME = 'location_paths'

UNION ALL

SELECT 
    'waf_proxy_backends.location_path' AS field_name,
    CASE 
        WHEN COUNT(*) > 0 THEN 'EXISTS'
        ELSE 'NOT EXISTS'
    END AS status
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'waf_proxy_backends'
  AND COLUMN_NAME = 'location_path';
