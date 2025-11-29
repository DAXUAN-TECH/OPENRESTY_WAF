# TCP/UDP Server 配置说明

## 目录说明

`conf.d/vhost_conf/tcp_udp/` 目录用于存放 **TCP / UDP 代理的 server 配置文件**，这些文件通常由系统根据数据库中的代理配置 **自动生成**，用于四层反向代理（如数据库、DNS 等服务）。

> 说明：对应的 upstream（后端集群）配置位于 `conf.d/upstream/tcp_udp/` 目录，本目录主要存放 `stream {}` 块下的 `server` 配置。

## 配置文件类型

- `proxy_stream_{id}.conf`：TCP/UDP 代理的 server 配置（文件命名示例，实际以系统生成规则为准）

**特点：**

- 由后台 Lua 模块 `lua/waf/nginx_config_generator.lua` 自动生成
- 通常不建议手工修改，避免下次更新代理配置时被覆盖
- 与 upstream 文件一一对应，负责监听端口、协议类型（TCP/UDP）、超时等

## 典型配置结构示例

```nginx
server {
    # TCP 监听
    listen 3306;

    # 如为 UDP：
    # listen 53 udp;

    # 通过 upstream 转发到后端
    proxy_pass stream_upstream_{id};

    # 可选的超时与缓冲区配置
    # proxy_timeout 60s;
    # proxy_connect_timeout 10s;
    # proxy_buffer_size 4k;
}
```

## 与 upstream 的关系

- upstream 配置目录：`conf.d/upstream/tcp_udp/`
- server 配置目录：`conf.d/vhost_conf/tcp_udp/`
- 典型引用方式：

```nginx
proxy_pass stream_upstream_{id};
```

其中 `{id}` 与数据库中的代理配置 ID 一致。

> 注意：`stream` 代理的 `proxy_pass` **不需要** `http://` 前缀，直接使用 upstream 名称即可。

## 使用与管理建议

- **推荐方式**：通过 Web 管理界面创建 / 修改 / 删除 TCP/UDP 代理，由系统自动生成本目录下的配置文件
- **不建议**：直接在本目录下手工新增或修改文件，否则：
  - 可能与系统生成的命名规则冲突
  - 后续更新代理时，手工修改可能被覆盖

如需手工维护特殊的 stream 配置，建议：

- 在单独的自定义目录中维护，并在 `nginx.conf` 的 `stream {}` 中单独 include

## 配置加载顺序（参考）

在 `nginx.conf` 的 `stream {}` 块中，推荐的 include 顺序为：

```nginx
stream {
    # 1. upstream 配置（必须先于 server）
    include /path/to/project/conf.d/upstream/tcp_udp/*.conf;

    # 2. server 配置（本目录）
    include /path/to/project/conf.d/vhost_conf/tcp_udp/*.conf;
}
```

## 故障排查建议

1. **端口未监听**
   - 使用 `ss -lnptu` 或 `netstat -lnptu` 检查实际监听端口
   - 确认对应的 `proxy_stream_{id}.conf` 已被 `nginx.conf` include
2. **后端不可达**
   - 检查 upstream 名称是否正确、后端地址是否可达
3. **UDP 代理异常**
   - 确认 `listen` 指令中是否添加了 `udp` 关键字
4. **配置语法错误**
   - 执行：`/usr/local/openresty/bin/openresty -t` 检查语法

## 相关文档

- `conf.d/upstream/tcp_udp/README.md`：TCP/UDP upstream 配置说明
- `conf.d/vhost_conf/README.md`：vhost_conf 目录整体说明
- `lua/waf/nginx_config_generator.lua`：Nginx 配置自动生成逻辑


