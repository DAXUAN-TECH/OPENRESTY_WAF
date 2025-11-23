#!/bin/bash

# OpenResty WAF 部署脚本
# 用途：自动部署配置文件，处理路径替换

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 获取项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# OpenResty 安装目录
OPENRESTY_PREFIX="${OPENRESTY_PREFIX:-/usr/local/openresty}"
NGINX_CONF_DIR="${OPENRESTY_PREFIX}/nginx/conf"
NGINX_PREFIX="${OPENRESTY_PREFIX}/nginx"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}OpenResty WAF 部署脚本${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "项目根目录: $PROJECT_ROOT"
echo "OpenResty 前缀: $OPENRESTY_PREFIX"
echo "Nginx 配置目录: $NGINX_CONF_DIR"
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}警告: 需要 root 权限来部署文件${NC}"
    echo "请使用: sudo $0"
    exit 1
fi

# 创建必要的目录
echo -e "${GREEN}[1/4] 创建目录...${NC}"
mkdir -p "$PROJECT_ROOT/logs"
mkdir -p "$PROJECT_ROOT/lua/geoip"
echo -e "${GREEN}✓ 目录创建完成${NC}"

# 复制 nginx.conf（只复制主配置文件）
echo -e "${GREEN}[2/4] 复制主配置文件...${NC}"
cp "$PROJECT_ROOT/init_file/nginx.conf" "$NGINX_CONF_DIR/nginx.conf"
echo -e "${GREEN}✓ 主配置文件已复制${NC}"
echo -e "${YELLOW}  注意: conf.d 目录保持在项目目录，不复制到系统目录${NC}"

# 处理路径替换
echo -e "${GREEN}[3/4] 处理路径配置...${NC}"

# 更新 nginx.conf 中的项目根目录变量和日志路径
# 注意：转义 $ 符号，避免被 shell 解释为变量
# 使用单引号包裹模式部分，双引号包裹替换部分
sed -i 's|set $project_root "/path/to/project"|set $project_root "'"$PROJECT_ROOT"'"|g' "$NGINX_CONF_DIR/nginx.conf"
sed -i "s|/path/to/project/logs/error.log|$PROJECT_ROOT/logs/error.log|g" "$NGINX_CONF_DIR/nginx.conf"
sed -i "s|/path/to/project/logs/nginx.pid|$PROJECT_ROOT/logs/nginx.pid|g" "$NGINX_CONF_DIR/nginx.conf"

# 更新 nginx.conf 中的 conf.d include 路径（指向项目目录）
# 转义 * 和 . 避免被 shell 解释为正则表达式
sed -i "s|include /path/to/project/conf.d/set_conf/\*\.conf|include $PROJECT_ROOT/conf.d/set_conf/*.conf|g" "$NGINX_CONF_DIR/nginx.conf"
sed -i "s|include /path/to/project/conf.d/vhost_conf/\*\.conf|include $PROJECT_ROOT/conf.d/vhost_conf/*.conf|g" "$NGINX_CONF_DIR/nginx.conf"

# 更新 conf.d 配置文件中的路径（在项目目录中直接修改）
# 检查并替换所有配置文件中的路径占位符
echo "检查并更新 conf.d 配置文件中的路径..."

# 需要更新的配置文件列表
CONF_FILES=(
    "$PROJECT_ROOT/conf.d/set_conf/lua.conf"
    "$PROJECT_ROOT/conf.d/set_conf/log.conf"
    "$PROJECT_ROOT/conf.d/set_conf/waf.conf"
    "$PROJECT_ROOT/conf.d/set_conf/performance.conf"
    "$PROJECT_ROOT/conf.d/vhost_conf/default.conf"
)

# 路径替换模式
for conf_file in "${CONF_FILES[@]}"; do
    if [ -f "$conf_file" ]; then
        # 替换 $project_root 变量为实际路径
        sed -i "s|\$project_root|$PROJECT_ROOT|g" "$conf_file"
        # 替换 /path/to/project 占位符
        sed -i "s|/path/to/project|$PROJECT_ROOT|g" "$conf_file"
        echo "  ✓ 已更新: $(basename "$conf_file")"
    fi
done

# 检查是否还有未替换的路径占位符
REMAINING_PATHS=$(grep -r "/path/to/project\|\\\$project_root" "$PROJECT_ROOT/conf.d" 2>/dev/null | wc -l)
if [ "$REMAINING_PATHS" -gt 0 ]; then
    echo -e "${YELLOW}⚠ 警告: 仍有 $REMAINING_PATHS 处路径占位符未替换${NC}"
    echo "未替换的路径:"
    grep -rn "/path/to/project\|\\\$project_root" "$PROJECT_ROOT/conf.d" 2>/dev/null | head -10
else
    echo -e "${GREEN}✓ 所有路径占位符已替换${NC}"
fi

echo -e "${GREEN}✓ 路径配置已更新${NC}"

# 验证配置文件
echo -e "${GREEN}[4/4] 验证配置...${NC}"

# 验证 nginx.conf 语法
if [ -f "${OPENRESTY_PREFIX}/bin/openresty" ]; then
    echo "验证 nginx.conf 语法..."
    if ${OPENRESTY_PREFIX}/bin/openresty -t > /dev/null 2>&1; then
        echo -e "${GREEN}✓ nginx.conf 语法正确${NC}"
    else
        echo -e "${RED}✗ nginx.conf 语法错误${NC}"
        echo "错误信息："
        ${OPENRESTY_PREFIX}/bin/openresty -t 2>&1 | head -20
        echo -e "${YELLOW}⚠ 请修复配置文件后重新部署${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ OpenResty 未安装，跳过语法验证${NC}"
fi

echo -e "${GREEN}✓ 配置文件处理完成${NC}"
echo -e "${YELLOW}  注意: conf.d 和 lua 目录保持在项目目录，方便配置管理${NC}"

# 设置权限
echo -e "${GREEN}设置文件权限...${NC}"
chown -R nobody:nobody "$PROJECT_ROOT/logs" 2>/dev/null || true
chmod 755 "$PROJECT_ROOT/logs"
chmod 644 "$NGINX_CONF_DIR/nginx.conf"
# conf.d 保持在项目目录，设置项目目录权限
chmod -R 755 "$PROJECT_ROOT/conf.d" 2>/dev/null || true
find "$PROJECT_ROOT/conf.d" -type f -name "*.conf" -exec chmod 644 {} \; 2>/dev/null || true

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}部署完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "系统配置文件（已复制）:"
echo "  - nginx.conf: $NGINX_CONF_DIR/nginx.conf"
echo ""
echo "项目文件位置（保持在项目目录，方便配置）:"
echo "  - 配置文件: $PROJECT_ROOT/conf.d/"
echo "  - Lua 脚本: $PROJECT_ROOT/lua/"
echo "  - 日志文件: $PROJECT_ROOT/logs/"
echo ""
echo "配置说明:"
echo "  - nginx.conf 中的 include 路径已指向项目目录的 conf.d"
echo "  - 修改 conf.d 中的配置文件后，无需重新部署，直接 reload 即可"
echo ""
echo "下一步:"
echo "  1. 测试配置: $OPENRESTY_PREFIX/bin/openresty -t"
echo "  2. 启动服务: $OPENRESTY_PREFIX/bin/openresty"
echo "  3. 查看日志: tail -f $PROJECT_ROOT/logs/error.log"
echo ""
echo -e "${YELLOW}提示: 修改 conf.d 中的配置后，运行以下命令重新加载:${NC}"
echo "  $OPENRESTY_PREFIX/bin/openresty -s reload"

