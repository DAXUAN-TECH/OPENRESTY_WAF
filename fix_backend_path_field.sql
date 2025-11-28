-- ============================================
-- 修复 waf_proxy_backends 表的路径字段
-- ============================================
-- 此脚本会根据实际字段名进行修复
-- 执行前请先运行 check_actual_field_names.sql 查看实际字段名

USE waf_db;

-- ============================================
-- 情况1：如果字段名是 backen（不是 bcken）
-- ============================================
-- 取消下面的注释并执行
-- ALTER TABLE waf_proxy_backends 
-- CHANGE COLUMN backen backend_path VARCHAR(255) DEFAULT NULL 
-- COMMENT '后端路径（HTTP/HTTPS代理时使用，代理到后端的特定路径，如:/path，留空则代理到根路径）';

-- ============================================
-- 情况2：如果字段名已经是 backend_path
-- ============================================
-- 不需要执行任何操作，字段名已经正确

-- ============================================
-- 情况3：如果字段不存在，需要创建
-- ============================================
-- 取消下面的注释并执行
-- ALTER TABLE waf_proxy_backends 
-- ADD COLUMN backend_path VARCHAR(255) DEFAULT NULL 
-- COMMENT '后端路径（HTTP/HTTPS代理时使用，代理到后端的特定路径，如:/path，留空则代理到根路径）'
-- AFTER backend_port;

-- ============================================
-- 情况4：如果字段名是其他名字（如 backend_path_old）
-- ============================================
-- 需要先查看实际字段名，然后手动修改下面的语句
-- ALTER TABLE waf_proxy_backends 
-- CHANGE COLUMN [实际字段名] backend_path VARCHAR(255) DEFAULT NULL 
-- COMMENT '后端路径（HTTP/HTTPS代理时使用，代理到后端的特定路径，如:/path，留空则代理到根路径）';

