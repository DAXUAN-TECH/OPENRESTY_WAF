-- 更新功能开关表，统一管理所有功能
-- 执行方法：mysql -uwaf -p123456 waf_db < scripts/update_feature_switches.sql

-- 插入或更新所有功能开关（统一管理）
INSERT INTO waf_feature_switches (feature_key, feature_name, description, enable, config_source) VALUES
-- 核心功能
('ip_block', 'IP封控', 'IP封控功能，包括单个IP、IP段封控', 1, 'database'),
('geo_block', '地域封控', '基于地理位置封控功能', 0, 'database'),
('auto_block', '自动封控', '基于频率和行为的自动封控功能', 1, 'database'),
('whitelist', '白名单', 'IP白名单功能', 1, 'database'),
('block_enable', '封控功能', '是否启用封控功能（1-启用，0-禁用）', 1, 'database'),
-- 日志和监控
('log_collect', '日志采集', '访问日志采集功能', 1, 'database'),
('metrics', '监控指标', 'Prometheus监控指标导出功能', 1, 'database'),
('alert', '告警功能', '系统告警功能', 1, 'database'),
('performance_monitor', '性能监控', '性能监控功能，监控慢查询和系统性能', 1, 'database'),
('pool_monitor', '连接池监控', '连接池监控功能，监控数据库连接池状态', 1, 'database'),
-- 缓存相关
('cache_warmup', '缓存预热', '缓存预热功能', 1, 'database'),
('cache_protection', '缓存穿透防护', '缓存穿透防护功能，防止缓存穿透攻击', 1, 'database'),
('cache_optimizer', '缓存策略优化', '缓存策略优化功能，动态TTL调整和热点数据识别', 1, 'database'),
('cache_tuner', '缓存自动调优', '缓存自动调优功能，根据实际业务场景动态调整缓存', 1, 'database'),
('redis_cache', 'Redis二级缓存', 'Redis二级缓存功能，使用Redis作为二级缓存', 1, 'database'),
('shared_memory_optimizer', '共享内存优化', '共享内存优化功能，使用Redis替代部分共享内存', 1, 'database'),
('cache_invalidation', '缓存失效', '缓存失效功能，版本号检查和缓存失效机制', 1, 'database'),
-- 规则相关
('rule_backup', '规则备份', '规则备份功能', 1, 'database'),
('rule_notification', '规则更新通知', '规则更新通知功能，通知所有工作进程更新缓存', 1, 'database'),
('rule_management_ui', '规则管理界面', '规则管理Web界面，提供规则的CRUD操作和审批流程', 1, 'database'),
-- 系统功能
('fallback', '降级机制', '降级机制功能，系统异常时自动降级', 1, 'database'),
('config_validation', '配置验证', '配置验证功能，启动时检查配置有效性', 1, 'database'),
('config_check_api', '配置检查API', '配置检查API端点，提供配置验证结果查询', 1, 'database'),
-- 安全功能
('csrf', 'CSRF防护', 'CSRF防护功能，防止跨站请求伪造攻击', 1, 'database'),
('rate_limit_login', '登录速率限制', '登录接口速率限制功能', 1, 'database'),
('rate_limit_api', 'API速率限制', 'API接口速率限制功能', 1, 'database'),
('proxy_trusted_check', '受信任代理检查', '受信任代理检查功能，安全获取客户端真实IP', 1, 'database'),
('system_access_whitelist', '系统访问白名单', '系统访问白名单功能，限制管理系统访问IP', 0, 'database'),
-- 网络优化
('http2', 'HTTP/2支持', 'HTTP/2支持功能（需要SSL/TLS）', 0, 'database'),
('brotli', 'Brotli压缩', 'Brotli压缩功能（需要ngx_brotli模块）', 0, 'database'),
-- 界面功能
('stats', '统计报表', '封控统计报表功能，提供封控数据统计和分析', 1, 'database'),
('monitor', '监控面板', '实时监控面板功能，显示系统运行状态和关键指标', 1, 'database'),
('proxy_management', '反向代理管理', '反向代理配置管理功能，支持HTTP、TCP、UDP代理配置', 1, 'database'),
-- 其他功能
('testing', '测试功能', '单元测试和集成测试功能', 1, 'database')
ON DUPLICATE KEY UPDATE 
    feature_name = VALUES(feature_name),
    description = VALUES(description),
    config_source = 'database';

-- 验证更新结果
SELECT COUNT(*) as total_features, 
       SUM(CASE WHEN enable = 1 THEN 1 ELSE 0 END) as enabled_features,
       SUM(CASE WHEN enable = 0 THEN 1 ELSE 0 END) as disabled_features
FROM waf_feature_switches 
WHERE config_source = 'database';

