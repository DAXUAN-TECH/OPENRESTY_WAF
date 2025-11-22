# 安装脚本使用说明

## `install_geoip.sh` - GeoIP2 数据库安装脚本

**功能全面的安装脚本，支持所有下载方式**

- ✅ 支持 Account ID + License Key（推荐）
- ✅ 支持 Permalink URL
- ✅ 自动处理 Basic Authentication
- ✅ 自动跟随重定向
- ✅ 完整的错误处理和提示

**使用方法：**

```bash
# 方式 1：提供 Account ID 和 License Key（推荐）
sudo ./scripts/install_geoip.sh ACCOUNT_ID LICENSE_KEY

# 方式 2：交互式输入
sudo ./scripts/install_geoip.sh
# 会提示输入 Account ID 和 License Key

# 方式 3：使用 Permalink URL（仍需要认证）
sudo ./scripts/install_geoip.sh 'https://download.maxmind.com/geoip/databases/GeoLite2-City/download?suffix=tar.gz'
```

## 推荐使用方式

### 最佳实践：使用 `install_geoip.sh` + Account ID + License Key

```bash
# 1. 获取 Account ID 和 License Key
#    访问：https://www.maxmind.com/en/accounts/current

# 2. 运行安装脚本
sudo ./scripts/install_geoip.sh YOUR_ACCOUNT_ID YOUR_LICENSE_KEY

# 3. 等待安装完成
```

## 获取凭证

### Account ID

1. 登录 [MaxMind 账号页面](https://www.maxmind.com/en/accounts/current)
2. 在账号信息中可以找到 Account ID

### License Key

1. 访问 [License Keys 页面](https://www.maxmind.com/en/accounts/current/license-key)
2. 查看现有的 License Key 或创建新的

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
4. 参考 `scripts/README.md` 中的故障排查部分

## 总结

- ✅ **使用 `install_geoip.sh`** - 功能全面，支持所有下载方式
- ✅ **推荐使用 Account ID + License Key** - 最可靠的方式

