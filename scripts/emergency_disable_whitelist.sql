-- ============================================
-- 紧急禁用系统访问白名单脚本
-- 用途：当系统白名单导致无法访问时，通过数据库直接禁用
-- 使用方法：mysql -u waf -p waf_db < emergency_disable_whitelist.sql
-- ============================================

USE waf_db;

-- 禁用系统访问白名单开关
UPDATE waf_system_config 
SET config_value = '0' 
WHERE config_key = 'system_access_whitelist_enabled';

-- 验证更新结果
SELECT 
    config_key, 
    config_value, 
    updated_at,
    CASE 
        WHEN config_value = '0' THEN '✓ 系统白名单已禁用'
        WHEN config_value = '1' THEN '✗ 系统白名单仍启用'
        ELSE '? 未知状态'
    END AS status
FROM waf_system_config 
WHERE config_key = 'system_access_whitelist_enabled';

-- 如果配置不存在，创建默认配置（禁用状态）
INSERT INTO waf_system_config (config_key, config_value, description)
VALUES ('system_access_whitelist_enabled', '0', '是否启用系统访问白名单（1-启用，0-禁用，开启时只有白名单内的IP才能访问管理系统）')
ON DUPLICATE KEY UPDATE config_value = '0';

-- 再次验证
SELECT 
    config_key, 
    config_value, 
    updated_at,
    CASE 
        WHEN config_value = '0' THEN '✓ 系统白名单已禁用，所有IP可以访问'
        WHEN config_value = '1' THEN '✗ 系统白名单仍启用'
        ELSE '? 未知状态'
    END AS status
FROM waf_system_config 
WHERE config_key = 'system_access_whitelist_enabled';

