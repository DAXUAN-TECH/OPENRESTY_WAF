# HTTPS反向代理访问问题排查指南

## 问题现象

- **HTTPS访问**：显示OpenResty默认页面
- **HTTP访问**：显示WAF系统登录页面

## 问题分析

这是典型的Nginx `server_name`匹配问题。可能的原因：

1. **server_name未设置或为空**：业务代理配置中`server_name`字段为空，导致无法匹配
2. **server_name不匹配**：访问的域名与配置的`server_name`不一致
3. **配置文件未生成**：业务代理的配置文件未正确生成
4. **include顺序问题**：虽然include顺序正确，但配置文件可能未被加载
5. **SSL配置问题**：HTTPS的443端口监听配置有问题
6. **default_server优先级**：WAF管理界面的`default_server`捕获了所有请求

## 排查步骤

### 步骤1：检查数据库中的代理配置

```sql
-- 查看所有HTTP/HTTPS代理配置
SELECT 
    id, 
    proxy_name, 
    proxy_type, 
    listen_port, 
    listen_address,
    server_name,
    ssl_enable,
    force_https_redirect,
    status
FROM waf_proxy_configs 
WHERE proxy_type = 'http' 
ORDER BY id DESC;
```

**重点关注**：
- `server_name`字段是否有值？
- `ssl_enable`是否为1（启用SSL）？
- `status`是否为1（启用状态）？

### 步骤2：检查生成的配置文件

```bash
# 查看HTTP/HTTPS代理配置文件
ls -la /data/OPENRESTY_WAF/conf.d/vhost_conf/http_https/

# 查看最新的代理配置文件内容
cat /data/OPENRESTY_WAF/conf.d/vhost_conf/http_https/proxy_http_*.conf | tail -50
```

**重点关注**：
- 配置文件是否存在？
- `server_name`是否正确？
- `listen 443 ssl;`是否存在？
- SSL证书路径是否正确？

### 步骤3：检查SSL证书文件

```bash
# 查看SSL证书文件
ls -la /data/OPENRESTY_WAF/conf.d/cert/proxy_*.pem
ls -la /data/OPENRESTY_WAF/conf.d/cert/proxy_*.key

# 检查证书文件内容（前几行）
head -5 /data/OPENRESTY_WAF/conf.d/cert/proxy_*.pem
```

**重点关注**：
- 证书文件是否存在？
- 证书文件内容是否正确（应该以`-----BEGIN CERTIFICATE-----`开头）？

### 步骤4：检查Nginx配置语法

```bash
# 测试Nginx配置语法
sudo /usr/local/openresty/bin/openresty -t

# 查看详细的配置测试输出
sudo /usr/local/openresty/bin/openresty -T 2>&1 | grep -A 10 "server_name"
```

**重点关注**：
- 配置语法是否正确？
- 是否有SSL证书路径错误？

### 步骤5：检查Nginx server块匹配

```bash
# 查看所有监听的server块
sudo /usr/local/openresty/bin/openresty -T 2>&1 | grep -E "listen|server_name" | grep -A 1 "listen"
```

**重点关注**：
- 业务代理的`server_name`是否正确显示？
- 是否有多个`default_server`？

### 步骤6：检查访问日志

```bash
# 查看访问日志（实时）
tail -f /data/OPENRESTY_WAF/logs/access.log | grep -E "your-domain.com|your-ip"

# 查看错误日志
tail -f /data/OPENRESTY_WAF/logs/error.log | grep -E "SSL|server_name|proxy"
```

**重点关注**：
- 请求是否到达了业务代理？
- 是否有SSL相关错误？

### 步骤7：使用curl测试

```bash
# 测试HTTP访问（指定Host头）
curl -v -H "Host: your-domain.com" http://your-server-ip/

# 测试HTTPS访问（跳过证书验证）
curl -v -k -H "Host: your-domain.com" https://your-server-ip/
```

**重点关注**：
- HTTP请求是否被正确路由？
- HTTPS请求是否被正确路由？
- 响应头中的`Server`字段是什么？

## 常见问题及解决方案

### 问题1：server_name为空

**现象**：生成的配置文件中没有`server_name`行

**原因**：数据库中的`server_name`字段为空或NULL

**解决方案**：
1. 检查数据库中的`server_name`字段
2. 如果为空，需要在创建/编辑代理时填写`server_name`
3. 重新生成配置文件并reload

### 问题2：server_name不匹配

**现象**：访问的域名与配置的`server_name`不一致

**原因**：用户访问的域名与数据库中配置的`server_name`不匹配

**解决方案**：
1. 确认访问的域名与数据库中的`server_name`一致
2. 如果使用IP访问，需要配置`server_name _;`（匹配所有域名）
3. 或者使用正确的域名访问

### 问题3：配置文件未生成

**现象**：`conf.d/vhost_conf/http_https/`目录下没有对应的配置文件

**原因**：
- 代理状态为禁用（`status = 0`）
- 配置文件生成失败（权限问题、数据库连接问题等）

**解决方案**：
1. 检查代理状态：`SELECT id, proxy_name, status FROM waf_proxy_configs WHERE id = ?;`
2. 检查错误日志：`tail -f /data/OPENRESTY_WAF/logs/error.log | grep "generate"`
3. 手动触发配置生成（通过编辑代理并保存）

### 问题4：SSL证书文件不存在或内容错误

**现象**：HTTPS访问失败，错误日志显示SSL证书相关错误

**原因**：
- SSL证书文件未生成
- SSL证书文件内容为空或格式错误

**解决方案**：
1. 检查证书文件是否存在：`ls -la /data/OPENRESTY_WAF/conf.d/cert/proxy_*.pem`
2. 检查证书文件内容：`head -5 /data/OPENRESTY_WAF/conf.d/cert/proxy_*.pem`
3. 检查数据库中的SSL证书内容：`SELECT id, proxy_name, ssl_enable, LENGTH(ssl_pem) as pem_len, LENGTH(ssl_key) as key_len FROM waf_proxy_configs WHERE id = ?;`
4. 如果证书内容为空，需要重新填写SSL证书并保存

### 问题5：default_server优先级问题

**现象**：所有请求都被WAF管理界面捕获

**原因**：
- 业务代理的`server_name`未正确匹配
- WAF管理界面的`default_server`优先级过高

**解决方案**：
1. 确认业务代理的`server_name`已正确配置
2. 确认业务代理配置文件在`waf.conf`之前被include（已在`nginx.conf`中正确配置）
3. 使用`openresty -T`检查server块匹配顺序

## 快速诊断命令

```bash
# 一键诊断脚本
#!/bin/bash
PROXY_ID=1  # 替换为实际的代理ID

echo "=== 1. 检查数据库配置 ==="
mysql -u waf_user -p'waf_password' waf_db -e "
SELECT id, proxy_name, server_name, ssl_enable, status 
FROM waf_proxy_configs 
WHERE id = $PROXY_ID;
"

echo -e "\n=== 2. 检查生成的配置文件 ==="
ls -la /data/OPENRESTY_WAF/conf.d/vhost_conf/http_https/proxy_http_*.conf

echo -e "\n=== 3. 检查SSL证书文件 ==="
ls -la /data/OPENRESTY_WAF/conf.d/cert/proxy_*.pem
ls -la /data/OPENRESTY_WAF/conf.d/cert/proxy_*.key

echo -e "\n=== 4. 检查Nginx配置语法 ==="
sudo /usr/local/openresty/bin/openresty -t

echo -e "\n=== 5. 查看server块配置 ==="
sudo /usr/local/openresty/bin/openresty -T 2>&1 | grep -A 5 "server_name"
```

## 下一步操作

根据排查结果，按照以下顺序处理：

1. **如果server_name为空**：编辑代理配置，填写正确的`server_name`
2. **如果配置文件未生成**：检查代理状态，确保`status = 1`，然后编辑并保存代理配置
3. **如果SSL证书文件不存在**：检查数据库中的SSL证书内容，确保已正确填写
4. **如果配置语法错误**：根据错误信息修复配置
5. **如果server_name不匹配**：确认访问的域名与配置的`server_name`一致

修改后，系统会自动：
1. 重新生成配置文件
2. 测试配置语法
3. 执行reload（如果测试通过）

