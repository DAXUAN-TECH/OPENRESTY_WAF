# GeoIP 数据库一键卸载脚本使用说明

## 脚本说明

**uninstall_geoip.sh** - GeoIP 数据库一键卸载脚本

用于卸载 GeoIP 数据库文件、配置文件和计划任务。

### 功能特性

- ✅ 删除 GeoIP 数据库文件
- ✅ 删除备份文件
- ✅ 删除配置文件（`.geoip_config`）
- ✅ 删除 crontab 计划任务
- ✅ 可选删除空目录
- ✅ 支持命令行参数控制删除行为

## 前置条件

1. **root 权限**：建议使用 root 权限（删除文件时）
2. **GeoIP 已安装**：脚本会自动检测是否已安装

## 使用方法

### 方式 1：通过 start.sh 调用（推荐）

```bash
# 单独卸载 GeoIP（会询问是否删除数据）
sudo ./start.sh uninstall geoip

# 完整卸载（统一询问是否删除所有数据）
sudo ./start.sh uninstall all
```

### 方式 2：直接调用脚本

#### 交互式卸载（推荐）

```bash
# 运行卸载脚本
sudo ./scripts/uninstall_geoip.sh
```

脚本会询问是否删除空目录，默认保留。

#### 非交互式卸载

```bash
# 删除空目录（Y）
sudo ./scripts/uninstall_geoip.sh Y

# 保留空目录（N）
sudo ./scripts/uninstall_geoip.sh N
```

## 卸载过程

脚本会按以下顺序执行：

1. **[1/3] 删除 GeoIP 数据库文件**
   - 删除数据库文件：`lua/geoip/GeoLite2-City.mmdb`
   - 删除所有备份文件：`GeoLite2-City.mmdb.backup.*`
   - 如果目录为空，询问是否删除目录

2. **[2/3] 删除配置文件**
   - 删除配置文件：`scripts/.geoip_config`
   - 配置文件包含 MaxMind Account ID 和 License Key

3. **[3/3] 删除计划任务**
   - 从 crontab 中删除 GeoIP 更新任务
   - 查找包含 `update_geoip.sh` 的任务并删除

## 卸载内容

### 默认卸载

- ✅ 删除数据库文件：`lua/geoip/GeoLite2-City.mmdb`
- ✅ 删除备份文件：`GeoLite2-City.mmdb.backup.*`
- ✅ 删除配置文件：`scripts/.geoip_config`
- ✅ 删除 crontab 计划任务
- ❌ **保留空目录**：`lua/geoip/`（如果为空）

### 完全卸载

如果选择删除空目录，将额外删除：
- ✅ 空目录：`lua/geoip/`（如果目录为空）

## 数据保留说明

### 默认行为（N）

- **保留空目录**：`lua/geoip/`
- **可以重新安装**：重新安装 GeoIP 后，目录可以继续使用

### 删除空目录（Y）

- **删除空目录**：`lua/geoip/`（仅当目录为空时）
- **需要重新创建**：重新安装时需要重新创建目录

## 文件位置

### 数据库文件

```
lua/geoip/GeoLite2-City.mmdb          # 主数据库文件
lua/geoip/GeoLite2-City.mmdb.backup.*  # 备份文件
```

### 配置文件

```
scripts/.geoip_config                  # 配置文件（包含 Account ID 和 License Key）
```

### 计划任务

```
crontab -l                             # 查看计划任务
# 包含 update_geoip.sh 的任务会被删除
```

## 注意事项

1. **备份重要数据**
   - 如果需要保留数据库文件，请先备份：
     ```bash
     cp lua/geoip/GeoLite2-City.mmdb /path/to/backup/
     ```

2. **配置文件**
   - 配置文件包含 MaxMind Account ID 和 License Key
   - 删除后需要重新输入这些信息才能重新安装

3. **计划任务**
   - 脚本会自动从 crontab 中删除 GeoIP 更新任务
   - 如果任务在其他位置（如 `/etc/cron.d/`），需要手动删除

4. **目录结构**
   - 默认保留空目录，不影响项目结构
   - 如果删除空目录，重新安装时会自动创建

5. **重新安装**
   - 卸载后可以随时重新安装
   - 需要重新输入 MaxMind Account ID 和 License Key

## 卸载后清理

卸载完成后，可能需要手动清理：

```bash
# 检查是否还有残留文件
ls -la lua/geoip/

# 检查是否还有配置文件
ls -la scripts/.geoip_config

# 检查是否还有计划任务
crontab -l | grep update_geoip
```

## 故障排查

### 问题 1: 文件无法删除

**错误信息**：权限不足

**解决方法**：
```bash
# 使用 root 权限
sudo ./scripts/uninstall_geoip.sh

# 或手动删除
sudo rm -f lua/geoip/GeoLite2-City.mmdb
sudo rm -f scripts/.geoip_config
```

### 问题 2: 计划任务无法删除

**错误信息**：crontab 操作失败

**解决方法**：
```bash
# 手动编辑 crontab
crontab -e

# 删除包含 update_geoip.sh 的行
```

### 问题 3: 目录不为空

**错误信息**：目录不为空，无法删除

**解决方法**：
- 这是正常的，脚本只会删除空目录
- 如果目录中有其他文件，会保留目录

## 相关脚本

- `install_geoip.sh` - GeoIP 数据库安装脚本
- `update_geoip.sh` - GeoIP 数据库更新脚本
- `start.sh` - 主启动脚本（可调用卸载功能）

## 版本历史

- v1.0 - 初始版本，支持基本卸载功能
- v1.1 - 添加命令行参数支持，可通过 start.sh 调用

