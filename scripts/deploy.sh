#!/bin/bash

# OpenResty WAF 部署脚本
# 用途：自动部署配置文件，使用相对路径和 $project_root 变量

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 获取脚本目录（使用相对路径）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."

# OpenResty 安装目录
OPENRESTY_PREFIX="${OPENRESTY_PREFIX:-/usr/local/openresty}"
NGINX_CONF_DIR="${OPENRESTY_PREFIX}/nginx/conf"

# 获取项目根目录的绝对路径（仅用于写入配置文件，因为 error_log 和 pid 不支持变量）
PROJECT_ROOT_ABS="$(cd "$PROJECT_ROOT" && pwd)"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}OpenResty WAF 部署脚本${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "项目根目录: $PROJECT_ROOT_ABS"
echo "OpenResty 前缀: $OPENRESTY_PREFIX"
echo "Nginx 配置目录: $NGINX_CONF_DIR"
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}警告: 需要 root 权限来部署文件${NC}"
    echo "请使用: sudo $0"
    exit 1
fi

# 创建必要的目录（如果不存在）
echo -e "${GREEN}[1/3] 检查并创建目录...${NC}"
if [ ! -d "${PROJECT_ROOT}/logs" ]; then
    mkdir -p "${PROJECT_ROOT}/logs"
    echo -e "${GREEN}✓ 已创建: logs/${NC}"
else
    echo -e "${BLUE}✓ 已存在: logs/${NC}"
fi

if [ ! -d "${PROJECT_ROOT}/lua/geoip" ]; then
    mkdir -p "${PROJECT_ROOT}/lua/geoip"
    echo -e "${GREEN}✓ 已创建: lua/geoip/${NC}"
else
    echo -e "${BLUE}✓ 已存在: lua/geoip/${NC}"
fi

if [ ! -d "${PROJECT_ROOT}/conf.d/cert" ]; then
    mkdir -p "${PROJECT_ROOT}/conf.d/cert"
    echo -e "${GREEN}✓ 已创建: conf.d/cert/${NC}"
else
    echo -e "${BLUE}✓ 已存在: conf.d/cert/${NC}"
fi
echo -e "${GREEN}✓ 目录检查完成${NC}"

# 复制 nginx.conf（只复制主配置文件）
echo -e "${GREEN}[2/3] 复制并配置主配置文件...${NC}"
cp "${PROJECT_ROOT}/init_file/nginx.conf" "$NGINX_CONF_DIR/nginx.conf"

# 替换 nginx.conf 中的路径占位符
# 1. 替换 error_log 和 pid 路径（这些指令不支持变量，必须使用绝对路径）
sed -i "s|/path/to/project/logs/error.log|$PROJECT_ROOT_ABS/logs/error.log|g" "$NGINX_CONF_DIR/nginx.conf"
sed -i "s|/path/to/project/logs/nginx.pid|$PROJECT_ROOT_ABS/logs/nginx.pid|g" "$NGINX_CONF_DIR/nginx.conf"

# 2. 替换 $project_root 变量为实际项目路径（用于 include 和其他配置）
# 注意：转义 $ 符号，避免被 shell 解释为变量
sed -i 's|set $project_root "/path/to/project"|set $project_root "'"$PROJECT_ROOT_ABS"'"|g' "$NGINX_CONF_DIR/nginx.conf"

echo -e "${GREEN}✓ 主配置文件已复制并配置${NC}"
echo -e "${YELLOW}  注意: conf.d、lua、logs、cert 目录保持在项目目录，使用相对路径引用${NC}"

# 验证配置文件
echo -e "${GREEN}[3/3] 验证配置...${NC}"

# 验证 nginx.conf 语法
if [ -f "${OPENRESTY_PREFIX}/bin/openresty" ]; then
    echo "验证 nginx.conf 语法..."
    
    # 检查 set 指令是否在 http 块内
    if [ -f "$NGINX_CONF_DIR/nginx.conf" ]; then
        set_line=$(grep -n "set \$project_root" "$NGINX_CONF_DIR/nginx.conf" | cut -d: -f1 | head -1)
        http_start=$(grep -n "^http {" "$NGINX_CONF_DIR/nginx.conf" | cut -d: -f1 | head -1)
        
        if [ -n "$set_line" ] && [ -n "$http_start" ]; then
            # 检查 set 指令是否在 http 块之后
            if [ "$set_line" -lt "$http_start" ]; then
                echo -e "${YELLOW}⚠ 检测到 set 指令在 http 块前，尝试修复...${NC}"
                # 删除原来的 set 指令
                sed -i "${set_line}d" "$NGINX_CONF_DIR/nginx.conf"
                # 在 http 块内第一行添加 set 指令
                sed -i "${http_start}a\    set \$project_root \"$PROJECT_ROOT_ABS\";" "$NGINX_CONF_DIR/nginx.conf"
                echo -e "${GREEN}✓ 已修复: 将 set 指令移动到 http 块内${NC}"
            fi
        fi
    fi
    
    if ${OPENRESTY_PREFIX}/bin/openresty -t > /dev/null 2>&1; then
        echo -e "${GREEN}✓ nginx.conf 语法正确${NC}"
    else
        echo -e "${RED}✗ nginx.conf 语法错误${NC}"
        echo "错误信息："
        ${OPENRESTY_PREFIX}/bin/openresty -t 2>&1 | head -20
        echo ""
        echo -e "${YELLOW}显示配置文件相关部分：${NC}"
        if [ -f "$NGINX_CONF_DIR/nginx.conf" ]; then
            grep -A 5 "set \$project_root" "$NGINX_CONF_DIR/nginx.conf" || true
        fi
        echo ""
        echo -e "${YELLOW}⚠ 请修复配置文件后重新部署${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ OpenResty 未安装，跳过语法验证${NC}"
fi

# 设置权限
echo -e "${GREEN}设置文件权限...${NC}"
chown -R nobody:nobody "${PROJECT_ROOT}/logs" 2>/dev/null || true
chmod 755 "${PROJECT_ROOT}/logs"
chmod 644 "$NGINX_CONF_DIR/nginx.conf"
# conf.d 保持在项目目录，设置项目目录权限
chmod -R 755 "${PROJECT_ROOT}/conf.d" 2>/dev/null || true
find "${PROJECT_ROOT}/conf.d" -type f -name "*.conf" -exec chmod 644 {} \; 2>/dev/null || true

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}部署完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "系统配置文件（已复制）:"
echo "  - nginx.conf: $NGINX_CONF_DIR/nginx.conf"
echo ""
echo "项目文件位置（保持在项目目录，使用相对路径）:"
echo "  - 配置文件: ${PROJECT_ROOT}/conf.d/"
echo "    - set_conf/: 参数配置文件"
echo "    - vhost_conf/: 虚拟主机配置"
echo "    - cert/: SSL 证书目录"
echo "  - Lua 脚本: ${PROJECT_ROOT}/lua/"
echo "  - GeoIP 数据库: ${PROJECT_ROOT}/lua/geoip/"
echo "  - 日志文件: ${PROJECT_ROOT}/logs/"
echo ""
echo "路径说明:"
echo "  - 所有路径使用 \$project_root 变量引用项目根目录"
echo "  - 配置文件中的路径示例:"
echo "    - 日志: \$project_root/logs/access.log"
echo "    - Lua: \$project_root/lua/?.lua"
echo "    - SSL: \$project_root/conf.d/cert/your_domain.crt"
echo "    - GeoIP: \$project_root/lua/geoip/GeoLite2-Country.mmdb"
echo ""
echo "配置说明:"
echo "  - nginx.conf 中的 include 路径使用 \$project_root 变量"
echo "  - 修改 conf.d 中的配置文件后，无需重新部署，直接 reload 即可"
echo ""
echo "下一步:"
echo "  1. 测试配置: $OPENRESTY_PREFIX/bin/openresty -t"
echo "  2. 启动服务: $OPENRESTY_PREFIX/bin/openresty"
echo "  3. 查看日志: tail -f ${PROJECT_ROOT}/logs/error.log"
echo ""
echo -e "${YELLOW}提示: 修改 conf.d 中的配置后，运行以下命令重新加载:${NC}"
echo "  $OPENRESTY_PREFIX/bin/openresty -s reload"

