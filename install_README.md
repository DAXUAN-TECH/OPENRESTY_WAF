# 一键安装脚本使用说明

## 概述

`install.sh` 是 OpenResty WAF 系统的一键安装脚本，用于统一执行所有安装和配置步骤。

## 功能特性

### 自动化安装流程

1. ✅ **收集配置信息** - 交互式输入 MySQL 和 Redis 配置
2. ✅ **创建必要目录** - 自动创建日志目录（`logs/`）
3. ✅ **安装 OpenResty** - 自动检测系统并安装 OpenResty
4. ✅ **部署配置文件** - 自动部署并处理路径配置
5. ✅ **配置数据库连接** - 自动更新 `lua/config.lua` 中的连接信息
6. ✅ **初始化数据库** - 自动执行 SQL 脚本创建数据库和表
7. ✅ **安装 GeoIP** - 可选，安装地域封控数据库
8. ✅ **系统优化** - 可选，根据硬件自动优化系统参数

### 错误处理机制

**必须步骤**（失败会退出安装）：
- OpenResty 安装失败 → 显示错误并退出
- 配置文件部署失败 → 显示错误并退出
- MySQL 配置更新失败 → 显示错误并退出
- 数据库初始化失败 → 显示错误并退出

**可选步骤**（失败不影响整体安装）：
- GeoIP 安装失败 → 显示警告但继续安装
- 系统优化失败 → 显示警告但继续安装

### 脚本执行优先级

脚本按以下顺序执行，确保依赖关系正确：

```
1. install_openresty.sh  (必须)
   ↓
2. deploy.sh             (必须)
   ↓
3. 配置 MySQL/Redis      (必须)
   ↓
4. 初始化数据库         (必须)
   ↓
5. install_geoip.sh      (可选)
   ↓
6. optimize_system.sh    (可选，建议)
```

## 使用方法

### 基本使用

```bash
# 运行一键安装脚本
sudo ./install.sh
```

### 交互式配置

脚本会依次询问以下配置信息：

#### 1. MySQL 配置（必须）

- **主机地址**：默认 `127.0.0.1`
- **端口**：默认 `3306`
- **数据库名称**：默认 `waf_db`
- **用户名**：默认 `waf_user`
- **密码**：必须输入（不会显示）

**配置更新位置**：`lua/config.lua` 中的 `_M.mysql` 配置块

#### 2. Redis 配置（可选）

- **是否使用 Redis**：输入 `y` 启用，直接回车跳过
- **主机地址**：默认 `127.0.0.1`
- **端口**：默认 `6379`
- **密码**：可选，直接回车跳过
- **数据库编号**：默认 `0`

**配置更新位置**：`lua/config.lua` 中的 `_M.redis` 配置块

#### 3. GeoIP 配置（可选）

- **是否安装 GeoIP**：输入 `y` 安装，直接回车跳过
- **MaxMind Account ID**：必须输入
- **MaxMind License Key**：必须输入（不会显示）

#### 4. 系统优化（可选）

- **是否执行系统优化**：默认 `Y`，直接回车执行

## 安装流程详解

### 步骤 1: 收集配置信息

脚本会交互式询问所有必要的配置信息，包括：
- MySQL 连接信息
- Redis 连接信息（可选）
- GeoIP 认证信息（可选）
- 系统优化选项

### 步骤 2: 安装 OpenResty

- 自动检测操作系统类型
- 自动安装依赖包
- 自动安装 OpenResty（包管理器或源码编译）
- 自动配置 systemd 服务
- 自动安装 Lua 模块

**如果 OpenResty 已安装**：
- 会询问是否重新安装
- 选择 `N` 则跳过安装步骤

**错误处理**：
- 如果安装失败，脚本会显示错误信息并退出
- 必须修复错误后才能继续安装

### 步骤 3: 部署配置文件

- 自动创建日志目录（`logs/`）
- 自动复制 `init_file/nginx.conf` 到系统目录
- 自动处理所有路径替换
- 自动设置文件权限
- `conf.d` 和 `lua` 目录保持在项目目录

**错误处理**：
- 如果部署失败，脚本会显示错误信息并退出
- 必须修复错误后才能继续安装

### 步骤 4: 配置 MySQL 和 Redis

- 自动备份原配置文件（`config.lua.bak.时间戳`）
- 自动更新 MySQL 连接信息
- 自动更新 Redis 连接信息（如果启用）
- 自动转义特殊字符，确保配置正确

### 步骤 5: 初始化数据库

- 自动测试 MySQL 连接
- 自动执行 `init_file/数据库设计.sql`
- 创建数据库和所有表结构
- 如果数据库已存在，会显示警告（这是正常的）

### 步骤 6: 安装 GeoIP（可选）

- 如果选择安装，会调用 `install_geoip.sh`
- 自动下载并安装 GeoLite2-City 数据库
- 自动保存配置用于后续更新
- 自动设置 crontab 计划任务

**错误处理**：
- 如果安装失败，脚本会显示警告但**继续安装**
- 这是可选步骤，失败不会影响整体安装
- 可以稍后手动运行：`sudo scripts/install_geoip.sh`

### 步骤 7: 系统优化（可选）

- 如果选择优化，会调用 `optimize_system.sh`
- 自动检测硬件信息
- 自动计算优化参数
- 自动优化系统内核参数
- 自动优化 OpenResty/Nginx 配置

**错误处理**：
- 如果优化失败，脚本会显示警告但**继续安装**
- 这是可选步骤，失败不会影响整体安装
- 可以稍后手动运行：`sudo scripts/optimize_system.sh`

## 前置条件

### 必须条件

1. **root 权限**：需要 root 权限执行安装
2. **网络连接**：需要下载 OpenResty 和依赖包
3. **MySQL 服务**：MySQL 服务必须已安装并运行
4. **MySQL 用户权限**：用户需要有创建数据库的权限

### 可选条件

1. **Redis 服务**：如果使用 Redis 缓存（可选）
2. **MaxMind 账号**：如果安装 GeoIP 数据库（可选）

## 配置说明

### MySQL 配置

安装脚本会自动更新 `lua/config.lua` 中的 MySQL 配置：

```lua
_M.mysql = {
    host = "你输入的主机地址",
    port = 你输入的端口,
    database = "你输入的数据库名",
    user = "你输入的用户名",
    password = "你输入的密码",
    pool_size = 50,        -- 连接池大小
    pool_timeout = 10000,  -- 连接池超时（毫秒）
}
```

### Redis 配置

如果启用 Redis，会自动更新配置：

```lua
_M.redis = {
    host = "你输入的主机地址",
    port = 你输入的端口,
    password = "你输入的密码" 或 nil,
    db = 你输入的数据库编号,
    timeout = 1000,        -- 超时时间（毫秒）
    pool_size = 100,      -- 连接池大小
}
```

### 缓存配置（优化项）

以下配置项已预设，可根据需要调整：

```lua
_M.cache = {
    ttl = 60,              -- 缓存过期时间（秒）
    max_items = 10000,    -- 最大缓存项数
    rule_list_ttl = 300,  -- IP 段规则列表缓存时间（秒，5分钟）
}
```

### 日志配置（优化项）

以下配置项已预设，可根据需要调整：

```lua
_M.log = {
    batch_size = 100,           -- 批量写入大小
    batch_interval = 1,        -- 批量写入间隔（秒）
    enable_async = true,        -- 是否异步写入
    max_retry = 3,              -- 最大重试次数
    retry_delay = 0.1,          -- 重试延迟（秒）
    buffer_warn_threshold = 0.8,  -- 缓冲区警告阈值（80%）
}
```

### 配置文件备份

原配置文件会自动备份为：
```
lua/config.lua.bak.YYYYMMDD_HHMMSS
```

### 配置验证

安装脚本在更新配置后会自动验证 Lua 配置文件语法：
- 使用 `luajit -bl` 或 `luac -p` 检查语法
- 如果语法错误，会显示警告信息
- 如果未找到 Lua 编译器，会跳过语法检查（仅显示警告）

**注意**：配置验证仅检查语法，不检查配置值的有效性。

## 故障排查

### 问题 1: MySQL 连接失败

**错误信息**：`MySQL 连接失败`

**解决方法**：
1. 检查 MySQL 服务是否启动：`systemctl status mysql`
2. 检查用户名和密码是否正确
3. 检查用户是否有创建数据库的权限
4. 检查防火墙是否允许连接

### 问题 2: OpenResty 安装失败

**错误信息**：`✗ OpenResty 安装失败`

**解决方法**：
1. 检查网络连接
2. 检查系统依赖是否安装完整
3. 查看详细错误信息
4. 可以手动运行 `scripts/install_openresty.sh` 查看详细错误
5. 修复错误后重新运行 `install.sh`

**注意**：OpenResty 安装是必须步骤，失败会导致整个安装过程中断。

### 问题 5: 配置文件部署失败

**错误信息**：`✗ 配置文件部署失败`

**解决方法**：
1. 检查 `init_file/nginx.conf` 文件是否存在
2. 检查是否有写入权限
3. 检查 OpenResty 是否已正确安装
4. 可以手动运行 `scripts/deploy.sh` 查看详细错误

**注意**：配置文件部署是必须步骤，失败会导致整个安装过程中断。

### 问题 6: GeoIP 安装失败（可选）

**错误信息**：`⚠ GeoIP 安装失败，但这是可选步骤，将继续安装`

**解决方法**：
1. 检查 MaxMind Account ID 和 License Key 是否正确
2. 检查网络连接
3. 可以稍后手动运行：`sudo scripts/install_geoip.sh`
4. 这不会影响整体安装，可以继续使用其他功能

**注意**：GeoIP 安装是可选的，失败不会影响整体安装。

### 问题 7: 系统优化失败（可选）

**错误信息**：`⚠ 系统优化失败，但这是可选步骤，将继续安装`

**解决方法**：
1. 检查是否有 root 权限
2. 检查系统内核参数是否可修改
3. 可以稍后手动运行：`sudo scripts/optimize_system.sh`
4. 这不会影响整体安装，可以继续使用其他功能

**注意**：系统优化是可选的，失败不会影响整体安装。

### 问题 3: 数据库初始化失败

**错误信息**：SQL 执行错误

**解决方法**：
1. 检查数据库是否已存在（如果已存在，这是正常的）
2. 检查用户权限是否足够
3. 手动执行 SQL 脚本：`mysql -u user -p < init_file/数据库设计.sql`

### 问题 4: 配置文件更新失败

**错误信息**：配置未正确更新

**解决方法**：
1. 检查配置文件是否存在：`lua/config.lua`
2. 从备份恢复：`cp lua/config.lua.bak.* lua/config.lua`
3. 手动编辑配置文件

## 安装后验证

### 1. 检查 OpenResty

```bash
# 检查版本
/usr/local/openresty/bin/openresty -v

# 检查服务状态
systemctl status openresty
```

### 2. 检查配置文件

```bash
# 测试配置
/usr/local/openresty/bin/openresty -t

# 检查配置内容
grep -A 5 "mysql" lua/config.lua
```

### 3. 检查数据库

```bash
# 连接数据库
mysql -u waf_user -p waf_db

# 查看表
SHOW TABLES;
```

### 4. 检查日志

```bash
# 查看错误日志
tail -f logs/error.log

# 查看访问日志
tail -f logs/access.log
```

## 后续操作

### 1. 启动服务

```bash
# 启动 OpenResty
systemctl start openresty

# 设置开机自启
systemctl enable openresty
```

### 2. 添加封控规则

参考文档：[地域封控使用示例](docs/地域封控使用示例.md)

### 3. 配置后端服务器

编辑 `conf.d/vhost_conf/default.conf`，配置实际的后端服务器地址。

### 4. 监控和维护

- 定期查看日志：`logs/error.log`、`logs/access.log`
- 定期更新 GeoIP 数据库（如果已安装）
- 定期检查系统性能

## 相关脚本

- `scripts/install_openresty.sh` - OpenResty 安装脚本
- `scripts/deploy.sh` - 配置文件部署脚本
- `scripts/install_geoip.sh` - GeoIP 数据库安装脚本
- `scripts/optimize_system.sh` - 系统优化脚本
- `scripts/check_all.sh` - 项目检查脚本

## 注意事项

1. **配置文件备份**：安装前会自动备份配置文件
2. **密码安全**：输入的密码不会显示在屏幕上
3. **特殊字符**：密码中的特殊字符会自动转义
4. **数据库已存在**：如果数据库已存在，SQL 执行会显示警告，这是正常的
5. **路径一致性**：所有路径都使用项目根目录，不要移动项目目录
6. **日志目录**：脚本会自动创建 `logs/` 目录，无需手动创建
7. **错误处理**：
   - 必须步骤失败会中断安装，需要修复错误后重试
   - 可选步骤失败会显示警告但继续安装，可以稍后手动处理
8. **安装顺序**：脚本按固定顺序执行，确保依赖关系正确

## 卸载

如果需要卸载系统：

```bash
# 停止服务
systemctl stop openresty
systemctl disable openresty

# 删除配置文件（系统目录）
rm -f /usr/local/openresty/nginx/conf/nginx.conf

# 注意：init_file 目录中的文件不会被删除

# 删除项目目录（可选）
# rm -rf /path/to/project
```

**注意**：卸载不会删除 OpenResty 本身，只会删除项目配置文件。

---

**总结**：`install.sh` 提供了一键安装和配置的完整解决方案，简化了部署流程，确保所有步骤按正确顺序执行。

