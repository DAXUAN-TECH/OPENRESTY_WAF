-- WAF 配置文件
-- 路径：项目目录下的 lua/config.lua（保持在项目目录，不复制到系统目录）

local _M = {}

-- MySQL 配置
_M.mysql = {
    host = "127.0.0.1",
    port = 3306,
    database = "waf_db",
    user = "waf_user",
    password = "waf_password",
    max_packet_size = 1024 * 1024,
    pool_size = 50,  -- 连接池大小
    pool_timeout = 10000,  -- 连接池超时（毫秒）
}

-- Redis 配置（可选）
_M.redis = {
    host = "127.0.0.1",
    port = 6379,
    password = nil,
    db = 0,
    timeout = 1000,  -- 超时时间（毫秒）
    pool_size = 100,
}

-- 缓存配置
_M.cache = {
    ttl = 60,  -- 缓存过期时间（秒）
    max_items = 10000,  -- 最大缓存项数
    rule_list_ttl = 300,  -- IP 段规则列表缓存时间（秒，5分钟）
}

-- 日志配置
_M.log = {
    batch_size = 100,  -- 批量写入大小
    batch_interval = 1,  -- 批量写入间隔（秒）
    enable_async = true,  -- 是否异步写入
    max_retry = 3,  -- 最大重试次数
    retry_delay = 0.1,  -- 重试延迟（秒）
    buffer_warn_threshold = 0.8,  -- 缓冲区警告阈值（80%）
}

-- 封控配置
_M.block = {
    enable = true,  -- 是否启用封控
    block_page = [[
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Access Denied</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #d32f2f; }
    </style>
</head>
<body>
    <h1>403 Forbidden</h1>
    <p>Your access has been denied.</p>
</body>
</html>
    ]],
}

-- 白名单配置
_M.whitelist = {
    enable = true,  -- 是否启用白名单
}

-- 地域封控配置
_M.geo = {
    enable = false,  -- 是否启用地域封控
    -- GeoIP2 数据库路径（相对于项目根目录）
    -- 使用 GeoLite2-City.mmdb 以支持省市级别查询
    -- 数据库文件需要放在项目目录的 lua/geoip/ 下
    -- 路径会在运行时动态获取
    geoip_db_path = nil,  -- 将在 init_by_lua 中动态设置
}

return _M

