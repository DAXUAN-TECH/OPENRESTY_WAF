-- 启用共享内存优化（使用Redis缓存存储非关键数据）
-- 执行方法：mysql -uwaf -p123456 waf_db < scripts/enable_shared_memory_optimizer.sql

-- 启用 shared_memory_optimizer_enable
UPDATE waf_system_config 
SET config_value = '1', 
    description = '是否启用共享内存优化（使用Redis替代部分共享内存，1-启用，0-禁用）',
    updated_at = CURRENT_TIMESTAMP
WHERE config_key = 'shared_memory_optimizer_enable';

-- 确保 redis_cache_enable 已启用
UPDATE waf_system_config 
SET config_value = '1', 
    description = '是否启用Redis二级缓存（1-启用，0-禁用）',
    updated_at = CURRENT_TIMESTAMP
WHERE config_key = 'redis_cache_enable';

-- 确保 shared_memory_redis_fallback_enable 已启用
UPDATE waf_system_config 
SET config_value = '1', 
    description = '是否启用Redis回退机制（Redis失败时回退到共享内存，1-启用，0-禁用）',
    updated_at = CURRENT_TIMESTAMP
WHERE config_key = 'shared_memory_redis_fallback_enable';

-- 验证配置
SELECT config_key, config_value, description 
FROM waf_system_config 
WHERE config_key IN ('shared_memory_optimizer_enable', 'redis_cache_enable', 'shared_memory_redis_fallback_enable')
ORDER BY config_key;

