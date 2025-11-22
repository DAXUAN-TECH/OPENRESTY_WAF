# GeoIP2 数据库自动更新脚本使用说明

## 脚本说明

**update_geoip.sh** - GeoIP2 数据库自动更新脚本

用于定期自动更新 GeoIP2 数据库，保持地域封控功能的准确性。

### 功能特性

- ✅ 自动读取配置文件（由 install_geoip.sh 生成）
- ✅ 自动下载最新数据库
- ✅ 自动备份旧数据库
- ✅ 自动清理旧备份（保留最近 5 个）
- ✅ 完整的日志记录
- ✅ 适合 crontab 计划任务

## 前置条件

1. **已完成初始安装**
   - 已运行 `install_geoip.sh` 进行初始安装
   - 配置文件 `.geoip_config` 已生成

2. **配置文件位置**
   ```
   scripts/.geoip_config
   ```

3. **配置文件格式**
   ```bash
   ACCOUNT_ID="your_account_id"
   LICENSE_KEY="your_license_key"
   ```

## 使用方法

### 手动更新

```bash
# 需要 root 权限
sudo ./scripts/update_geoip.sh
```

### 配置计划任务（推荐）

#### 方式 1：使用 crontab（推荐）

```bash
# 编辑 root 用户的 crontab
sudo crontab -e

# 添加以下行（每周一凌晨 2 点更新）
# 注意：日志文件在项目目录的 logs 文件夹
0 2 * * 1 /path/to/scripts/update_geoip.sh >> /path/to/project/logs/geoip_update.log 2>&1
```

**注意**：日志文件路径是项目目录的 `logs/geoip_update.log`，不是 `/var/log/geoip_update.log`

#### 方式 2：使用 systemd timer（更现代的方式）

创建 `/etc/systemd/system/geoip-update.service`:

```ini
[Unit]
Description=Update GeoIP2 Database
After=network.target

[Service]
Type=oneshot
ExecStart=/path/to/scripts/update_geoip.sh
User=root
```

创建 `/etc/systemd/system/geoip-update.timer`:

```ini
[Unit]
Description=Update GeoIP2 Database Weekly
Requires=geoip-update.service

[Timer]
OnCalendar=weekly
# 每周一凌晨 2 点执行
OnCalendar=Mon *-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

启用并启动：

```bash
sudo systemctl daemon-reload
sudo systemctl enable geoip-update.timer
sudo systemctl start geoip-update.timer

# 查看状态
sudo systemctl status geoip-update.timer
```

## 更新频率建议

### MaxMind 更新频率

- MaxMind 通常**每周更新一次** GeoIP 数据库
- 更新通常在**周二**发布

### 推荐配置

1. **每周更新一次**（推荐）
   ```bash
   # 每周一凌晨 2 点更新（日志在项目目录）
   0 2 * * 1 /path/to/scripts/update_geoip.sh >> /path/to/project/logs/geoip_update.log 2>&1
   ```

2. **每两周更新一次**
   ```bash
   # 每两周的周一凌晨 2 点更新
   0 2 1,15 * * /path/to/scripts/update_geoip.sh >> /path/to/project/logs/geoip_update.log 2>&1
   ```

3. **每月更新一次**
   ```bash
   # 每月 1 号凌晨 2 点更新
   0 2 1 * * /path/to/scripts/update_geoip.sh >> /path/to/project/logs/geoip_update.log 2>&1
   ```

## 日志文件

更新日志保存在项目目录：

```
$project_root/logs/geoip_update.log
```

### 查看日志

```bash
# 查看最新日志（项目目录）
tail -f logs/geoip_update.log

# 查看最近 50 行
tail -n 50 logs/geoip_update.log

# 查看错误日志
grep ERROR logs/geoip_update.log

# 查看所有日志级别
grep -E "INFO|WARN|ERROR" logs/geoip_update.log
```

## 备份文件

脚本会自动备份旧数据库文件：

- 备份位置：`$project_root/lua/geoip/`（项目目录）
- 备份命名：`GeoLite2-City.mmdb.backup.YYYYMMDD_HHMMSS`
- 保留数量：最近 5 个备份（自动清理旧备份）

### 手动恢复备份

```bash
# 查看可用备份（项目目录）
ls -lh lua/geoip/GeoLite2-City.mmdb.backup.*

# 恢复备份
cp lua/geoip/GeoLite2-City.mmdb.backup.20240101_020000 \
   lua/geoip/GeoLite2-City.mmdb

# 设置权限
sudo chown nobody:nobody lua/geoip/GeoLite2-City.mmdb
sudo chmod 644 lua/geoip/GeoLite2-City.mmdb

# 重启 OpenResty（如果需要）
sudo systemctl reload openresty
# 或
sudo /usr/local/openresty/bin/openresty -s reload
```

## 故障排查

### 问题 1：配置文件不存在

**错误信息**：
```
配置文件不存在: /path/to/scripts/.geoip_config
```

**解决方法**：
1. 运行 `install_geoip.sh` 进行初始安装
2. 或手动创建配置文件（参考前置条件）

### 问题 2：认证失败

**错误信息**：
```
认证失败或下载失败
```

**解决方法**：
1. 检查 Account ID 和 License Key 是否正确
2. 检查 License Key 是否过期
3. 检查网络连接

### 问题 3：权限不足

**错误信息**：
```
需要 root 权限来更新数据库文件
```

**解决方法**：
```bash
# 使用 sudo 运行
sudo ./scripts/update_geoip.sh
```

### 问题 4：更新后 OpenResty 未重新加载数据库

**说明**：
- GeoIP2 数据库在 OpenResty 启动时加载
- 更新数据库文件后，需要重启或重新加载 OpenResty

**解决方法**：

1. **自动重新加载**（修改脚本）：
   在 `update_geoip.sh` 的 `verify_installation` 函数后添加：
   ```bash
   # 重新加载 OpenResty
   systemctl reload openresty 2>/dev/null || systemctl restart openresty
   ```

2. **手动重新加载**：
   ```bash
   sudo systemctl reload openresty
   # 或
   sudo systemctl restart openresty
   ```

## 安全建议

1. **配置文件权限**
   - 配置文件 `.geoip_config` 权限应设置为 600
   - 只允许 root 用户读取

2. **日志文件权限**
   - 日志文件 `/var/log/geoip_update.log` 权限应设置为 644
   - 避免泄露敏感信息

3. **定期检查**
   - 定期检查更新日志
   - 确保更新成功执行
   - 监控磁盘空间（备份文件）

## 测试更新

在配置计划任务前，建议先手动测试：

```bash
# 手动运行更新脚本
sudo ./scripts/update_geoip.sh

# 检查日志
tail -f /var/log/geoip_update.log

# 验证数据库文件
ls -lh /usr/local/openresty/nginx/lua/geoip/GeoLite2-City.mmdb
```

## 相关文档

- [安装脚本说明](install_geoip_README.md)
- [地域封控使用示例](../../docs/地域封控使用示例.md)

