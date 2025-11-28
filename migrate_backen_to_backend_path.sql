-- ============================================
-- 将 waf_proxy_configs 表的 backen 字段重命名为 backend_path
-- ============================================
-- 执行前请先备份数据库！
-- 此脚本用于将旧字段名 backen 重命名为 backend_path

USE waf_db;

-- 检查字段是否存在
-- 如果 backen 字段存在，则重命名为 backend_path
-- 如果 backen 字段不存在但 backend_path 已存在，则跳过
-- 如果两个字段都不存在，则创建 backend_path 字段

-- 方法1：直接重命名（如果 backen 字段存在）
-- 注意：如果 backend_path 字段已存在，此语句会失败
ALTER TABLE waf_proxy_configs 
CHANGE COLUMN backen backend_path VARCHAR(255) DEFAULT NULL 
COMMENT '后端路径（HTTP代理时使用，代理到后端的特定路径，如/aaa，留空则代理到根路径，注意：后端服务器路径存储在waf_proxy_backends表中）';

-- 如果上面的语句执行失败（因为 backen 字段不存在或 backend_path 已存在），
-- 可以使用下面的方法：

-- 方法2：先检查再重命名（适用于 MySQL 5.7+）
-- 如果 backen 字段存在且 backend_path 不存在，则重命名
-- 注意：MySQL 5.7 不支持 IF EXISTS，需要手动检查

-- 方法3：如果 backen 字段不存在，但需要创建 backend_path 字段
-- ALTER TABLE waf_proxy_configs 
-- ADD COLUMN backend_path VARCHAR(255) DEFAULT NULL 
-- COMMENT '后端路径（HTTP代理时使用，代理到后端的特定路径，如/aaa，留空则代理到根路径，注意：后端服务器路径存储在waf_proxy_backends表中）'
-- AFTER backend_type;

-- 方法4：如果两个字段都存在，需要先删除 backen 字段（数据会丢失！）
-- 注意：此操作会丢失 backen 字段的数据，请谨慎使用！
-- 建议：先备份 backen 字段的数据到 backend_path，然后再删除 backen 字段
-- 
-- 步骤1：备份数据（如果 backend_path 为空，将 backen 的值复制过去）
-- UPDATE waf_proxy_configs 
-- SET backend_path = backen 
-- WHERE backend_path IS NULL AND backen IS NOT NULL;
--
-- 步骤2：删除 backen 字段
-- ALTER TABLE waf_proxy_configs DROP COLUMN backen;

