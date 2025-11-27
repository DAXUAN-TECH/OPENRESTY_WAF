# 部署脚本使用说明

## 概述

`deploy.sh` 脚本用于自动部署 OpenResty WAF 配置文件，自动处理路径替换，确保所有文件路径正确。

## 部署策略

### 文件部署位置

1. **init_file/nginx.conf** - 复制到 `${OPENRESTY_PREFIX}/nginx/conf/nginx.conf`（默认：`/usr/local/openresty/nginx/conf/nginx.conf`）
2. **conf.d/** - **保持在项目目录**（不复制，方便配置管理）⭐
3. **lua/** - **保持在项目目录**（不复制）
4. **logs/** - **保持在项目目录**（日志文件）

**注意**：所有路径通过环境变量 `OPENRESTY_PREFIX` 配置，无硬编码绝对路径。

### 路径处理

部署脚本会自动：
- 检测项目根目录
- 替换 init_file/nginx.conf 中的占位符路径
- 更新 Lua 脚本路径指向项目目录
- 更新日志路径指向项目目录的 logs 文件夹

## 使用方法

### 基本部署

```bash
# 使用默认 OpenResty 路径（/usr/local/openresty）
sudo ./scripts/deploy.sh
```

### 指定 OpenResty 路径

```bash
# 如果 OpenResty 安装在其他位置
sudo OPENRESTY_PREFIX=/opt/openresty ./scripts/deploy.sh
```

## 部署流程

1. **创建目录**
   - Nginx 配置目录
   - 项目 logs 目录
   - 项目 lua/geoip 目录

2. **复制配置文件**
   - init_file/nginx.conf → `${OPENRESTY_PREFIX}/nginx/conf/nginx.conf`（默认：`/usr/local/openresty/nginx/conf/nginx.conf`）
   - **注意**：conf.d/ 目录保持在项目目录，不复制到系统目录

3. **路径替换**
   - 替换 `$project_root` 变量为实际项目路径
   - 更新 Lua 脚本路径
   - 更新日志文件路径

4. **设置权限**
   - 设置日志目录权限
   - 设置配置文件权限

## 路径说明

### 项目目录结构

```
OPENRESTY_WAF/
├── init_file/          # 初始配置文件目录
│   ├── nginx.conf      # 主配置文件（复制到系统目录）
│   └── init.sql        # 数据库表结构
├── conf.d/             # 配置文件（保持在项目目录）⭐
│   ├── set_conf/       # 参数配置
│   ├── vhost_conf/     # 虚拟主机配置
│   ├── cert/           # SSL 证书目录（可选）
│   └── logs/           # 日志配置目录（可选）
├── lua/                # Lua 脚本（保持在项目目录）⭐
│   ├── config.lua
│   └── waf/
├── logs/               # 日志文件（保持在项目目录）⭐
│   ├── error.log
│   ├── access.log
│   └── geoip_update.log
└── scripts/            # 脚本文件（保持在项目目录）
```

### 路径变量

- `$project_root` - 项目根目录（在 nginx.conf 中设置）
- 配置文件路径：`$project_root/conf.d/`（保持在项目目录）
- Lua 脚本路径：`$project_root/lua/`
- 日志路径：`$project_root/logs/`
- GeoIP 数据库：`$project_root/lua/geoip/`

## 验证部署

### 1. 测试配置

```bash
# 使用默认路径
/usr/local/openresty/bin/openresty -t

# 或使用环境变量指定的路径
${OPENRESTY_PREFIX}/bin/openresty -t
```

### 2. 检查路径

```bash
# 检查 nginx.conf 中的路径（系统目录）
grep project_root /usr/local/openresty/nginx/conf/nginx.conf

# 检查 Lua 路径（项目目录）
grep lua_package_path conf.d/set_conf/lua.conf

# 检查日志路径（项目目录）
grep access_log conf.d/set_conf/log.conf

# 检查 conf.d include 路径（系统目录）
grep "include.*conf.d" /usr/local/openresty/nginx/conf/nginx.conf
```

### 3. 启动服务

```bash
/usr/local/openresty/bin/openresty
```

### 4. 查看日志

```bash
# 查看错误日志（项目目录）
tail -f /path/to/project/logs/error.log

# 查看访问日志（项目目录）
tail -f /path/to/project/logs/access.log
```

## 注意事项

1. **项目目录位置**
   - 部署后不要移动项目目录
   - 如果必须移动，需要重新运行部署脚本

2. **权限要求**
   - 需要 root 权限来复制 init_file/nginx.conf
   - 日志目录需要可写权限
   - conf.d 目录需要可读权限

3. **路径一致性**
   - 确保所有脚本使用相同的项目路径
   - GeoIP 更新脚本会自动检测项目路径

4. **配置修改**
   - **优势**：修改 conf.d 中的配置后，无需重新部署
   - 直接运行 `openresty -s reload` 即可生效
   - 配置文件和代码在同一目录，便于版本控制

5. **日志轮转**
   - 日志文件在项目目录的 logs 文件夹
   - 需要配置日志轮转（logrotate）

## 故障排查

### 问题 1：Lua 脚本找不到

**错误**：`failed to load module`

**解决**：
1. 检查 `$project_root` 变量是否正确设置
2. 检查 lua.conf 中的路径
3. 确认项目目录存在且可访问

### 问题 2：日志文件无法写入

**错误**：`Permission denied`

**解决**：
```bash
# 设置日志目录权限
sudo chown -R nobody:nobody /path/to/project/logs
sudo chmod 755 /path/to/project/logs
```

### 问题 3：路径变量未替换

**错误**：配置中仍有 `/path/to/project`

**解决**：
1. 重新运行部署脚本
2. 检查脚本是否有执行权限
3. 检查项目目录路径是否正确

## 部署流程详解

### 步骤 1：创建目录
- 创建项目 `logs/` 目录（存放日志文件）
- 创建项目 `lua/geoip/` 目录（存放 GeoIP 数据库）

### 步骤 2：复制主配置文件
- 只复制 `init_file/nginx.conf` 到系统目录
- `conf.d/` 目录保持在项目目录，不复制

### 步骤 3：处理路径配置
脚本会自动替换以下路径：

**在系统目录的 nginx.conf 中**（从 init_file/nginx.conf 复制）：
- `/path/to/project` → 实际项目路径
- `set $project_root "/path/to/project"` → `set $project_root "/实际路径"`
- `/path/to/project/logs/error.log` → `/实际路径/logs/error.log`
- `pid /usr/local/openresty/nginx/logs/nginx.pid` → **保持不变**（固定路径，必须与 systemd 服务文件一致）
- `include /path/to/project/conf.d/set_conf/*.conf` → `include /实际路径/conf.d/set_conf/*.conf`
- `include /path/to/project/conf.d/vhost_conf/*.conf` → `include /实际路径/conf.d/vhost_conf/*.conf`

**在项目目录的 conf.d/set_conf/lua.conf 中**：
- `$project_root/lua` → `/实际路径/lua`

**在项目目录的 conf.d/set_conf/log.conf 中**：
- `$project_root/logs/access.log` → `/实际路径/logs/access.log`

### 步骤 4：验证配置
- 验证配置文件处理完成
- 设置文件权限

## 脚本与 Lua 代码集成

### 路径集成

1. **项目路径设置**：
   - `deploy.sh` 在 `nginx.conf` 中设置 `set $project_root "/实际路径"`
   - Lua 代码通过 `ngx.var.project_root` 获取项目路径
   - 位置：`lua/waf/init.lua:41-48`

2. **Lua 模块路径**：
   - `deploy.sh` 确保 `lua_package_path` 指向项目目录
   - Lua 代码通过 `require` 加载模块
   - 位置：`conf.d/set_conf/lua.conf:8`

3. **配置文件路径**：
   - `lua/config.lua` 保持在项目目录
   - 脚本通过 `set_lua_database_connect.sh` 更新配置
   - Lua 代码通过 `require("config")` 加载配置

### 数据库集成

1. **数据库初始化**：
   - `install_mysql.sh` 执行 `init_file/init.sql`
   - 创建数据库和表结构
   - Lua 代码通过 `mysql_pool.lua` 连接数据库

2. **配置更新**：
   - `install_mysql.sh` 和 `install_redis.sh` 自动调用 `set_lua_database_connect.sh`
   - 更新 `lua/config.lua` 中的连接信息
   - Lua 代码读取配置并建立连接

### GeoIP 集成

1. **数据库安装**：
   - `install_geoip.sh` 下载 GeoIP 数据库到 `lua/geoip/`
   - `lua/waf/geo_block.lua` 读取 GeoIP 数据库
   - 位置：`lua/waf/geo_block.lua`

## 相关脚本

- `start.sh` - 一键安装脚本（推荐使用）
- `install_openresty.sh` - 安装 OpenResty
- `install_mysql.sh` - 安装 MySQL（包含数据库初始化和配置更新）
- `install_redis.sh` - 安装 Redis（包含配置更新）
- `install_geoip.sh` - 安装 GeoIP 数据库
- `set_lua_database_connect.sh` - 更新数据库连接配置
- `update_geoip.sh` - 更新 GeoIP 数据库
- `optimize_system.sh` - 系统优化（推荐在部署后运行）

