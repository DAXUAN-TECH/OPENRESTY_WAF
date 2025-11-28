-- ============================================
-- 验证 waf_proxy_configs 表的 backend_path 字段是否已删除
-- ============================================
-- 执行此脚本可以验证字段是否已删除

USE waf_db;

-- 检查 waf_proxy_configs 表的 backend_path 字段是否存在
SELECT 
    CASE 
        WHEN COUNT(*) > 0 THEN 'backend_path 字段仍然存在（需要删除）'
        ELSE 'backend_path 字段已删除（正确）'
    END AS backend_path_status
FROM information_schema.COLUMNS 
WHERE TABLE_SCHEMA = 'waf_db' 
  AND TABLE_NAME = 'waf_proxy_configs' 
  AND COLUMN_NAME = 'backend_path';

-- 如果字段仍然存在，执行删除
-- 取消下面的注释并执行
-- ALTER TABLE waf_proxy_configs DROP COLUMN backend_path;

-- 查看 waf_proxy_configs 表的完整结构
DESCRIBE waf_proxy_configs;

