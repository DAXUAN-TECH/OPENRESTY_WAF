# HTTP/HTTPS Server 配置说明

## 目录说明

`conf.d/vhost_conf/http_https/` 目录用于存放 **HTTP / HTTPS 代理的 server 配置文件**，这些文件通常由系统根据数据库中的代理配置 **自动生成**，用于反向代理 Web 服务。

> 说明：upstream（后端集群）配置位于 `conf.d/upstream/http_https/` 目录，本目录主要存放与监听端口、域名、TLS 证书等相关的 `server` 块配置。

## 配置文件类型

- `proxy_http_{id}.conf`：HTTP/HTTPS 代理的 server 配置（文件命名示例，实际以系统生成规则为准）

**特点：**

- 由后台 Lua 模块 `lua/waf/nginx_config_generator.lua` 自动生成
- 通常不建议手工修改，避免下次更新代理配置时被覆盖
- 与 upstream 文件一一对应，负责监听端口、域名匹配、TLS 终端、WAF 接入等

## 典型配置结构示例

```nginx
server {
    listen 80;
    # 或：
    # listen 443 ssl http2;

    # 监听域名（可为空）
    # server_name example.com www.example.com;

    # TLS 证书配置（仅 HTTPS 时）
    # ssl_certificate     /path/to/cert.pem;
    # ssl_certificate_key /path/to/cert.key;

    # 日志、WAF、限速等通用配置
    # access_log /path/to/log;
    # error_log  /path/to/error_log;
    # include    /path/to/waf.conf;

    location / {
        # 通过 upstream 转发到后端
        proxy_pass http://upstream_{id};
        # 其他 proxy_* 相关配置由系统自动生成
    }
}
```

## 与 upstream 的关系

- upstream 配置目录：`conf.d/upstream/http_https/`
- server 配置目录：`conf.d/vhost_conf/http_https/`
- 典型引用方式：

```nginx
proxy_pass http://upstream_{id};
```

其中 `{id}` 与数据库中的代理配置 ID 一致。

## 使用与管理建议

- **推荐方式**：通过 Web 管理界面创建 / 修改 / 删除 HTTP/HTTPS 代理，由系统自动生成本目录下的配置文件
- **不建议**：直接在本目录下手工新增或修改文件，否则：
  - 可能与系统生成的命名规则冲突
  - 后续更新代理时，手工修改可能被覆盖

如果确需手工维护特殊 server 配置，建议：

- 使用单独的自定义文件目录（例如 `conf.d/http_set/` 中的公共配置）
- 或在 `nginx.conf` 中单独 include 其他路径

## 配置加载顺序（参考）

在 `nginx.conf` 的 `http {}` 块中，推荐的 include 顺序为：

```nginx
http {
    # 1. 公共基础配置
    include /path/to/project/conf.d/http_set/*.conf;

    # 2. upstream 配置（必须先于 server）
    include /path/to/project/conf.d/upstream/http_https/*.conf;

    # 3. server 配置（本目录）
    include /path/to/project/conf.d/vhost_conf/http_https/*.conf;
}
```

## 故障排查建议

1. **配置不生效**
   - 确认生成的 `proxy_http_{id}.conf` 已被主配置文件 `nginx.conf` include
   - 执行语法检查：`/usr/local/openresty/bin/openresty -t`
2. **域名或端口不监听**
   - 检查 `listen` 与 `server_name` 是否与预期一致
   - 注意监听 `0.0.0.0` / 指定 IP / IPv6 的差异
3. **后端不可达**
   - 检查对应 upstream 配置是否存在且名称正确
   - 使用 `curl -v` 或 `openresty -T` 查看实际生效配置

## 相关文档

- `conf.d/upstream/http_https/README.md`：HTTP/HTTPS upstream 配置说明
- `conf.d/vhost_conf/README.md`：vhost_conf 目录整体说明
- `lua/waf/nginx_config_generator.lua`：Nginx 配置自动生成逻辑


