# Scripts 目录说明

本目录包含所有安装、部署、维护脚本，用于自动化 OpenResty WAF 系统的部署和管理。

## 脚本分类

### 安装脚本

- **install_openresty.sh** - OpenResty 一键安装脚本（支持多种 Linux 发行版）
- **install_mysql.sh** - MySQL 一键安装脚本（支持多种 Linux 发行版）
  - 自动检测硬件配置（CPU 核心数、内存大小）
  - 根据硬件自动优化 MySQL 配置参数（InnoDB 缓冲池、连接数、I/O 线程等）
  - 自动创建数据库和用户
  - 自动执行 SQL 脚本初始化数据库
  - 自动更新 `lua/config.lua` 配置
- **install_redis.sh** - Redis 一键安装脚本（支持多种 Linux 发行版）
  - 自动检测硬件配置（CPU 核心数、内存大小）
  - 根据硬件自动优化 Redis 配置参数（maxmemory、tcp-backlog、持久化策略等）
  - 自动配置密码（可选）
  - 自动更新 `lua/config.lua` 配置
- **install_geoip.sh** - GeoIP2 数据库安装脚本
  - 自动下载 GeoLite2-City 数据库
  - 自动保存配置用于后续更新

### 部署脚本

- **deploy.sh** - 配置文件部署脚本
  - 复制 `init_file/nginx.conf` 到系统目录
  - 自动处理路径替换（`$project_root` 变量）
  - 验证配置文件语法
  - `conf.d/` 和 `lua/` 目录保持在项目目录

### 配置脚本

- **set_lua_database_connect.sh** - 数据库连接配置脚本
  - 更新 `lua/config.lua` 中的 MySQL 和 Redis 配置
  - 支持交互式配置和命令行参数
  - 自动备份原配置文件
  - 配置文件语法验证

### 维护脚本

- **update_geoip.sh** - GeoIP 数据库更新脚本
  - 自动更新 GeoLite2-City 数据库
  - 支持 crontab 计划任务
- **optimize_system.sh** - 系统优化脚本
  - 根据硬件自动优化系统内核参数
  - 自动优化 OpenResty/Nginx 配置
- **硬件自动优化** ⭐
  - `install_mysql.sh` 和 `install_redis.sh` 会自动检测硬件配置
  - 根据 CPU 核心数和内存大小自动优化配置参数
  - 最大化并发处理能力和读写性能
  - 无需手动调整，自动适配不同硬件环境
- **check_all.sh** - 项目全面检查脚本
  - 检查脚本语法和逻辑
  - 检查路径引用
  - 检查配置文件完整性
- **check_dependencies.sh** - 依赖检查脚本 ⭐
  - 检查所有 Lua 模块依赖的安装状态
  - 交互式安装缺失的依赖
  - 提供详细的依赖信息和统计
- **install_dependencies.sh** - 依赖自动安装脚本 ⭐
  - 自动安装所有缺失的依赖
  - 适合自动化部署场景
  - 优先安装必需依赖

### 卸载脚本

- **uninstall_openresty.sh** - 卸载 OpenResty
- **uninstall_mysql.sh** - 卸载 MySQL
- **uninstall_redis.sh** - 卸载 Redis
- **uninstall_geoip.sh** - 卸载 GeoIP 数据库
- **uninstall_deploy.sh** - 卸载部署的配置文件
- **uninstall_dependencies.sh** - 卸载 Lua 模块依赖 ⭐

### 工具脚本

- **common.sh** - 公共函数库（可选工具）

### 依赖管理脚本 ⭐

依赖管理脚本用于管理第三方 Lua 模块依赖：

- **check_dependencies.sh** - 依赖检查脚本
  - 检查所有第三方 Lua 模块依赖的安装状态
  - 显示依赖状态和说明
  - 交互式安装缺失的依赖
  - 提供详细的依赖信息和统计
- **install_dependencies.sh** - 依赖自动安装脚本
  - 自动安装所有缺失的依赖
  - 不询问，直接安装
  - 适合自动化部署场景
  - 优先安装必需依赖
- **uninstall_dependencies.sh** - 依赖卸载脚本
  - 交互式卸载已安装的依赖模块
  - 必需模块卸载前会警告
  - 提供卸载统计信息

**说明**：依赖管理脚本的详细使用方式请直接查看 `check_dependencies.sh`、`install_dependencies.sh`、`uninstall_dependencies.sh` 内部注释。

## 一键安装（推荐）

使用项目根目录的 `start.sh` 脚本进行一键安装：

```bash
sudo ./start.sh
```

`start.sh` 会自动调用本目录下的各个脚本，按正确顺序完成安装。

## 脚本与 Lua 代码集成

### 1. 配置传递

**Shell 脚本 → Lua 配置**：
- `install_mysql.sh` 和 `install_redis.sh` 自动调用 `set_lua_database_connect.sh`
- 更新 `lua/config.lua` 中的数据库连接信息
- Lua 代码通过 `require("config")` 读取配置

**路径**：
- `scripts/install_mysql.sh:2170-2195` - 更新 WAF 配置
- `scripts/install_redis.sh:665-685` - 更新 WAF 配置
- `scripts/set_lua_database_connect.sh` - 配置更新脚本
- `lua/config.lua` - 配置文件

### 2. 路径一致性

**Shell 脚本设置路径 → Lua 代码读取路径**：
- `deploy.sh` 在 `nginx.conf` 中设置 `set $project_root "/实际路径"`
- Lua 代码通过 `ngx.var.project_root` 获取项目路径
- 所有相对路径都基于 `$project_root` 变量

**路径**：
- `scripts/deploy.sh:77` - 设置 `$project_root` 变量
- `lua/waf/init.lua:41-48` - 读取 `$project_root` 变量
- `conf.d/http_set/lua.conf` - Lua 模块路径与初始化配置

### 3. 数据库初始化

**Shell 脚本初始化 → Lua 代码使用**：
- `install_mysql.sh` 执行 `init_file/init.sql`
- 创建数据库和所有表结构
- Lua 代码通过 `mysql_pool.lua` 连接数据库并执行操作

**路径**：
- `scripts/install_mysql.sh:2198-2248` - 数据库初始化
- `init_file/init.sql` - SQL 脚本
- `lua/waf/mysql_pool.lua` - MySQL 连接池

### 4. GeoIP 数据库管理

**Shell 脚本安装 → Lua 代码使用**：
- `install_geoip.sh` 下载 GeoIP 数据库到 `lua/geoip/`
- `update_geoip.sh` 定期更新数据库
- `lua/waf/geo_block.lua` 读取并查询 GeoIP 数据库

**路径**：
- `scripts/install_geoip.sh` - 安装 GeoIP 数据库
- `scripts/update_geoip.sh` - 更新 GeoIP 数据库
- `lua/waf/geo_block.lua` - 地域封控模块

## 脚本执行顺序

### 完整安装流程

```
1. start.sh (主脚本)
   ↓
2. install_openresty.sh (安装 OpenResty)
   ├─ 自动安装常用 Lua 模块（resty.mysql, resty.redis 等）
   └─ 配置 systemd 服务
   ↓
3. deploy.sh (部署配置文件)
   ↓
4. install_dependencies.sh (安装依赖，可选，推荐)
   ├─ 检查并安装缺失的 Lua 模块
   └─ 确保所有必需依赖已安装
   ↓
5. install_mysql.sh (安装 MySQL)
   ├─ 创建数据库和用户
   ├─ 执行 SQL 脚本初始化数据库
   └─ 更新 lua/config.lua (调用 set_lua_database_connect.sh)
   ↓
6. install_redis.sh (安装 Redis，可选)
   └─ 更新 lua/config.lua (调用 set_lua_database_connect.sh)
   ↓
7. install_geoip.sh (安装 GeoIP，可选)
   ↓
8. optimize_system.sh (系统优化，可选)
```

**注意**：`install_openresty.sh` 会自动安装部分常用 Lua 模块，但建议运行 `install_dependencies.sh` 确保所有依赖完整。

### 单独安装

每个脚本都可以独立运行：

```bash
# 只安装 OpenResty
sudo ./scripts/install_openresty.sh

# 只安装 MySQL
sudo ./scripts/install_mysql.sh

# 只部署配置文件
sudo ./scripts/deploy.sh

# 只更新数据库配置
sudo ./scripts/set_lua_database_connect.sh

# 依赖管理
sudo ./scripts/check_dependencies.sh      # 检查依赖（交互式）
sudo ./scripts/install_dependencies.sh    # 自动安装所有依赖
sudo ./scripts/uninstall_dependencies.sh  # 卸载依赖（交互式）

# 或通过 start.sh 使用
sudo ./start.sh dependencies              # 依赖管理菜单
sudo ./start.sh uninstall dependencies   # 卸载依赖
```

## 脚本特性

### 1. 错误处理

- 所有脚本使用 `set -e`（遇到错误立即退出）
- 区分必须步骤和可选步骤的错误处理
- 详细的错误提示和解决建议

### 2. 跨平台支持

- 支持多种 Linux 发行版：
  - **RedHat 系列**：CentOS、RHEL、Fedora、Rocky Linux、AlmaLinux、Oracle Linux、Amazon Linux
  - **Debian 系列**：Debian、Ubuntu、Linux Mint、Kali Linux、Raspbian
  - **SUSE 系列**：openSUSE、SLES
  - **Arch 系列**：Arch Linux、Manjaro
  - **其他**：Alpine Linux、Gentoo
- 自动检测系统类型
- 自动选择适合的安装方式（包管理器或源码编译）
- 所有路径使用环境变量配置，无硬编码绝对路径

### 3. 交互式配置

- 友好的交互式提示
- 默认值支持（直接回车使用默认值）
- 密码输入隐藏（`read -sp`）

### 4. 配置备份

- 自动备份原配置文件（`.bak.时间戳`）
- 配置文件语法验证
- 支持特殊字符密码（使用 Python3）

## 注意事项

1. **执行权限**：所有脚本都需要执行权限
   ```bash
   chmod +x scripts/*.sh
   ```

2. **Root 权限**：安装脚本需要 root 权限
   ```bash
   sudo ./scripts/install_*.sh
   ```

3. **路径配置**：所有脚本使用环境变量配置路径，无硬编码绝对路径
   - OpenResty 安装路径：通过 `OPENRESTY_PREFIX` 环境变量配置（默认：`/usr/local/openresty`）
   - 项目路径：使用相对路径，通过 `$project_root` 变量在配置文件中引用
   - 示例：`sudo OPENRESTY_PREFIX=/opt/openresty ./scripts/install_openresty.sh`
   - 部署后不要移动项目目录，如果必须移动，需要重新运行 `deploy.sh`

4. **配置更新**：修改 `conf.d/` 中的配置后无需重新部署
   - 直接运行 `openresty -s reload` 即可生效

5. **数据库配置**：数据库连接配置会自动更新
   - `install_mysql.sh` 和 `install_redis.sh` 会自动更新 `lua/config.lua`
   - 也可以手动运行 `set_lua_database_connect.sh` 更新配置

6. **依赖管理**：建议在安装 OpenResty 后检查依赖
   - `install_openresty.sh` 会自动安装部分常用模块
   - 建议运行 `check_dependencies.sh` 或 `install_dependencies.sh` 确保所有依赖完整
   - 可以通过 `start.sh dependencies` 使用依赖管理功能

## 相关说明

- 安装与部署整体流程：参考根目录 `README.md` 与 `docs/部署文档.md`。
- 各脚本的详细参数与行为：参考对应 `*.sh` 文件顶部的注释说明。

