# API接口模块说明

本目录包含所有API接口处理模块，按功能分类组织。

## 目录结构

```
lua/api/
├── handler.lua                 # API 路由分发器（主入口，统一路由分发）
├── utils.lua                   # API 工具函数（响应处理、参数解析等）
├── auth.lua                    # 认证 API（登录、登出、TOTP、密码管理）
├── rules.lua                   # 规则管理 API
├── templates.lua               # 规则模板 API
├── batch.lua                   # 规则批量导入/导出 API
├── features.lua                # 功能开关管理 API
├── config_check.lua            # 配置检查 API
├── stats.lua                   # 统计报表 API
├── proxy.lua                   # 反向代理管理 API
├── system.lua                  # 系统管理 API（重载配置、系统状态等）
├── system_access_whitelist.lua # 系统访问白名单 API
├── logs.lua                    # 日志查看 API
├── performance.lua             # 性能监控与调优 API
└── README.md                   # 本文件
```

## 模块说明

### handler.lua
API路由分发器，作为所有API请求的统一入口：
- 接收nginx配置中的API请求
- 根据请求路径和方法，分发到相应的API模块
- 提供统一的API接口，保持向后兼容

### utils.lua
提供API处理中常用的工具函数：
- `json_response()` - 设置JSON响应
- `csv_response()` - 设置CSV响应
- `get_args()` - 获取请求参数（URL参数和Body参数）
- `extract_id_from_uri()` - 从URI路径提取ID
- `validate_required()` - 验证必填参数
- `parse_pagination()` - 解析分页参数

### rules.lua
规则管理API接口：
- `create()` - 创建规则
- `list()` - 查询规则列表
- `get()` - 查询规则详情
- `update()` - 更新规则
- `delete()` - 删除规则
- `enable()` - 启用规则
- `disable()` - 禁用规则

### templates.lua
模板管理API接口：
- `list()` - 获取模板列表
- `get()` - 获取模板详情
- `apply()` - 应用模板
- `list_from_db()` - 从数据库获取模板列表
- `get_from_db()` - 从数据库获取模板详情
- `apply_from_db()` - 应用数据库中的模板

### batch.lua
批量操作API接口：
- `export_json()` - 导出规则（JSON格式）
- `export_csv()` - 导出规则（CSV格式）
- `import_json()` - 导入规则（JSON格式）
- `import_csv()` - 导入规则（CSV格式）

### auth.lua
认证相关API接口：
- `login()` - 用户登录（支持TOTP双因素认证）
- `logout()` - 用户登出
- `check()` - 检查登录状态
- `me()` - 获取当前用户信息
- `setup_totp()` - 设置TOTP双因素认证
- `enable_totp()` - 启用TOTP
- `disable_totp()` - 禁用TOTP
- `hash_password()` - 生成密码哈希（管理员）
- `check_password_strength()` - 检查密码强度
- `generate_password()` - 生成随机密码（管理员）

### features.lua
功能开关管理API接口：
- `list()` - 获取所有功能开关列表
- `get()` - 获取单个功能开关状态
- `update()` - 更新功能开关状态
- `batch_update()` - 批量更新功能开关

### config_check.lua
配置检查API接口：
- `check()` - 执行配置检查
- `get_results()` - 获取配置验证结果
- `get_formatted()` - 获取格式化的配置验证结果

### stats.lua
统计报表API接口：
- `overview()` - 获取统计概览
- `timeseries()` - 获取时间序列统计数据
- `ip_stats()` - 获取IP统计信息
- `rule_stats()` - 获取规则统计信息

### proxy.lua
反向代理管理 API 接口（HTTP/HTTPS/TCP/UDP 代理）：
- `create()` / `update()` / `delete()` - 管理代理配置
- `list()` / `get()` - 查询代理配置
- `enable()` / `disable()` - 启用/禁用代理

### system.lua
系统管理API接口：
- `reload_nginx()` - 重新加载Nginx配置
- `test_nginx_config()` - 测试Nginx配置
- `get_status()` - 获取系统状态

### system_access_whitelist.lua
系统访问白名单 API 接口：
- `get_config()` / `update_config()` - 获取/更新系统访问白名单开关（启用/禁用）
- `list()` / `get()` - 查询白名单条目
- `create()` / `update()` / `delete()` - 管理白名单条目
- 内部逻辑负责在**第一条启用的条目创建时自动开启白名单**，在**最后一条启用条目删除时自动关闭白名单**，并触发配置缓存清理与审计日志。

### logs.lua
日志查看 API 接口：
- 提供访问日志、封控日志、审计日志等查询能力（具体字段见实现）。

### performance.lua
性能监控与缓存调优 API 接口：
- `get_slow_queries()` - 获取慢查询列表
- `get_stats()` - 获取整体性能统计
- `analyze_slow_queries()` - 分析慢查询（配合 `waf.performance_monitor` 与 `waf.cache_tuner` 使用）

## API路由

所有API请求通过统一的 `/api/` 路径访问，由 `handler.lua` 进行路由分发：

### 认证相关
- `POST /api/auth/login` - 用户登录
- `POST /api/auth/logout` - 用户登出
- `GET /api/auth/check` - 检查登录状态
- `GET /api/auth/me` - 获取当前用户信息
- `POST /api/auth/totp/setup` - 设置TOTP
- `POST /api/auth/totp/enable` - 启用TOTP
- `POST /api/auth/totp/disable` - 禁用TOTP
- `POST /api/auth/password/hash` - 生成密码哈希（管理员）
- `POST /api/auth/password/check` - 检查密码强度
- `POST /api/auth/password/generate` - 生成随机密码（管理员）

### 规则管理
- `GET /api/rules` - 获取规则列表
- `POST /api/rules` - 创建规则
- `GET /api/rules/{id}` - 获取规则详情
- `PUT /api/rules/{id}` - 更新规则
- `DELETE /api/rules/{id}` - 删除规则
- `POST /api/rules/{id}/enable` - 启用规则
- `POST /api/rules/{id}/disable` - 禁用规则
- `GET /api/rules/groups` - 获取规则分组列表
- `GET /api/rules/groups/stats` - 获取分组统计信息

### 批量操作
- `GET /api/rules/export/json` - 导出规则（JSON）
- `GET /api/rules/export/csv` - 导出规则（CSV）
- `POST /api/rules/import/json` - 导入规则（JSON）
- `POST /api/rules/import/csv` - 导入规则（CSV）

### 功能开关
- `GET /api/features` - 获取所有功能开关
- `GET /api/features/{key}` - 获取单个功能开关
- `PUT /api/features/{key}` - 更新功能开关
- `POST /api/features/batch` - 批量更新功能开关

### 配置检查
- `GET /api/config/check` - 执行配置检查
- `GET /api/config/results` - 获取配置验证结果
- `GET /api/config/formatted` - 获取格式化的配置验证结果

### 统计报表
- `GET /api/stats/overview` - 获取统计概览
- `GET /api/stats/timeseries` - 获取时间序列统计数据
- `GET /api/stats/ip` - 获取IP统计信息
- `GET /api/stats/rules` - 获取规则统计信息

### 反向代理
- `GET /api/proxy` - 获取代理配置列表
- `POST /api/proxy` - 创建代理配置
- `GET /api/proxy/{id}` - 获取代理配置详情
- `PUT /api/proxy/{id}` - 更新代理配置
- `DELETE /api/proxy/{id}` - 删除代理配置
- `POST /api/proxy/{id}/enable` - 启用代理配置
- `POST /api/proxy/{id}/disable` - 禁用代理配置

### 系统管理
- `POST /api/system/reload` - 重新加载Nginx配置
- `GET /api/system/test-config` - 测试Nginx配置
- `GET /api/system/status` - 获取系统状态

### 模板管理
- `GET /api/templates/list` - 获取模板列表
- `GET /api/templates/get` - 获取模板详情
- `POST /api/templates/apply` - 应用模板
- `GET /api/templates/db/list` - 从数据库获取模板列表
- `GET /api/templates/db/get` - 从数据库获取模板详情
- `POST /api/templates/db/apply` - 应用数据库中的模板

## 认证要求

**重要**：除了以下API外，所有API都需要登录认证：
- `/api/auth/login` - 登录接口
- `/api/auth/check` - 检查登录状态

其他所有API都需要在请求头中包含有效的会话Cookie（`waf_session`）。

## 使用方式

在nginx配置中通过 `handler.lua` 调用API：

```lua
local api_handler = require "api.handler"

-- 所有API请求都通过route()函数处理
api_handler.route()
```

`handler.lua` 内部会自动调用相应的API模块（`rules.lua`、`templates.lua`、`batch.lua`、`auth.lua`等）。

## 功能开关控制

部分API受功能开关控制，如果功能被禁用，API会返回403错误：
- 规则管理API：受 `rule_management_ui` 功能开关控制
- 统计报表API：受 `stats` 功能开关控制
- 反向代理API：受 `proxy_management` 功能开关控制
- 配置检查API：受 `config_check_api` 功能开关控制

## 注意事项

1. 所有API模块都依赖 `api.utils` 模块提供的工具函数
2. 业务逻辑实现在 `waf/` 目录下的相应模块中
3. API模块只负责HTTP请求处理和响应格式化
4. 错误处理统一使用 `api_utils.json_response()` 返回错误信息
5. 所有API（除登录相关）都需要登录认证
6. 部分API需要管理员权限（如密码管理、系统管理）
7. 功能开关可以通过 `/api/features` API动态控制

