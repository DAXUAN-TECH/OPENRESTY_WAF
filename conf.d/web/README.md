# Web静态文件目录

本目录存放Web相关的静态文件，包括错误页面、模板文件等。

## 目录说明

```
conf.d/web/
├── 403_waf.html    # WAF系统访问白名单403错误页面
└── README.md       # 本文件
```

## 文件说明

### 403_waf.html

WAF系统访问白名单的403错误页面模板文件。

**用途：**
- 当系统访问白名单功能启用时，未在白名单中的IP访问WAF管理系统时显示此页面
- 用于替代在Nginx配置中直接嵌入HTML内容，避免Lua长括号语法冲突问题

**特点：**
- 使用占位符 `{{IP_ADDRESS}}` 动态插入客户端IP地址
- 美观的渐变背景和现代化UI设计
- 响应式布局，适配不同屏幕尺寸
- 包含详细的错误说明和操作指引

**使用方式：**
- 在 `conf.d/vhost_conf/waf.conf` 的 `access_by_lua_block` 中读取此文件
- 使用 `gsub()` 函数替换 `{{IP_ADDRESS}}` 占位符
- 如果文件读取失败，使用简单的fallback错误信息

**文件路径：**
- 项目根目录：`conf.d/web/403_waf.html`
- 在Lua代码中通过 `path_utils.get_project_root() .. "/conf.d/web/403_waf.html"` 访问

**修改说明：**
- 可以直接编辑此HTML文件来修改403错误页面的样式和内容
- 修改后需要重启OpenResty服务才能生效
- 建议保持 `{{IP_ADDRESS}}` 占位符，确保IP地址能正确显示

## 注意事项

1. **文件权限：** 确保OpenResty运行用户（通常是 `nobody`）对此文件有读取权限
2. **文件路径：** 文件路径是相对于项目根目录的，确保路径正确
3. **占位符：** 不要删除或修改 `{{IP_ADDRESS}}` 占位符，否则IP地址无法正确显示
4. **编码：** 文件使用UTF-8编码，确保中文字符正确显示

## 相关文件

- `conf.d/vhost_conf/waf.conf` - 使用此文件的Nginx配置文件
- `lua/waf/path_utils.lua` - 提供项目根目录路径的工具模块

