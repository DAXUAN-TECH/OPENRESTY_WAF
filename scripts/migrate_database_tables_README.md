# 数据库表结构迁移说明

## 问题说明

由于优化了数据库表结构，将以下表合并到了 `waf_system_config` 表：
- `waf_system_access_whitelist_config` → `waf_system_config` (使用 `config_key='system_access_whitelist_enabled'`)
- `waf_cache_versions` → `waf_system_config` (使用 `cache_version_*` 配置项)

**重要提示**：如果您的数据库是旧版本，需要执行迁移脚本才能正常使用系统白名单功能。

## 迁移步骤

### 1. 备份数据库（重要！）

```bash
# 备份整个数据库
mysqldump -u waf -p waf_db > waf_db_backup_$(date +%Y%m%d_%H%M%S).sql

# 或者只备份相关表
mysqldump -u waf -p waf_db waf_system_config waf_system_access_whitelist_config waf_cache_versions > tables_backup_$(date +%Y%m%d_%H%M%S).sql
```

### 2. 执行迁移脚本

```bash
# 进入项目目录
cd /data/OPENRESTY_WAF

# 执行迁移脚本
mysql -u waf -p waf_db < scripts/migrate_database_tables.sql
```

### 3. 验证迁移结果

```bash
# 检查配置项是否存在
mysql -u waf -p waf_db -e "SELECT config_key, config_value FROM waf_system_config WHERE config_key LIKE 'system_access_whitelist%' OR config_key LIKE 'cache_version%'"
```

应该看到以下配置项：
- `system_access_whitelist_enabled` (值应该是 0 或 1)
- `cache_version_rules` (值应该是 1)
- `cache_version_whitelist` (值应该是 1)
- `cache_version_geo` (值应该是 1)
- `cache_version_frequency` (值应该是 1)

### 4. 启用系统白名单功能

**重要**：即使添加了白名单条目，如果开关没有启用，白名单也不会生效！

#### 方法1：通过Web界面启用

1. 登录WAF管理系统
2. 进入"系统设置" → "系统访问白名单"
3. 点击"启用"按钮

#### 方法2：通过SQL直接启用

```sql
-- 启用系统访问白名单
UPDATE waf_system_config 
SET config_value = '1' 
WHERE config_key = 'system_access_whitelist_enabled';
```

### 5. 验证功能

1. 添加一个测试IP到系统白名单
2. 从该IP访问WAF管理系统，应该可以正常访问
3. 从未在白名单中的IP访问，应该返回403错误

### 6. 清理旧表（可选）

**注意**：只有在确认系统运行正常后，才执行此步骤！

```sql
-- 删除旧表（如果存在）
DROP TABLE IF EXISTS waf_system_access_whitelist_config;
DROP TABLE IF EXISTS waf_cache_versions;
```

## 常见问题

### Q1: 添加了白名单条目，但不生效？

**A**: 请检查以下几点：
1. **系统白名单开关是否启用**：
   ```sql
   SELECT config_value FROM waf_system_config WHERE config_key = 'system_access_whitelist_enabled';
   ```
   如果值为 `0`，需要先启用开关。

2. **白名单条目状态是否为启用**：
   ```sql
   SELECT id, ip_address, status FROM waf_system_access_whitelist WHERE status = 1;
   ```
   确保 `status = 1`。

3. **IP地址格式是否正确**：
   - 单个IP：`192.168.1.100`
   - CIDR格式：`192.168.1.0/24`
   - IP范围：`192.168.1.1-192.168.1.100`
   - 多个IP：`192.168.1.1,192.168.1.2`

4. **清除配置缓存**（如果使用了缓存）：
   - 重启OpenResty/Nginx
   - 或者等待缓存过期（默认5分钟）

### Q2: 迁移后无法访问管理系统？

**A**: 如果迁移后无法访问，可能是：
1. 系统白名单开关被意外启用，但白名单为空
2. 解决方案：从数据库直接访问，禁用开关：
   ```sql
   UPDATE waf_system_config SET config_value = '0' WHERE config_key = 'system_access_whitelist_enabled';
   ```

### Q3: 如何查看当前系统白名单配置？

```sql
-- 查看开关状态
SELECT config_key, config_value, updated_at 
FROM waf_system_config 
WHERE config_key = 'system_access_whitelist_enabled';

-- 查看白名单条目
SELECT id, ip_address, description, status, created_at 
FROM waf_system_access_whitelist 
ORDER BY id DESC;
```

## 回滚方案

如果迁移出现问题，可以回滚：

```bash
# 恢复数据库备份
mysql -u waf -p waf_db < waf_db_backup_YYYYMMDD_HHMMSS.sql
```

## 技术支持

如有问题，请查看日志：
- OpenResty错误日志：`logs/error.log`
- 系统日志：检查nginx错误日志

