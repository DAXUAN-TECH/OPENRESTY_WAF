# GeoIP2 数据库安装脚本使用说明

## 脚本说明

**install_geoip.sh** - GeoIP2 数据库安装脚本

根据 [MaxMind 最新文档](https://dev.maxmind.com/geoip/updating-databases/)，MaxMind 在 2024 年 1 月开始使用新的下载方式，需要使用 **Account ID** 和 **License Key** 进行 Basic Authentication。

### 功能特性

- ✅ 支持 Account ID + License Key（推荐）
- ✅ 支持 Permalink URL
- ✅ 自动处理 Basic Authentication
- ✅ 自动跟随重定向
- ✅ 自动下载 GeoLite2-City 数据库
- ✅ 自动解压并安装到正确位置
- ✅ 自动备份旧文件
- ✅ 自动设置文件权限
- ✅ 验证安装结果
- ✅ 完整的错误处理和提示

## 使用方法

### 方式 1：使用 Account ID 和 License Key（推荐）

```bash
sudo ./scripts/install_geoip.sh ACCOUNT_ID LICENSE_KEY
```

### 方式 2：交互式输入 Account ID 和 License Key

```bash
sudo ./scripts/install_geoip.sh
# 脚本会提示输入 Account ID 和 License Key
```

### 方式 3：使用 Permalink URL

```bash
sudo ./scripts/install_geoip.sh 'https://download.maxmind.com/geoip/databases/GeoLite2-City/download?suffix=tar.gz'
```

**注意**：Permalink URL 仍然需要 Account ID 和 License Key 进行认证，所以推荐使用方式 1 或 2。

## 推荐使用方式

### 最佳实践：使用 Account ID + License Key

```bash
# 1. 获取 Account ID 和 License Key
#    访问：https://www.maxmind.com/en/accounts/current

# 2. 运行安装脚本
sudo ./scripts/install_geoip.sh YOUR_ACCOUNT_ID YOUR_LICENSE_KEY

# 3. 等待安装完成
```

## 安装位置

数据库文件将安装到：
```
/usr/local/openresty/nginx/lua/geoip/GeoLite2-City.mmdb
```

## 获取 Account ID 和 License Key

### Account ID

1. 登录 [MaxMind 账号页面](https://www.maxmind.com/en/accounts/current)
2. 在账号信息中可以找到 Account ID

### License Key

1. 访问 [License Keys 页面](https://www.maxmind.com/en/accounts/current/license-key)
2. 查看现有的 License Key 或创建新的

## 重要变化（2024年1月）

根据 [MaxMind 最新文档](https://dev.maxmind.com/geoip/updating-databases/)：

1. **不再支持旧的 URL 参数方式**：`?edition_id=GeoLite2-City&license_key=XXX`
2. **需要使用 Basic Authentication**：使用 `Account ID:License Key` 进行认证
3. **支持重定向**：MaxMind 使用 R2 presigned URLs，会重定向到 Cloudflare R2 存储
4. **重定向目标**：`mm-prod-geoip-databases.a2649acb697e2c09b632799562c076f2.r2.cloudflarestorage.com`

## 使用 Permalink URL（备选方案）

如果从 MaxMind 账号页面获取了 permalink URL：

1. 登录 MaxMind 账号
2. 进入 "Download Databases" 页面
3. 找到 GeoLite2-City 数据库
4. 点击 "Get Permalink(s)" 按钮
5. 复制 permalink URL
6. 使用脚本下载（仍需要 Account ID 和 License Key 认证）

## 注意事项

1. **需要 root 权限**：因为需要安装文件到系统目录
2. **需要有效的 License Key**：从 MaxMind 账号获取
3. **需要网络连接**：用于下载数据库文件
4. **文件大小**：数据库文件约 30-50MB
5. **必须使用 GeoLite2-City.mmdb**：Country 版本不包含省市信息，无法支持国内省市封控

## 常见问题

### Q: Permalink URL 还需要认证吗？

**A:** 是的，根据 MaxMind 最新文档，即使使用 Permalink URL，仍然需要使用 Account ID 和 License Key 进行 Basic Authentication。所以推荐使用方式 1 或 2（直接提供 Account ID 和 License Key）。

### Q: 脚本支持哪些下载方式？

**A:** `install_geoip.sh` 支持：
- Account ID + License Key（推荐，最可靠）
- Permalink URL（仍需要认证）
- 交互式输入（方便使用）

### Q: 如果下载失败怎么办？

**A:** 
1. 检查 Account ID 和 License Key 是否正确
2. 检查网络连接
3. 查看脚本的错误提示信息
4. 参考下面的故障排查部分

### Q: 为什么必须使用 City 版本而不是 Country 版本？

**A:** 因为地域封控功能需要支持国内（省市级别）和国外（国家级别）封控，Country 版本不包含省市信息，无法支持国内省市封控。

## 故障排查

### 问题 1：License Key 无效

**错误信息**：`Invalid license key` 或 `认证失败`

**解决方法**：
- 检查 Account ID 和 License Key 是否正确
- 确认 License Key 是否已激活
- 尝试从 MaxMind 账号页面重新生成
- 检查 License Key 是否已过期

### 问题 2：下载失败

**错误信息**：`下载失败` 或网络错误

**解决方法**：
- 检查网络连接
- 检查防火墙设置
- 确保可以访问 MaxMind 服务器
- 检查重定向目标是否可访问：`mm-prod-geoip-databases.a2649acb697e2c09b632799562c076f2.r2.cloudflarestorage.com`
- 尝试手动下载

### 问题 3：权限不足

**错误信息**：`需要 root 权限`

**解决方法**：
- 使用 `sudo` 运行脚本
- 确保有写入目标目录的权限
- 检查目标目录是否存在

### 问题 4：文件大小异常

**错误信息**：`下载的文件太小`

**解决方法**：
- 检查下载是否完整
- 重新运行脚本
- 检查磁盘空间是否充足

## 手动安装（备选方案）

如果脚本无法使用，可以手动安装：

### 1. 下载数据库（使用 Account ID 和 License Key）

```bash
# 使用 Basic Authentication
curl -L -u ACCOUNT_ID:LICENSE_KEY \
  "https://download.maxmind.com/geoip/databases/GeoLite2-City/download?suffix=tar.gz" \
  -o /tmp/GeoLite2-City.tar.gz
```

或者使用 permalink URL：

```bash
# 从账号页面获取 permalink URL 后使用
curl -L -u ACCOUNT_ID:LICENSE_KEY \
  "YOUR_PERMALINK_URL" \
  -o /tmp/GeoLite2-City.tar.gz
```

### 2. 解压

```bash
tar -xzf /tmp/GeoLite2-City.tar.gz -C /tmp/
```

### 3. 复制文件

```bash
sudo mkdir -p /usr/local/openresty/nginx/lua/geoip
sudo cp /tmp/GeoLite2-City_*/GeoLite2-City.mmdb /usr/local/openresty/nginx/lua/geoip/
```

### 4. 设置权限

```bash
sudo chown nobody:nobody /usr/local/openresty/nginx/lua/geoip/GeoLite2-City.mmdb
sudo chmod 644 /usr/local/openresty/nginx/lua/geoip/GeoLite2-City.mmdb
```

## 使用示例

```bash
# 示例 1：使用 Account ID 和 License Key
sudo ./scripts/install_geoip.sh 123456 YOUR_LICENSE_KEY

# 示例 2：交互式输入
sudo ./scripts/install_geoip.sh
# 会提示输入 Account ID 和 License Key

# 示例 3：使用 Permalink URL（仍需要认证）
sudo ./scripts/install_geoip.sh 'https://download.maxmind.com/geoip/databases/GeoLite2-City/download?suffix=tar.gz'
```

## 验证安装

安装完成后，验证安装：

```bash
# 检查文件是否存在
ls -lh /usr/local/openresty/nginx/lua/geoip/GeoLite2-City.mmdb

# 检查文件大小（应该约 30-50MB）
du -h /usr/local/openresty/nginx/lua/geoip/GeoLite2-City.mmdb

# 检查文件权限
ls -l /usr/local/openresty/nginx/lua/geoip/GeoLite2-City.mmdb
```

## 后续配置

安装完成后，需要在 `lua/config.lua` 中启用地域封控：

```lua
_M.geo = {
    enable = true,  -- 启用地域封控
    geoip_db_path = "/usr/local/openresty/nginx/lua/geoip/GeoLite2-City.mmdb",
}
```

然后重启 OpenResty 服务：

```bash
sudo systemctl restart openresty
```

## 参考文档

- [MaxMind 数据库更新文档](https://dev.maxmind.com/geoip/updating-databases/)
- [MaxMind 账号页面](https://www.maxmind.com/en/accounts/current)
- [License Key 页面](https://www.maxmind.com/en/accounts/current/license-key)
- [地域封控使用示例](../08-地域封控使用示例.md)

## 总结

- ✅ **使用 `install_geoip.sh`** - 功能全面，支持所有下载方式
- ✅ **推荐使用 Account ID + License Key** - 最可靠的方式
- ✅ **必须使用 GeoLite2-City.mmdb** - 支持省市级别封控
- ✅ **定期更新数据库** - 建议每月更新一次
