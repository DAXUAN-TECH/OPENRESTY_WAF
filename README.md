# OpenResty + MySQL IP 采集与封控系统

基于 OpenResty 和 MySQL 的 Web 应用防火墙（WAF）系统，实现 IP 访问日志采集和智能封控功能。

## 📋 项目概述

本项目实现了一个高性能的 IP 采集与封控系统，主要功能包括：

1. **IP 采集**：实时采集客户端 IP、请求路径、响应状态码等信息
2. **IP 封控**：支持单个 IP、IP 段、地域等多种封控方式
3. **规则管理**：灵活的封控规则配置和管理
4. **日志分析**：访问日志查询和统计分析

## ✨ 核心特性

- 🚀 **高性能**：基于 OpenResty，理论最大并发可达 200 万+（32核配置），实际支持 10,000-100,000 QPS
- 🔒 **灵活封控**：支持单个 IP、IP 段（CIDR）、地域封控
- 📊 **实时采集**：异步批量写入，不阻塞请求
- 🎯 **精确识别**：支持代理环境下的真实 IP 识别
- 💾 **数据持久化**：MySQL 存储，支持复杂查询
- ⚡ **缓存优化**：本地 LRU 缓存 + Redis 分布式缓存
- 🛡️ **白名单机制**：防止误封正常用户
- 🔐 **安全加固**：所有API和页面都需要登录认证，支持TOTP双因素认证
- 🎛️ **功能开关**：所有功能都可通过数据库动态控制开启/关闭
- 📦 **可移植性**：代码使用相对路径，支持环境变量配置，易于部署
- 💻 **硬件友好**：最低配置 2核4GB 即可运行，支持 5,000-10,000 并发

## 🏗️ 系统架构

```
客户端请求
    ↓
OpenResty (access_by_lua: 封控检查)
    ↓
后端应用处理
    ↓
OpenResty (log_by_lua: 日志采集)
    ↓
MySQL 数据库
```

## 📁 项目结构

```
OPENRESTY_WAF/
├── README.md                # 项目说明（本文件）
├── start.sh                 # 一键启动脚本（推荐使用）⭐
├── start_README.md          # 一键启动脚本说明
├── init_file/               # 初始配置文件目录
│   ├── nginx.conf           # Nginx 主配置文件（部署时复制到系统目录）
│   └── 数据库设计.sql       # 数据库表结构
├── conf.d/                  # 配置文件目录（保持在项目目录）⭐
│   ├── README.md            # 配置说明
│   ├── set_conf/            # 参数配置文件
│   │   ├── basic.conf       # 基础配置
│   │   ├── gzip.conf        # Gzip 压缩配置
│   │   ├── log.conf         # 日志配置
│   │   ├── lua.conf         # Lua 模块配置
│   │   ├── mime.conf        # MIME 类型配置
│   │   ├── performance.conf # 性能优化配置
│   │   ├── upstream.conf    # 后端服务器配置
│   │   └── waf.conf         # WAF 配置
│   ├── vhost_conf/          # 虚拟主机配置
│   │   └── default.conf     # 默认 HTTP 服务器配置
│   ├── cert/                # SSL 证书目录（可选）
│   └── logs/                # 日志配置目录（可选）
├── docs/                    # 文档目录
│   ├── 方案总结.md          # 方案总结
│   ├── 可行性分析.md        # 可行性分析文档
│   ├── 需求文档.md          # 需求文档
│   ├── 技术实施方案.md      # 技术实施方案
│   ├── 部署文档.md          # 部署文档
│   ├── 地域封控使用示例.md  # 地域封控使用示例
│   ├── 性能优化指南.md      # 性能优化指南
│   └── 代码审计报告.md      # 代码审计报告
├── scripts/                 # 脚本目录
│   ├── install_mysql.sh     # MySQL 一键安装脚本（支持多种 Linux 发行版）
│   ├── install_mysql_README.md  # MySQL 安装说明
│   ├── install_redis.sh     # Redis 一键安装脚本（支持多种 Linux 发行版）
│   ├── install_redis_README.md  # Redis 安装说明
│   ├── install_openresty.sh # OpenResty 一键安装脚本
│   ├── install_openresty_README.md  # OpenResty 安装说明
│   ├── deploy.sh            # 部署脚本（自动处理路径）
│   ├── deploy_README.md     # 部署脚本说明
│   ├── install_geoip.sh     # GeoIP2 数据库安装脚本
│   ├── install_geoip_README.md  # GeoIP 安装说明
│   ├── update_geoip.sh      # GeoIP2 数据库更新脚本
│   ├── update_geoip_README.md  # GeoIP 更新说明
│   ├── optimize_system.sh   # 系统优化脚本（根据硬件自动优化）
│   ├── optimize_system_README.md  # 系统优化脚本说明
│   ├── check_all.sh         # 项目检查脚本
│   ├── check_all_README.md  # 项目检查脚本说明
│   ├── common.sh            # 公共函数库（可选工具）
│   └── common_README.md     # 公共函数库说明
├── lua/                     # Lua 脚本目录（保持在项目目录）
│   ├── config.lua           # 配置文件（数据库连接等）
│   ├── api/                 # API接口模块
│   │   ├── handler.lua     # API路由分发器
│   │   ├── auth.lua        # 认证API
│   │   ├── rules.lua       # 规则管理API
│   │   ├── stats.lua        # 统计报表API
│   │   ├── proxy.lua       # 反向代理管理API
│   │   ├── features.lua    # 功能开关管理API
│   │   ├── templates.lua   # 模板管理API
│   │   ├── batch.lua       # 批量操作API
│   │   ├── config_check.lua # 配置检查API
│   │   ├── system.lua      # 系统管理API
│   │   ├── utils.lua       # API工具函数
│   │   └── README.md       # API模块说明
│   ├── web/                 # Web前端文件
│   │   ├── handler.lua    # Web路由分发器
│   │   ├── login.html      # 登录页面
│   │   ├── features.html   # 功能管理界面
│   │   ├── rule_management.html # 规则管理界面
│   │   ├── proxy_management.html # 反向代理管理界面
│   │   ├── stats.html      # 统计报表界面
│   │   ├── monitor.html    # 监控面板界面
│   │   └── README.md       # Web模块说明
│   ├── tests/               # 测试文件
│   │   ├── unit/           # 单元测试
│   │   ├── integration/    # 集成测试
│   │   ├── run_tests.lua   # 测试运行器
│   │   └── README.md       # 测试说明
│   ├── geoip/               # GeoIP 数据库目录
│   │   └── README.md        # GeoIP 使用说明
│   └── waf/                 # WAF 核心模块
│       ├── init.lua         # 初始化模块
│       ├── ip_block.lua     # IP 封控模块
│       ├── ip_utils.lua     # IP 工具函数
│       ├── ip_trie.lua      # IP Trie树（高效IP匹配）
│       ├── log_collect.lua  # 日志采集模块
│       ├── log_queue.lua    # 日志队列模块
│       ├── mysql_pool.lua   # MySQL 连接池
│       ├── geo_block.lua    # 地域封控模块
│       ├── auto_block.lua   # 自动封控模块
│       ├── auto_unblock.lua # 自动解封模块
│       ├── auth.lua         # 用户认证模块
│       ├── totp.lua         # TOTP双因素认证
│       ├── password_utils.lua # 密码工具模块
│       ├── rule_management.lua # 规则管理模块
│       ├── rule_templates.lua # 规则模板模块
│       ├── rule_backup.lua  # 规则备份模块
│       ├── rule_notification.lua # 规则更新通知
│       ├── batch_operations.lua # 批量操作模块
│       ├── feature_switches.lua # 功能开关模块
│       ├── proxy_management.lua # 反向代理管理
│       ├── frequency_stats.lua # 频率统计模块
│       ├── lru_cache.lua    # LRU缓存模块
│       ├── redis_cache.lua  # Redis缓存模块
│       ├── cache_warmup.lua # 缓存预热模块
│       ├── cache_invalidation.lua # 缓存失效模块
│       ├── cache_protection.lua # 缓存穿透防护
│       ├── serializer.lua  # 序列化模块
│       ├── metrics.lua      # 监控指标模块
│       ├── alert.lua        # 告警模块
│       ├── health_check.lua # 健康检查模块
│       ├── fallback.lua     # 降级机制模块
│       ├── pool_monitor.lua # 连接池监控模块
│       ├── path_utils.lua   # 路径工具模块
│       ├── config_validator.lua # 配置验证模块
│       └── test_framework.lua # 测试框架模块
└── logs/                    # 日志文件目录（保持在项目目录）
    ├── error.log            # 错误日志
    ├── access.log           # 访问日志
    └── geoip_update.log     # GeoIP 更新日志
```

**部署策略说明**：
- ✅ `init_file/nginx.conf` - 复制到 `${OPENRESTY_PREFIX}/nginx/conf/nginx.conf`（默认：`/usr/local/openresty/nginx/conf/nginx.conf`）
- ✅ `init_file/数据库设计.sql` - 用于初始化数据库
- ✅ `conf.d/` - **保持在项目目录**（方便配置管理，修改后无需重新部署）
- ✅ `lua/` - **保持在项目目录**（不复制）
- ✅ `logs/` - **保持在项目目录**（日志文件）

**路径配置说明**：
- 所有脚本支持通过环境变量 `OPENRESTY_PREFIX` 配置 OpenResty 安装路径（默认：`/usr/local/openresty`）
- 项目路径使用相对路径，通过 `$project_root` 变量在配置文件中引用
- 无硬编码绝对路径，支持灵活部署

## 🚀 快速开始

### 方式一：一键安装（推荐）⭐

使用统一的一键安装脚本，自动完成所有安装和配置步骤：

```bash
# 运行一键安装脚本
sudo ./start.sh
```

**脚本会自动完成**：
1. ✅ 收集配置信息（支持本地/外部数据库选择，默认本地）
2. ✅ 安装数据库（如果选择本地，自动安装 MySQL 和 Redis）
3. ✅ 创建必要目录（自动创建日志目录）
4. ✅ 安装 OpenResty（自动检测系统类型）
5. ✅ 部署配置文件（自动处理路径）
6. ✅ 配置 MySQL 和 Redis 连接（自动同步密码）
7. ✅ 初始化数据库（自动执行 SQL 脚本）
8. ✅ 安装 GeoIP 数据库（可选）
9. ✅ 系统优化（可选，推荐）

**优势**：
- 🎯 一步到位，无需手动操作
- 🗄️ 支持本地/外部数据库选择
- 🔧 本地数据库自动安装和配置
- 🔒 自动配置数据库连接，密码自动同步
- 📝 自动备份配置文件
- ⚙️ 支持交互式配置
- 🛡️ 完善的错误处理（必须步骤失败会退出，可选步骤失败会继续）
- 📁 自动创建必要目录（日志目录等）

详细说明请参考：[install_README.md](install_README.md)

---

### 方式二：分步安装

如果需要分步安装，可以按照以下步骤操作：

### 1. 环境要求

**操作系统支持**：
- **RedHat 系列**：CentOS、RHEL、Fedora、Rocky Linux、AlmaLinux、Oracle Linux、Amazon Linux
- **Debian 系列**：Debian、Ubuntu、Linux Mint、Kali Linux、Raspbian
- **SUSE 系列**：openSUSE、SLES
- **Arch 系列**：Arch Linux、Manjaro
- **其他**：Alpine Linux、Gentoo

**软件要求**：
- OpenResty 1.21.4.1+（脚本自动安装，支持多种 Linux 发行版）
- MySQL 8.0+ 或 MariaDB 10.6+（可选择本地安装或使用外部数据库）
- Redis 5.0+（可选，可选择本地安装或使用外部数据库）

### 2. 安装 OpenResty（推荐使用一键安装脚本）

```bash
# 使用一键安装脚本（支持多种 Linux 发行版）
sudo ./scripts/install_openresty.sh

# 脚本会自动：
# - 检测操作系统类型
# - 安装所需依赖
# - 安装 OpenResty
# - 配置 systemd 服务
# - 安装常用 Lua 模块
```

**自定义安装路径**：

```bash
# 通过环境变量指定安装路径（默认：/usr/local/openresty）
sudo OPENRESTY_PREFIX=/opt/openresty ./scripts/install_openresty.sh
```

**或者手动安装**：

```bash
# CentOS/RHEL
sudo yum install -y openresty openresty-resty

# Ubuntu/Debian
sudo apt-get install -y openresty

# 安装 Lua 模块（推荐使用依赖管理脚本）
sudo ./scripts/install_dependencies.sh

# 或手动安装
opm get openresty/lua-resty-mysql
opm get openresty/lua-resty-redis  # 可选
```

**注意**：所有脚本都支持通过环境变量 `OPENRESTY_PREFIX` 配置路径，无硬编码绝对路径。

详细说明请参考：
- [install_openresty_README.md](scripts/install_openresty_README.md) - OpenResty 安装说明
- [dependencies_README.md](scripts/dependencies_README.md) - 依赖管理说明（推荐）⭐

### 3. 数据库配置

**方式一：使用一键安装脚本（推荐）**

如果使用 `start.sh` 一键安装，可以选择：
- **本地数据库**（默认）：输入 `Y` 或直接回车，脚本会自动安装 MySQL 和 Redis，并创建数据库和用户
- **外部数据库**：输入 `n`，然后填写外部数据库连接信息

**方式二：手动安装和配置**

```bash
# 安装 MySQL（使用一键安装脚本）
sudo ./scripts/install_mysql.sh

# 或安装 Redis（使用一键安装脚本）
sudo ./scripts/install_redis.sh

# 创建数据库
mysql -u root -p < init_file/数据库设计.sql

# 修改配置文件中的数据库连接信息
vim lua/config.lua
```

详细说明请参考：
- [MySQL 安装说明](scripts/install_mysql_README.md)
- [Redis 安装说明](scripts/install_redis_README.md)

### 4. 安装 GeoIP2 数据库（可选，用于地域封控）

```bash
# 使用一键安装脚本（推荐）
sudo ./scripts/install_geoip.sh YOUR_LICENSE_KEY

# 或者交互式输入 License Key
sudo ./scripts/install_geoip.sh
```

**注意**：
- 需要有效的 MaxMind License Key
- 如果不使用地域封控功能，可以跳过此步骤
- 详细说明请参考 `scripts/install_geoip_README.md`

### 5. 部署文件（推荐使用部署脚本）

```bash
# 使用部署脚本（自动处理路径替换）
sudo ./scripts/deploy.sh
```

部署脚本会自动：
- 复制 `init_file/nginx.conf` 到系统目录
- 更新所有路径配置
- 设置文件权限

**注意**：
- `conf.d/`、`lua/`、`logs/` 目录保持在项目目录，方便配置管理
- 修改配置后无需重新部署，直接 reload 即可

### 6. 启动服务

```bash
# 测试配置（使用默认路径）
sudo /usr/local/openresty/bin/openresty -t

# 或使用环境变量指定的路径
sudo ${OPENRESTY_PREFIX:-/usr/local/openresty}/bin/openresty -t

# 启动服务
sudo /usr/local/openresty/bin/openresty

# 重新加载配置（修改 conf.d 后使用）
sudo /usr/local/openresty/bin/openresty -s reload
```

详细部署步骤请参考 [部署文档](docs/部署文档.md) 或 [部署脚本说明](scripts/deploy_README.md)

### 7. 系统优化（推荐，提高性能）

```bash
# 使用系统优化脚本（根据硬件自动优化）
sudo ./scripts/optimize_system.sh
```

优化脚本会自动：
- 检测硬件信息（CPU、内存等）
- 计算最优配置参数
- 优化系统内核参数（文件描述符、网络参数等）
- 优化 OpenResty/Nginx 配置（worker_processes、worker_connections 等）
- 自动创建备份

**优化效果**：
- 理论最大并发连接数：从数千提升到数十万
- 文件描述符限制：从 4096 提升到 100 万
- 充分利用多核 CPU：worker_processes 自动设置为 CPU 核心数

详细说明请参考 [系统优化脚本说明](scripts/optimize_system_README.md)

## 📖 文档说明

### 核心文档
- [项目全面分析报告](docs/项目全面分析报告.md) - **全方位项目分析报告（运维、架构、产品视角）** ⭐
- [需求文档](docs/需求文档.md) - 功能需求、非功能需求、数据需求
- [技术实施方案](docs/技术实施方案.md) - 架构设计、实现方案、性能优化
- [数据库设计](init_file/数据库设计.sql) - 表结构设计、索引优化

### 部署与运维
- [一键安装脚本说明](install_README.md) - 一键安装脚本使用说明（推荐）⭐
- [部署文档](docs/部署文档.md) - 安装步骤、配置说明、故障排查
- [MySQL 安装说明](scripts/install_mysql_README.md) - MySQL 安装脚本说明
- [Redis 安装说明](scripts/install_redis_README.md) - Redis 安装脚本说明
- [OpenResty 安装说明](scripts/install_openresty_README.md) - OpenResty 安装脚本说明
- [部署脚本说明](scripts/deploy_README.md) - 部署脚本使用说明
- [GeoIP 安装说明](scripts/install_geoip_README.md) - GeoIP 数据库安装说明
- [GeoIP 更新说明](scripts/update_geoip_README.md) - GeoIP 数据库更新说明
- [系统优化说明](scripts/optimize_system_README.md) - 系统优化脚本说明
- [项目检查说明](scripts/check_all_README.md) - 项目检查脚本说明
- [依赖管理说明](scripts/dependencies_README.md) - 第三方依赖管理和自动安装 ⭐
- [依赖卸载说明](scripts/uninstall_dependencies_README.md) - 依赖卸载脚本说明 ⭐
- [项目全面分析报告](docs/项目全面分析报告.md) - **全方位项目分析报告（运维、架构、产品视角）** ⭐
- [代码审计报告](docs/代码审计报告.md) - 代码安全审计报告

### 功能文档
- [地域封控使用示例](docs/地域封控使用示例.md) - 地域封控功能使用示例
- [性能优化指南](docs/性能优化指南.md) - 性能优化配置和调优指南
- [硬件开销与并发量分析](docs/硬件开销与并发量分析.md) - 硬件配置方案和并发支持能力分析 ⭐

### 配置说明
- [配置文件说明](conf.d/README.md) - Nginx 配置文件结构说明
- [GeoIP 使用说明](lua/geoip/README.md) - GeoIP2 数据库配置和使用

## 🔧 配置说明

### 数据库配置

编辑 `lua/config.lua`（配置文件保持在项目目录）：

**Shell 脚本关联**：
- `start.sh update-config` - 自动更新 MySQL 和 Redis 配置，自动验证配置文件语法（推荐）
- `scripts/deploy.sh` - 更新 Lua 脚本路径配置（`conf.d/set_conf/lua.conf`）
- `scripts/install_geoip.sh` - 安装 GeoIP 数据库到 `lua/geoip/`，提示启用地域封控
- `scripts/optimize_system.sh` - 优化共享内存配置（`conf.d/set_conf/waf.conf`）

**配置验证**：
- `start.sh update-config` 在更新配置后会自动验证 Lua 配置文件语法
- 使用 `luajit -bl` 或 `luac -p` 检查语法
- 如果语法错误，会显示警告信息

**主要配置项**：

```lua
_M.mysql = {
    host = "127.0.0.1",
    port = 3306,
    database = "waf_db",
    user = "waf_user",
    password = "your_password",
    pool_size = 50,
}
```

### 日志配置

```lua
_M.log = {
    batch_size = 100,        -- 批量写入大小
    batch_interval = 1,      -- 批量写入间隔（秒）
    enable_async = true,     -- 是否异步写入
    max_retry = 3,           -- 最大重试次数
    retry_delay = 0.1,       -- 重试延迟（秒）
    buffer_warn_threshold = 0.8,  -- 缓冲区警告阈值（80%）
}
```

### 缓存配置

```lua
_M.cache = {
    ttl = 60,                -- 缓存过期时间（秒）
    max_items = 10000,       -- 最大缓存项数
    rule_list_ttl = 300,     -- IP 段规则列表缓存时间（秒，5分钟）
}
```

### 封控配置

```lua
_M.block = {
    enable = true,           -- 是否启用封控
    block_page = "...",      -- 封控页面 HTML
}
```

### 白名单配置

```lua
_M.whitelist = {
    enable = true,           -- 是否启用白名单
}
```

### 地域封控配置

```lua
_M.geo = {
    enable = false,          -- 是否启用地域封控（需要先安装 GeoIP 数据库）
    -- geoip_db_path 会在运行时自动设置，无需手动配置
}
```

**启用地域封控**：
1. 安装 GeoIP 数据库：`sudo ./scripts/install_geoip.sh`
2. 在 `lua/config.lua` 中设置 `_M.geo.enable = true`
3. 重新加载配置：`sudo /usr/local/openresty/bin/openresty -s reload`

详细使用说明请参考：[地域封控使用示例](docs/地域封控使用示例.md)

## 📊 使用示例

### 添加封控规则

```sql
-- 单个 IP 封控
INSERT INTO waf_block_rules (rule_type, rule_value, rule_name, status, priority)
VALUES ('single_ip', '192.168.1.100', '封控恶意IP', 1, 100);

-- IP 段封控（CIDR）
INSERT INTO waf_block_rules (rule_type, rule_value, rule_name, status, priority)
VALUES ('ip_range', '192.168.1.0/24', '封控IP段', 1, 90);

-- IP 范围封控
INSERT INTO waf_block_rules (rule_type, rule_value, rule_name, status, priority)
VALUES ('ip_range', '192.168.1.1-192.168.1.100', '封控IP范围', 1, 90);
```

### 添加白名单

```sql
INSERT INTO waf_whitelist (ip_type, ip_value, description, status)
VALUES ('single_ip', '192.168.1.50', '管理员IP', 1);
```

### 查询访问日志

```sql
-- 查询最近 1 小时的访问记录
SELECT * FROM waf_access_logs 
WHERE request_time >= DATE_SUB(NOW(), INTERVAL 1 HOUR)
ORDER BY request_time DESC;

-- 统计 IP 访问次数
SELECT client_ip, COUNT(*) as count 
FROM waf_access_logs 
WHERE request_time >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
GROUP BY client_ip 
ORDER BY count DESC;
```

## 🎯 功能特性

### IP 采集功能

- ✅ 采集客户端真实 IP（支持代理环境，X-Forwarded-For安全增强）
- ✅ 采集请求路径、方法、状态码、域名
- ✅ 采集 User-Agent、Referer
- ✅ 异步批量写入，不阻塞请求
- ✅ 日志队列机制，防止日志丢失
- ✅ 支持高并发场景（10,000+ QPS）

### IP 封控功能

- ✅ 单个 IP 精确封控
- ✅ IP 段封控（CIDR 格式）
- ✅ IP 范围封控（起始-结束）
- ✅ IP Trie树高效匹配
- ✅ 地域封控（基于 GeoIP2，支持国家/省/市三级）
- ✅ 白名单机制（优先级最高）
- ✅ 规则优先级管理
- ✅ 规则分组管理
- ✅ 定时生效/失效
- ✅ 自动封控（基于频率、错误率、扫描行为）
- ✅ 自动解封机制

### 管理功能

- ✅ Web管理界面（登录认证）
- ✅ RESTful API接口（完整CRUD）
- ✅ 规则管理（创建、查询、更新、删除、启用/禁用）
- ✅ 规则导入/导出（JSON、CSV格式）
- ✅ 规则模板管理
- ✅ 规则备份和恢复
- ✅ 功能开关管理（动态启用/禁用功能）
- ✅ 反向代理管理（HTTP/TCP/UDP）
- ✅ 统计报表（概览、时间序列、IP统计、规则统计）
- ✅ 实时监控面板（系统状态、性能指标）
- ✅ Prometheus指标导出

### 安全功能

- ✅ 用户认证（用户名密码登录）
- ✅ TOTP双因素认证（支持本地QR码生成）
- ✅ BCrypt密码哈希
- ✅ 会话管理（Cookie-based）
- ✅ 密码强度检查
- ✅ 密码生成工具
- ✅ X-Forwarded-For安全增强（受信任代理检查）
- ✅ 所有API和页面都需要登录认证

### 性能优化

- ✅ 多级缓存（共享内存、LRU、Redis二级缓存）
- ✅ 缓存预热机制
- ✅ 缓存失效机制（版本号检查）
- ✅ 缓存穿透防护（布隆过滤器、频率限制）
- ✅ 数据库连接池（可监控、可自动调整）
- ✅ 异步批量写入
- ✅ IP 整数比较优化
- ✅ IP Trie树高效匹配
- ✅ 系统级优化脚本（自动优化内核参数和 Nginx 配置）
- ✅ 高并发配置（支持数十万并发连接）
- ✅ 降级机制（数据库故障时自动降级）

### 监控与运维

- ✅ 实时监控指标（Prometheus格式）
- ✅ 告警功能（封控率、缓存未命中率、数据库故障等）
- ✅ 健康检查（数据库连接状态）
- ✅ 连接池监控（使用率、自动调整）
- ✅ 日志采集和统计
- ✅ 配置验证（启动时和运行时）
- ✅ 规则更新通知（Redis Pub/Sub）

## 🔍 监控与运维

### 查看日志

```bash
# 错误日志（项目目录）
tail -f logs/error.log

# 访问日志（项目目录）
tail -f logs/access.log

# GeoIP 更新日志（项目目录）
tail -f logs/geoip_update.log
```

### 性能监控

```bash
# 查看进程状态
ps aux | grep nginx

# 查看连接数
netstat -an | grep :80 | wc -l

# 查看数据库连接
mysql -u waf_user -p -e "SHOW PROCESSLIST;"
```

## ⚠️ 注意事项

1. **生产环境**：务必修改默认密码和配置
2. **性能调优**：根据实际负载调整连接池和缓存大小，参考 [性能优化指南](docs/性能优化指南.md)
3. **数据备份**：定期备份数据库，建议每日备份
4. **日志归档**：定期归档历史日志，避免数据库过大
5. **安全加固**：配置防火墙、使用 HTTPS、限制管理接口访问
6. **配置管理**：修改 `conf.d/` 中的配置后，无需重新部署，直接 `reload` 即可生效
7. **路径管理**：所有文件路径已优化，使用部署脚本自动处理，无需手动修改

## 🐛 故障排查

### 常见问题

1. **配置文件错误**
   - 检查 `nginx -t` 输出
   - 检查 Lua 模块路径

2. **数据库连接失败**
   - 检查 MySQL 服务状态
   - 检查用户名密码
   - 检查防火墙规则

3. **性能问题**
   - 检查数据库连接池配置
   - 检查缓存是否生效
   - 检查系统资源使用

详细故障排查请参考 [部署文档](docs/部署文档.md)

## 📝 开发计划

### 已完成功能 ✅
- [x] 基础 IP 采集功能
- [x] 单个 IP 封控
- [x] IP 段封控（CIDR）
- [x] IP 范围封控
- [x] IP Trie树高效匹配
- [x] 白名单机制
- [x] 地域封控（基于 GeoIP2，支持国家/省/市三级）
- [x] 异步批量日志写入
- [x] 日志队列机制
- [x] 多级缓存（共享内存、LRU、Redis）
- [x] MySQL 连接池（可监控、可自动调整）
- [x] 一键安装脚本（统一安装脚本）⭐
- [x] OpenResty 自动安装脚本
- [x] 自动部署脚本
- [x] GeoIP 数据库自动安装和更新
- [x] 系统自动优化脚本（根据硬件自动优化）
- [x] 项目检查脚本
- [x] 管理 API 接口（完整的RESTful API）
- [x] Web 管理界面（登录、功能管理、规则管理、代理管理、统计、监控）
- [x] 自动封控规则（基于访问频率、错误率、扫描行为）
- [x] 自动解封机制
- [x] Redis 分布式缓存集成
- [x] 实时监控面板
- [x] 统计报表功能（概览、时间序列、IP统计、规则统计）
- [x] 用户认证和权限管理
- [x] TOTP双因素认证（支持本地QR码生成）
- [x] BCrypt密码哈希
- [x] 密码强度检查
- [x] 密码生成工具
- [x] 功能开关管理（动态控制功能启用/禁用）
- [x] 反向代理管理（HTTP/TCP/UDP）
- [x] 规则模板管理
- [x] 规则备份和恢复
- [x] 规则分组管理
- [x] 规则导入/导出（JSON、CSV）
- [x] 配置验证功能（启动时和运行时）
- [x] 告警功能（封控率、缓存未命中率、数据库故障等）
- [x] Prometheus指标导出
- [x] X-Forwarded-For安全增强（受信任代理检查）
- [x] 缓存预热机制
- [x] 缓存失效机制（版本号检查）
- [x] 缓存穿透防护（布隆过滤器、频率限制）
- [x] 健康检查（数据库连接状态）
- [x] 连接池监控（使用率、自动调整）
- [x] 降级机制（数据库故障时自动降级）
- [x] 规则更新通知（Redis Pub/Sub）
- [x] 测试框架（单元测试、集成测试）

### 计划功能 🚧
- [ ] 更全面的测试覆盖
- [ ] API文档自动生成
- [ ] 更多监控指标
- [ ] 日志分析报表增强

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

本项目采用 MIT 许可证。

## 📞 联系方式

如有问题或建议，请提交 Issue。

---

**注意**：本项目仅供学习和参考使用，生产环境使用前请充分测试。

