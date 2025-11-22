# OpenResty + MySQL IP 采集与封控系统

基于 OpenResty 和 MySQL 的 Web 应用防火墙（WAF）系统，实现 IP 访问日志采集和智能封控功能。

## 📋 项目概述

本项目实现了一个高性能的 IP 采集与封控系统，主要功能包括：

1. **IP 采集**：实时采集客户端 IP、请求路径、响应状态码等信息
2. **IP 封控**：支持单个 IP、IP 段、地域等多种封控方式
3. **规则管理**：灵活的封控规则配置和管理
4. **日志分析**：访问日志查询和统计分析

## ✨ 核心特性

- 🚀 **高性能**：基于 OpenResty，支持 10,000+ QPS
- 🔒 **灵活封控**：支持单个 IP、IP 段（CIDR）、地域封控
- 📊 **实时采集**：异步批量写入，不阻塞请求
- 🎯 **精确识别**：支持代理环境下的真实 IP 识别
- 💾 **数据持久化**：MySQL 存储，支持复杂查询
- ⚡ **缓存优化**：本地 LRU 缓存 + Redis 分布式缓存
- 🛡️ **白名单机制**：防止误封正常用户

## 🏗️ 系统架构

```
客户端请求
    ↓
OpenResty (access_by_lua: 封控检查)
    ↓
后端应用处理
    ↓
OpenResty (log_by_lua: 日志采集)
    ↓
MySQL 数据库
```

## 📁 项目结构

```
OPENRESTY_WAF/
├── 01-可行性分析.md          # 可行性分析文档
├── 02-需求文档.md            # 需求文档
├── 03-技术实施方案.md        # 技术实施方案
├── 04-数据库设计.sql        # 数据库表结构
├── 05-nginx.conf            # Nginx 主配置文件
├── 06-waf.conf             # WAF 配置文件
├── 07-部署文档.md           # 部署文档
├── 08-地域封控使用示例.md    # 地域封控使用示例
├── README.md                # 项目说明
├── scripts/                 # 安装脚本目录
│   ├── install_geoip.sh    # GeoIP2 数据库安装脚本
│   └── README.md            # 脚本说明
└── lua/                     # Lua 脚本目录
    ├── config.lua           # 配置文件
    └── waf/                 # WAF 模块
        ├── init.lua         # 初始化模块
        ├── ip_block.lua     # IP 封控模块
        ├── ip_utils.lua     # IP 工具函数
        ├── log_collect.lua  # 日志采集模块
        └── mysql_pool.lua   # MySQL 连接池
```

## 🚀 快速开始

### 1. 环境要求

- OpenResty 1.21.4.1+
- MySQL 8.0+ 或 MariaDB 10.6+
- Redis 5.0+（可选）

### 2. 安装依赖

```bash
# 安装 OpenResty（以 CentOS 为例）
sudo yum install -y openresty openresty-resty

# 安装 Lua 模块
opm get openresty/lua-resty-mysql
opm get openresty/lua-resty-redis  # 可选
```

### 3. 数据库配置

```bash
# 创建数据库
mysql -u root -p < 04-数据库设计.sql

# 修改配置文件中的数据库连接信息
vim lua/config.lua
```

### 4. 安装 GeoIP2 数据库（可选，用于地域封控）

```bash
# 使用一键安装脚本（推荐）
sudo ./scripts/install_geoip.sh YOUR_LICENSE_KEY

# 或者交互式输入 License Key
sudo ./scripts/install_geoip.sh
```

**注意**：
- 需要有效的 MaxMind License Key
- 如果不使用地域封控功能，可以跳过此步骤
- 详细说明请参考 `scripts/README.md`

### 5. 部署文件

```bash
# 复制配置文件
sudo cp 05-nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
sudo cp 06-waf.conf /usr/local/openresty/nginx/conf/waf.conf

# 复制 Lua 脚本
sudo cp -r lua/* /usr/local/openresty/nginx/lua/
```

### 6. 启动服务

```bash
# 测试配置
sudo /usr/local/openresty/bin/openresty -t

# 启动服务
sudo /usr/local/openresty/bin/openresty
```

详细部署步骤请参考 [部署文档](07-部署文档.md)

## 📖 文档说明

- [可行性分析](01-可行性分析.md) - 技术可行性、风险评估、成本效益分析
- [需求文档](02-需求文档.md) - 功能需求、非功能需求、数据需求
- [技术实施方案](03-技术实施方案.md) - 架构设计、实现方案、性能优化
- [数据库设计](04-数据库设计.sql) - 表结构设计、索引优化
- [部署文档](07-部署文档.md) - 安装步骤、配置说明、故障排查

## 🔧 配置说明

### 数据库配置

编辑 `lua/config.lua`：

```lua
_M.mysql = {
    host = "127.0.0.1",
    port = 3306,
    database = "waf_db",
    user = "waf_user",
    password = "your_password",
    pool_size = 50,
}
```

### 日志配置

```lua
_M.log = {
    batch_size = 100,        -- 批量写入大小
    batch_interval = 1,      -- 批量写入间隔（秒）
    enable_async = true,     -- 是否异步写入
}
```

### 封控配置

```lua
_M.block = {
    enable = true,           -- 是否启用封控
    block_page = "...",      -- 封控页面 HTML
}
```

## 📊 使用示例

### 添加封控规则

```sql
-- 单个 IP 封控
INSERT INTO block_rules (rule_type, rule_value, rule_name, status, priority)
VALUES ('single_ip', '192.168.1.100', '封控恶意IP', 1, 100);

-- IP 段封控（CIDR）
INSERT INTO block_rules (rule_type, rule_value, rule_name, status, priority)
VALUES ('ip_range', '192.168.1.0/24', '封控IP段', 1, 90);

-- IP 范围封控
INSERT INTO block_rules (rule_type, rule_value, rule_name, status, priority)
VALUES ('ip_range', '192.168.1.1-192.168.1.100', '封控IP范围', 1, 90);
```

### 添加白名单

```sql
INSERT INTO whitelist (ip_type, ip_value, description, status)
VALUES ('single_ip', '192.168.1.50', '管理员IP', 1);
```

### 查询访问日志

```sql
-- 查询最近 1 小时的访问记录
SELECT * FROM access_logs 
WHERE request_time >= DATE_SUB(NOW(), INTERVAL 1 HOUR)
ORDER BY request_time DESC;

-- 统计 IP 访问次数
SELECT client_ip, COUNT(*) as count 
FROM access_logs 
WHERE request_time >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
GROUP BY client_ip 
ORDER BY count DESC;
```

## 🎯 功能特性

### IP 采集功能

- ✅ 采集客户端真实 IP（支持代理环境）
- ✅ 采集请求路径、方法、状态码
- ✅ 采集 User-Agent、Referer
- ✅ 异步批量写入，不阻塞请求
- ✅ 支持高并发场景

### IP 封控功能

- ✅ 单个 IP 精确封控
- ✅ IP 段封控（CIDR 格式）
- ✅ IP 范围封控（起始-结束）
- ✅ 地域封控（基于 GeoIP2）
- ✅ 白名单机制（优先级最高）
- ✅ 规则优先级管理
- ✅ 定时生效/失效

### 性能优化

- ✅ 本地 LRU 缓存
- ✅ Redis 分布式缓存（可选）
- ✅ 数据库连接池
- ✅ 异步批量写入
- ✅ IP 整数比较优化

## 🔍 监控与运维

### 查看日志

```bash
# 错误日志
tail -f /usr/local/openresty/nginx/logs/error.log

# 访问日志
tail -f /usr/local/openresty/nginx/logs/access.log
```

### 性能监控

```bash
# 查看进程状态
ps aux | grep nginx

# 查看连接数
netstat -an | grep :80 | wc -l

# 查看数据库连接
mysql -u waf_user -p -e "SHOW PROCESSLIST;"
```

## ⚠️ 注意事项

1. **生产环境**：务必修改默认密码和配置
2. **性能调优**：根据实际负载调整连接池和缓存大小
3. **数据备份**：定期备份数据库，建议每日备份
4. **日志归档**：定期归档历史日志，避免数据库过大
5. **安全加固**：配置防火墙、使用 HTTPS、限制管理接口访问

## 🐛 故障排查

### 常见问题

1. **配置文件错误**
   - 检查 `nginx -t` 输出
   - 检查 Lua 模块路径

2. **数据库连接失败**
   - 检查 MySQL 服务状态
   - 检查用户名密码
   - 检查防火墙规则

3. **性能问题**
   - 检查数据库连接池配置
   - 检查缓存是否生效
   - 检查系统资源使用

详细故障排查请参考 [部署文档](07-部署文档.md)

## 📝 开发计划

- [x] 基础 IP 采集功能
- [x] 单个 IP 封控
- [x] IP 段封控（CIDR）
- [x] 白名单机制
- [ ] 地域封控（需要 GeoIP2 数据库）
- [ ] 管理 API 接口
- [ ] Web 管理界面
- [ ] 自动封控规则（基于访问频率）

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

本项目采用 MIT 许可证。

## 📞 联系方式

如有问题或建议，请提交 Issue。

---

**注意**：本项目仅供学习和参考使用，生产环境使用前请充分测试。

