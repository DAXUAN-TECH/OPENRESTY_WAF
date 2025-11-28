# SSL 证书目录

此目录用于存放 SSL 证书文件。

## 使用方法

### 放置证书文件

将 SSL 证书文件放在此目录下：

```bash
conf.d/cert/
├── your-domain.crt      # SSL 证书文件
├── your-domain.key      # 私钥文件
└── ca-bundle.crt        # CA 证书链（可选）
```

### 在配置文件中引用

在 `conf.d/vhost_conf/` 中的 server 配置中引用证书：

```nginx
server {
    listen 443 ssl http2;
    server_name your-domain.com;
    
    # SSL 证书配置
    ssl_certificate /data/project/OPENRESTY_WAF/conf.d/cert/your-domain.crt;
    ssl_certificate_key /data/project/OPENRESTY_WAF/conf.d/cert/your-domain.key;
    
    # SSL 优化配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    # 其他配置...
}
```

## 注意事项

1. **安全性**：
   - 私钥文件（.key）权限应设置为 600（仅所有者可读写）
   - 证书文件（.crt）权限应设置为 644
   - 不要将私钥提交到版本控制系统

2. **路径**：
   - 配置文件中的路径应使用绝对路径
   - 或使用 `$project_root` 变量：`$project_root/conf.d/cert/your-domain.crt`

3. **证书更新**：
   - 更新证书后，需要重新加载 Nginx：`openresty -s reload`
   - 建议使用证书自动续期工具（如 certbot）

## 示例：Let's Encrypt 证书

如果使用 Let's Encrypt 证书：

```bash
# 创建符号链接到 Let's Encrypt 证书目录
ln -s /etc/letsencrypt/live/your-domain.com/fullchain.pem conf.d/cert/your-domain.crt
ln -s /etc/letsencrypt/live/your-domain.com/privkey.pem conf.d/cert/your-domain.key
```

## 证书格式

- **证书文件**：通常是 `.crt`、`.pem` 或 `.cer` 格式
- **私钥文件**：通常是 `.key` 或 `.pem` 格式
- **证书链**：如果需要，可以包含 CA 证书链

