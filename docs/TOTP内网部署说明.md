# TOTP 双因素认证内网部署说明

## 概述

Google Authenticator（TOTP）**完全支持内网部署**。TOTP 算法本身不需要网络连接，只需要服务器和客户端（手机）时间同步即可。

## 工作原理

### 1. TOTP 算法特性

- **无需网络连接**：Google Authenticator 应用在手机上离线生成验证码
- **基于时间**：使用服务器和手机的时间戳计算验证码
- **时间同步**：只需要服务器和手机时间大致同步（通常允许 ±30 秒偏差）

### 2. 内网部署的关键点

#### ✅ 支持的功能

1. **验证码生成**：Google Authenticator 应用离线生成，无需联网
2. **验证码验证**：服务器端验证，无需外网访问
3. **密钥管理**：密钥存储在服务器本地，不依赖外部服务

#### ⚠️ 需要注意的点

1. **QR 码生成**：默认使用外部服务（`api.qrserver.com`），内网无法访问
2. **解决方案**：使用前端 JavaScript QR 码库或手动输入密钥

## 配置说明

### 1. 修改配置文件

编辑 `lua/config.lua`，设置 TOTP 配置：

```lua
-- TOTP 配置
_M.totp = {
    -- QR 码生成方式：local（本地前端生成）或 external（使用外部服务）
    qr_generator = "local",  -- 内网部署必须使用 "local"
    -- 外部 QR 码服务 URL（当 qr_generator 为 "external" 时使用）
    external_qr_url = "https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=",
    -- 是否允许手动输入密钥（当无法扫描 QR 码时）
    allow_manual_entry = true  -- 内网部署建议启用
}
```

### 2. 内网部署配置

```lua
_M.totp = {
    qr_generator = "local",  -- 使用前端生成 QR 码
    allow_manual_entry = true  -- 允许手动输入密钥
}
```

## 使用方式

### 方式一：扫描 QR 码（推荐）

1. **前端生成 QR 码**：
   - 系统会返回 `otpauth_url` 和密钥
   - 前端使用 JavaScript QR 码库（如 `qrcode.js`）生成 QR 码
   - 用户使用 Google Authenticator 扫描

2. **前端集成 QR 码库**：
   ```html
   <!-- 在管理页面引入 qrcode.js -->
   <script src="https://cdn.jsdelivr.net/npm/qrcode@1.5.3/build/qrcode.min.js"></script>
   ```
   
   或者下载到本地：
   ```html
   <script src="/static/js/qrcode.min.js"></script>
   ```

### 方式二：手动输入密钥（内网推荐）

1. **获取密钥**：
   - 调用 `/api/auth/totp/setup` 获取密钥
   - 系统返回 Base32 编码的密钥（如：`JBSWY3DPEHPK3PXP`）

2. **手动添加**：
   - 打开 Google Authenticator 应用
   - 点击"+" → "输入提供的密钥"
   - 输入账户名称（如：WAF Management:admin）
   - 输入密钥
   - 选择"基于时间"
   - 完成添加

3. **验证启用**：
   - 输入 Google Authenticator 显示的 6 位验证码
   - 调用 `/api/auth/totp/enable` 启用

## 时间同步要求

### 服务器时间

确保服务器时间准确：

```bash
# 检查服务器时间
date

# 同步时间（如果使用 NTP）
sudo ntpdate -s time.nist.gov
# 或
sudo chrony sources
```

### 手机时间

- Google Authenticator 使用手机系统时间
- 确保手机时间准确（通常自动同步）
- 允许 ±30 秒的时间偏差

## 测试验证

### 1. 测试 TOTP 生成

```bash
# 使用测试工具验证（可选）
# 安装 oathtool
sudo apt-get install oathtool  # Debian/Ubuntu
sudo yum install oathtool       # CentOS/RHEL

# 测试密钥（Base32）
oathtool --totp -b JBSWY3DPEHPK3PXP
```

### 2. 验证流程

1. 用户登录系统
2. 调用 `/api/auth/totp/setup` 获取密钥
3. 使用 Google Authenticator 添加账户（扫描或手动输入）
4. 输入验证码调用 `/api/auth/totp/enable` 启用
5. 下次登录时，输入用户名密码后，系统要求输入 TOTP 验证码
6. 输入 Google Authenticator 显示的 6 位验证码完成登录

## 常见问题

### Q1: 内网无法访问外部 QR 码服务怎么办？

**A**: 使用前端 JavaScript QR 码库生成，或手动输入密钥。

### Q2: 验证码一直错误？

**A**: 检查服务器和手机时间是否同步，允许 ±30 秒偏差。

### Q3: 可以离线使用吗？

**A**: 可以。Google Authenticator 完全离线工作，只需要时间同步。

### Q4: 多个服务器如何同步？

**A**: TOTP 密钥需要在所有服务器上相同，建议：
- 使用数据库存储密钥（而不是内存）
- 或使用配置中心统一管理

## 安全建议

1. **密钥存储**：生产环境建议将 TOTP 密钥存储到数据库，而不是内存
2. **时间同步**：确保服务器时间准确，使用 NTP 同步
3. **备份密钥**：为用户提供备份密钥，防止手机丢失
4. **强制启用**：可以配置强制所有管理员启用 TOTP

## 总结

✅ **Google Authenticator 完全支持内网部署**

- TOTP 算法本身不需要网络连接
- 只需要服务器和手机时间同步
- QR 码可以通过前端 JavaScript 生成，无需外网
- 也可以手动输入密钥，完全离线操作

内网部署时，只需要：
1. 配置 `qr_generator = "local"`
2. 前端集成 QR 码库（或使用手动输入）
3. 确保服务器时间准确

