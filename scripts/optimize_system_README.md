# 系统优化脚本使用说明

## 概述

`optimize_system.sh` 脚本用于根据服务器硬件信息自动优化系统和 OpenResty 配置，提高系统的负载并发能力。

## 功能特性

### 1. 硬件信息检测
- 自动检测 CPU 核心数
- 自动检测内存大小
- 自动检测系统架构和内核版本

### 2. 智能参数计算
- 根据 CPU 核心数计算最优 Worker 进程数
- 根据内存大小计算共享内存配置
- 根据硬件配置计算文件描述符限制
- 计算 Keepalive 连接数

### 3. 系统参数优化
- **文件描述符限制**：提高系统可打开文件数
- **内核网络参数**：优化 TCP 连接处理
- **内存管理**：优化内存使用策略
- **连接跟踪**：优化连接跟踪表大小

### 4. OpenResty/Nginx 配置优化
- 自动调整 `worker_processes`
- 自动调整 `worker_connections`
- 自动调整 `keepalive` 连接数
- 优化共享内存配置

## 使用方法

### 基本使用

```bash
# 使用默认配置优化
sudo ./scripts/optimize_system.sh
```

### 自定义 OpenResty 路径

```bash
# 如果 OpenResty 安装在其他位置
sudo OPENRESTY_PREFIX=/opt/openresty ./scripts/optimize_system.sh
```

## 优化内容详解

### 1. 文件描述符限制

**优化前**：通常为 1024 或 4096
**优化后**：根据硬件自动计算，最大可达 100 万

**影响**：
- 提高系统可同时处理的连接数
- 避免 "too many open files" 错误

### 2. 内核网络参数

#### net.core.somaxconn
- **默认值**：128
- **优化值**：65535
- **作用**：提高 TCP 连接队列大小

#### net.core.netdev_max_backlog
- **默认值**：1000
- **优化值**：32768
- **作用**：提高网络设备接收队列大小

#### net.ipv4.tcp_max_syn_backlog
- **默认值**：512
- **优化值**：8192
- **作用**：提高 SYN 连接队列大小

#### TCP Keepalive 优化
- `tcp_keepalive_time = 1200`：空闲连接保持时间
- `tcp_keepalive_probes = 3`：探测次数
- `tcp_keepalive_intvl = 15`：探测间隔

### 3. 内存管理优化

#### vm.overcommit_memory
- **值**：1
- **作用**：允许内存过度分配，提高性能

#### vm.swappiness
- **默认值**：60
- **优化值**：10
- **作用**：减少 swap 使用，优先使用物理内存

### 4. OpenResty 配置优化

#### worker_processes
- **计算方式**：等于 CPU 核心数
- **示例**：8 核 CPU → `worker_processes 8;`

#### worker_connections
- **固定值**：65535（最大）
- **作用**：每个 Worker 进程的最大连接数

#### 理论最大并发
- **计算公式**：`worker_processes × worker_connections`
- **示例**：8 核 × 65535 = 524,280 并发连接

#### keepalive
- **计算方式**：`worker_connections / 4`，最大 1024
- **作用**：保持与后端服务器的连接，减少连接建立开销

## 优化效果

### 性能提升

1. **并发连接数**：从数千提升到数十万
2. **响应速度**：减少连接建立时间
3. **资源利用**：充分利用多核 CPU
4. **稳定性**：减少连接错误和超时

### 实际案例

**优化前**：
- 最大并发：约 10,000
- 文件描述符：4,096
- Worker 进程：1

**优化后**（8 核 CPU，16GB 内存）：
- 最大并发：524,280
- 文件描述符：1,048,576
- Worker 进程：8

## 注意事项

### 1. 文件描述符限制

文件描述符限制需要**重新登录**才能完全生效，或者运行：

```bash
ulimit -n <计算出的值>
```

### 2. 内核参数

内核参数优化已写入 `/etc/sysctl.conf`，需要：
- 立即生效：`sysctl -p`
- 永久生效：重启系统（或已自动应用）

### 3. 配置备份

脚本会自动创建备份，位置：
```
$project_root/backup/optimize_YYYYMMDD_HHMMSS/
```

备份内容包括：
- `/etc/security/limits.conf` - 文件描述符限制配置
- `/etc/sysctl.conf` - 内核参数配置
- `/usr/local/openresty/nginx/conf/nginx.conf` - Nginx 主配置
- `$project_root/conf.d/set_conf/performance.conf` - 性能配置

**恢复备份**：
```bash
# 恢复系统配置
sudo cp backup/optimize_*/limits.conf.bak /etc/security/limits.conf
sudo cp backup/optimize_*/sysctl.conf.bak /etc/sysctl.conf
sudo sysctl -p

# 恢复 Nginx 配置
sudo cp backup/optimize_*/nginx.conf.bak /usr/local/openresty/nginx/conf/nginx.conf
cp backup/optimize_*/performance.conf.bak conf.d/set_conf/performance.conf
```

### 4. 验证配置

优化后务必验证配置：

```bash
# 测试 Nginx 配置
/usr/local/openresty/bin/openresty -t

# 查看当前限制
ulimit -n
sysctl net.core.somaxconn
```

### 5. 恢复配置

如需恢复，从备份目录恢复文件：

```bash
# 恢复系统配置
sudo cp backup/optimize_*/limits.conf.bak /etc/security/limits.conf
sudo cp backup/optimize_*/sysctl.conf.bak /etc/sysctl.conf
sysctl -p

# 恢复 Nginx 配置
sudo cp backup/optimize_*/nginx.conf.bak /usr/local/openresty/nginx/conf/nginx.conf
```

## 优化参数说明

### 根据硬件自动计算的参数

| 参数 | 计算方式 | 说明 |
|------|---------|------|
| worker_processes | CPU 核心数 | 充分利用多核 |
| worker_connections | 65535（固定） | 每个 Worker 最大连接数 |
| 文件描述符限制 | worker_processes × worker_connections × 2 | 最大 100 万 |
| keepalive | worker_connections / 4 | 最大 1024 |
| 共享内存 | 总内存的 1% | 最小 100MB，最大 500MB |

### 固定优化值

| 参数 | 优化值 | 说明 |
|------|--------|------|
| net.core.somaxconn | 65535 | TCP 连接队列 |
| net.core.netdev_max_backlog | 32768 | 网络设备队列 |
| net.ipv4.tcp_max_syn_backlog | 8192 | SYN 队列 |
| vm.swappiness | 10 | 减少 swap |

## 故障排查

### 问题 1：文件描述符限制未生效

**症状**：运行 `ulimit -n` 仍显示旧值

**解决**：
```bash
# 方法 1：重新登录
exit
# 重新 SSH 登录

# 方法 2：临时设置（当前会话）
ulimit -n <计算出的值>

# 方法 3：检查 limits.conf
cat /etc/security/limits.conf | grep nofile
```

### 问题 2：内核参数未生效

**症状**：`sysctl` 显示旧值

**解决**：
```bash
# 手动应用
sudo sysctl -p

# 检查配置
sudo sysctl -a | grep somaxconn
```

### 问题 3：Nginx 配置错误

**症状**：`openresty -t` 报错

**解决**：
```bash
# 查看详细错误
/usr/local/openresty/bin/openresty -t

# 恢复备份
sudo cp backup/optimize_*/nginx.conf.bak /usr/local/openresty/nginx/conf/nginx.conf
```

## 性能测试建议

优化后建议进行压力测试：

```bash
# 使用 ab 工具测试
ab -n 100000 -c 1000 http://your-server/

# 使用 wrk 工具测试（更准确）
wrk -t8 -c1000 -d30s http://your-server/
```

## 相关文档

- [性能优化指南](../docs/性能优化指南.md)
- [部署文档](../docs/部署文档.md)
- [Nginx 官方文档](http://nginx.org/en/docs/)

---

**注意**：系统优化涉及系统级配置，请在生产环境使用前充分测试。

