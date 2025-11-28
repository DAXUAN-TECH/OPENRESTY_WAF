：# HTTP/HTTPS Upstream 配置说明

## 目录说明

`conf.d/upstream/HTTP_HTTPS/` 目录用于存放 HTTP 和 HTTPS 代理的 upstream 配置文件。

## 配置文件类型

### 自动生成的 Upstream 配置

**位置**：`conf.d/upstream/HTTP_HTTPS/http_upstream_{proxy_id}.conf`

这些文件由系统根据数据库中的 HTTP/HTTPS 代理配置自动生成。

**特点**：
- 自动生成，无需手动修改
- 每个代理配置对应一个独立的 upstream 文件
- 删除代理时自动删除对应的配置文件
- 支持动态添加/删除后端服务器

**生成时机**：
- 创建 HTTP/HTTPS 代理配置时（如果使用 upstream 类型）
- 更新代理配置时
- 启用/禁用代理时
- 删除代理时（自动清理）

## 配置参数说明

### 后端服务器配置

```nginx
server <address>:<port> [parameters];
```

**参数说明**：

| 参数 | 说明 | 默认值 | 示例 |
|------|------|--------|------|
| `weight` | 权重，数字越大权重越高 | 1 | `weight=2` |
| `max_fails` | 最大失败次数，超过此次数后标记为不可用 | 3 | `max_fails=5` |
| `fail_timeout` | 失败超时时间，失败后在此时间内不再尝试 | 30s | `fail_timeout=60s` |
| `backup` | 标记为备用服务器，主服务器不可用时使用 | - | `backup` |
| `down` | 手动标记为不可用 | - | `down` |

### Keepalive 配置

HTTP/HTTPS 代理的 upstream 配置包含 Keepalive 连接池配置，用于提高性能：

```nginx
keepalive <connections>;              # 每个 worker 进程保持的连接数
keepalive_requests <count>;           # 每个连接最多处理的请求数
keepalive_timeout <time>;             # Keepalive 超时时间
```

**参数说明**：

| 参数 | 说明 | 推荐值 | 示例 |
|------|------|--------|------|
| `keepalive` | 每个 worker 进程保持的 keepalive 连接数 | worker_connections 的 10-20% | `keepalive 1024` |
| `keepalive_requests` | 每个连接最多处理的请求数 | 10000 | `keepalive_requests 10000` |
| `keepalive_timeout` | Keepalive 超时时间 | 60s | `keepalive_timeout 60s` |

### 负载均衡算法

```nginx
# 轮询（默认）
# 不指定任何算法，默认使用轮询

# 最少连接数
least_conn;

# IP 哈希（会话保持）
ip_hash;
```

**算法说明**：

| 算法 | 说明 | 适用场景 |
|------|------|----------|
| `round_robin` | 轮询，依次分配请求到各个后端服务器 | 默认算法，适用于大多数场景 |
| `least_conn` | 最少连接数，将请求分配给当前连接数最少的服务器 | 后端服务器处理时间差异较大 |
| `ip_hash` | IP 哈希，相同 IP 的请求总是分配到同一台服务器 | 需要会话保持的场景 |

## 配置示例

### HTTP 代理 Upstream 配置

```nginx
# ============================================
# Upstream配置: 我的HTTP代理 (代理ID: 1)
# 类型: HTTP
# 自动生成，请勿手动修改
# ============================================

upstream upstream_1 {
    # 负载均衡算法
    least_conn;
    
    # 后端服务器
    server 192.168.1.10:8080 weight=2 max_fails=3 fail_timeout=30s;
    server 192.168.1.11:8080 weight=1 max_fails=3 fail_timeout=30s;
    server 192.168.1.12:8080 weight=1 max_fails=3 fail_timeout=30s backup;
    
    # Keepalive 配置
    keepalive 1024;
    keepalive_requests 10000;
    keepalive_timeout 60s;
}
```

### HTTPS 代理 Upstream 配置

```nginx
# ============================================
# Upstream配置: 我的HTTPS代理 (代理ID: 2)
# 类型: HTTP
# 自动生成，请勿手动修改
# ============================================

upstream upstream_2 {
    # 负载均衡算法
    ip_hash;
    
    # 后端服务器
    server 192.168.1.20:8443 weight=1 max_fails=3 fail_timeout=30s;
    server 192.168.1.21:8443 weight=1 max_fails=3 fail_timeout=30s;
    
    # Keepalive 配置
    keepalive 1024;
    keepalive_requests 10000;
    keepalive_timeout 60s;
}
```

## Server 配置引用

在 `conf.d/vhost_conf/proxy_http_{id}.conf` 文件中，server 配置通过 `proxy_pass` 指令引用 upstream：

```nginx
server {
    listen 80;
    server_name example.com;
    
    location / {
        # 引用 upstream（upstream配置在HTTP_HTTPS目录下）
        proxy_pass http://upstream_1;
    }
}
```

**重要**：
- Upstream 配置必须在 server 配置之前加载（在 nginx.conf 中，upstream 的 include 在 server 的 include 之前）
- Server 配置通过 upstream 名称引用，例如：`proxy_pass http://upstream_1;`
- Upstream 名称格式：`upstream_{proxy_id}`

## 配置加载顺序

在 `nginx.conf` 中，HTTP 块的配置加载顺序如下：

```nginx
http {
    # 1. 参数配置
    include /path/to/project/conf.d/set_conf/*.conf;
    
    # 2. HTTP/HTTPS upstream 配置（在 server 配置之前）
    include /path/to/project/conf.d/upstream/HTTP_HTTPS/*.conf;
    
    # 3. 服务器配置（可以引用 upstream）
    include /path/to/project/conf.d/vhost_conf/*.conf;
    include /path/to/project/conf.d/vhost_conf/proxy_http_*.conf;
}
```

**重要**：upstream 配置必须在 server 配置之前加载，因为 server 配置中会引用 upstream 名称。

## 使用方式

### 自动生成 Upstream（推荐）

1. 在 Web 管理界面创建 HTTP/HTTPS 代理配置
2. 选择后端类型为 "upstream"（多个后端服务器）
3. 添加后端服务器配置
4. 系统自动生成 upstream 配置文件到 `conf.d/upstream/HTTP_HTTPS/` 目录
5. 系统自动生成 server 配置文件到 `conf.d/vhost_conf/` 目录
6. Server 配置自动引用对应的 upstream
7. 自动触发 Nginx 重载（如果代理已启用）

## 注意事项

### 1. 自动生成的文件

- **不要手动修改** `conf.d/upstream/HTTP_HTTPS/` 目录下自动生成的文件
- 这些文件会在代理配置更新时自动覆盖
- 如果需要自定义配置，请使用手动配置方式（`conf.d/set_conf/upstream.conf`）

### 2. 文件命名规则

- 文件命名：`http_upstream_{proxy_id}.conf`
- `{proxy_id}` 是代理配置在数据库中的 ID
- Upstream 名称：`upstream_{proxy_id}`（在 server 配置中引用）

### 3. 配置验证

- 修改配置后，建议先验证配置语法：
  ```bash
  /usr/local/openresty/bin/openresty -t
  ```
- 验证通过后再重新加载配置

### 4. 性能优化建议

- **Keepalive 连接数**：根据实际并发量调整，建议为 `worker_connections` 的 10-20%
- **权重设置**：根据后端服务器的性能差异设置合理的权重
- **健康检查**：合理设置 `max_fails` 和 `fail_timeout`，避免频繁切换后端服务器

### 5. 故障处理

- 如果后端服务器不可用，Nginx 会自动标记为不可用
- 使用 `backup` 参数标记备用服务器
- 使用 `down` 参数可以手动下线服务器（需要手动修改配置或通过 API）

## 常见问题

### Q1: 为什么我的 upstream 配置没有生效？

**A**: 检查以下几点：
1. 配置文件是否在正确的目录（`conf.d/upstream/HTTP_HTTPS/`）
2. 配置文件是否被 nginx.conf 正确包含
3. Nginx 配置是否已重新加载
4. 配置文件语法是否正确
5. Upstream 配置是否在 server 配置之前加载

### Q2: 如何查看当前生效的 upstream 配置？

**A**: 可以通过以下方式查看：
1. 查看配置文件：`cat conf.d/upstream/HTTP_HTTPS/http_upstream_*.conf`
2. 查看 Nginx 配置：`/usr/local/openresty/bin/openresty -T`
3. 在 Web 管理界面查看代理配置详情

### Q3: Server 配置如何引用 upstream？

**A**: Server 配置通过 `proxy_pass` 指令引用 upstream：
```nginx
proxy_pass http://upstream_{proxy_id};
```
Upstream 名称必须与 upstream 配置块中的名称一致。

### Q4: 如何删除自动生成的 upstream 配置？

**A**: 删除对应的代理配置即可，系统会自动清理：
1. 在 Web 管理界面删除代理配置
2. 系统自动删除对应的 upstream 配置文件
3. 系统自动删除对应的 server 配置文件
4. 自动触发 Nginx 重载

## 相关文档

- [TCP/UDP Upstream 配置说明](../TCP_UDP/README.md)
- [Server 配置说明](../../vhost_conf/README.md)
- [Nginx 配置说明](../../../init_file/nginx.conf)
- [部署脚本说明](../../../scripts/deploy_README.md)

