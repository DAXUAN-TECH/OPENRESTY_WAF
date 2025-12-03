-- ============================================
-- 数据库迁移脚本：添加 location_paths 字段
-- 执行时间：2025-12-03
-- 说明：为 waf_proxy_configs 表添加 location_paths 字段，支持多个location路径配置
-- ============================================

-- 检查并添加 location_paths 字段（如果不存在）
-- 注意：MySQL 5.7+ 支持 JSON 类型，如果版本较低，请先升级或使用 TEXT 类型

-- 方法1：使用 ALTER TABLE 添加字段（推荐）
-- 如果字段已存在，会报错，可以使用方法2先检查

ALTER TABLE waf_proxy_configs 
ADD COLUMN IF NOT EXISTS location_paths JSON DEFAULT NULL 
COMMENT '路径匹配列表（HTTP代理时使用，JSON格式，存储多个location_path配置，格式：[{"location_path":"/api","backend_path":"/api"},{"location_path":"/v1","backend_path":"/v1"}]）'
AFTER server_name;

-- 方法2：如果 MySQL 版本不支持 IF NOT EXISTS，使用以下方式（先检查再添加）
-- 注意：需要手动执行，或者使用存储过程

-- 检查字段是否存在，如果不存在则添加
-- SET @dbname = DATABASE();
-- SET @tablename = 'waf_proxy_configs';
-- SET @columnname = 'location_paths';
-- SET @preparedStatement = (SELECT IF(
--   (
--     SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
--     WHERE
--       (table_name = @tablename)
--       AND (table_schema = @dbname)
--       AND (column_name = @columnname)
--   ) > 0,
--   "SELECT 'Column already exists.';",
--   CONCAT('ALTER TABLE ', @tablename, ' ADD COLUMN ', @columnname, ' JSON DEFAULT NULL COMMENT ''路径匹配列表（HTTP代理时使用，JSON格式，存储多个location_path配置，格式：[{"location_path":"/api","backend_path":"/api"},{"location_path":"/v1","backend_path":"/v1"}]）'' AFTER server_name;')
-- ));
-- PREPARE alterIfNotExists FROM @preparedStatement;
-- EXECUTE alterIfNotExists;
-- DEALLOCATE PREPARE alterIfNotExists;

-- ============================================
-- 验证：检查字段是否添加成功
-- ============================================
-- SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_DEFAULT, COLUMN_COMMENT
-- FROM INFORMATION_SCHEMA.COLUMNS
-- WHERE TABLE_SCHEMA = DATABASE()
--   AND TABLE_NAME = 'waf_proxy_configs'
--   AND COLUMN_NAME = 'location_paths';

