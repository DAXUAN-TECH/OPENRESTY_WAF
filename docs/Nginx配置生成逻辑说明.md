# Nginx 配置文件生成逻辑说明

## 一、功能概述

本系统实现了基于数据库配置的**自动生成 Nginx 配置文件**功能。当用户通过 Web 界面创建、修改、删除或启用/禁用代理配置时，系统会自动从数据库读取配置并生成对应的 Nginx 配置文件，然后触发 Nginx 重载使配置生效。

## 二、核心模块

### 2.1 主要文件

- **`lua/waf/nginx_config_generator.lua`**：Nginx 配置生成器核心模块
- **`lua/waf/proxy_management.lua`**：代理配置管理模块（CRUD 操作）
- **`lua/api/proxy.lua`**：代理管理 API 接口
- **`lua/waf/init.lua`**：系统初始化模块（启动时自动生成配置）
- **`init_file/nginx.conf`**：主配置文件（包含自动生成的配置文件）

### 2.2 数据库表结构

- **`waf_proxy_configs`**：代理配置主表
  - `id`：代理ID
  - `proxy_name`：代理名称
  - `proxy_type`：代理类型（`http`、`tcp`、`udp`）
  - `listen_port`：监听端口
  - `listen_address`：监听地址
  - `server_name`：服务器名称（域名）
  - `location_paths`：路径匹配列表（JSON格式，支持多个location）
  - `load_balance`：负载均衡算法
  - `ssl_enable`：是否启用SSL
  - `ssl_pem`：SSL证书内容（PEM格式）
  - `ssl_key`：SSL私钥内容（KEY格式）
  - `proxy_connect_timeout`：连接超时
  - `proxy_send_timeout`：发送超时
  - `proxy_read_timeout`：读取超时
  - `ip_rule_ids`：关联的防护规则ID（JSON格式）
  - `status`：状态（1=启用，0=禁用）

- **`waf_proxy_backends`**：后端服务器配置表
  - `id`：后端服务器ID
  - `proxy_id`：关联的代理ID
  - `location_path`：关联的Location路径（HTTP/HTTPS代理时使用）
  - `backend_address`：后端服务器地址
  - `backend_port`：后端服务器端口
  - `backend_path`：后端路径（目标路径）
  - `weight`：权重
  - `max_fails`：最大失败次数
  - `fail_timeout`：失败超时时间
  - `backup`：是否备用服务器
  - `down`：是否下线
  - `status`：状态（1=启用，0=禁用）

## 三、配置文件生成流程

### 3.1 触发时机

配置文件生成在以下情况下会被触发：

1. **系统启动时**（`init_worker` 阶段）
   - 位置：`lua/waf/init.lua` 的 `init_worker()` 函数
   - 延迟1秒执行，确保数据库连接已建立
   - 调用 `nginx_config_generator.generate_all_configs()`

2. **创建代理时**（`proxy_management.create_proxy()`）
   - 如果代理状态为启用（`status = 1`），立即生成配置

3. **更新代理时**（`proxy_management.update_proxy()`）
   - 如果状态发生变化，重新生成配置

4. **删除代理时**（`proxy_management.delete_proxy()`）
   - 重新生成配置（已删除的代理会被排除）

5. **启用/禁用代理时**（`proxy_management.enable_proxy()` / `disable_proxy()`）
   - 重新生成配置（禁用的代理会被排除）

### 3.2 生成流程详解

#### 步骤1：查询启用的代理配置

```lua
-- 从数据库查询所有 status = 1 的代理配置
SELECT id, proxy_name, proxy_type, listen_port, listen_address, server_name, 
       location_path, location_paths, backend_type, load_balance,
       ssl_enable, ssl_pem, ssl_key,
       proxy_timeout, proxy_connect_timeout, proxy_send_timeout, proxy_read_timeout,
       status
FROM waf_proxy_configs
WHERE status = 1
ORDER BY id ASC
```

#### 步骤2：确保目录存在

系统会确保以下目录存在：

- `conf.d/vhost_conf/http_https/`：HTTP/HTTPS 代理的 server 配置
- `conf.d/vhost_conf/tcp_udp/`：TCP/UDP 代理的 server 配置
- `conf.d/upstream/http_https/`：HTTP/HTTPS 代理的 upstream 配置
- `conf.d/upstream/tcp_udp/`：TCP/UDP 代理的 upstream 配置

#### 步骤3：为每个代理生成配置

对于每个启用的代理，系统会：

1. **解析 `location_paths` JSON 字段**（如果存在）
2. **查询后端服务器配置**
   ```lua
   SELECT id, location_path, backend_address, backend_port, backend_path, 
          weight, max_fails, fail_timeout, backup, down, status
   FROM waf_proxy_backends
   WHERE proxy_id = ? AND status = 1
   ORDER BY location_path, weight DESC, id ASC
   ```

3. **生成 Upstream 配置**

   **HTTP/HTTPS 代理（支持多个 location）：**
   - 如果 `location_paths` 存在且不为空：
     - 为每个 location 生成独立的 upstream 配置
     - 文件名：`http_upstream_{proxy_id}_loc_{index}.conf`
     - upstream 名称：`upstream_{proxy_id}_loc_{index}`
     - 筛选属于该 location 的后端服务器（通过 `backend.location_path` 匹配）
   - 否则（向后兼容）：
     - 生成单个 upstream 配置
     - 文件名：`http_upstream_{proxy_id}.conf`
     - upstream 名称：`upstream_{proxy_id}`

   **TCP/UDP 代理：**
   - 生成单个 upstream 配置
   - 文件名：`stream_upstream_{proxy_id}.conf`
   - upstream 名称：`stream_upstream_{proxy_id}`

4. **生成 Server 配置**

   **HTTP/HTTPS 代理：**
   - 文件名：`proxy_http_{proxy_id}.conf`
   - 包含：
     - `listen` 指令（端口、SSL配置）
     - `server_name` 指令（如果配置了域名）
     - SSL 配置（如果启用）
     - WAF 封控检查（如果关联了防护规则）
     - 日志采集
     - Location 块：
       - 如果 `location_paths` 存在：为每个 location 生成独立的 location 块
       - 否则：生成单个 location 块（向后兼容）
     - 禁止访问隐藏文件

   **TCP/UDP 代理：**
   - 文件名：`proxy_stream_{proxy_id}.conf`
   - 包含：
     - `listen` 指令（端口、UDP标识）
     - WAF 封控检查（如果关联了防护规则）
     - `proxy_pass` 指令（指向 upstream）
     - 超时设置

#### 步骤4：清理已删除或禁用的代理的配置文件

系统会扫描所有已生成的配置文件，如果对应的代理ID不在活跃代理列表中（即已删除或禁用），则删除该配置文件。

## 四、配置文件结构

### 4.1 目录结构

```
conf.d/
├── upstream/
│   ├── http_https/
│   │   ├── http_upstream_1.conf          # 单个upstream（向后兼容）
│   │   ├── http_upstream_1_loc_1.conf    # location 1 的upstream
│   │   ├── http_upstream_1_loc_2.conf    # location 2 的upstream
│   │   └── ...
│   └── tcp_udp/
│       ├── stream_upstream_1.conf
│       └── ...
└── vhost_conf/
    ├── http_https/
    │   ├── proxy_http_1.conf             # HTTP/HTTPS代理server配置
    │   └── ...
    └── tcp_udp/
        ├── proxy_stream_1.conf            # TCP/UDP代理server配置
        └── ...
```

### 4.2 Upstream 配置示例

**HTTP/HTTPS Upstream（单个location）：**

```nginx
upstream upstream_1 {
    least_conn;  # 或 round_robin、ip_hash
    server 192.168.1.10:8080 weight=10 max_fails=3 fail_timeout=30s;
    server 192.168.1.11:8080 weight=10 max_fails=3 fail_timeout=30s;
    keepalive 1024;
    keepalive_requests 10000;
    keepalive_timeout 60s;
}
```

**HTTP/HTTPS Upstream（多个location）：**

```nginx
# Location 1 的upstream
upstream upstream_1_loc_1 {
    least_conn;
    server 192.168.1.10:8080 weight=10;
    server 192.168.1.11:8080 weight=10;
    keepalive 1024;
    keepalive_requests 10000;
    keepalive_timeout 60s;
}

# Location 2 的upstream
upstream upstream_1_loc_2 {
    least_conn;
    server 192.168.1.20:8080 weight=10;
    server 192.168.1.21:8080 weight=10;
    keepalive 1024;
    keepalive_requests 10000;
    keepalive_timeout 60s;
}
```

**TCP/UDP Upstream：**

```nginx
upstream stream_upstream_1 {
    least_conn;
    server 192.168.1.10:3306 weight=10 max_fails=3 fail_timeout=30s;
    server 192.168.1.11:3306 weight=10 max_fails=3 fail_timeout=30s;
}
```

### 4.3 Server 配置示例

**HTTP/HTTPS Server（单个location）：**

```nginx
server {
    listen       80;
    server_name  example.com;
    charset utf-8;
    client_max_body_size 10m;

    # SSL配置（如果启用）
    # ssl_certificate     /path/to/cert.pem;
    # ssl_certificate_key /path/to/key.pem;

    # WAF封控检查（如果关联了防护规则）
    set $proxy_ip_rule_ids '{1,2,3}';
    access_by_lua_block {
        local rule_ids_str = ngx.var.proxy_ip_rule_ids
        -- ... 解析规则ID并调用检查函数
        require("waf.ip_block").check_multiple(rule_ids)
    }

    # 日志采集
    log_by_lua_block {
        require("waf.log_collect").collect()
    }

    # Location配置
    location /api {
        proxy_pass http://upstream_1/target;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection "";
        proxy_http_version 1.1;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # 禁止访问隐藏文件
    location ~ /\. {
        deny all;
        access_log off;
    }
}
```

**HTTP/HTTPS Server（多个location）：**

```nginx
server {
    listen       80;
    server_name  example.com;
    charset utf-8;
    client_max_body_size 10m;

    # Location 1
    location /api {
        proxy_pass http://upstream_1_loc_1/target1;
        # ... 其他配置
    }

    # Location 2
    location /v1 {
        proxy_pass http://upstream_1_loc_2/target2;
        # ... 其他配置
    }

    # 禁止访问隐藏文件
    location ~ /\. {
        deny all;
        access_log off;
    }
}
```

**TCP/UDP Server：**

```nginx
server {
    listen 3306;
    # 如果是UDP，添加 udp 标识

    # WAF封控检查（如果关联了防护规则）
    set $proxy_ip_rule_ids '{1,2,3}';
    preread_by_lua_block {
        -- ... 解析规则ID并调用检查函数
        require("waf.ip_block").check_stream_multiple(rule_ids)
    }

    proxy_pass stream_upstream_1;
    proxy_timeout 60s;
    proxy_connect_timeout 60s;
}
```

## 五、主配置文件引入

### 5.1 nginx.conf 中的 include 顺序

在 `init_file/nginx.conf` 中，配置文件的引入顺序如下：

**HTTP 块：**

```nginx
http {
    # 1. 公共基础配置
    include /path/to/project/conf.d/http_set/*.conf;

    # 2. 手动配置的server（如WAF管理界面）
    include /path/to/project/conf.d/vhost_conf/waf.conf;

    # 3. Upstream配置（必须先于server配置）
    include /path/to/project/conf.d/upstream/http_https/http_upstream_*.conf;

    # 4. Server配置（可以引用upstream）
    include /path/to/project/conf.d/vhost_conf/http_https/proxy_http_*.conf;
}
```

**Stream 块：**

```nginx
stream {
    # 1. 公共基础配置
    include /path/to/project/conf.d/stream_set/*.conf;

    # 2. Upstream配置（必须先于server配置）
    include /path/to/project/conf.d/upstream/tcp_udp/stream_upstream_*.conf;

    # 3. Server配置（可以引用upstream）
    include /path/to/project/conf.d/vhost_conf/tcp_udp/proxy_stream_*.conf;
}
```

**重要提示：**
- Upstream 配置必须在 Server 配置之前加载，以便 Server 配置可以引用 Upstream
- 如果没有任何配置文件，`include` 不会报错（Nginx 会忽略不存在的通配符匹配）

## 六、Nginx 重载机制

### 6.1 自动重载触发

在以下 API 操作后，系统会自动触发 Nginx 重载（异步，不阻塞响应）：

1. **创建代理**（`/api/proxy` POST）
   - 如果代理状态为启用，触发重载

2. **更新代理**（`/api/proxy/:id` PUT）
   - 无论状态如何，都触发重载（使新配置生效）

3. **删除代理**（`/api/proxy/:id` DELETE）
   - 触发重载（使删除生效）

4. **启用代理**（`/api/proxy/:id/enable` POST）
   - 触发重载

5. **禁用代理**（`/api/proxy/:id/disable` POST）
   - 触发重载

### 6.2 重载流程

1. **生成配置文件**（同步）
   - 在 `proxy_management` 模块中完成

2. **触发 Nginx 重载**（异步）
   - 使用 `ngx.timer.at(0, ...)` 确保在当前请求处理完成后立即执行
   - 调用 `system_api.reload_nginx_internal()`
   - 内部会先测试配置（`openresty -t`），再执行重载（`openresty -s reload`）

## 七、关键函数说明

### 7.1 `generate_all_configs()`

**功能：** 生成所有启用的代理配置

**流程：**
1. 获取项目根目录
2. 验证 `conf.d` 目录是否存在
3. 查询所有 `status = 1` 的代理配置
4. 确保必要的目录存在
5. 为每个代理生成 upstream 和 server 配置
6. 清理已删除或禁用的代理的配置文件

**返回值：**
- `true, "配置生成成功，共生成 N 个代理配置文件"`
- `false, "错误信息"`

### 7.2 `generate_upstream_config_for_location(proxy, backends, upstream_name)`

**功能：** 为单个 location 生成 upstream 配置

**参数：**
- `proxy`：代理配置对象
- `backends`：后端服务器列表（已筛选属于该 location 的）
- `upstream_name`：upstream 名称

**返回值：** upstream 配置字符串

### 7.3 `generate_http_server_config(proxy, upstream_name, backends)`

**功能：** 生成 HTTP/HTTPS server 配置

**参数：**
- `proxy`：代理配置对象
- `upstream_name`：upstream 名称（可能是表，用于多个 location）
- `backends`：后端服务器列表

**返回值：** server 配置字符串

**特殊处理：**
- 如果 `proxy.location_paths` 存在，为每个 location 生成独立的 location 块
- 每个 location 使用对应的 upstream（通过 `upstream_name[location_path]` 获取）

### 7.4 `generate_stream_server_config(proxy, upstream_name)`

**功能：** 生成 TCP/UDP stream server 配置

**参数：**
- `proxy`：代理配置对象
- `upstream_name`：upstream 名称

**返回值：** stream server 配置字符串

### 7.5 `cleanup_orphaned_files(project_root, active_proxy_ids)`

**功能：** 清理已删除或禁用的代理的配置文件

**参数：**
- `project_root`：项目根目录
- `active_proxy_ids`：活跃代理ID映射表（`{proxy_id = true, ...}`）

**清理范围：**
- HTTP/HTTPS upstream 配置文件
- HTTP/HTTPS server 配置文件
- TCP/UDP upstream 配置文件
- TCP/UDP server 配置文件

## 八、数据流转

### 8.1 创建代理流程

```
前端提交 → API层（proxy.lua）→ 业务层（proxy_management.lua）
  ↓
验证配置 → 插入数据库 → 生成Nginx配置 → 触发Nginx重载
  ↓
返回结果给前端
```

### 8.2 更新代理流程

```
前端提交 → API层 → 业务层
  ↓
验证配置 → 更新数据库 → 重新生成Nginx配置 → 触发Nginx重载
  ↓
返回结果给前端
```

### 8.3 删除代理流程

```
前端提交 → API层 → 业务层
  ↓
删除数据库记录 → 重新生成Nginx配置（排除已删除的）→ 触发Nginx重载
  ↓
返回结果给前端
```

## 九、安全机制

### 9.1 配置值转义

所有用户输入的配置值都会经过 `escape_nginx_value()` 函数转义，防止 Nginx 配置注入攻击：

- 转义特殊字符：`;`、`\`、`"`、`'`
- 去除换行符
- 去除前后空格

### 9.2 配置验证

在插入数据库前，会进行严格的配置验证：

- 代理名称格式验证（防止SQL注入）
- 端口范围验证（1-65535）
- 后端服务器地址和端口验证
- 代理类型验证（只允许 `http`、`tcp`、`udp`）

## 十、重要说明

### 10.1 location_paths 字段要求

所有HTTP/HTTPS代理必须配置 `location_paths` 字段。如果 `location_paths` 为空或不存在，Nginx配置生成时会返回503错误。

### 10.2 字段说明

- `location_paths`：必需字段，用于多个 location（JSON格式）
- `waf_proxy_configs.location_path` 字段已被完全删除，不再存在于数据库表中

## 十一、错误处理

### 11.1 配置生成失败

- 记录错误日志
- 返回错误信息给调用者
- **不阻塞**其他代理的配置生成

### 11.2 文件写入失败

- 检查目录权限
- 检查磁盘空间
- 返回详细的错误信息

### 11.3 Nginx 重载失败

- 记录警告日志
- **不阻塞**API响应
- 管理员可以手动重载

## 十二、性能优化

### 12.1 批量生成

- 一次性查询所有启用的代理
- 一次性生成所有配置文件
- 减少数据库查询次数

### 12.2 异步重载

- 使用 `ngx.timer.at(0, ...)` 异步触发 Nginx 重载
- 不阻塞 API 响应
- 提升用户体验

### 12.3 目录检查

- 只在首次生成时检查目录是否存在
- 使用 `path_utils.ensure_dir()` 确保目录存在

## 十三、调试建议

### 13.1 查看生成的配置文件

```bash
# HTTP/HTTPS upstream配置
ls -la /path/to/project/conf.d/upstream/http_https/

# HTTP/HTTPS server配置
ls -la /path/to/project/conf.d/vhost_conf/http_https/

# TCP/UDP upstream配置
ls -la /path/to/project/conf.d/upstream/tcp_udp/

# TCP/UDP server配置
ls -la /path/to/project/conf.d/vhost_conf/tcp_udp/
```

### 13.2 查看日志

```bash
# 查看错误日志
tail -f /path/to/project/logs/error.log | grep nginx_config_generator

# 查看配置生成日志
tail -f /path/to/project/logs/error.log | grep "生成.*配置文件"
```

### 13.3 测试配置

```bash
# 测试Nginx配置语法
/usr/local/openresty/bin/openresty -t

# 查看实际生效的配置
/usr/local/openresty/bin/openresty -T
```

## 十四、总结

本系统实现了完整的**基于数据库的 Nginx 配置自动生成**功能，具有以下特点：

1. **自动化**：创建/修改/删除代理时自动生成配置
2. **灵活性**：支持 HTTP/HTTPS、TCP/UDP 多种代理类型
3. **扩展性**：支持多个 location，每个 location 独立的 upstream
4. **安全性**：配置值转义、严格验证
5. **可靠性**：错误处理、向后兼容
6. **性能**：批量生成、异步重载

通过这套机制，管理员可以通过 Web 界面轻松管理代理配置，无需手动编写 Nginx 配置文件。

