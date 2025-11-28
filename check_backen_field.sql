-- ============================================
-- 检查 waf_proxy_configs 表的字段情况
-- ============================================
-- 执行此脚本可以检查 backen 和 backend_path 字段是否存在

USE waf_db;

-- 检查 backen 字段是否存在
SELECT 
    CASE 
        WHEN COUNT(*) > 0 THEN 'backen 字段存在'
        ELSE 'backen 字段不存在'
    END AS backen_status
FROM information_schema.COLUMNS 
WHERE TABLE_SCHEMA = 'waf_db' 
  AND TABLE_NAME = 'waf_proxy_configs' 
  AND COLUMN_NAME = 'backen';

-- 检查 backend_path 字段是否存在
SELECT 
    CASE 
        WHEN COUNT(*) > 0 THEN 'backend_path 字段存在'
        ELSE 'backend_path 字段不存在'
    END AS backend_path_status
FROM information_schema.COLUMNS 
WHERE TABLE_SCHEMA = 'waf_db' 
  AND TABLE_NAME = 'waf_proxy_configs' 
  AND COLUMN_NAME = 'backend_path';

-- 查看表结构
DESCRIBE waf_proxy_configs;

-- 查看所有字段名（包含 backen 或 backend 的字段）
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_DEFAULT, COLUMN_COMMENT
FROM information_schema.COLUMNS 
WHERE TABLE_SCHEMA = 'waf_db' 
  AND TABLE_NAME = 'waf_proxy_configs' 
  AND (COLUMN_NAME LIKE '%backen%' OR COLUMN_NAME LIKE '%backen%');
