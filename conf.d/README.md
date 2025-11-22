# Nginx 配置文件目录结构

## 目录说明

```
conf.d/
├── set_conf/         # 参数配置文件目录
│   ├── mime.conf     # MIME 类型配置
│   ├── log.conf      # 日志格式和访问日志配置
│   ├── basic.conf    # 基础配置（sendfile、keepalive 等）
│   ├── gzip.conf     # Gzip 压缩配置
│   ├── lua.conf      # Lua 模块配置
│   ├── waf.conf      # WAF 共享内存和限流配置
│   ├── performance.conf # 性能优化配置
│   └── upstream.conf # 后端服务器配置
├── vhost_conf/       # 虚拟主机配置目录
│   └── default.conf  # 默认 HTTP 服务器配置
├── cert/             # SSL 证书目录（可选）
│   └── (证书文件)    # SSL 证书和密钥文件
└── logs/             # 日志配置目录（可选）
    └── (日志配置)    # 日志相关配置文件
```

## 配置文件说明

### set_conf/ 目录（参数配置）

#### mime.conf
- MIME 类型映射
- 默认文件类型

#### log.conf
- 日志格式定义
- 访问日志配置

#### basic.conf
- 基础性能参数
- sendfile、tcp_nopush、tcp_nodelay
- keepalive_timeout
- client_max_body_size

#### gzip.conf
- Gzip 压缩配置
- 压缩级别和类型

#### lua.conf
- Lua 模块路径配置
- init_by_lua_block（初始化）
- init_worker_by_lua_block（工作进程初始化）

#### waf.conf
- WAF 共享内存配置
- 限流配置（limit_req、limit_conn）

#### upstream.conf
- 后端服务器 upstream 配置

### vhost_conf/ 目录（虚拟主机配置）

#### default.conf
- HTTP 服务器配置
- WAF 封控检查（access_by_lua_block）
- 日志采集（log_by_lua_block）
- location 配置

## 加载顺序

配置文件按以下顺序加载：

1. **mime.conf** - MIME 类型（最先加载）
2. **log.conf** - 日志格式（需要在 server 之前定义）
3. **basic.conf** - 基础配置
4. **gzip.conf** - Gzip 配置
5. **lua.conf** - Lua 配置（需要在 server 之前加载）
6. **waf.conf** - WAF 配置（需要在 server 之前加载）
7. **upstream.conf** - 后端服务器配置（需要在 server 之前加载）
8. **vhost_conf/*.conf** - 虚拟主机配置（最后加载）

## 添加新配置

### 添加新的参数配置

在 `conf.d/set_conf/` 目录下创建新的 `.conf` 文件，然后在 `nginx.conf` 中添加 include：

```nginx
include conf.d/set_conf/your_config.conf;
```

### 添加新的虚拟主机配置

在 `conf.d/vhost_conf/` 目录下创建新的 `.conf` 文件，会自动被加载：

```nginx
# nginx.conf 中已有：
include conf.d/vhost_conf/*.conf;
```

### SSL 证书配置

将 SSL 证书文件放在 `conf.d/cert/` 目录下：

```bash
# 示例：放置证书文件
conf.d/cert/your-domain.crt  # SSL 证书
conf.d/cert/your-domain.key  # 私钥
```

在 `conf.d/vhost_conf/` 中的 server 配置中引用：

```nginx
server {
    listen 443 ssl;
    ssl_certificate conf.d/cert/your-domain.crt;
    ssl_certificate_key conf.d/cert/your-domain.key;
    # ...
}
```

### 日志配置

如果需要额外的日志配置，可以放在 `conf.d/logs/` 目录下。

## 注意事项

1. **加载顺序很重要**：某些配置必须在其他配置之前加载
2. **不要重复定义**：避免在不同文件中重复定义相同的指令
3. **路径使用相对路径**：配置文件中的路径相对于 nginx 配置目录
4. **测试配置**：修改后使用 `nginx -t` 测试配置语法

## 部署说明

**重要**：`conf.d/` 目录保持在项目目录，不复制到系统目录，方便配置管理。

### 使用部署脚本（推荐）

```bash
# 使用部署脚本自动处理路径
sudo ./scripts/deploy.sh
```

部署脚本会自动：
- 复制 `init_file/nginx.conf` 到系统目录
- 更新 `nginx.conf` 中的 include 路径指向项目目录的 `conf.d/`
- 处理所有路径替换

### 手动部署

```bash
# 只复制主配置文件
sudo cp init_file/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf

# 手动更新 nginx.conf 中的 include 路径
# 将 include conf.d/set_conf/*.conf 改为 include /path/to/project/conf.d/set_conf/*.conf
# 将 include conf.d/vhost_conf/*.conf 改为 include /path/to/project/conf.d/vhost_conf/*.conf

# 测试配置
sudo /usr/local/openresty/bin/openresty -t
```

### 配置修改

**优势**：修改 `conf.d/` 中的配置文件后，无需重新部署，直接 reload 即可生效：

```bash
sudo /usr/local/openresty/bin/openresty -s reload
```

