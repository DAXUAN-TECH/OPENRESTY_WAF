-- ============================================
-- 数据库迁移脚本：添加 location_paths 和 location_path 字段（简化版）
-- 执行时间：2025-12-03
-- 说明：
--   1. 为 waf_proxy_configs 表添加 location_paths 字段
--   2. 为 waf_proxy_backends 表添加 location_path 字段（如果不存在）
-- ============================================

-- 1. 为 waf_proxy_configs 表添加 location_paths 字段
-- 注意：如果字段已存在，此语句会报错，可以忽略或先删除字段再执行
ALTER TABLE waf_proxy_configs 
ADD COLUMN location_paths JSON DEFAULT NULL 
COMMENT '路径匹配列表（HTTP代理时使用，JSON格式，存储多个location_path配置，格式：[{"location_path":"/api","backend_path":"/api"},{"location_path":"/v1","backend_path":"/v1"}]，如果为空则使用location_path字段）'
AFTER location_path;

-- 2. 为 waf_proxy_backends 表添加 location_path 字段（如果不存在）
-- 注意：如果字段已存在，此语句会报错，可以忽略
ALTER TABLE waf_proxy_backends 
ADD COLUMN location_path VARCHAR(255) DEFAULT NULL 
COMMENT '关联的Location路径（HTTP/HTTPS代理时使用，用于将后端服务器与特定location关联）'
AFTER proxy_id;

-- 3. 为 waf_proxy_backends 表添加 location_path 索引（如果不存在）
-- 注意：如果索引已存在，此语句会报错，可以忽略
ALTER TABLE waf_proxy_backends 
ADD INDEX idx_proxy_id_location_path (proxy_id, location_path);
