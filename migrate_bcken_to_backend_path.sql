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
-- 步骤1：重命名 waf_proxy_backends 表的路径字段
-- ============================================
-- 注意：请先执行 check_actual_field_names.sql 查看实际字段名
-- 根据实际字段名选择对应的方法

-- 方法1：如果字段名是 backen（不是 bcken）
-- 取消下面的注释并执行
-- ALTER TABLE waf_proxy_backends 
-- CHANGE COLUMN backen backend_path VARCHAR(255) DEFAULT NULL 
-- COMMENT '后端路径（HTTP/HTTPS代理时使用，代理到后端的特定路径，如:/path，留空则代理到根路径）';

-- 方法2：如果字段名是 bcken（虽然报错说不存在，但可能在某些环境中存在）
-- 取消下面的注释并执行
-- ALTER TABLE waf_proxy_backends 
-- CHANGE COLUMN bcken backend_path VARCHAR(255) DEFAULT NULL 
-- COMMENT '后端路径（HTTP/HTTPS代理时使用，代理到后端的特定路径，如:/path，留空则代理到根路径）';

-- 方法3：如果字段名已经是 backend_path
-- 不需要执行任何操作，字段名已经正确

-- 方法4：如果字段不存在，需要创建
-- 取消下面的注释并执行
-- ALTER TABLE waf_proxy_backends 
-- ADD COLUMN backend_path VARCHAR(255) DEFAULT NULL 
-- COMMENT '后端路径（HTTP/HTTPS代理时使用，代理到后端的特定路径，如:/path，留空则代理到根路径）'
-- AFTER backend_port;

-- ============================================
-- 步骤2：删除 waf_proxy_configs 表的 backend_path 字段
-- ============================================
-- 注意：此字段已确认冗余，后端路径存储在 waf_proxy_backends 表中
-- 执行前请确认没有重要数据需要保留
ALTER TABLE waf_proxy_configs DROP COLUMN backend_path;

