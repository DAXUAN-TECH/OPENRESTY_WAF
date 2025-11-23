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
echo -e "${GREEN}[3/4] 验证配置...${NC}"

# 验证 nginx.conf 语法
if [ -f "${OPENRESTY_PREFIX}/bin/openresty" ]; then
    echo "验证 nginx.conf 语法..."
    
    # 确保 set 指令在 http 块内的正确位置
    if [ -f "$NGINX_CONF_DIR/nginx.conf" ]; then
        # 查找所有 set 指令行（可能有多行）
        set_lines=$(grep -n "set \$project_root" "$NGINX_CONF_DIR/nginx.conf" | cut -d: -f1)
        
        # 删除所有现有的 set 指令及其相关注释
        if [ -n "$set_lines" ]; then
            echo -e "${YELLOW}⚠ 清理现有的 set 指令...${NC}"
            for set_line in $(echo "$set_lines" | tac); do
                # 删除 set 指令行
                sed -i "${set_line}d" "$NGINX_CONF_DIR/nginx.conf"
                # 如果上一行是注释，也删除
                if [ "$set_line" -gt 1 ]; then
                    prev_line=$((set_line - 1))
                    if sed -n "${prev_line}p" "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null | grep -qE "^[[:space:]]*#.*project_root|^[[:space:]]*#.*项目根目录"; then
                        sed -i "${prev_line}d" "$NGINX_CONF_DIR/nginx.conf"
                    fi
                fi
            done
        fi
        
        # 重新查找 http 块开始行（因为可能删除了行）
        http_start=$(grep -n "^http {" "$NGINX_CONF_DIR/nginx.conf" | cut -d: -f1 | head -1)
        
        if [ -n "$http_start" ]; then
            # 检查是否已经有 set 指令在 http 块内
            http_end=$(grep -n "^}" "$NGINX_CONF_DIR/nginx.conf" | awk -v start="$http_start" '$1 > start {print $1; exit}' | cut -d: -f1)
            if [ -z "$http_end" ]; then
                # 如果没有找到 http 块的结束，使用文件末尾
                http_end=$(wc -l < "$NGINX_CONF_DIR/nginx.conf")
            fi
            
            # 检查 http 块内是否已有 set 指令
            set_in_http=$(sed -n "${http_start},${http_end}p" "$NGINX_CONF_DIR/nginx.conf" | grep -c "set \$project_root" || echo "0")
            
            if [ "$set_in_http" -eq 0 ]; then
                # 在 http 块内第一行添加 set 指令（确保正确的缩进）
                echo -e "${YELLOW}⚠ 在 http 块内添加 set 指令...${NC}"
                # 使用 sed 在 http { 行后插入 set 指令
                sed -i "${http_start}a\    # 项目根目录变量\n    set \$project_root \"$PROJECT_ROOT_ABS\";" "$NGINX_CONF_DIR/nginx.conf"
                echo -e "${GREEN}✓ 已确保 set 指令在 http 块内的正确位置${NC}"
            else
                echo -e "${GREEN}✓ set 指令已在 http 块内${NC}"
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
            # 显示 http 块和 set 指令周围的内容
            http_start=$(grep -n "^http {" "$NGINX_CONF_DIR/nginx.conf" | cut -d: -f1 | head -1)
            if [ -n "$http_start" ]; then
                sed -n "${http_start},$((http_start + 10))p" "$NGINX_CONF_DIR/nginx.conf" || true
            fi
            grep -B 2 -A 5 "set \$project_root" "$NGINX_CONF_DIR/nginx.conf" || true
        fi
        echo ""
        echo -e "${YELLOW}⚠ 请修复配置文件后重新部署${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ OpenResty 未安装，跳过语法验证${NC}"
fi

# 检查部署路径完整性
echo -e "${GREEN}[4/5] 检查部署路径完整性...${NC}"

# 检查所有必需的路径是否存在
REQUIRED_PATHS=(
    "${PROJECT_ROOT}/conf.d"
    "${PROJECT_ROOT}/lua"
    "${PROJECT_ROOT}/logs"
    "${PROJECT_ROOT}/conf.d/set_conf"
    "${PROJECT_ROOT}/conf.d/vhost_conf"
    "${PROJECT_ROOT}/lua/waf"
)

ALL_PATHS_OK=1
for path in "${REQUIRED_PATHS[@]}"; do
    if [ ! -d "$path" ]; then
        echo -e "${YELLOW}⚠ 路径不存在: $path${NC}"
        ALL_PATHS_OK=0
        # 尝试创建缺失的目录
        read -p "是否创建缺失的目录？[Y/n]: " CREATE_MISSING
        CREATE_MISSING="${CREATE_MISSING:-Y}"
        if [[ "$CREATE_MISSING" =~ ^[Yy]$ ]]; then
            mkdir -p "$path"
            echo -e "${GREEN}✓ 已创建: $path${NC}"
            ALL_PATHS_OK=1
        fi
    fi
done

if [ $ALL_PATHS_OK -eq 1 ]; then
    echo -e "${GREEN}✓ 所有必需路径存在${NC}"
else
    echo -e "${YELLOW}⚠ 部分路径不存在，可能影响功能${NC}"
fi

# 检查配置文件中的路径引用是否正确
if [ -f "$NGINX_CONF_DIR/nginx.conf" ]; then
    # 检查是否包含 project_root 变量
    if grep -q "\$project_root" "$NGINX_CONF_DIR/nginx.conf"; then
        echo -e "${GREEN}✓ nginx.conf 包含 project_root 变量${NC}"
        # 验证 project_root 路径是否存在
        project_root_in_conf=$(grep "set \$project_root" "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null | sed 's/.*"\(.*\)".*/\1/' | head -1)
        if [ -n "$project_root_in_conf" ]; then
            if [ -d "$project_root_in_conf" ]; then
                echo -e "${GREEN}✓ project_root 路径存在: $project_root_in_conf${NC}"
            else
                echo -e "${RED}✗ project_root 路径不存在: $project_root_in_conf${NC}"
                echo -e "${YELLOW}  建议修复为: $PROJECT_ROOT_ABS${NC}"
            fi
        fi
    else
        echo -e "${RED}✗ nginx.conf 未找到 project_root 变量${NC}"
    fi
    
    # 检查 include 路径是否正确
    if grep -q "include.*conf.d" "$NGINX_CONF_DIR/nginx.conf"; then
        echo -e "${GREEN}✓ nginx.conf 包含 conf.d 配置引用${NC}"
        # 检查引用的配置文件是否存在
        include_paths=$(grep "include.*conf.d" "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null | sed "s|.*include.*\$project_root/\(.*\);|\1|" | head -1)
        if [ -n "$include_paths" ]; then
            full_include_path="${PROJECT_ROOT_ABS}/${include_paths}"
            if [ -f "$full_include_path" ] || [ -d "$full_include_path" ]; then
                echo -e "${GREEN}✓ 引用的配置文件存在: $full_include_path${NC}"
            else
                echo -e "${YELLOW}⚠ 引用的配置文件不存在: $full_include_path${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}⚠ nginx.conf 未找到 conf.d 配置引用${NC}"
    fi
    
    # 检查是否还有未替换的路径占位符
    if grep -q "/path/to/project" "$NGINX_CONF_DIR/nginx.conf"; then
        echo -e "${RED}✗ nginx.conf 仍包含路径占位符 /path/to/project${NC}"
        echo -e "${YELLOW}  请检查路径替换是否完整${NC}"
    else
        echo -e "${GREEN}✓ 所有路径占位符已替换${NC}"
    fi
fi

# 5. 检查配置文件语法和完整性
echo -e "${GREEN}[5/5] 检查配置文件语法和完整性...${NC}"

# 验证 nginx.conf 语法
if [ -f "${OPENRESTY_PREFIX}/bin/openresty" ]; then
    if ${OPENRESTY_PREFIX}/bin/openresty -t > /dev/null 2>&1; then
        echo -e "${GREEN}✓ nginx.conf 语法正确${NC}"
    else
        echo -e "${RED}✗ nginx.conf 语法错误${NC}"
        echo -e "${YELLOW}错误信息：${NC}"
        ${OPENRESTY_PREFIX}/bin/openresty -t 2>&1 | head -10
    fi
fi

# 检查关键配置文件是否存在
CRITICAL_CONFIGS=(
    "${PROJECT_ROOT}/conf.d/set_conf/waf.conf"
    "${PROJECT_ROOT}/conf.d/set_conf/lua.conf"
    "${PROJECT_ROOT}/lua/config.lua"
    "${PROJECT_ROOT}/lua/waf/init.lua"
)

for config in "${CRITICAL_CONFIGS[@]}"; do
    if [ -f "$config" ]; then
        echo -e "${GREEN}✓ 配置文件存在: $(basename $config)${NC}"
    else
        echo -e "${RED}✗ 关键配置文件不存在: $config${NC}"
    fi
done

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

