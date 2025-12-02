-- ============================================
-- 数据库迁移脚本：添加 location_paths 字段（简化版）
-- 执行时间：2025-12-03
-- 说明：为 waf_proxy_configs 表添加 location_paths 字段
-- ============================================

-- 添加 location_paths 字段
-- 注意：如果字段已存在，此语句会报错，可以忽略或先删除字段再执行

ALTER TABLE waf_proxy_configs 
ADD COLUMN location_paths JSON DEFAULT NULL 
COMMENT '路径匹配列表（HTTP代理时使用，JSON格式，存储多个location_path配置，格式：[{"location_path":"/api","backend_path":"/api"},{"location_path":"/v1","backend_path":"/v1"}]，如果为空则使用location_path字段）'
AFTER location_path;
