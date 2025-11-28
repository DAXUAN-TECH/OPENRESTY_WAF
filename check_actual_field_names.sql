-- ============================================
-- 检查 waf_proxy_backends 表的实际字段名
-- ============================================
-- 执行此脚本可以查看 waf_proxy_backends 表的所有字段名

USE waf_db;

-- 查看 waf_proxy_backends 表的所有字段
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_DEFAULT, COLUMN_COMMENT
FROM information_schema.COLUMNS 
WHERE TABLE_SCHEMA = 'waf_db' 
  AND TABLE_NAME = 'waf_proxy_backends'
ORDER BY ORDINAL_POSITION;

-- 查找包含 "back" 或 "path" 的字段名
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_DEFAULT, COLUMN_COMMENT
FROM information_schema.COLUMNS 
WHERE TABLE_SCHEMA = 'waf_db' 
  AND TABLE_NAME = 'waf_proxy_backends'
  AND (COLUMN_NAME LIKE '%back%' OR COLUMN_NAME LIKE '%path%' OR COLUMN_NAME LIKE '%bcken%');

-- 查看完整的表结构
DESCRIBE waf_proxy_backends;

