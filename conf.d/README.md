# Nginx 配置文件目录结构（conf.d）

本目录存放项目内所有 Nginx 配置片段，由 `init_file/nginx.conf` 通过绝对路径 `include` 引入。  
这些文件都 **保持在项目目录**，方便版本管理和统一部署。

## 目录总览

```text
conf.d/
├── http_set/         # HTTP 参数与 Lua/WAF 相关配置
├── stream_set/       # stream(TCP/UDP) 参数配置
├── upstream/         # 自动生成的 upstream 配置（HTTP/HTTPS/TCP/UDP）
├── vhost_conf/       # 管理服务与代理 server 配置
├── cert/             # 证书目录
└── web/              # 静态错误页等
```

## http_set/ 目录（HTTP 参数与 Lua/WAF 配置）

这些文件在 `init_file/nginx.conf` 的 `http {}` 中通过：

```nginx
include /path/to/project/conf.d/http_set/*.conf;
```

统一加载。

- **`mime.conf`**
  - MIME 类型映射与默认类型。
- **`log.conf`**
  - HTTP 访问日志格式与日志路径配置。
- **`basic.conf`**
  - 基础性能参数：`sendfile`、`tcp_nopush`、`tcp_nodelay`、`keepalive_timeout`、`client_max_body_size` 等。
- **`gzip.conf`**
  - Gzip 压缩参数：开启/关闭、压缩级别、压缩类型等。
- **`lua.conf`**
  - HTTP 块的 `init_by_lua_block` / `init_worker_by_lua_block`，负责：
    - 加载 `lua/config.lua`。
    - 初始化 `waf.init`、日志采集等核心模块。
  - 注意：`lua_package_path` / `lua_package_cpath` 已在 `nginx.conf` 中配置，此处仅负责初始化逻辑。
- **`waf.conf`**
  - HTTP WAF 共享内存（`lua_shared_dict`）与限流（`limit_req` / `limit_conn`）配置。
- **`performance.conf`**
  - HTTP 层面的额外性能优化选项（缓冲区、超时等）。
- **`upstream.conf`**
  - 手工维护的 upstream 配置（如果有）。  
  - 自动生成的 upstream 位于 `conf.d/upstream/`，不在此文件中。

## stream_set/ 目录（Stream/TCP/UDP 参数配置）

这些文件在 `init_file/nginx.conf` 的 `stream {}` 中通过：

```nginx
include /path/to/project/conf.d/stream_set/*.conf;
```

统一加载，用于 TCP/UDP 代理。

- **`lua.conf`**
  - 说明并约束 Stream 块中 Lua 的使用方式。
  - 核心提示：Stream 块 **不支持** `init_by_lua_block` / `init_worker_by_lua_block`，Lua 模块一般在 `preread_by_lua_block` 等指令中按需加载。
- **`waf.conf`**
  - Stream 相关共享内存和限流配置。
  - 常与 HTTP WAF 共享部分共享内存区域。

## upstream/ 目录（自动生成的 upstream 配置）

由 Lua 后端根据数据库内的代理配置自动生成：

- **`upstream/http_https/`**
  - HTTP/HTTPS 代理使用的 upstream。
  - 文件命名：`http_upstream_{proxy_id}.conf`。
  - 在 `http {}` 中按以下方式加载：
    ```nginx
    include /path/to/project/conf.d/upstream/http_https/http_upstream_*.conf;
    ```
  - 详细说明见 `conf.d/upstream/http_https/README.md`。

- **`upstream/tcp_udp/`**
  - TCP/UDP 代理使用的 upstream。
  - 文件命名：`stream_upstream_{proxy_id}.conf`。
  - 在 `stream {}` 中按以下方式加载：
    ```nginx
    include /path/to/project/conf.d/upstream/tcp_udp/stream_upstream_*.conf;
    ```
  - 详细说明见 `conf.d/upstream/tcp_udp/README.md`。

这些文件 **不建议手工修改**，应通过 Web 管理界面或 API 修改代理配置，由系统重新生成。

## vhost_conf/ 目录（管理服务与代理 server）

该目录包含：

- **`waf.conf`**
  - WAF 管理服务 HTTP server：
    - `location /api/`：统一 API 入口（`lua/api/handler.lua` 分发）。
    - `location /`：统一 Web 管理入口（`lua/web/handler.lua` 分发）。
    - `location /metrics`：Prometheus 指标导出（可选）。
  - 功能开关控制各模块（规则管理、代理管理、统计、监控等），详细说明见 `conf.d/vhost_conf/README.md`。

- **`default.conf.example`**
  - 示例业务 HTTP server 配置，演示如何将业务流量接入 WAF/代理。

- **`http_https/`**
  - HTTP/HTTPS 代理的 server 配置（自动生成），通常命名为：
    - `proxy_http_{proxy_id}.conf`
  - 使用 `proxy_pass http://upstream_{proxy_id};` 引用对应 upstream。
  - 详细说明见 `conf.d/vhost_conf/http_https/README.md`。

- **`tcp_udp/`**
  - TCP/UDP 代理的 stream server 配置（自动生成），通常命名为：
    - `proxy_stream_{proxy_id}.conf`
  - 使用 `proxy_pass stream_upstream_{proxy_id};` 引用对应 upstream。
  - 详细说明见 `conf.d/vhost_conf/tcp_udp/README.md`。

## cert/ 目录（证书）

用于存放 TLS 证书和私钥文件。  
具体如何在 server 配置中引用、证书命名建议等，请参考 `conf.d/cert/README.md`。

## web/ 目录（静态错误页）

主要存放静态错误页等 HTML 文件，例如：

- `403_waf.html`：系统访问白名单拦截时返回的页面，由 Lua 从该文件读取并输出。

详细说明见 `conf.d/web/README.md`。

## 与 init_file/nginx.conf 的加载关系（简化示意）

```nginx
http {
    lua_package_path "/path/to/project/lua/?.lua;/path/to/project/lua/waf/?.lua;;";
    include /path/to/project/conf.d/http_set/*.conf;

    include /path/to/project/conf.d/upstream/http_https/http_upstream_*.conf;
    include /path/to/project/conf.d/vhost_conf/waf.conf;
    include /path/to/project/conf.d/vhost_conf/http_https/proxy_http_*.conf;
}

stream {
    lua_package_path "/path/to/project/lua/?.lua;/path/to/project/lua/waf/?.lua;;";
    include /path/to/project/conf.d/stream_set/*.conf;

    include /path/to/project/conf.d/upstream/tcp_udp/stream_upstream_*.conf;
    include /path/to/project/conf.d/vhost_conf/tcp_udp/proxy_stream_*.conf;
}
```

**要点：**
- upstream 配置必须在对应的 server 配置前加载。
- 管理服务 `waf.conf` 独立于自动生成的代理 server。

## 使用建议

- `conf.d/` **始终放在项目目录**，不要复制到系统 Nginx 配置目录。
- 修改 `conf.d/` 任意配置后：
  - 先执行 `openresty -t` 验证语法；
  - 再执行 `openresty -s reload` 重新加载。
- 自动生成的 upstream/server 配置不要直接编辑，应通过 Web 界面或 API 修改代理配置，由系统生成新文件并触发 reload。


