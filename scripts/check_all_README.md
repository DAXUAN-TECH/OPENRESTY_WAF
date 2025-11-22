# 项目检查脚本使用说明

## 概述

`check_all.sh` 是一个项目全面检查脚本，用于自动检查项目的代码质量、脚本逻辑完整性、路径配置正确性等，帮助发现潜在问题。

## 功能特性

### 1. 脚本文件检查
- ✅ 检查执行权限
- ✅ 检查 shebang（`#!/bin/bash`）
- ✅ 检查错误处理（`set -e`）

### 2. 重复逻辑检查
- ✅ 检查重复的函数定义
- ✅ 检查重复的代码块（如 PROJECT_ROOT 获取逻辑）

### 3. 路径引用检查
- ✅ 检查硬编码路径（应使用变量）
- ✅ 检查占位符路径（应使用 PROJECT_ROOT）

### 4. 脚本逻辑完整性检查
- ✅ 检查 `install_geoip.sh` 的关键函数
- ✅ 检查 `update_geoip.sh` 的关键函数
- ✅ 检查 `deploy.sh` 的关键逻辑

### 5. 文件存在性检查
- ✅ 检查必要的配置文件
- ✅ 检查必要的 Lua 脚本文件

## 使用方法

### 基本使用

```bash
# 运行检查脚本
./scripts/check_all.sh
```

### 输出说明

脚本会输出详细的检查结果：

```
========================================
项目全面检查
========================================

[1/5] 检查脚本文件...
✓ deploy.sh 有执行权限
✓ install_geoip.sh 有执行权限
...

[2/5] 检查重复逻辑...
✓ 未发现重复的函数定义
⚠ 多个脚本中有相同的 PROJECT_ROOT 获取逻辑（可提取为公共函数）

[3/5] 检查路径引用...
✓ 未发现硬编码路径
✓ 未发现占位符路径

[4/5] 检查脚本逻辑完整性...
✓ install_geoip.sh 逻辑完整
✓ update_geoip.sh 逻辑完整
✓ deploy.sh 逻辑完整

[5/5] 检查必要文件...
✓ nginx.conf 存在
✓ conf.d/set_conf/lua.conf 存在
...

========================================
检查完成
========================================

错误: 0
警告: 1

⚠ 有警告，但无错误
```

## 检查项详解

### 1. 脚本文件检查

#### 执行权限
- **检查内容**：脚本是否有执行权限（`chmod +x`）
- **问题示例**：`check_warning "deploy.sh 缺少执行权限"`
- **解决方法**：`chmod +x scripts/deploy.sh`

#### Shebang
- **检查内容**：脚本第一行是否为 `#!/bin/bash`
- **问题示例**：`check_warning "deploy.sh 缺少或错误的 shebang"`
- **解决方法**：在脚本第一行添加 `#!/bin/bash`

#### 错误处理
- **检查内容**：脚本是否使用 `set -e`（遇到错误立即退出）
- **问题示例**：`check_warning "deploy.sh 未使用 'set -e'"`
- **解决方法**：在脚本开头添加 `set -e`

### 2. 重复逻辑检查

#### 重复函数定义
- **检查内容**：是否有多个脚本定义了相同的函数名
- **问题示例**：发现 `check_root()` 在多个脚本中定义
- **建议**：提取为公共函数（参考 `common.sh`）

#### PROJECT_ROOT 获取逻辑
- **检查内容**：多个脚本是否有相同的 PROJECT_ROOT 获取代码
- **问题示例**：`⚠ 多个脚本中有相同的 PROJECT_ROOT 获取逻辑`
- **建议**：可提取为公共函数，但当前策略是保持脚本独立性

### 3. 路径引用检查

#### 硬编码路径
- **检查内容**：脚本中是否有硬编码的 `/usr/local/openresty` 路径
- **问题示例**：`⚠ 发现硬编码路径（应使用变量）`
- **解决方法**：使用 `OPENRESTY_PREFIX` 变量

#### 占位符路径
- **检查内容**：脚本中是否有 `/path/to` 占位符路径
- **问题示例**：`⚠ 发现占位符路径（应使用 PROJECT_ROOT）`
- **解决方法**：使用 `PROJECT_ROOT` 变量

### 4. 脚本逻辑完整性检查

#### install_geoip.sh
检查是否包含以下关键函数：
- `check_root` - 检查 root 权限
- `get_credentials` - 获取认证信息
- `download_database` - 下载数据库
- `extract_database` - 解压数据库
- `install_database` - 安装数据库
- `save_config` - 保存配置
- `setup_crontab` - 设置计划任务

#### update_geoip.sh
检查是否包含以下关键函数：
- `load_config` - 读取配置文件
- `check_dependencies` - 检查依赖
- `download_database` - 下载数据库
- `extract_database` - 解压数据库
- `install_database` - 安装数据库（含备份）

#### deploy.sh
检查是否包含以下关键逻辑：
- `PROJECT_ROOT` 变量 - 项目根目录
- `NGINX_CONF_DIR` 变量 - Nginx 配置目录
- `sed.*project_root` 路径替换 - 路径替换逻辑

#### optimize_system.sh
检查是否包含以下关键功能：
- 硬件信息检测
- 优化参数计算
- 系统参数优化
- OpenResty 配置优化

### 5. 文件存在性检查

检查以下必要文件是否存在：
- `init_file/nginx.conf`
- `init_file/数据库设计.sql`
- `conf.d/set_conf/lua.conf`
- `conf.d/set_conf/log.conf`
- `conf.d/set_conf/waf.conf`
- `conf.d/vhost_conf/default.conf`
- `lua/config.lua`
- `lua/waf/init.lua`
- `lua/waf/ip_block.lua`
- `lua/waf/ip_utils.lua`
- `lua/waf/log_collect.lua`
- `lua/waf/mysql_pool.lua`
- `lua/waf/geo_block.lua`

## 检查结果说明

### 输出格式

- ✅ **绿色 ✓**：检查通过
- ⚠️ **黄色 ⚠**：警告（不影响运行，但建议修复）
- ✗ **红色 ✗**：错误（需要修复）

### 退出码

- `0`：所有检查通过，或只有警告无错误
- `1`：发现错误，需要修复

### 结果统计

脚本最后会输出：
- **错误数**：需要立即修复的问题
- **警告数**：建议修复的问题

## 使用场景

### 1. 开发阶段
在开发新功能或修改代码后运行检查：

```bash
./scripts/check_all.sh
```

### 2. 部署前检查
在部署到服务器前运行检查，确保代码质量：

```bash
./scripts/check_all.sh
if [ $? -eq 0 ]; then
    echo "检查通过，可以部署"
else
    echo "发现错误，请修复后再部署"
fi
```

### 3. CI/CD 集成
可以在 CI/CD 流程中集成此检查：

```yaml
# 示例：GitHub Actions
- name: Check Project
  run: ./scripts/check_all.sh
```

### 4. 定期检查
可以设置定时任务定期检查项目状态：

```bash
# 添加到 crontab
0 2 * * * /path/to/project/scripts/check_all.sh >> /var/log/project_check.log 2>&1
```

## 扩展检查项

如果需要添加新的检查项，可以修改 `check_all.sh`：

```bash
# 示例：检查 Lua 脚本语法
echo -e "${BLUE}[6/6] 检查 Lua 脚本语法...${NC}"
for lua_file in lua/**/*.lua; do
    if [ -f "$lua_file" ]; then
        # 使用 luac 检查语法
        if luac -p "$lua_file" > /dev/null 2>&1; then
            check_ok "$lua_file 语法正确"
        else
            check_error "$lua_file 语法错误"
        fi
    fi
done
```

## 故障排查

### 问题 1：脚本无执行权限

**症状**：`Permission denied`

**解决**：
```bash
chmod +x scripts/check_all.sh
```

### 问题 2：检查结果不准确

**症状**：检查结果与实际情况不符

**解决**：
1. 检查脚本中的正则表达式是否正确
2. 检查文件路径是否正确
3. 检查脚本逻辑是否完整

### 问题 3：误报警告

**症状**：某些警告是预期的（如代码重复）

**解决**：
- 如果警告是预期的，可以忽略
- 或者修改脚本，添加例外规则

## 最佳实践

1. **定期运行**：在开发过程中定期运行检查
2. **修复错误**：优先修复错误，警告可以逐步修复
3. **记录结果**：将检查结果记录到日志文件
4. **持续改进**：根据检查结果持续改进代码质量

## 相关文档

- [项目检查报告](../docs/项目检查报告.md) - 详细的检查报告
- [代码检查报告](../docs/代码检查报告.md) - 代码检查结果
- [公共函数库说明](common_README.md) - 关于代码重复的说明

---

**总结**：`check_all.sh` 是一个有用的项目质量检查工具，建议在开发、部署前定期运行，确保代码质量。

