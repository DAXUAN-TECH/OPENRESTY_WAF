# MySQL 一键安装脚本说明

## 脚本功能

`install_mysql.sh` 是一个全自动的 MySQL 安装和配置脚本，支持多种 Linux 发行版。

### 支持的系统

#### RedHat 系列
- ✅ **CentOS** (6.x, 7.x, 8.x)
- ✅ **RHEL** (6.x, 7.x, 8.x, 9.x)
- ✅ **Fedora** (所有版本)
- ✅ **Rocky Linux** (8.x, 9.x)
- ✅ **AlmaLinux** (8.x, 9.x)
- ✅ **Oracle Linux** (7.x, 8.x, 9.x)
- ✅ **Amazon Linux** (1, 2, 2023)

#### Debian 系列
- ✅ **Debian** (9+, 包括 Debian 10/11/12)
- ✅ **Ubuntu** (16.04+, 包括 18.04/20.04/22.04)
- ✅ **Linux Mint** (所有版本，基于 Ubuntu)
- ✅ **Kali Linux** (所有版本，基于 Debian)
- ✅ **Raspbian** (所有版本，基于 Debian)

#### SUSE 系列
- ✅ **openSUSE** (Leap, Tumbleweed，使用 MariaDB)
- ✅ **SLES** (SUSE Linux Enterprise Server，使用 MariaDB)

#### Arch 系列
- ✅ **Arch Linux** (需要 yay/paru 或从 AUR 安装)
- ✅ **Manjaro** (需要 yay/paru 或从 AUR 安装)

#### 其他发行版
- ✅ **Alpine Linux** (使用 MariaDB，MySQL 兼容)
- ✅ **Gentoo** (使用 emerge 安装)
- ✅ **其他未列出的发行版** (自动检测包管理器)

### 功能特性

- 🔍 **自动检测系统类型**：自动识别 Linux 发行版
- 💻 **硬件自动检测**：自动检测 CPU 核心数和内存大小
- ⚡ **硬件自动优化**：根据硬件配置自动优化 MySQL 参数，最大化性能
- 📦 **自动安装依赖**：根据系统类型安装所需依赖包
- 🚀 **多种安装方式**：优先使用包管理器，失败则从源码编译
- ⚙️ **自动配置**：启动服务、设置开机自启
- 🔒 **安全配置**：可选运行 mysql_secure_installation
- ✅ **验证安装**：检查安装是否成功

## 使用方法

### 基本使用

```bash
# 运行安装脚本（需要 root 权限）
sudo ./scripts/install_mysql.sh
```

### 指定 root 密码

```bash
# 通过环境变量指定 root 密码
sudo MYSQL_ROOT_PASSWORD='your_password' ./scripts/install_mysql.sh
```

### 指定 MySQL 版本

```bash
# 通过环境变量指定版本（默认 8.0）
sudo MYSQL_VERSION=8.0 ./scripts/install_mysql.sh
```

## 安装过程

脚本会执行以下步骤：

1. **[1/8] 检测操作系统** - 自动识别 Linux 发行版
2. **检测硬件配置** - 自动检测 CPU 核心数和内存大小
3. **[2/8] 检查是否已安装** - 如果已安装，询问是否继续
4. **[3/8] 安装 MySQL** - 使用包管理器或从源码编译
   - RedHat 系列：使用 yum/dnf 安装，自动添加 MySQL 官方仓库
   - Debian 系列：使用 apt-get 安装
   - openSUSE：安装 MariaDB（MySQL 兼容）
   - Arch Linux：使用 yay 或 pacman 安装
5. **[4/8] 配置 MySQL** - 根据硬件自动优化配置参数
   - InnoDB 缓冲池：根据内存自动设置（50-70% 内存）
   - 连接数优化：根据内存和 CPU 自动设置 max_connections
   - I/O 优化：根据 CPU 核心数设置 I/O 线程数
   - 并发优化：根据 CPU 核心数设置线程并发数
   - 查询优化：根据内存设置临时表和排序缓冲区
   - 其他优化：慢查询日志、二进制日志、字符集等
6. **[5/8] 启动服务** - 启动 MySQL 并设置开机自启
7. **[6/8] 设置 root 密码** - 交互式输入或使用环境变量
8. **[7/8] 安全配置** - 可选运行 mysql_secure_installation
9. **[8/8] 验证安装** - 检查安装是否成功，测试连接

## 安装位置

MySQL 将安装到以下位置：

```
/etc/my.cnf              # 主配置文件（CentOS/RHEL）
/etc/mysql/my.cnf        # 主配置文件（Ubuntu/Debian）
/var/lib/mysql/          # 数据目录
/var/log/mysqld.log      # 日志文件（CentOS/RHEL）
/var/log/mysql/error.log # 日志文件（Ubuntu/Debian）
```

## 服务管理

安装完成后，可以使用 systemd 管理 MySQL：

```bash
# 启动服务
sudo systemctl start mysqld    # CentOS/RHEL
sudo systemctl start mysql     # Ubuntu/Debian

# 停止服务
sudo systemctl stop mysqld
sudo systemctl stop mysql

# 重启服务
sudo systemctl restart mysqld
sudo systemctl restart mysql

# 查看状态
sudo systemctl status mysqld
sudo systemctl status mysql

# 设置开机自启
sudo systemctl enable mysqld
sudo systemctl enable mysql

# 禁用开机自启
sudo systemctl disable mysqld
sudo systemctl disable mysql
```

## 连接 MySQL

### 使用 root 用户连接

```bash
# 如果设置了密码
mysql -u root -p

# 如果使用临时密码
mysql -u root -p'临时密码'
```

### 创建数据库和用户（用于 WAF 系统）

```bash
# 1. 连接 MySQL
mysql -u root -p

# 2. 创建数据库和用户
CREATE DATABASE waf_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'waf_user'@'localhost' IDENTIFIED BY 'your_password';
GRANT ALL PRIVILEGES ON waf_db.* TO 'waf_user'@'localhost';
FLUSH PRIVILEGES;
EXIT;

# 3. 导入数据库结构
mysql -u waf_user -p waf_db < init_file/数据库设计.sql
```

## 故障排查

### 问题 1：MySQL 安装失败

**可能原因**：
- 网络连接问题
- 仓库配置问题
- 依赖包安装失败

**解决方法**：
```bash
# 检查网络连接
ping -c 3 dev.mysql.com

# 检查仓库配置
cat /etc/yum.repos.d/mysql-community.repo  # CentOS/RHEL
cat /etc/apt/sources.list.d/mysql.list     # Ubuntu/Debian

# 手动安装依赖后重试
```

### 问题 2：服务启动失败

**可能原因**：
- 端口被占用
- 配置文件错误
- 权限问题

**解决方法**：
```bash
# 检查端口占用
netstat -tlnp | grep :3306

# 检查错误日志
tail -f /var/log/mysqld.log        # CentOS/RHEL
tail -f /var/log/mysql/error.log   # Ubuntu/Debian

# 检查服务状态
systemctl status mysqld
systemctl status mysql
```

### 问题 3：无法连接 MySQL

**可能原因**：
- 服务未启动
- 密码错误
- 防火墙阻止

**解决方法**：
```bash
# 检查服务状态
systemctl status mysqld

# 检查防火墙
firewall-cmd --list-all    # CentOS/RHEL
ufw status                 # Ubuntu/Debian

# 获取临时密码
sudo grep 'temporary password' /var/log/mysqld.log
```

### 问题 4：忘记 root 密码

**解决方法**：
```bash
# 1. 停止 MySQL 服务
sudo systemctl stop mysqld

# 2. 以安全模式启动
sudo mysqld_safe --skip-grant-tables &

# 3. 连接并修改密码
mysql -u root
ALTER USER 'root'@'localhost' IDENTIFIED BY 'new_password';
FLUSH PRIVILEGES;
EXIT;

# 4. 重启 MySQL 服务
sudo systemctl restart mysqld
```

## 硬件自动优化 ⭐

脚本会自动检测硬件配置并根据硬件自动优化 MySQL 参数，最大化并发处理能力和读写性能。

### 自动检测的硬件信息

- **CPU 核心数**：自动检测系统 CPU 核心数
- **内存大小**：自动检测总内存（GB 和 MB）

### 自动优化项

#### 1. InnoDB 缓冲池优化（最重要的性能参数）

根据总内存自动设置 `innodb_buffer_pool_size`：
- **小内存（<4GB）**：使用 50% 内存
- **中等内存（4-16GB）**：使用 60% 内存
- **大内存（>16GB）**：使用 70% 内存

**缓冲池实例数**：根据缓冲池大小自动设置（1-8 个实例）

#### 2. 连接优化

根据内存和 CPU 自动设置 `max_connections`：
- **低配（<4GB）**：200 连接
- **中配（4-8GB）**：300-500 连接
- **高配（16GB+, 8 核+）**：1000 连接

#### 3. I/O 优化

- **innodb_log_file_size**：根据缓冲池大小设置（256MB-1GB）
- **innodb_log_buffer_size**：根据内存设置（16MB-64MB）
- **innodb_read_io_threads / innodb_write_io_threads**：根据 CPU 核心数设置（4-8 个）
- **innodb_flush_method**：`O_DIRECT`（提高性能）

#### 4. 并发优化

- **innodb_thread_concurrency**：CPU 核心数 × 2（最大 64）
- **table_open_cache**：根据内存设置（2000-4000）
- **open_files_limit**：根据内存设置（32768-65535）

#### 5. 查询优化

- **tmp_table_size / max_heap_table_size**：根据内存设置（64MB-256MB）
- **sort_buffer_size**：根据内存设置（256KB-512KB）

#### 6. 其他优化

- **慢查询日志**：启用（阈值 2 秒）
- **二进制日志**：启用（用于主从复制）
- **字符集**：UTF8MB4
- **时区**：+08:00（中国时区）

### 优化效果示例

| 硬件配置 | InnoDB 缓冲池 | max_connections | I/O 线程数 | 缓冲池实例数 |
|---------|--------------|----------------|-----------|------------|
| 2 核 4GB | ~2GB | 200 | 4 | 2 |
| 8 核 16GB | ~9.6GB | 500-1000 | 6-8 | 4-8 |
| 32 核 64GB | ~44.8GB | 1000 | 8 | 8 |

### 手动调整

如果需要手动调整配置，可以编辑配置文件：

```bash
sudo vim /etc/my.cnf          # CentOS/RHEL
sudo vim /etc/mysql/my.cnf    # Ubuntu/Debian
```

修改后重启服务：

```bash
sudo systemctl restart mysqld
```

## 安全建议

1. **设置强密码**：使用复杂的 root 密码
2. **运行安全配置**：安装后运行 `mysql_secure_installation`
3. **限制远程访问**：默认只允许 localhost 连接
4. **定期更新**：保持 MySQL 版本最新
5. **备份数据**：定期备份数据库

## 后续配置

安装完成后，需要：

1. **创建 WAF 数据库**：
   ```bash
   mysql -u root -p < init_file/数据库设计.sql
   ```

2. **配置 WAF 连接**：
   - 使用 `install.sh` 自动配置（推荐）
   - 或手动编辑 `lua/config.lua`

3. **测试连接**：
   ```bash
   mysql -u waf_user -p waf_db -e "SHOW TABLES;"
   ```

## 注意事项

1. **需要 root 权限**：安装过程需要 root 权限
2. **网络连接**：需要网络连接下载包和源码
3. **磁盘空间**：确保有足够的磁盘空间（至少 1GB）
4. **端口占用**：确保 3306 端口未被占用
5. **临时密码**：MySQL 8.0 首次安装会生成临时 root 密码

## 参考文档

- [MySQL 官网](https://www.mysql.com/)
- [MySQL 安装文档](https://dev.mysql.com/doc/refman/8.0/en/installing.html)
- [MySQL 安全配置](https://dev.mysql.com/doc/refman/8.0/en/mysql-secure-installation.html)

