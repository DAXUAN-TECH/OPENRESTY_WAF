# 部署脚本使用说明

## 概述

`deploy.sh` 脚本用于自动部署 OpenResty WAF 配置文件，自动处理路径替换，确保所有文件路径正确。

## 部署策略

### 文件部署位置

1. **init_file/nginx.conf** - 复制到 `/usr/local/openresty/nginx/conf/nginx.conf`
2. **conf.d/** - **保持在项目目录**（不复制，方便配置管理）⭐
3. **lua/** - **保持在项目目录**（不复制）
4. **logs/** - **保持在项目目录**（日志文件）

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
   - init_file/nginx.conf → `/usr/local/openresty/nginx/conf/nginx.conf`
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
│   └── 数据库设计.sql  # 数据库表结构
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
/usr/local/openresty/bin/openresty -t
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
- `/path/to/project/logs/nginx.pid` → `/实际路径/logs/nginx.pid`
- `include /path/to/project/conf.d/set_conf/*.conf` → `include /实际路径/conf.d/set_conf/*.conf`
- `include /path/to/project/conf.d/vhost_conf/*.conf` → `include /实际路径/conf.d/vhost_conf/*.conf`

**在项目目录的 conf.d/set_conf/lua.conf 中**：
- `$project_root/lua` → `/实际路径/lua`

**在项目目录的 conf.d/set_conf/log.conf 中**：
- `$project_root/logs/access.log` → `/实际路径/logs/access.log`

### 步骤 4：验证配置
- 验证配置文件处理完成
- 设置文件权限

## 相关脚本

- `install_openresty.sh` - 安装 OpenResty
- `install_geoip.sh` - 安装 GeoIP 数据库
- `update_geoip.sh` - 更新 GeoIP 数据库
- `optimize_system.sh` - 系统优化（推荐在部署后运行）

