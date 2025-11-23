# Redis 一键卸载脚本使用说明

## 脚本说明

**uninstall_redis.sh** - Redis 一键卸载脚本

用于完全卸载 Redis 及其相关配置、数据目录和日志文件。

### 功能特性

- ✅ 自动停止 Redis 服务
- ✅ 禁用开机自启
- ✅ 支持多种 Linux 发行版
- ✅ 通过包管理器卸载
- ✅ 删除源码编译的文件
- ✅ 可选删除数据目录（默认保留）
- ✅ 可选删除配置文件和日志
- ✅ 可选删除 Redis 用户
- ✅ 支持命令行参数控制删除行为

## 前置条件

1. **root 权限**：需要 root 权限执行卸载
2. **Redis 已安装**：脚本会自动检测是否已安装

## 使用方法

### 方式 1：通过 start.sh 调用（推荐）

```bash
# 单独卸载 Redis（会询问是否删除数据）
sudo ./start.sh uninstall redis

# 完整卸载（统一询问是否删除所有数据）
sudo ./start.sh uninstall all
```

### 方式 2：直接调用脚本

#### 交互式卸载（推荐）

```bash
# 运行卸载脚本
sudo ./scripts/uninstall_redis.sh
```

脚本会询问是否删除配置和数据目录，默认保留。

#### 非交互式卸载

```bash
# 删除数据目录（Y）
sudo ./scripts/uninstall_redis.sh Y

# 保留数据目录（N）
sudo ./scripts/uninstall_redis.sh N
```

## 卸载过程

脚本会按以下顺序执行：

1. **[1/4] 停止 Redis 服务**
   - 检查并停止 `redis` 或 `redis-server` 服务
   - 如果服务未运行，尝试通过进程停止

2. **[2/4] 禁用开机自启**
   - 禁用 systemd 服务开机自启

3. **[3/4] 卸载 Redis**
   - 根据系统类型使用相应的包管理器卸载
   - RedHat 系列：`yum remove` 或 `dnf remove`
   - Debian 系列：`apt-get remove` 和 `apt-get purge`
   - 删除源码编译的文件：`/usr/local/bin/redis-server`、`/usr/local/bin/redis-cli`

4. **[4/4] 清理配置和数据目录（可选）**
   - 询问是否删除配置和数据目录（默认：保留）
   - 如果选择删除，将删除：
     - 配置文件：`/etc/redis/redis.conf`、`/etc/redis.conf` 等
     - 数据目录：`/var/lib/redis`、`/var/db/redis` 等
     - 日志目录：`/var/log/redis/`
     - systemd 服务文件：`/etc/systemd/system/redis.service`
     - Redis 用户（可选，会再次询问）

## 卸载内容

### 默认卸载（保留数据）

- ✅ 停止并禁用服务
- ✅ 通过包管理器卸载 Redis
- ✅ 删除源码编译的文件
- ❌ **保留配置文件**：`/etc/redis/redis.conf`、`/etc/redis.conf`
- ❌ **保留数据目录**：`/var/lib/redis`
- ❌ **保留日志目录**：`/var/log/redis/`

### 完全卸载（删除数据）

如果选择删除数据，将额外删除：
- ✅ 配置文件：`/etc/redis/redis.conf`、`/etc/redis.conf`、`/usr/local/etc/redis.conf`
- ✅ 数据目录：`/var/lib/redis`、`/var/db/redis`
- ✅ 日志目录：`/var/log/redis/`
- ✅ systemd 服务文件：`/etc/systemd/system/redis.service`
- ✅ Redis 用户（可选，会再次询问）
- ⚠️ **警告**：删除数据目录将永久删除所有 Redis 数据，无法恢复！

## 数据保留说明

### 默认行为（N）

- **保留配置文件**：`/etc/redis/redis.conf`、`/etc/redis.conf`
- **保留数据目录**：`/var/lib/redis`
- **保留日志目录**：`/var/log/redis/`
- **可以重新安装**：重新安装 Redis 后，可以恢复数据

### 删除数据（Y）

- **永久删除所有数据**：包括所有键值对、持久化文件等
- **删除配置文件**：所有 Redis 配置文件
- **删除日志文件**：所有日志文件
- **删除服务文件**：systemd 服务文件
- **可选删除用户**：Redis 系统用户（会再次询问）
- ⚠️ **无法恢复**：删除后无法恢复，请确保已备份重要数据

## 支持的系统

脚本支持所有主流 Linux 发行版：

- ✅ **RedHat 系列**：CentOS、RHEL、Fedora、Rocky Linux、AlmaLinux、Oracle Linux、Amazon Linux
- ✅ **Debian 系列**：Ubuntu、Debian、Linux Mint、Kali Linux、Raspbian
- ✅ **SUSE 系列**：openSUSE、SLES
- ✅ **Arch 系列**：Arch Linux、Manjaro
- ✅ **其他**：Alpine Linux、Gentoo

## 注意事项

1. **备份重要数据**
   - ⚠️ **强烈建议**：卸载前备份所有重要数据
   - 使用 `redis-cli` 备份数据：
     ```bash
     redis-cli --rdb /path/to/backup.rdb
     # 或
     redis-cli SAVE
     ```

2. **数据目录位置**
   - 默认：`/var/lib/redis`
   - 其他可能位置：`/var/db/redis`

3. **配置文件位置**
   - 默认：`/etc/redis/redis.conf` 或 `/etc/redis.conf`
   - 源码编译：`/usr/local/etc/redis.conf`

4. **服务名称**
   - 可能是 `redis` 或 `redis-server`

5. **Redis 用户**
   - 如果选择删除数据，会询问是否删除 Redis 用户
   - 默认保留用户（N）

6. **重新安装**
   - 如果保留数据目录，重新安装后可以恢复数据
   - 如果删除数据目录，需要重新导入数据

## 卸载后清理

卸载完成后，可能需要手动清理：

```bash
# 检查是否还有残留文件
ls -la /var/lib/redis
ls -la /etc/redis/redis.conf
ls -la /etc/redis.conf

# 检查是否还有服务文件
systemctl status redis
systemctl status redis-server

# 检查是否还有进程
ps aux | grep redis

# 检查是否还有用户
id redis
```

## 故障排查

### 问题 1: 服务无法停止

**错误信息**：服务停止失败

**解决方法**：
```bash
# 强制停止服务
systemctl stop redis --force
# 或
systemctl stop redis-server --force

# 或直接杀死进程
pkill -9 redis-server
```

### 问题 2: 数据目录无法删除

**错误信息**：权限不足或文件被占用

**解决方法**：
```bash
# 检查是否有进程在使用
lsof /var/lib/redis

# 确保服务已停止
systemctl stop redis

# 手动删除
rm -rf /var/lib/redis
```

### 问题 3: 包管理器卸载失败

**错误信息**：包管理器卸载失败

**解决方法**：
- 检查 Redis 是否已安装
- 手动使用包管理器卸载：
  ```bash
  # CentOS/RHEL
  yum remove redis
  
  # Ubuntu/Debian
  apt-get remove redis-server redis-tools
  ```

### 问题 4: 数据恢复

如果需要恢复数据：

```bash
# 1. 重新安装 Redis
sudo ./scripts/install_redis.sh

# 2. 如果数据目录保留，Redis 会自动识别
# 3. 如果数据目录已删除，需要从备份恢复
redis-cli --rdb /path/to/backup.rdb
```

## 相关脚本

- `install_redis.sh` - Redis 安装脚本
- `start.sh` - 主启动脚本（可调用卸载功能）

## 版本历史

- v1.0 - 初始版本，支持基本卸载功能
- v1.1 - 添加命令行参数支持，可通过 start.sh 调用

