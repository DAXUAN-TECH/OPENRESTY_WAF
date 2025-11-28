-- ============================================
-- 将 waf_proxy_backends 表的 bcken 字段重命名为 backend_path
-- 删除 waf_proxy_configs 表的 backend_path 字段（已确认冗余）
-- ============================================
-- 执行前请先备份数据库！
-- 此脚本用于：
-- 1. 将 waf_proxy_backends 表的 bcken 字段重命名为 backend_path
-- 2. 删除 waf_proxy_configs 表的 backend_path 字段（已确认冗余，后端路径存储在 waf_proxy_backends 表中）

USE waf_db;

-- ============================================
-- 步骤1：重命名 waf_proxy_backends 表的 bcken 字段
-- ============================================
-- 方法1：直接重命名（如果 bcken 字段存在）
-- 注意：如果 backend_path 字段已存在，此语句会失败
ALTER TABLE waf_proxy_backends 
CHANGE COLUMN bcken backend_path VARCHAR(255) DEFAULT NULL 
COMMENT '后端路径（HTTP/HTTPS代理时使用，代理到后端的特定路径，如:/path，留空则代理到根路径）';

-- 如果上面的语句执行失败（因为 bcken 字段不存在或 backend_path 已存在），
-- 可以使用下面的方法：

-- 方法2：如果 bcken 字段不存在，但需要创建 backend_path 字段
-- ALTER TABLE waf_proxy_backends 
-- ADD COLUMN backend_path VARCHAR(255) DEFAULT NULL 
-- COMMENT '后端路径（HTTP/HTTPS代理时使用，代理到后端的特定路径，如:/path，留空则代理到根路径）'
-- AFTER backend_port;

-- 方法3：如果两个字段都存在，需要先备份数据再删除旧字段
-- 注意：此操作会丢失 bcken 字段的数据，请谨慎使用！
-- 
-- 步骤1：备份数据（如果 backend_path 为空，将 bcken 的值复制过去）
-- UPDATE waf_proxy_backends 
-- SET backend_path = bcken 
-- WHERE backend_path IS NULL AND bcken IS NOT NULL;
--
-- 步骤2：删除 bcken 字段
-- ALTER TABLE waf_proxy_backends DROP COLUMN bcken;

-- ============================================
-- 步骤2：删除 waf_proxy_configs 表的 backend_path 字段
-- ============================================
-- 注意：此字段已确认冗余，后端路径存储在 waf_proxy_backends 表中
-- 执行前请确认没有重要数据需要保留
ALTER TABLE waf_proxy_configs DROP COLUMN backend_path;

