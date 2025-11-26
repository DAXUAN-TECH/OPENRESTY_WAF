# Upstream 配置说明

## 目录说明

`conf.d/upstream/` 目录用于存放 Nginx upstream 配置文件，包括：

1. **手动配置的 upstream**：`conf.d/set_conf/upstream.conf`（示例配置文件）
2. **自动生成的 upstream**：`conf.d/upstream/` 目录下的配置文件（由系统自动生成）

## 配置文件类型

### 1. 手动配置的 Upstream

**位置**：`conf.d/set_conf/upstream.conf`

这是手动配置的 upstream 示例文件，用于定义静态的后端服务器组。适用于：
- 固定的后端服务器配置
- 不需要动态管理的 upstream
- 示例和参考配置

**配置示例**：
```nginx
upstream backend {
    server 127.0.0.1:8080 max_fails=3 fail_timeout=30s weight=1;
    server 127.0.0.1:8081 max_fails=3 fail_timeout=30s weight=1;
    
    # Keepalive 连接池（高并发场景下非常重要）
    keepalive 1024;
    keepalive_requests 10000;
    keepalive_timeout 60s;
    
    # 负载均衡算法（可选）
    # least_conn;  # 最少连接数
    # ip_hash;    # IP 哈希（会话保持）
}
```

### 2. 自动生成的 Upstream

**位置**：`conf.d/upstream/`

这些文件由系统根据数据库中的代理配置自动生成，命名规则：
- **HTTP 代理**：`upstream_{proxy_id}.conf`
- **Stream 代理**：`stream_upstream_{proxy_id}.conf`

**特点**：
- 自动生成，无需手动修改
- 每个代理配置对应一个独立的 upstream 文件
- 删除代理时自动删除对应的配置文件
- 支持动态添加/删除后端服务器

**生成时机**：
- 创建代理配置时（如果使用 upstream 类型）
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

### Keepalive 配置（仅 HTTP 代理）

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

### Stream 代理 Upstream 配置

```nginx
# ============================================
# Upstream配置: 我的TCP代理 (代理ID: 2)
# 类型: TCP
# 自动生成，请勿手动修改
# ============================================

upstream stream_upstream_2 {
    # 负载均衡算法
    ip_hash;
    
    # 后端服务器
    server 192.168.1.20:3306 weight=1 max_fails=3 fail_timeout=30s;
    server 192.168.1.21:3306 weight=1 max_fails=3 fail_timeout=30s;
}
```

## 使用方式

### 手动配置 Upstream

1. 编辑 `conf.d/set_conf/upstream.conf` 文件
2. 添加或修改 upstream 配置块
3. 重新加载 Nginx 配置：
   ```bash
   /usr/local/openresty/bin/openresty -s reload
   ```

### 自动生成 Upstream（推荐）

1. 在 Web 管理界面创建代理配置
2. 选择后端类型为 "upstream"（多个后端服务器）
3. 添加后端服务器配置
4. 系统自动生成 upstream 配置文件
5. 自动触发 Nginx 重载（如果代理已启用）

## 配置加载顺序

在 `nginx.conf` 中，upstream 配置的加载顺序如下：

```nginx
http {
    # 1. 参数配置
    include /path/to/project/conf.d/set_conf/*.conf;
    
    # 2. 自动生成的 upstream 配置（在 server 配置之前）
    include /path/to/project/conf.d/upstream/upstream_*.conf;
    
    # 3. 服务器配置
    include /path/to/project/conf.d/vhost_conf/*.conf;
    include /path/to/project/conf.d/vhost_conf/proxy_http_*.conf;
}

stream {
    # 1. 自动生成的 stream upstream 配置
    include /path/to/project/conf.d/upstream/stream_upstream_*.conf;
    
    # 2. Stream 服务器配置
    include /path/to/project/conf.d/vhost_conf/proxy_stream_*.conf;
}
```

**重要**：upstream 配置必须在 server 配置之前加载，因为 server 配置中会引用 upstream 名称。

## 注意事项

### 1. 自动生成的文件

- **不要手动修改** `conf.d/upstream/` 目录下自动生成的文件
- 这些文件会在代理配置更新时自动覆盖
- 如果需要自定义配置，请使用手动配置方式

### 2. 文件命名规则

- HTTP 代理：`upstream_{proxy_id}.conf`
- Stream 代理：`stream_upstream_{proxy_id}.conf`
- `{proxy_id}` 是代理配置在数据库中的 ID

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
1. 配置文件是否在正确的目录（`conf.d/upstream/` 或 `conf.d/set_conf/`）
2. 配置文件是否被 nginx.conf 正确包含
3. Nginx 配置是否已重新加载
4. 配置文件语法是否正确

### Q2: 如何查看当前生效的 upstream 配置？

**A**: 可以通过以下方式查看：
1. 查看配置文件：`cat conf.d/upstream/upstream_*.conf`
2. 查看 Nginx 配置：`/usr/local/openresty/bin/openresty -T`
3. 在 Web 管理界面查看代理配置详情

### Q3: 自动生成的配置文件可以手动修改吗？

**A**: 不建议手动修改，因为：
- 配置会在代理更新时自动覆盖
- 可能导致配置不一致
- 如果需要自定义配置，请使用手动配置方式

### Q4: 如何删除自动生成的 upstream 配置？

**A**: 删除对应的代理配置即可，系统会自动清理：
1. 在 Web 管理界面删除代理配置
2. 系统自动删除对应的 upstream 配置文件
3. 自动触发 Nginx 重载

## 相关文档

- [代理管理说明](../vhost_conf/README.md)
- [Nginx 配置说明](../../init_file/nginx.conf)
- [部署脚本说明](../../scripts/deploy_README.md)

