# Lua 数据库连接配置脚本使用说明

## 脚本说明

**set_lua_database_connect.sh** - 设置 Lua 数据库连接配置脚本

用于更新 `lua/config.lua` 配置文件中的 MySQL 和 Redis 连接参数，支持交互式配置和命令行参数。

### 功能特性

- ✅ 更新 MySQL 连接配置（host、port、database、user、password）
- ✅ 更新 Redis 连接配置（host、port、db、password）
- ✅ 自动备份原配置文件
- ✅ 配置文件语法验证
- ✅ 支持特殊字符密码（使用 Python3）
- ✅ 备用 sed 方案（无 Python3 时）

## 前置条件

1. **配置文件存在**
   - `lua/config.lua` 文件必须存在
   - 配置文件应包含 MySQL 和 Redis 配置块

2. **可选依赖**
   - Python3（推荐）：支持特殊字符密码
   - LuaJIT 或 luac：用于语法验证

## 使用方法

### 方式 1：通过 start.sh 调用（推荐）

```bash
# 交互式更新配置
sudo ./start.sh update-config
```

脚本会提示选择：
- 更新 MySQL 配置
- 更新 Redis 配置
- 验证配置文件语法

### 方式 2：直接调用脚本

#### 更新 MySQL 配置

```bash
./scripts/set_lua_database_connect.sh mysql <host> <port> <database> <user> <password>
```

**示例：**
```bash
# 更新 MySQL 配置
./scripts/set_lua_database_connect.sh mysql 127.0.0.1 3306 waf_db waf_user mypassword

# 使用远程 MySQL
./scripts/set_lua_database_connect.sh mysql 192.168.1.100 3306 waf_db waf_user secure_password
```

#### 更新 Redis 配置

```bash
./scripts/set_lua_database_connect.sh redis <host> <port> <db> <password>
```

**示例：**
```bash
# 更新 Redis 配置（无密码）
./scripts/set_lua_database_connect.sh redis 127.0.0.1 6379 0 ""

# 更新 Redis 配置（有密码）
./scripts/set_lua_database_connect.sh redis 127.0.0.1 6379 0 redis_password

# 使用远程 Redis
./scripts/set_lua_database_connect.sh redis 192.168.1.100 6379 1 my_redis_password
```

#### 验证配置文件语法

```bash
./scripts/set_lua_database_connect.sh verify
```

## 配置更新说明

### MySQL 配置更新

脚本会更新 `config.lua` 中的以下配置项：

```lua
_M.mysql = {
    host = "127.0.0.1",      -- 更新为指定 host
    port = 3306,              -- 更新为指定 port
    database = "waf_db",      -- 更新为指定 database
    user = "waf_user",        -- 更新为指定 user
    password = "waf_password"  -- 更新为指定 password
}
```

### Redis 配置更新

脚本会更新 `config.lua` 中的以下配置项：

```lua
_M.redis = {
    host = "127.0.0.1",       -- 更新为指定 host
    port = 6379,              -- 更新为指定 port
    db = 0,                   -- 更新为指定 db
    password = nil             -- 更新为指定 password（如果有）
}
```

## 安全说明

### 密码处理

1. **有 Python3 时**（推荐）
   - 自动转义特殊字符（`\`、`"`）
   - 安全处理包含引号、反斜杠的密码

2. **无 Python3 时**
   - 使用 sed 简单替换
   - 密码包含特殊字符时，会提示手动更新

### 配置文件备份

每次更新配置前，脚本会自动备份原配置文件：

```
lua/config.lua.bak.YYYYMMDD_HHMMSS
```

## 错误处理

### 常见错误

1. **配置文件不存在**
   ```
   错误: 配置文件不存在: /path/to/lua/config.lua
   ```
   **解决方法：** 确保 `lua/config.lua` 文件存在

2. **语法验证失败**
   ```
   ⚠ 警告: 配置文件语法检查失败，请手动检查
   ```
   **解决方法：** 检查配置文件语法，确保 Lua 语法正确

3. **参数不足**
   ```
   用法: set_lua_database_connect.sh mysql <host> <port> <database> <user> <password>
   ```
   **解决方法：** 检查命令参数是否完整

## 使用示例

### 完整配置流程

```bash
# 1. 更新 MySQL 配置
./scripts/set_lua_database_connect.sh mysql 127.0.0.1 3306 waf_db waf_user mypassword

# 2. 更新 Redis 配置
./scripts/set_lua_database_connect.sh redis 127.0.0.1 6379 0 redis_password

# 3. 验证配置语法
./scripts/set_lua_database_connect.sh verify

# 4. 重新加载 OpenResty（如果正在运行）
systemctl reload openresty
```

### 通过 start.sh 使用

```bash
# 交互式更新配置
sudo ./start.sh update-config

# 选择 1：更新 MySQL
# 输入 MySQL 连接信息

# 选择 2：更新 Redis
# 输入 Redis 连接信息

# 选择 3：验证配置
# 检查配置文件语法
```

## 注意事项

1. **配置文件格式**
   - 确保 `config.lua` 使用 UTF-8 编码
   - 配置块格式必须正确（`_M.mysql = {...}` 和 `_M.redis = {...}`）

2. **密码安全**
   - 密码包含特殊字符时，建议使用 Python3
   - 避免在命令行历史中暴露密码（使用交互式模式）

3. **服务重启**
   - 更新配置后，需要重新加载 OpenResty 才能生效
   - 使用 `systemctl reload openresty` 或 `openresty -s reload`

4. **备份文件**
   - 备份文件会保留在 `lua/` 目录下
   - 定期清理旧的备份文件

## 相关文件

- `lua/config.lua` - 主配置文件
- `start.sh` - 主启动脚本（可调用此脚本）
- `scripts/deploy.sh` - 部署脚本（会部署 config.lua）

## 故障排查

### 配置未生效

1. 检查配置文件语法：`./scripts/set_lua_database_connect.sh verify`
2. 检查 OpenResty 错误日志：`tail -f logs/error.log`
3. 测试配置文件：`/usr/local/openresty/bin/openresty -t`

### 密码更新失败

1. 检查是否有 Python3：`command -v python3`
2. 手动编辑配置文件（如果密码包含特殊字符）
3. 使用交互式模式（通过 start.sh）

## 版本历史

- v1.0 - 初始版本，支持 MySQL 和 Redis 配置更新

