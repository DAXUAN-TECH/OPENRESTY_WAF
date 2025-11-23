# OpenResty 一键卸载脚本使用说明

## 脚本说明

**uninstall_openresty.sh** - OpenResty 一键卸载脚本

用于完全卸载 OpenResty 及其相关配置、服务文件和符号链接。

### 功能特性

- ✅ 自动停止 OpenResty 服务
- ✅ 禁用开机自启
- ✅ 删除 systemd 服务文件
- ✅ 删除符号链接（openresty、opm、resty）
- ✅ 支持通过包管理器卸载（如果是从包管理器安装的）
- ✅ 可选删除安装目录
- ✅ 支持命令行参数控制删除行为

## 前置条件

1. **root 权限**：需要 root 权限执行卸载
2. **OpenResty 已安装**：脚本会自动检测是否已安装

## 使用方法

### 方式 1：通过 start.sh 调用（推荐）

```bash
# 单独卸载 OpenResty（会询问是否删除安装目录）
sudo ./start.sh uninstall openresty

# 完整卸载（统一询问是否删除所有数据）
sudo ./start.sh uninstall all
```

### 方式 2：直接调用脚本

#### 交互式卸载（推荐）

```bash
# 运行卸载脚本
sudo ./scripts/uninstall_openresty.sh
```

脚本会询问是否删除安装目录，默认保留。

#### 非交互式卸载

```bash
# 删除安装目录（Y）
sudo ./scripts/uninstall_openresty.sh Y

# 保留安装目录（N）
sudo ./scripts/uninstall_openresty.sh N
```

## 卸载过程

脚本会按以下顺序执行：

1. **[1/5] 停止 OpenResty 服务**
   - 检查 systemd 服务状态
   - 如果服务正在运行，停止服务
   - 如果通过 PID 文件运行，优雅退出

2. **[2/5] 禁用开机自启**
   - 禁用 systemd 服务开机自启

3. **[3/5] 删除 systemd 服务文件**
   - 删除 `/etc/systemd/system/openresty.service`
   - 重新加载 systemd 守护进程

4. **[4/5] 删除符号链接**
   - 删除 `/usr/local/bin/openresty`
   - 删除 `/usr/local/bin/opm`
   - 删除 `/usr/local/bin/resty`

5. **[5/5] 卸载 OpenResty**
   - 尝试使用包管理器卸载（如果是从包管理器安装的）
   - 询问是否删除安装目录（默认：保留）

## 卸载内容

### 默认卸载（保留安装目录）

- ✅ 停止并禁用服务
- ✅ 删除服务文件
- ✅ 删除符号链接
- ✅ 通过包管理器卸载（如果适用）
- ❌ **保留安装目录**：`/usr/local/openresty`

### 完全卸载（删除安装目录）

如果选择删除安装目录，将额外删除：
- ✅ 整个安装目录：`/usr/local/openresty`
- ⚠️ **警告**：这将删除所有 OpenResty 文件，包括配置文件

## 数据保留说明

### 默认行为（N）

- **保留安装目录**：`/usr/local/openresty`
- **保留配置文件**：如果配置文件在安装目录中，将一并保留
- **保留日志文件**：日志文件也会保留

### 删除安装目录（Y）

- **删除整个安装目录**：`/usr/local/openresty`
- **删除所有文件**：包括二进制文件、配置文件、日志文件等
- ⚠️ **无法恢复**：删除后无法恢复

## 支持的系统

脚本支持所有主流 Linux 发行版：

- ✅ **RedHat 系列**：CentOS、RHEL、Fedora、Rocky Linux、AlmaLinux 等
- ✅ **Debian 系列**：Ubuntu、Debian、Linux Mint 等
- ✅ **SUSE 系列**：openSUSE、SLES
- ✅ **Arch 系列**：Arch Linux、Manjaro
- ✅ **其他**：Alpine、Gentoo 等

## 注意事项

1. **备份重要数据**
   - 卸载前请备份重要的配置文件
   - 如果选择删除安装目录，请确保已备份所有重要数据

2. **配置文件位置**
   - 如果配置文件在安装目录中，删除安装目录会一并删除
   - 如果配置文件在 `/etc/nginx/`，需要手动清理

3. **项目配置文件**
   - 项目目录中的配置文件（`conf.d/`、`lua/`）不会被删除
   - 如需删除项目配置，请使用 `uninstall_deploy.sh`

4. **服务状态**
   - 卸载前会自动停止服务
   - 如果服务正在处理请求，会等待请求完成后再停止

## 卸载后清理

卸载完成后，可能需要手动清理：

```bash
# 检查是否还有残留文件
ls -la /usr/local/openresty

# 检查是否还有配置文件
ls -la /etc/nginx/

# 检查是否还有服务文件
ls -la /etc/systemd/system/openresty.service

# 检查是否还有符号链接
ls -la /usr/local/bin/openresty
```

## 故障排查

### 问题 1: 服务无法停止

**错误信息**：服务停止失败

**解决方法**：
```bash
# 强制停止服务
systemctl stop openresty --force

# 或直接杀死进程
pkill -9 openresty
```

### 问题 2: 安装目录无法删除

**错误信息**：权限不足或文件被占用

**解决方法**：
```bash
# 检查是否有进程在使用
lsof /usr/local/openresty

# 手动删除
rm -rf /usr/local/openresty
```

### 问题 3: 包管理器卸载失败

**错误信息**：包管理器卸载失败

**解决方法**：
- 这是正常的，如果 OpenResty 是从源码编译安装的
- 脚本会继续执行，删除安装目录即可

## 相关脚本

- `install_openresty.sh` - OpenResty 安装脚本
- `uninstall_deploy.sh` - 部署配置卸载脚本
- `start.sh` - 主启动脚本（可调用卸载功能）

## 版本历史

- v1.0 - 初始版本，支持基本卸载功能
- v1.1 - 添加命令行参数支持，可通过 start.sh 调用

