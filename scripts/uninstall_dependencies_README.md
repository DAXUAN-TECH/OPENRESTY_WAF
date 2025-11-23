# 依赖卸载脚本说明

## 脚本功能

`uninstall_dependencies.sh` 用于卸载已安装的第三方 Lua 模块依赖。

## 使用方法

### 基本使用

```bash
# 卸载依赖（交互式）
sudo ./scripts/uninstall_dependencies.sh
```

### 功能特性

- ✅ 检查所有已安装的依赖模块
- ✅ 交互式卸载（可选模块会询问）
- ✅ 必需模块卸载前会警告
- ✅ 提供详细的卸载统计信息
- ✅ 验证卸载结果

## 卸载流程

### 1. 检查 OpenResty

脚本首先检查 OpenResty 是否已安装：
- 如果未安装，直接退出（无需卸载依赖）
- 如果已安装，继续卸载流程

### 2. 检查已安装的模块

脚本会检查以下模块的安装状态：

**必需模块**：
- `resty.mysql` - MySQL 客户端

**可选模块**：
- `resty.redis` - Redis 客户端
- `resty.maxminddb` - GeoIP2 数据库查询
- `resty.http` - HTTP 客户端
- `resty.file` - 文件操作
- `resty.msgpack` - MessagePack 序列化

### 3. 交互式卸载

对于每个已安装的模块：
- **必需模块**：会显示警告，需要确认才能卸载
- **可选模块**：会询问是否卸载（默认 Y）

### 4. 验证卸载结果

脚本会验证所有模块是否已成功卸载，并显示结果。

## 注意事项

### ⚠️ 重要警告

1. **必需模块卸载**：
   - `resty.mysql` 是必需模块，卸载后系统将无法连接数据库
   - 卸载前会显示警告，需要明确确认

2. **功能影响**：
   - 卸载 `resty.redis` 后，Redis 二级缓存功能将无法使用
   - 卸载 `resty.maxminddb` 后，地域封控功能将无法使用
   - 卸载 `resty.http` 后，告警 Webhook 功能将无法使用
   - 卸载 `resty.file` 后，日志队列本地备份功能将无法使用
   - 卸载 `resty.msgpack` 后，将回退到 JSON 序列化

3. **服务重启**：
   - 卸载模块后，需要重启 OpenResty 服务使更改生效

## 卸载示例

### 示例 1：卸载可选模块

```bash
$ sudo ./scripts/uninstall_dependencies.sh

========================================
依赖卸载工具
========================================

✓ OpenResty 已安装

[1/2] 检查已安装的依赖模块...

已安装的模块:
检查 resty.redis... 已安装
  说明: Redis 客户端，用于二级缓存
  是否卸载？[Y/n]: Y
  卸载中... ✓ 卸载成功

检查 resty.maxminddb... 未安装

...

========================================
卸载完成
========================================

统计信息:
  总计: 6
  已卸载: 1
  跳过: 5

下一步:
  1. 如果卸载了必需模块，需要重新安装: sudo ./scripts/install_dependencies.sh
  2. 重启 OpenResty 服务使更改生效
```

### 示例 2：卸载必需模块（会警告）

```bash
$ sudo ./scripts/uninstall_dependencies.sh

检查 resty.mysql... 已安装
  警告: 这是必需模块，卸载后系统将无法正常工作！
  说明: MySQL 客户端，用于数据库连接
  确认要卸载？[y/N]: y
  卸载中... ✓ 卸载成功
```

## 手动卸载

如果需要手动卸载特定模块：

```bash
# 删除模块文件
rm -rf /usr/local/openresty/site/lualib/resty/mysql.lua
rm -rf /usr/local/openresty/site/lualib/resty/redis.lua
rm -rf /usr/local/openresty/site/lualib/resty/maxminddb.lua
rm -rf /usr/local/openresty/site/lualib/resty/http.lua
rm -rf /usr/local/openresty/site/lualib/resty/file.lua
rm -rf /usr/local/openresty/site/lualib/resty/msgpack.lua

# 或删除整个目录（如果模块是目录结构）
rm -rf /usr/local/openresty/site/lualib/resty/mysql
rm -rf /usr/local/openresty/site/lualib/resty/redis
```

## 重新安装

卸载后如果需要重新安装：

```bash
# 自动安装所有依赖
sudo ./scripts/install_dependencies.sh

# 或检查并交互式安装
sudo ./scripts/check_dependencies.sh
```

## 故障排查

### 问题 1：卸载失败

**错误信息**：
```
✗ 卸载失败
```

**可能原因**：
- 文件权限不足
- 文件被其他进程占用
- 路径不正确

**解决方法**：
```bash
# 检查文件权限
ls -la /usr/local/openresty/site/lualib/resty/

# 使用 root 权限
sudo ./scripts/uninstall_dependencies.sh

# 手动删除
sudo rm -rf /usr/local/openresty/site/lualib/resty/<module_name>
```

### 问题 2：模块仍存在

**可能原因**：
- 模块文件在多个位置
- 卸载脚本未完全删除

**解决方法**：
```bash
# 检查所有可能的路径
find /usr/local/openresty -name "*mysql*" -type f
find /usr/local/openresty -name "*redis*" -type f

# 手动删除
sudo rm -rf <found_path>
```

## 相关脚本

- `check_dependencies.sh` - 检查依赖状态
- `install_dependencies.sh` - 安装依赖
- `dependencies_README.md` - 依赖管理说明

## 最佳实践

1. **卸载前备份**：
   - 如果需要保留配置，建议先备份相关配置文件

2. **测试环境**：
   - 建议在测试环境先验证卸载流程

3. **逐步卸载**：
   - 不要一次性卸载所有模块
   - 先卸载可选模块，确认系统正常后再考虑卸载必需模块

4. **重新安装**：
   - 卸载后如需恢复功能，使用 `install_dependencies.sh` 重新安装

