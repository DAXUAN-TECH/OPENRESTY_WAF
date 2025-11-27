# 文件描述符限制快速修复脚本

## 用途

快速修复 OpenResty WAF 系统中的 "worker_connections exceed open file resource limit" 警告。

## 问题说明

当 Nginx 配置的 `worker_connections` 超过系统文件描述符限制时，会出现以下警告：

```
32768 worker_connections exceed open file resource limit: 1024
```

这会导致 Nginx 无法创建足够的连接，影响系统性能。

## 使用方法

### 方法 1：运行快速修复脚本（推荐）

```bash
cd /data/OPENRESTY_WAF
sudo ./scripts/fix_file_descriptor_limit.sh
```

脚本会自动：
1. 检测当前配置（内存、CPU、worker_connections）
2. 计算所需的文件描述符限制
3. 更新 `/etc/security/limits.conf`
4. 更新 systemd 服务文件（如果存在）
5. 应用临时限制（当前会话）

### 方法 2：手动修复

#### 步骤 1：编辑 limits.conf

```bash
sudo vi /etc/security/limits.conf
```

添加以下内容（注意：脚本会自动检测 OpenResty 运行用户并添加）：

```
# OpenResty WAF 文件描述符限制
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
nobody soft nofile 65535
nobody hard nofile 65535
waf soft nofile 65535
waf hard nofile 65535
```

**说明**：
- 如果 OpenResty 以 `waf` 用户运行（推荐），需要添加 `waf` 用户
- 脚本会自动检测 OpenResty 的运行用户并添加到配置中

#### 步骤 2：更新 systemd 服务文件（如果使用 systemd）

```bash
sudo vi /etc/systemd/system/openresty.service
```

在 `[Service]` 部分添加：

```ini
[Service]
LimitNOFILE=65535
```

然后重新加载配置：

```bash
sudo systemctl daemon-reload
```

#### 步骤 3：重启 OpenResty

```bash
sudo systemctl restart openresty
```

或者：

```bash
sudo /usr/local/openresty/bin/openresty -s reload
```

## 验证修复

### 1. 检查当前限制

```bash
ulimit -n
```

应该显示计算出的值（如 65535 或更高）。

### 2. 检查 Nginx worker 进程的限制

```bash
cat /proc/$(pgrep -f "nginx: worker" | head -1)/limits | grep "Max open files"
```

### 3. 检查错误日志

```bash
tail -f /data/OPENRESTY_WAF/logs/error.log
```

确认警告已消失。

## 注意事项

1. **需要重新登录**：`/etc/security/limits.conf` 的更改需要重新登录才能完全生效。
2. **systemd 服务**：如果使用 systemd 管理 OpenResty，需要在服务文件中设置 `LimitNOFILE`。
3. **临时限制**：脚本会应用临时限制（当前会话），但重新登录后会自动应用永久限制。

## 计算规则

文件描述符限制的计算公式：

```
限制 = worker_processes × worker_connections × 2
```

其中：
- `worker_processes` = CPU 核心数
- `worker_connections` = 根据内存自动计算：
  - 低内存（<2GB）：10240
  - 中等内存（2GB-8GB）：32768
  - 高内存（>=8GB）：65535

最终限制值：
- 最小值：65535
- 最大值：1000000

## 相关文档

- [故障排查：文件描述符和权限问题](../docs/故障排查-文件描述符和权限问题.md)
- [系统优化脚本](../scripts/optimize_system.sh)
- [性能优化指南](../docs/性能优化指南.md)

