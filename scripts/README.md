# 安装脚本说明

## GeoLite2-City 数据库安装脚本

根据 [MaxMind 最新文档](https://dev.maxmind.com/geoip/updating-databases/)，MaxMind 在 2024 年 1 月开始使用新的下载方式，需要使用 **Account ID** 和 **License Key** 进行 Basic Authentication。

### 脚本说明

**install_geoip.sh** - GeoIP2 数据库安装脚本

支持多种下载方式：
- Account ID + License Key（推荐）
- Permalink URL
- 交互式输入

### 使用方法

#### 方式 1：使用 Account ID 和 License Key（推荐）

```bash
sudo ./scripts/install_geoip.sh ACCOUNT_ID LICENSE_KEY
```

#### 方式 2：交互式输入 Account ID 和 License Key

```bash
sudo ./scripts/install_geoip.sh
# 脚本会提示输入 Account ID 和 License Key
```

#### 方式 3：使用 Permalink URL

```bash
sudo ./scripts/install_geoip.sh 'https://download.maxmind.com/geoip/databases/GeoLite2-City/download?suffix=tar.gz'
```

**注意**：Permalink URL 仍然需要 Account ID 和 License Key 进行认证，所以推荐使用方式 1 或 2。

### 功能特性

- ✅ 自动下载 GeoLite2-City 数据库
- ✅ 自动解压并安装到正确位置
- ✅ 自动备份旧文件
- ✅ 自动设置文件权限
- ✅ 验证安装结果
- ✅ 错误处理和提示

### 安装位置

数据库文件将安装到：
```
/usr/local/openresty/nginx/lua/geoip/GeoLite2-City.mmdb
```

### 示例

```bash
# 使用 Account ID 和 License Key
sudo ./scripts/install_geoip.sh YOUR_ACCOUNT_ID YOUR_LICENSE_KEY

# 交互式输入
sudo ./scripts/install_geoip.sh
```

### 注意事项

1. **需要 root 权限**：因为需要安装文件到系统目录
2. **需要有效的 License Key**：从 MaxMind 账号获取
3. **需要网络连接**：用于下载数据库文件
4. **文件大小**：数据库文件约 30-50MB

### 获取 Account ID 和 License Key

1. 访问 [MaxMind 账号页面](https://www.maxmind.com/en/accounts/current)
2. 登录账号
3. 在账号页面可以找到：
   - **Account ID**：在账号信息中
   - **License Key**：在 "License Keys" 页面（https://www.maxmind.com/en/accounts/current/license-key）

### 重要变化（2024年1月）

根据 [MaxMind 最新文档](https://dev.maxmind.com/geoip/updating-databases/)：

1. **不再支持旧的 URL 参数方式**：`?edition_id=GeoLite2-City&license_key=XXX`
2. **需要使用 Basic Authentication**：使用 `Account ID:License Key` 进行认证
3. **支持重定向**：MaxMind 使用 R2 presigned URLs，会重定向到 Cloudflare R2 存储
4. **重定向目标**：`mm-prod-geoip-databases.a2649acb697e2c09b632799562c076f2.r2.cloudflarestorage.com`

### 使用 Permalink URL（备选方案）

如果从 MaxMind 账号页面获取了 permalink URL：

1. 登录 MaxMind 账号
2. 进入 "Download Databases" 页面
3. 找到 GeoLite2-City 数据库
4. 点击 "Get Permalink(s)" 按钮
5. 复制 permalink URL
6. 使用脚本下载（仍需要 Account ID 和 License Key 认证）

### 故障排查

#### 问题 1：License Key 无效

**错误信息**：`Invalid license key`

**解决方法**：
- 检查 License Key 是否正确
- 确认 License Key 是否已激活
- 尝试从 MaxMind 账号页面重新生成

#### 问题 2：下载失败

**错误信息**：`下载失败`

**解决方法**：
- 检查网络连接
- 检查防火墙设置
- 尝试手动下载

#### 问题 3：权限不足

**错误信息**：`需要 root 权限`

**解决方法**：
- 使用 `sudo` 运行脚本
- 确保有写入目标目录的权限

### 手动安装（备选方案）

如果脚本无法使用，可以手动安装：

1. **下载数据库**（使用 Account ID 和 License Key）

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

2. **解压**
   ```bash
   tar -xzf /tmp/GeoLite2-City.tar.gz -C /tmp/
   ```

3. **复制文件**
   ```bash
   sudo mkdir -p /usr/local/openresty/nginx/lua/geoip
   sudo cp /tmp/GeoLite2-City_*/GeoLite2-City.mmdb /usr/local/openresty/nginx/lua/geoip/
   ```

4. **设置权限**
   ```bash
   sudo chown nobody:nobody /usr/local/openresty/nginx/lua/geoip/GeoLite2-City.mmdb
   sudo chmod 644 /usr/local/openresty/nginx/lua/geoip/GeoLite2-City.mmdb
   ```

### 参考文档

- [MaxMind 数据库更新文档](https://dev.maxmind.com/geoip/updating-databases/)
- [MaxMind 账号页面](https://www.maxmind.com/en/accounts/current)
- [License Key 页面](https://www.maxmind.com/en/accounts/current/license-key)

