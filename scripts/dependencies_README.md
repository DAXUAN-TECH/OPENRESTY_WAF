# 依赖管理说明

本文档说明项目的第三方依赖管理和自动安装方法。

## 📋 依赖列表

### 必需依赖

| 模块 | OPM 包名 | 说明 | 用途 |
|------|---------|------|------|
| `resty.mysql` | `openresty/lua-resty-mysql` | MySQL 客户端 | 数据库连接，所有数据库操作 |

### 可选依赖

| 模块 | OPM 包名 | 说明 | 用途 |
|------|---------|------|------|
| `resty.redis` | `openresty/lua-resty-redis` | Redis 客户端 | Redis 二级缓存（已启用） |
| `resty.maxminddb` | `anjia0532/lua-resty-maxminddb` | GeoIP2 数据库查询 | 地域封控功能 |
| `resty.http` | `ledgetech/lua-resty-http` | HTTP 客户端 | 告警 Webhook 功能 |
| `resty.msgpack` | `chronolaw/lua-resty-msgpack` | MessagePack 序列化 | 高性能序列化（可选） |

**注意**：`resty.file` 模块在 OPM 中不存在。代码使用标准 Lua `io` 库进行文件操作，无需安装额外模块。

### 内置模块（OpenResty 自带）

- `cjson` - JSON 处理
- `bit` - 位运算（LuaJIT）

## 🛠️ 依赖管理工具

项目提供了两个依赖管理脚本：

### 1. 依赖检查脚本 (`check_dependencies.sh`)

**功能**：检查所有依赖的安装状态，交互式安装缺失的依赖

**使用方法**：
```bash
# 检查依赖（交互式）
sudo ./scripts/check_dependencies.sh
```

**特点**：
- ✅ 检查所有依赖的安装状态
- ✅ 显示详细的依赖信息
- ✅ 交互式安装（可选依赖会询问）
- ✅ 提供安装建议和统计信息

### 2. 依赖自动安装脚本 (`install_dependencies.sh`)

**功能**：自动安装所有缺失的依赖（不询问，直接安装）

**使用方法**：
```bash
# 自动安装所有依赖
sudo ./scripts/install_dependencies.sh
```

**特点**：
- ✅ 自动安装所有缺失的依赖
- ✅ 不询问，直接安装
- ✅ 适合自动化部署场景
- ✅ 优先安装必需依赖

## 📦 依赖安装方式

### 方式一：使用依赖管理脚本（推荐）

```bash
# 检查并交互式安装
sudo ./scripts/check_dependencies.sh

# 或自动安装所有依赖
sudo ./scripts/install_dependencies.sh
```

### 方式二：使用 OPM 手动安装

```bash
# 必需依赖
/usr/local/openresty/bin/opm get openresty/lua-resty-mysql

# 可选依赖
/usr/local/openresty/bin/opm get openresty/lua-resty-redis
/usr/local/openresty/bin/opm get anjia0532/lua-resty-maxminddb
/usr/local/openresty/bin/opm get ledgetech/lua-resty-http
# 注意：lua-resty-file 在 OPM 中不存在，代码使用标准 Lua io 库，无需安装
/usr/local/openresty/bin/opm get chronolaw/lua-resty-msgpack
```

### 方式三：使用 install_openresty.sh（已包含部分依赖）

`install_openresty.sh` 脚本会自动安装以下模块：
- `lua-resty-mysql`（必需）
- `lua-resty-redis`（可选）
- `lua-resty-maxminddb`（可选）

## 🔍 检查依赖状态

### 使用依赖检查脚本

```bash
sudo ./scripts/check_dependencies.sh
```

### 手动检查

```bash
# 检查模块文件是否存在
ls -la /usr/local/openresty/site/lualib/resty/mysql.lua
ls -la /usr/local/openresty/site/lualib/resty/redis.lua
ls -la /usr/local/openresty/site/lualib/resty/maxminddb.lua
```

### 使用 OPM 列出已安装的包

```bash
/usr/local/openresty/bin/opm list
```

## ⚠️ 依赖说明

### Redis 二级缓存（已启用）

**状态**：✅ 已启用（`config.redis_cache.enable = true`）

**依赖**：`resty.redis`

**影响**：如果未安装 `resty.redis`，Redis 二级缓存功能将自动降级到本地缓存，不影响基本功能。

### 地域封控功能

**状态**：可选功能（`config.geo.enable = false`）

**依赖**：`resty.maxminddb` + GeoIP2 数据库文件

**影响**：如果未安装 `resty.maxminddb` 或缺少数据库文件，地域封控功能将无法使用。

### 告警 Webhook 功能

**状态**：可选功能（需要配置 `config.alert.webhook_url`）

**依赖**：`resty.http`

**影响**：如果未安装 `resty.http`，Webhook 告警功能将无法使用。

### 日志队列本地备份

**状态**：可选功能（`config.log.enable_local_backup = true`）

**依赖**：标准 Lua `io` 库（无需安装额外模块）

**说明**：日志队列的本地备份功能使用标准 Lua `io` 库实现，无需安装 `resty.file` 模块（该模块在 OPM 中不存在）。

### MessagePack 序列化

**状态**：可选功能（`config.serializer.use_msgpack = false`）

**依赖**：`resty.msgpack`

**影响**：如果未安装 `resty.msgpack`，将自动回退到 JSON 序列化。

## 🔧 故障排查

### 问题 1：模块安装失败

**错误信息**：
```
✗ 安装失败
```

**可能原因**：
- 网络连接问题
- opm 不可用
- 模块名称错误

**解决方法**：
```bash
# 检查网络连接
ping -c 3 openresty.org

# 检查 opm 是否可用
/usr/local/openresty/bin/opm -h

# 手动安装
/usr/local/openresty/bin/opm get <package-name>
```

### 问题 2：模块已安装但无法使用

**可能原因**：
- 模块路径不正确
- OpenResty 未重启
- Lua 包路径配置错误

**解决方法**：
```bash
# 检查模块文件是否存在
ls -la /usr/local/openresty/site/lualib/resty/

# 重启 OpenResty
sudo systemctl restart openresty

# 检查 Lua 包路径配置
grep lua_package_path /usr/local/openresty/nginx/conf/nginx.conf
```

### 问题 3：必需模块未安装

**影响**：系统无法正常工作

**解决方法**：
```bash
# 立即安装必需模块
sudo ./scripts/install_dependencies.sh

# 或手动安装
/usr/local/openresty/bin/opm get openresty/lua-resty-mysql
```

## 📝 依赖更新

### 更新所有依赖

```bash
# 使用依赖检查脚本（会检查并更新）
sudo ./scripts/check_dependencies.sh
```

### 更新特定依赖

```bash
# 删除旧版本
rm -rf /usr/local/openresty/site/lualib/resty/<module>*

# 重新安装
/usr/local/openresty/bin/opm get <package-name>
```

## 🎯 最佳实践

1. **首次安装**：使用 `install_openresty.sh` 自动安装基础依赖
2. **依赖检查**：使用 `check_dependencies.sh` 检查所有依赖状态
3. **自动部署**：使用 `install_dependencies.sh` 自动安装所有依赖
4. **定期检查**：定期运行依赖检查脚本，确保依赖完整

## 📚 相关文档

- [OpenResty 安装说明](install_openresty_README.md)
- [项目检查脚本](check_all_README.md)
- [部署文档](../../docs/部署文档.md)

