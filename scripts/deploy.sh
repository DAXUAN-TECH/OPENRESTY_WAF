#!/bin/bash

# OpenResty WAF 部署脚本
# 用途：自动部署配置文件，使用相对路径和 $project_root 变量

set -e

# 引入公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/common.sh" ]; then
    source "${SCRIPT_DIR}/common.sh"
else
    # 如果 common.sh 不存在，定义基本颜色（向后兼容）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
fi

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

# 直接使用 sed 在复制时替换，避免多次操作导致重复
# 一次性完成：读取模板文件 -> 替换路径 -> 写入目标文件
# 先删除旧文件，确保干净
rm -f "$NGINX_CONF_DIR/nginx.conf.tmp" "$NGINX_CONF_DIR/nginx.conf"

# 使用 sed 替换并写入临时文件
sed -e "s|/path/to/project/logs/error.log|$PROJECT_ROOT_ABS/logs/error.log|g" \
    -e 's|set $project_root "/path/to/project"|set $project_root "'"$PROJECT_ROOT_ABS"'"|g' \
    "${PROJECT_ROOT}/init_file/nginx.conf" > "$NGINX_CONF_DIR/nginx.conf.tmp"

# 验证临时文件是否正确生成
if [ ! -f "$NGINX_CONF_DIR/nginx.conf.tmp" ]; then
    echo -e "${RED}✗ 无法创建临时配置文件${NC}"
    exit 1
fi

# 检查行数是否一致
template_lines=$(wc -l < "${PROJECT_ROOT}/init_file/nginx.conf" | tr -d ' ')
deployed_lines=$(wc -l < "$NGINX_CONF_DIR/nginx.conf.tmp" | tr -d ' ')
if [ "$template_lines" != "$deployed_lines" ]; then
    echo -e "${RED}✗ 文件行数不匹配: 模板 $template_lines 行, 生成 $deployed_lines 行${NC}"
    rm -f "$NGINX_CONF_DIR/nginx.conf.tmp"
    exit 1
fi

# 检查是否有重复的 http 块
http_count=$(grep -c "^http {" "$NGINX_CONF_DIR/nginx.conf.tmp" 2>/dev/null || echo "0")
if [ "$http_count" != "1" ]; then
    echo -e "${RED}✗ 检测到 $http_count 个 http 块（应该只有 1 个）${NC}"
    rm -f "$NGINX_CONF_DIR/nginx.conf.tmp"
    exit 1
fi

# 检查 set $project_root 是否在 http 块内（应该只有 1 个）
set_count=$(grep -c "set \$project_root" "$NGINX_CONF_DIR/nginx.conf.tmp" 2>/dev/null || echo "0")
if [ "$set_count" != "1" ]; then
    echo -e "${RED}✗ 检测到 $set_count 个 set \$project_root 指令（应该只有 1 个）${NC}"
    rm -f "$NGINX_CONF_DIR/nginx.conf.tmp"
    exit 1
fi

# 检查 set 指令是否在 http 块内
http_start_line=$(grep -n "^http {" "$NGINX_CONF_DIR/nginx.conf.tmp" | cut -d: -f1 | head -1)
set_line=$(grep -n "set \$project_root" "$NGINX_CONF_DIR/nginx.conf.tmp" | cut -d: -f1 | head -1)
# 使用 awk 找到 http 块的结束行（匹配 http { 后的第一个独立的 }）
http_end_line=$(awk -v start="$http_start_line" '
    BEGIN { in_http = 0; brace_count = 0 }
    NR >= start {
        if (/^http \{/) {
            in_http = 1
            brace_count = 1
        } else if (in_http) {
            # 计算大括号
            for (i = 1; i <= length($0); i++) {
                char = substr($0, i, 1)
                if (char == "{") brace_count++
                if (char == "}") brace_count--
            }
            # 如果大括号计数为 0，说明 http 块结束
            if (brace_count == 0) {
                print NR
                exit
            }
        }
    }
' "$NGINX_CONF_DIR/nginx.conf.tmp" | tail -1)

if [ -z "$http_start_line" ] || [ -z "$set_line" ] || [ -z "$http_end_line" ]; then
    echo -e "${RED}✗ 无法定位 http 块或 set 指令${NC}"
    rm -f "$NGINX_CONF_DIR/nginx.conf.tmp"
    exit 1
fi

if [ "$set_line" -le "$http_start_line" ] || [ "$set_line" -ge "$http_end_line" ]; then
    echo -e "${RED}✗ set \$project_root 指令不在 http 块内（http: $http_start_line-$http_end_line, set: $set_line）${NC}"
    rm -f "$NGINX_CONF_DIR/nginx.conf.tmp"
    exit 1
fi

# 所有检查通过，移动文件
mv "$NGINX_CONF_DIR/nginx.conf.tmp" "$NGINX_CONF_DIR/nginx.conf"

echo -e "${GREEN}✓ 主配置文件已复制并配置${NC}"
echo -e "${YELLOW}  注意: conf.d、lua、logs、cert 目录保持在项目目录，使用相对路径引用${NC}"

# 验证配置文件
echo -e "${GREEN}[3/4] 验证配置...${NC}"

# 验证 nginx.conf 语法
if [ -f "${OPENRESTY_PREFIX}/bin/openresty" ]; then
    echo "验证 nginx.conf 语法..."
    
    if ${OPENRESTY_PREFIX}/bin/openresty -t > /dev/null 2>&1; then
        echo -e "${GREEN}✓ nginx.conf 语法正确${NC}"
    else
        echo -e "${RED}✗ nginx.conf 语法错误${NC}"
        echo "错误信息："
        ${OPENRESTY_PREFIX}/bin/openresty -t 2>&1 | head -20
        echo ""
        echo -e "${YELLOW}显示配置文件相关部分：${NC}"
        if [ -f "$NGINX_CONF_DIR/nginx.conf" ]; then
            # 显示完整的 http 块
            http_start=$(grep -n "^http {" "$NGINX_CONF_DIR/nginx.conf" | cut -d: -f1 | head -1)
            if [ -n "$http_start" ]; then
                # 找到 http 块的结束行
                http_end=$(awk -v start="$http_start" '
                    BEGIN { in_http = 0; brace_count = 0 }
                    NR >= start {
                        if (/^http \{/) {
                            in_http = 1
                            brace_count = 1
                        } else if (in_http) {
                            for (i = 1; i <= length($0); i++) {
                                char = substr($0, i, 1)
                                if (char == "{") brace_count++
                                if (char == "}") brace_count--
                            }
                            if (brace_count == 0) {
                                print NR
                                exit
                            }
                        }
                    }
                ' "$NGINX_CONF_DIR/nginx.conf")
                
                if [ -n "$http_end" ]; then
                    echo "http 块内容（行 $http_start-$http_end）："
                    sed -n "${http_start},${http_end}p" "$NGINX_CONF_DIR/nginx.conf"
                else
                    echo "http 块内容（从行 $http_start 开始）："
                    sed -n "${http_start},$((http_start + 15))p" "$NGINX_CONF_DIR/nginx.conf"
                fi
            fi
            echo ""
            # 检查是否有重复的 set 指令
            set_lines=$(grep -n "set \$project_root" "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null | wc -l)
            if [ "$set_lines" -gt 1 ]; then
                echo -e "${RED}⚠ 发现 $set_lines 个 set \$project_root 指令：${NC}"
                grep -n "set \$project_root" "$NGINX_CONF_DIR/nginx.conf"
            fi
            echo ""
            echo -e "${BLUE}配置文件总行数：$(wc -l < "$NGINX_CONF_DIR/nginx.conf")${NC}"
            echo -e "${BLUE}http 块开始行：${http_start}${NC}"
            echo -e "${BLUE}http 块结束行：${http_end:-未知}${NC}"
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

