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
│   ├── default.conf  # 默认 HTTP 服务器配置（代理到后端服务器）
│   ├── waf.conf     # WAF 管理服务配置（API和Web管理界面）
│   └── README.md    # 虚拟主机配置说明
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
- HTTP 服务器配置（用于代理到后端服务器）
- WAF 封控检查（access_by_lua_block）
- 日志采集（log_by_lua_block）
- location 配置（代理配置）

#### waf.conf
- WAF 管理服务配置（专门用于WAF管理功能）
- API统一入口（`/api/` location，路由分发到各个API模块）
- Web管理界面统一入口（`/` location，路由分发到各个HTML页面）
- Prometheus指标导出（`/metrics` location）
- 功能开关控制（通过数据库动态控制功能启用/禁用）
- 详细说明请参考：[vhost_conf/README.md](vhost_conf/README.md)

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
# 使用 $project_root 变量引用项目目录（推荐）
include $project_root/conf.d/set_conf/your_config.conf;

# 或使用相对路径（如果 nginx.conf 在项目目录）
include conf.d/set_conf/your_config.conf;
```

**路径说明**：
- 配置文件使用 `$project_root` 变量引用项目根目录，无需硬编码绝对路径
- `$project_root` 变量在 `nginx.conf` 的 `http` 块中通过 `set` 指令设置
- 部署脚本会自动设置 `$project_root` 变量为实际项目路径

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
# 只复制主配置文件（使用默认路径）
sudo cp init_file/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf

# 或使用环境变量指定的路径
sudo cp init_file/nginx.conf ${OPENRESTY_PREFIX:-/usr/local/openresty}/nginx/conf/nginx.conf

# 手动更新 nginx.conf 中的 include 路径
# 推荐：使用 $project_root 变量（部署脚本会自动设置）
# include $project_root/conf.d/set_conf/*.conf;
# include $project_root/conf.d/vhost_conf/*.conf;

# 不推荐：硬编码绝对路径
# include /path/to/project/conf.d/set_conf/*.conf;
# include /path/to/project/conf.d/vhost_conf/*.conf;

# 测试配置
sudo /usr/local/openresty/bin/openresty -t
# 或使用环境变量指定的路径
sudo ${OPENRESTY_PREFIX:-/usr/local/openresty}/bin/openresty -t
```

**路径配置说明**：
- 所有脚本支持通过环境变量 `OPENRESTY_PREFIX` 配置 OpenResty 安装路径（默认：`/usr/local/openresty`）
- 项目路径使用 `$project_root` 变量，由部署脚本自动设置
- 无硬编码绝对路径，支持灵活部署

### 配置修改

**优势**：修改 `conf.d/` 中的配置文件后，无需重新部署，直接 reload 即可生效：

```bash
# 使用默认路径
sudo /usr/local/openresty/bin/openresty -s reload

# 或使用环境变量指定的路径
sudo ${OPENRESTY_PREFIX:-/usr/local/openresty}/bin/openresty -s reload
```

