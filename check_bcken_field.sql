-- ============================================
-- 检查 waf_proxy_backends 和 waf_proxy_configs 表的字段情况
-- ============================================
-- 执行此脚本可以检查 bcken、backend_path 字段是否存在

USE waf_db;

-- 检查 waf_proxy_backends 表的 bcken 字段是否存在
SELECT 
    CASE 
        WHEN COUNT(*) > 0 THEN 'bcken 字段存在'
        ELSE 'bcken 字段不存在'
    END AS bcken_status
FROM information_schema.COLUMNS 
WHERE TABLE_SCHEMA = 'waf_db' 
  AND TABLE_NAME = 'waf_proxy_backends' 
  AND COLUMN_NAME = 'bcken';

-- 检查 waf_proxy_backends 表的 backend_path 字段是否存在
SELECT 
    CASE 
        WHEN COUNT(*) > 0 THEN 'backend_path 字段存在'
        ELSE 'backend_path 字段不存在'
    END AS backend_path_status
FROM information_schema.COLUMNS 
WHERE TABLE_SCHEMA = 'waf_db' 
  AND TABLE_NAME = 'waf_proxy_backends' 
  AND COLUMN_NAME = 'backend_path';

-- 检查 waf_proxy_configs 表的 backend_path 字段是否存在
SELECT 
    CASE 
        WHEN COUNT(*) > 0 THEN 'backend_path 字段存在（需要删除）'
        ELSE 'backend_path 字段不存在'
    END AS proxy_configs_backend_path_status
FROM information_schema.COLUMNS 
WHERE TABLE_SCHEMA = 'waf_db' 
  AND TABLE_NAME = 'waf_proxy_configs' 
  AND COLUMN_NAME = 'backend_path';

-- 查看 waf_proxy_backends 表结构
DESCRIBE waf_proxy_backends;

-- 查看 waf_proxy_configs 表结构
DESCRIBE waf_proxy_configs;

-- 查看所有相关字段名
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_DEFAULT, COLUMN_COMMENT
FROM information_schema.COLUMNS 
WHERE TABLE_SCHEMA = 'waf_db' 
  AND TABLE_NAME IN ('waf_proxy_backends', 'waf_proxy_configs')
  AND (COLUMN_NAME LIKE '%bcken%' OR COLUMN_NAME LIKE '%backend_path%');

