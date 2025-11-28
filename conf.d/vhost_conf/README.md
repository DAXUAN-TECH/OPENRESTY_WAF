# WAF 管理服务配置文件说明

## 文件说明

- **`default.conf`**：HTTP 服务器模板配置，用于代理到后端服务器
- **`waf.conf`**：WAF 管理服务配置，提供 WAF 管理相关的 API 端点和 Web 管理界面

## Location 模块分类

### 1. 必须保留的 Location（核心功能）

这些 location 是系统运行所必需的，**不能删除**：

- **`/api/`** - API统一入口（必须）
  - 所有API请求都通过此location处理
  - `/api/features` - 功能管理API（必须）
  - `/api/auth/*` - 认证API（登录、登出、TOTP、密码管理）
  - `/api/rules/*` - 规则管理API（受功能开关控制）
  - `/api/stats/*` - 统计报表API（受功能开关控制）
  - `/api/proxy/*` - 反向代理管理API（受功能开关控制）
  - `/api/system/*` - 系统管理API
  - `/api/config/*` - 配置检查API（受功能开关控制）
  - `/api/templates/*` - 模板管理API
  - 路由逻辑在 `lua/api/handler.lua` 中实现

- **`/`** - Web管理界面（统一入口，必须）
  - 所有管理界面都通过此入口访问
  - `/login` - 登录页面（不需要认证）
  - `/admin` 或 `/admin/` - 管理首页
  - `/admin/features` - 功能管理界面（必须可用）
  - `/admin/rules` - 规则管理界面（受 `rule_management_ui` 功能开关控制）
  - `/admin/proxy` - 反向代理管理界面（受 `proxy_management` 功能开关控制）
  - `/admin/stats` - 统计报表界面（受 `stats` 功能开关控制）
  - `/admin/monitor` - 监控面板界面（受 `monitor` 功能开关控制）
  - `/metrics` - Prometheus指标导出（需要登录，受 `metrics` 配置控制）
  - 路由逻辑在 `lua/web/handler.lua` 中实现

- **`/metrics`** - Prometheus 指标导出（可选但推荐）
  - 受 `config.metrics.enable` 控制
  - 如果不需要监控，可以注释掉

### 2. 通过功能开关控制的 Location

这些 location 的功能可以通过数据库功能开关控制，**location 本身需要保留**，但功能会在代码中检查开关状态：

#### 规则管理相关（受 `rule_management_ui` 功能开关控制）

- `/api/rules/*` - 所有规则管理 API
  - 包括：创建、查询、更新、删除、启用、禁用、审批等
  - 如果 `rule_management_ui` 被禁用，这些 API 会返回 403

- `/api/rules/export/*` - 规则导出 API
  - JSON 和 CSV 格式导出
  - 受 `rule_management_ui` 功能开关控制

- `/api/rules/import/*` - 规则导入 API
  - JSON 和 CSV 格式导入
  - 受 `rule_management_ui` 功能开关控制

- `/admin/rules` - 规则管理界面
  - Web 界面，用于管理规则
  - 受 `rule_management_ui` 功能开关控制
  - 通过统一的 `/admin/` location 访问

#### 配置检查相关（受 `config_check_api` 功能开关控制）

- `/api/config/check` - 执行配置检查
- `/api/config/results` - 获取配置验证结果
- `/api/config/formatted` - 获取格式化的配置验证结果

### 3. 可选 Location（没有功能开关控制）

这些 location 目前**没有功能开关控制**，如果不需要可以**注释掉**：

- `/api/templates/*` - 规则模板管理 API
  - 包括：获取模板列表、获取模板详情、应用模板等
  - 如果不需要模板功能，可以注释掉这些 location 块

## 功能开关管理

### 如何启用/禁用功能

1. **通过 Web 界面**：访问 `/admin/features`
2. **通过 API**：调用 `/api/features` 接口
3. **通过数据库**：直接修改 `waf_feature_switches` 表

### 功能开关列表

- `rule_management_ui` - 规则管理界面（默认：启用）
- `config_check_api` - 配置检查 API（默认：启用）
- `stats` - 统计报表功能（默认：启用）
- `monitor` - 监控面板功能（默认：启用）
- `proxy_management` - 反向代理管理功能（默认：启用）
- `ip_block` - IP 封控功能（默认：启用）
- `geo_block` - 地域封控功能（默认：启用）
- `auto_block` - 自动封控功能（默认：启用）
- `whitelist` - 白名单功能（默认：启用）
- `log_collect` - 日志采集功能（默认：启用）
- `metrics` - 监控指标功能（默认：启用）
- `alert` - 告警功能（默认：启用）
- `cache_warmup` - 缓存预热功能（默认：启用）
- `rule_backup` - 规则备份功能（默认：启用）
- `testing` - 测试功能（默认：启用）
- `config_validation` - 配置验证功能（默认：启用）

## 配置建议

### 最小化配置（只保留核心功能）

如果只需要基本的功能管理，可以注释掉以下 location：

1. 规则管理相关（如果不需要规则管理功能）
   - 注释掉 `/api/rules/*` 相关 location
   - 注释掉 `/admin/rules` location

2. 配置检查相关（如果不需要配置检查功能）
   - 注释掉 `/api/config/*` 相关 location

3. 模板管理相关（如果不需要模板功能）
   - 注释掉 `/api/templates/*` 相关 location

4. 监控指标（如果不需要监控）
   - 注释掉 `/metrics` location

### 完整配置（保留所有功能）

保留所有 location 块，通过功能开关控制功能的启用/禁用。

## 注意事项

1. **功能管理 API 必须保留**：`/api/features` 和 `/admin/features` 是管理其他功能的基础，不能删除。

2. **Location 定义 vs 功能开关**：
   - Location 定义需要在配置文件中保留（即使功能被禁用）
   - 功能开关控制的是功能逻辑，不是 location 的存在
   - 如果功能被禁用，API 会返回 403 错误

3. **如果完全不需要某个功能**：
   - 可以注释掉对应的 location 块
   - 这样可以减少配置文件大小，但需要重新加载配置才能生效

4. **安全建议**：
   - 所有管理 API 建议限制为内网访问
   - 取消注释 `allow` 和 `deny` 指令来限制访问

## 配置结构说明

**重要**：`waf.conf` 使用统一的location结构：

1. **`location /api/`** - 所有API请求的统一入口
   - 路由分发在 `lua/api/handler.lua` 中实现
   - 支持所有API端点（认证、规则、统计、代理等）

2. **`location /`** - 所有Web界面的统一入口
   - 路由分发在 `lua/web/handler.lua` 中实现
   - 支持所有Web页面（登录、管理界面、监控等）

**优势**：
- 前后端各只有一个location，配置简洁
- 路由逻辑在Lua代码中实现，易于维护
- 功能开关控制灵活，无需修改配置文件

## 示例：最小化配置

```nginx
# API统一入口（必须）
location /api/ {
    content_by_lua_block {
        local api_handler = require "api.handler"
        api_handler.route()
    }
}

# Web界面统一入口（必须）
location / {
    content_by_lua_block {
        local web_handler = require "web.handler"
        web_handler.route()
    }
}
```

所有功能通过功能开关控制，无需修改配置文件。

