# 部署配置一键卸载脚本使用说明

## 脚本说明

**uninstall_deploy.sh** - 部署配置一键卸载脚本

用于删除部署到系统目录的 OpenResty 配置文件，保留项目目录中的配置文件。

### 功能特性

- ✅ 停止 OpenResty 服务
- ✅ 删除部署的配置文件（带备份）
- ✅ 可选清理项目日志目录
- ✅ 支持命令行参数控制删除行为

## 前置条件

1. **root 权限**：需要 root 权限执行卸载
2. **配置文件已部署**：脚本会自动检测配置文件是否存在

## 使用方法

### 方式 1：通过 start.sh 调用（推荐）

```bash
# 单独卸载部署配置（会询问是否删除配置文件）
sudo ./start.sh uninstall deploy

# 完整卸载（统一询问是否删除所有数据）
sudo ./start.sh uninstall all
```

### 方式 2：直接调用脚本

#### 交互式卸载（推荐）

```bash
# 运行卸载脚本
sudo ./scripts/uninstall_deploy.sh
```

脚本会询问是否删除配置文件，默认保留。

#### 非交互式卸载

```bash
# 删除配置文件（Y）
sudo ./scripts/uninstall_deploy.sh Y

# 保留配置文件（N）
sudo ./scripts/uninstall_deploy.sh N
```

## 卸载过程

脚本会按以下顺序执行：

1. **[1/3] 停止 OpenResty 服务**
   - 检查 systemd 服务状态
   - 如果服务正在运行，停止服务
   - 如果通过 PID 文件运行，优雅退出

2. **[2/3] 删除部署的配置文件**
   - 检查配置文件是否存在：`/usr/local/openresty/nginx/conf/nginx.conf`
   - 询问是否删除（默认：保留）
   - 如果选择删除，会先备份配置文件
   - 备份文件名：`nginx.conf.backup.YYYYMMDD_HHMMSS`

3. **[3/3] 清理项目目录（可选）**
   - 询问是否清理项目日志目录
   - 如果选择清理，会删除 `logs/` 目录中的所有文件
   - 保留项目目录结构

## 卸载内容

### 默认卸载（保留配置文件）

- ✅ 停止 OpenResty 服务
- ❌ **保留配置文件**：`/usr/local/openresty/nginx/conf/nginx.conf`
- ❌ **保留项目目录**：项目目录结构保持不变

### 完全卸载（删除配置文件）

如果选择删除配置文件，将额外执行：
- ✅ 备份配置文件：`nginx.conf.backup.YYYYMMDD_HHMMSS`
- ✅ 删除配置文件：`/usr/local/openresty/nginx/conf/nginx.conf`
- ⚠️ **注意**：配置文件会先备份，可以恢复

### 清理项目目录（可选）

如果选择清理项目目录：
- ✅ 清理日志目录：删除 `logs/` 目录中的所有文件
- ❌ **保留目录结构**：`conf.d/`、`lua/` 等目录保持不变

## 数据保留说明

### 默认行为（N）

- **保留配置文件**：`/usr/local/openresty/nginx/conf/nginx.conf`
- **保留项目目录**：所有项目文件保持不变
- **可以重新部署**：可以随时重新部署配置文件

### 删除配置文件（Y）

- **备份配置文件**：删除前会自动备份
- **删除配置文件**：从系统目录删除
- **可以恢复**：可以从备份文件恢复

### 清理项目目录（Y）

- **清理日志文件**：删除 `logs/` 目录中的所有文件
- **保留目录结构**：`conf.d/`、`lua/` 等目录保持不变
- ⚠️ **注意**：日志文件无法恢复

## 文件位置

### 系统配置文件

```
/usr/local/openresty/nginx/conf/nginx.conf              # 部署的配置文件
/usr/local/openresty/nginx/conf/nginx.conf.backup.*    # 备份文件
```

### 项目目录

```
项目根目录/
├── conf.d/          # 配置文件目录（保留）
├── lua/             # Lua 脚本目录（保留）
├── logs/            # 日志目录（可选清理）
└── init_file/       # 初始配置文件（保留）
```

## 注意事项

1. **备份配置文件**
   - 删除配置文件前会自动备份
   - 备份文件位置：`/usr/local/openresty/nginx/conf/nginx.conf.backup.*`
   - 可以随时从备份恢复

2. **项目目录**
   - 项目目录中的配置文件（`conf.d/`、`lua/`）不会被删除
   - 这些文件保持在项目目录中

3. **服务状态**
   - 卸载前会自动停止服务
   - 如果服务正在处理请求，会等待请求完成后再停止

4. **重新部署**
   - 卸载后可以随时重新部署
   - 使用 `deploy.sh` 或 `start.sh deploy` 重新部署

5. **日志文件**
   - 如果选择清理项目目录，会删除所有日志文件
   - 日志文件无法恢复，请确保已备份重要日志

## 卸载后清理

卸载完成后，可能需要手动清理：

```bash
# 检查是否还有配置文件
ls -la /usr/local/openresty/nginx/conf/nginx.conf

# 检查是否还有备份文件
ls -la /usr/local/openresty/nginx/conf/nginx.conf.backup.*

# 检查服务状态
systemctl status openresty

# 检查项目日志目录
ls -la logs/
```

## 恢复配置文件

如果需要恢复配置文件：

```bash
# 1. 查找备份文件
ls -la /usr/local/openresty/nginx/conf/nginx.conf.backup.*

# 2. 恢复配置文件
cp /usr/local/openresty/nginx/conf/nginx.conf.backup.YYYYMMDD_HHMMSS \
   /usr/local/openresty/nginx/conf/nginx.conf

# 3. 重新加载配置
/usr/local/openresty/bin/openresty -t
systemctl reload openresty
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

### 问题 2: 配置文件无法删除

**错误信息**：权限不足

**解决方法**：
```bash
# 使用 root 权限
sudo ./scripts/uninstall_deploy.sh

# 或手动删除
sudo rm -f /usr/local/openresty/nginx/conf/nginx.conf
```

### 问题 3: 配置文件不存在

**错误信息**：配置文件不存在

**解决方法**：
- 这是正常的，如果配置文件未部署或已被删除
- 脚本会跳过删除步骤

## 相关脚本

- `deploy.sh` - 配置文件部署脚本
- `uninstall_openresty.sh` - OpenResty 卸载脚本
- `start.sh` - 主启动脚本（可调用卸载功能）

## 版本历史

- v1.0 - 初始版本，支持基本卸载功能
- v1.1 - 添加命令行参数支持，可通过 start.sh 调用

