-- ============================================
-- 数据库迁移脚本：添加 location_paths 和 location_path 字段（直接执行版）
-- 执行时间：2025-12-03
-- 说明：直接执行ALTER TABLE语句，如果字段已存在会报错，可以忽略
-- 适用场景：已知字段不存在，或可以接受报错的情况
-- ============================================

-- 1. 为 waf_proxy_configs 表添加 location_paths 字段
-- 如果字段已存在，会报错：Duplicate column name 'location_paths'，可以忽略
ALTER TABLE waf_proxy_configs 
ADD COLUMN location_paths JSON DEFAULT NULL 
COMMENT '路径匹配列表（HTTP代理时使用，JSON格式，存储多个location_path配置，格式：[{"location_path":"/api","backend_path":"/api"},{"location_path":"/v1","backend_path":"/v1"}]）'
AFTER server_name;

-- 2. 为 waf_proxy_backends 表添加 location_path 字段
-- 如果字段已存在，会报错：Duplicate column name 'location_path'，可以忽略
ALTER TABLE waf_proxy_backends 
ADD COLUMN location_path VARCHAR(255) DEFAULT NULL 
COMMENT '关联的Location路径（HTTP/HTTPS代理时使用，用于将后端服务器与特定location关联）'
AFTER proxy_id;

-- 3. 为 waf_proxy_backends 表添加 location_path 索引
-- 如果索引已存在，会报错：Duplicate key name 'idx_proxy_id_location_path'，可以忽略
ALTER TABLE waf_proxy_backends 
ADD INDEX idx_proxy_id_location_path (proxy_id, location_path);

