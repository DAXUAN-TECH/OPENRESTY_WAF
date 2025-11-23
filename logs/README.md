# 日志目录

此目录用于存放 OpenResty WAF 系统的日志文件。

## 日志文件说明

### 错误日志
- **文件**: `error.log`
- **说明**: Nginx/OpenResty 的错误日志，记录服务器运行过程中的错误和警告信息
- **路径**: `$project_root/logs/error.log`

### 访问日志
- **文件**: `access.log`
- **说明**: HTTP 访问日志，记录所有客户端请求的详细信息
- **路径**: `$project_root/logs/access.log`

### PID 文件
- **文件**: `nginx.pid`
- **说明**: Nginx 主进程的进程 ID 文件
- **路径**: `$project_root/logs/nginx.pid`

## 日志配置

日志路径在以下配置文件中定义：

1. **主配置文件**: `init_file/nginx.conf`
   - `error_log`: 错误日志路径
   - `pid`: PID 文件路径

2. **日志配置文件**: `conf.d/set_conf/log.conf`
   - `access_log`: 访问日志路径和格式

## 日志轮转

建议配置日志轮转（logrotate）以防止日志文件过大：

```bash
# /etc/logrotate.d/openresty-waf
/path/to/project/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0644 nobody nobody
    sharedscripts
    postrotate
        /usr/local/openresty/bin/openresty -s reopen
    endscript
}
```

## 权限设置

日志目录权限：
- 目录权限: `755`
- 文件权限: `644`
- 所有者: `nobody:nobody`（与 Nginx worker 进程用户一致）

## 注意事项

1. **磁盘空间**: 定期检查日志文件大小，避免占用过多磁盘空间
2. **日志级别**: 错误日志级别可在 `nginx.conf` 中调整（debug/info/notice/warn/error/crit）
3. **日志格式**: 访问日志格式可在 `log.conf` 中自定义
4. **日志分析**: 可以使用工具如 `goaccess`、`awstats` 等分析访问日志

## 查看日志

```bash
# 实时查看错误日志
tail -f logs/error.log

# 实时查看访问日志
tail -f logs/access.log

# 查看最近的错误
tail -n 100 logs/error.log

# 搜索特定错误
grep -i error logs/error.log
```

