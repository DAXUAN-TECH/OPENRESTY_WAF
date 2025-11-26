-- 规则类型迁移脚本
-- 将旧的规则类型（single_ip, ip_range, geo）迁移为新的规则类型（ip_whitelist, ip_blacklist, geo_whitelist, geo_blacklist）
-- 注意：此脚本假设所有现有规则都是黑名单规则，如果需要区分白名单和黑名单，需要手动调整

-- 1. 添加ip_rule_id字段到waf_proxy_configs表（如果不存在）
ALTER TABLE waf_proxy_configs 
ADD COLUMN IF NOT EXISTS ip_rule_id BIGINT UNSIGNED DEFAULT NULL COMMENT '防护规则ID（关联waf_block_rules表）' AFTER description;

-- 2. 添加外键约束（如果不存在）
-- 注意：如果表中有数据，可能需要先处理数据再添加外键
-- ALTER TABLE waf_proxy_configs 
-- ADD CONSTRAINT fk_proxy_ip_rule FOREIGN KEY (ip_rule_id) REFERENCES waf_block_rules(id) ON DELETE SET NULL;

-- 3. 迁移规则类型
-- 将single_ip和ip_range迁移为ip_blacklist（默认作为黑名单）
UPDATE waf_block_rules 
SET rule_type = 'ip_blacklist' 
WHERE rule_type IN ('single_ip', 'ip_range');

-- 将geo迁移为geo_blacklist（默认作为黑名单）
UPDATE waf_block_rules 
SET rule_type = 'geo_blacklist' 
WHERE rule_type = 'geo';

-- 4. 更新表注释
ALTER TABLE waf_block_rules 
MODIFY COLUMN rule_type VARCHAR(20) NOT NULL COMMENT '规则类型：ip_whitelist-IP白名单, ip_blacklist-IP黑名单, geo_whitelist-地域白名单, geo_blacklist-地域黑名单';

-- 注意：
-- 1. 此脚本假设所有现有规则都是黑名单规则
-- 2. 如果需要将某些规则改为白名单，需要手动执行：
--    UPDATE waf_block_rules SET rule_type = 'ip_whitelist' WHERE id = ?;
--    UPDATE waf_block_rules SET rule_type = 'geo_whitelist' WHERE id = ?;
-- 3. 执行此脚本前，请先备份数据库

