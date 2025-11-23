# Web前端文件目录

本目录存放所有Web前端文件（HTML、CSS、JavaScript等）。

## 目录结构

```
lua/web/
├── handler.lua              # Web路由分发器（主入口）
├── login.html               # 登录页面
├── features.html            # 功能管理界面
├── rule_management.html     # 规则管理界面
├── proxy_management.html    # 反向代理管理界面
├── stats.html               # 统计报表界面
├── monitor.html             # 监控面板界面
└── README.md                # 本文件
```

## 文件说明

### handler.lua
Web路由分发器，作为所有Web请求的统一入口：
- 处理所有非 `/api/*` 路径的请求
- 根据请求路径返回相应的HTML文件
- 处理登录认证和功能开关检查
- 支持Prometheus指标导出（`/metrics`）

### login.html
用户登录页面，提供以下功能：
- 用户名密码登录
- TOTP双因素认证支持
- 登录状态保持
- 自动重定向到原请求页面

### features.html
功能管理界面，提供以下功能：
- 查看所有功能开关状态
- 启用/禁用功能开关
- 批量更新功能开关
- 功能说明和描述

### rule_management.html
WAF规则管理Web界面，提供以下功能：
- 规则列表管理（查看、编辑、启用/禁用、删除）
- 创建规则（单个IP、IP段、地域封控）
- 规则分组管理
- 分页显示
- 过滤和搜索功能
- 规则导入/导出（JSON、CSV）

### proxy_management.html
反向代理管理界面，提供以下功能：
- 代理配置列表管理
- 创建代理配置（HTTP、TCP、UDP）
- 编辑代理配置
- 启用/禁用代理配置
- 后端服务器管理（upstream）

### stats.html
统计报表界面，提供以下功能：
- 封控统计概览
- 时间序列统计图表
- IP访问统计
- 规则效果统计

### monitor.html
监控面板界面，提供以下功能：
- 系统运行状态
- 实时监控指标
- 性能指标展示
- 告警信息显示

## 部署说明

前端文件存放在 `lua/web/` 目录下，nginx配置会自动从该目录读取文件。

文件路径通过Lua代码动态获取项目根目录，然后拼接 `/lua/web/rule_management.html` 路径。

## 访问路径

所有Web界面都需要登录后才能访问（除了登录页面）：

- 登录页面：`http://your-domain/login`
- 管理首页：`http://your-domain/` 或 `http://your-domain/admin`
- 功能管理界面：`http://your-domain/admin/features`
- 规则管理界面：`http://your-domain/admin/rules`（受 `rule_management_ui` 功能开关控制）
- 反向代理管理界面：`http://your-domain/admin/proxy`（受 `proxy_management` 功能开关控制）
- 统计报表界面：`http://your-domain/admin/stats`（受 `stats` 功能开关控制）
- 监控面板界面：`http://your-domain/admin/monitor`（受 `monitor` 功能开关控制）
- Prometheus指标：`http://your-domain/metrics`（需要登录，受 `metrics` 配置控制）

## 功能开关控制

部分Web界面受功能开关控制，如果功能被禁用，访问会返回403错误：
- 规则管理界面：受 `rule_management_ui` 功能开关控制
- 统计报表界面：受 `stats` 功能开关控制
- 监控面板界面：受 `monitor` 功能开关控制
- 反向代理管理界面：受 `proxy_management` 功能开关控制

功能管理界面（`/admin/features`）必须可用，用于管理功能开关。

## 开发说明

前端文件使用原生HTML/CSS/JavaScript实现，不依赖外部框架，可以直接在浏览器中打开或通过nginx访问。

如果需要使用前端框架（如Vue、React等），可以将构建后的文件放在此目录下。

## 认证机制

所有Web界面（除了登录页面）都需要登录认证：
1. 未登录用户访问受保护页面时，会自动重定向到登录页面
2. 登录成功后，会重定向回原请求页面
3. 会话信息存储在Cookie中（`waf_session`）
4. 支持TOTP双因素认证

## 路由处理

所有Web请求由 `handler.lua` 统一处理：
- `/login` - 登录页面（不需要认证）
- `/metrics` - Prometheus指标（需要登录）
- `/admin/*` - 管理界面（需要登录）
- 其他路径 - 404页面

