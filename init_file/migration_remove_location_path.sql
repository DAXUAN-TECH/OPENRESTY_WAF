-- ============================================
-- 数据库迁移脚本：删除 waf_proxy_configs.location_path 字段
-- 执行时间：2025-12-03
-- 说明：
--   1. 删除 waf_proxy_configs 表中的 location_path 字段（已废弃）
--   2. 该字段已被 location_paths JSON 字段替代
--   3. 兼容MySQL 5.7+版本
-- 使用方法：
--   mysql -u waf -p waf_db < migration_remove_location_path.sql
-- ============================================

USE waf_db;

-- ============================================
-- 第一部分：检查字段是否存在
-- ============================================
SELECT '============================================' AS '';
SELECT '开始检查字段状态...' AS '';
SELECT '============================================' AS '';

-- 检查 waf_proxy_configs.location_path 字段
SELECT 
    'waf_proxy_configs.location_path' AS field_name,
    CASE 
        WHEN COUNT(*) > 0 THEN 'EXISTS (字段存在，需要删除)'
        ELSE 'NOT EXISTS (字段不存在，无需删除)'
    END AS status
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'waf_proxy_configs'
  AND COLUMN_NAME = 'location_path';

-- ============================================
-- 第二部分：删除字段（如果存在）
-- ============================================
SELECT '============================================' AS '';
SELECT '开始删除字段...' AS '';
SELECT '============================================' AS '';

-- 删除 waf_proxy_configs.location_path 字段
SET @sql1 = (
    SELECT IF(
        COUNT(*) > 0,
        'ALTER TABLE waf_proxy_configs DROP COLUMN location_path;',
        'SELECT ''Column location_path does not exist in waf_proxy_configs, skipping...'' AS message;'
    )
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'waf_proxy_configs'
      AND COLUMN_NAME = 'location_path'
);
PREPARE stmt1 FROM @sql1;
EXECUTE stmt1;
DEALLOCATE PREPARE stmt1;

-- ============================================
-- 第三部分：验证字段是否删除成功
-- ============================================
SELECT '============================================' AS '';
SELECT '验证字段状态...' AS '';
SELECT '============================================' AS '';

SELECT 
    'waf_proxy_configs.location_path' AS field_name,
    CASE 
        WHEN COUNT(*) > 0 THEN 'EXISTS ✗ (删除失败)'
        ELSE 'NOT EXISTS ✓ (删除成功)'
    END AS status,
    CASE 
        WHEN COUNT(*) > 0 THEN 'ERROR: 字段删除失败，请检查错误信息'
        ELSE 'OK'
    END AS action
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'waf_proxy_configs'
  AND COLUMN_NAME = 'location_path';

SELECT '============================================' AS '';
SELECT '迁移完成！如果字段状态为 NOT EXISTS ✓，则删除成功。' AS '';
SELECT '============================================' AS '';

