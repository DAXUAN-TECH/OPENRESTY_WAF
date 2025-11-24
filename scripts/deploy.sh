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
cp "${PROJECT_ROOT}/init_file/nginx.conf" "$NGINX_CONF_DIR/nginx.conf"

# 检查并修复重复的 http 块和内容（如果存在）
http_block_count=$(grep -c "^http {" "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null || echo "0")
if [ "$http_block_count" -gt 1 ]; then
    echo -e "${YELLOW}⚠ 检测到多个 http 块，正在修复...${NC}"
    # 找到第一个 http 块的位置
    first_http_line=$(grep -n "^http {" "$NGINX_CONF_DIR/nginx.conf" | cut -d: -f1 | head -1)
    # 使用更精确的方法找到第一个 http 块的结束位置
    first_http_end=$(awk -v start="$first_http_line" '
        BEGIN { brace_count = 0; found_start = 0 }
        NR >= start {
            if (NR == start) found_start = 1
            if (found_start) {
                for (i = 1; i <= length($0); i++) {
                    char = substr($0, i, 1)
                    if (char == "{") brace_count++
                    if (char == "}") {
                        brace_count--
                        if (brace_count == 0 && found_start) {
                            print NR
                            exit
                        }
                    }
                }
            }
        }
    ' "$NGINX_CONF_DIR/nginx.conf")
    if [ -z "$first_http_end" ]; then
        first_http_end=$(wc -l < "$NGINX_CONF_DIR/nginx.conf")
    fi
    # 删除第一个 http 块之后的所有内容，保留第一个 http 块
    sed -i "$((first_http_end + 1)),\$d" "$NGINX_CONF_DIR/nginx.conf"
    echo -e "${GREEN}✓ 已修复重复的 http 块${NC}"
fi

# 检查是否有重复的内容（在 http 块结束后）
# 如果 http 块结束后还有内容，可能是重复的配置
if [ -f "$NGINX_CONF_DIR/nginx.conf" ]; then
    http_start=$(grep -n "^http {" "$NGINX_CONF_DIR/nginx.conf" | cut -d: -f1 | head -1)
    if [ -n "$http_start" ]; then
        http_end=$(awk -v start="$http_start" '
            BEGIN { brace_count = 0; found_start = 0 }
            NR >= start {
                if (NR == start) found_start = 1
                if (found_start) {
                    for (i = 1; i <= length($0); i++) {
                        char = substr($0, i, 1)
                        if (char == "{") brace_count++
                        if (char == "}") {
                            brace_count--
                            if (brace_count == 0 && found_start) {
                                print NR
                                exit
                            }
                        }
                    }
                }
            }
        ' "$NGINX_CONF_DIR/nginx.conf")
        if [ -n "$http_end" ]; then
            total_lines=$(wc -l < "$NGINX_CONF_DIR/nginx.conf")
            # 检查 http 块结束后是否还有内容
            if [ "$http_end" -lt "$total_lines" ]; then
                # 检查 http 块后的内容是否包含 set 指令（可能是重复的）
                after_http_content=$(sed -n "$((http_end + 1)),\$p" "$NGINX_CONF_DIR/nginx.conf")
                if echo "$after_http_content" | grep -q "set \$project_root"; then
                    echo -e "${YELLOW}⚠ 检测到 http 块后有重复的 set 指令，正在清理...${NC}"
                    # 删除 http 块后的所有内容
                    sed -i "$((http_end + 1)),\$d" "$NGINX_CONF_DIR/nginx.conf"
                    echo -e "${GREEN}✓ 已清理重复内容${NC}"
                fi
            fi
        fi
    fi
fi

# 替换 nginx.conf 中的路径占位符
# 1. 替换 error_log 路径（这些指令不支持变量，必须使用绝对路径）
# 注意：PID 文件路径固定为 /usr/local/openresty/nginx/logs/nginx.pid，不能修改
#       必须与 systemd 服务文件 openresty.service 中的 PIDFile 一致
sed -i "s|/path/to/project/logs/error.log|$PROJECT_ROOT_ABS/logs/error.log|g" "$NGINX_CONF_DIR/nginx.conf"

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
    # 注意：由于第 100 行已经替换了 set 指令的值，这里需要清理和重新组织
    if [ -f "$NGINX_CONF_DIR/nginx.conf" ]; then
        # 首先，删除所有在 http 块外的 set 指令（防止语法错误）
        echo -e "${BLUE}清理 http 块外的 set 指令...${NC}"
        
        # 查找第一个 http 块（确保只有一个）
        http_start=$(grep -n "^http {" "$NGINX_CONF_DIR/nginx.conf" | cut -d: -f1 | head -1)
        
        if [ -z "$http_start" ]; then
            echo -e "${RED}✗ 未找到 http 块，配置文件可能已损坏${NC}"
            exit 1
        fi
        
        # 找到第一个 http 块的结束位置（查找匹配的 }）
        # 使用更精确的匹配，确保找到正确的 http 块结束
        http_end=$(awk -v start="$http_start" '
            BEGIN { brace_count = 0; found_start = 0 }
            NR >= start {
                if (NR == start) found_start = 1
                if (found_start) {
                    # 计算大括号
                    for (i = 1; i <= length($0); i++) {
                        char = substr($0, i, 1)
                        if (char == "{") brace_count++
                        if (char == "}") {
                            brace_count--
                            if (brace_count == 0 && found_start) {
                                print NR
                                exit
                            }
                        }
                    }
                }
            }
        ' "$NGINX_CONF_DIR/nginx.conf")
        if [ -z "$http_end" ]; then
            http_end=$(wc -l < "$NGINX_CONF_DIR/nginx.conf")
        fi
        
        # 删除 http 块外的所有 set 指令及其注释
        # 1. 删除 http 块之前的所有 set 指令
        if [ "$http_start" -gt 1 ]; then
            sed -i "1,$((http_start - 1)){/set \$project_root/d; /#.*项目根目录/d; /#.*project_root/d}" "$NGINX_CONF_DIR/nginx.conf"
        fi
        
        # 2. 删除 http 块之后的所有 set 指令
        total_lines=$(wc -l < "$NGINX_CONF_DIR/nginx.conf")
        if [ "$http_end" -lt "$total_lines" ]; then
            sed -i "$((http_end + 1)),\${/set \$project_root/d; /#.*项目根目录/d; /#.*project_root/d}" "$NGINX_CONF_DIR/nginx.conf"
        fi
        
        # 重新查找 http 块位置（因为可能删除了行）
        http_start=$(grep -n "^http {" "$NGINX_CONF_DIR/nginx.conf" | cut -d: -f1 | head -1)
        # 使用更精确的匹配，确保找到正确的 http 块结束
        http_end=$(awk -v start="$http_start" '
            BEGIN { brace_count = 0; found_start = 0 }
            NR >= start {
                if (NR == start) found_start = 1
                if (found_start) {
                    # 计算大括号
                    for (i = 1; i <= length($0); i++) {
                        char = substr($0, i, 1)
                        if (char == "{") brace_count++
                        if (char == "}") {
                            brace_count--
                            if (brace_count == 0 && found_start) {
                                print NR
                                exit
                            }
                        }
                    }
                }
            }
        ' "$NGINX_CONF_DIR/nginx.conf")
        if [ -z "$http_end" ]; then
            http_end=$(wc -l < "$NGINX_CONF_DIR/nginx.conf")
        fi
        
        # 检查 http 块内是否有 set 指令
        set_in_http=$(sed -n "${http_start},${http_end}p" "$NGINX_CONF_DIR/nginx.conf" | grep -c "set \$project_root" 2>/dev/null || echo "0")
        set_in_http=$(echo "$set_in_http" | tr -d '\n\r' | head -n1)
        if ! [[ "$set_in_http" =~ ^[0-9]+$ ]]; then
            set_in_http=0
        fi
        
        # 如果 http 块内有多个 set 指令，只保留第一个，删除其他的
        if [ "$set_in_http" -gt 1 ]; then
            echo -e "${YELLOW}⚠ 检测到 http 块内有多个 set 指令，正在清理...${NC}"
            # 在 http 块内找到第一个 set 指令的位置
            first_set_line=$(sed -n "${http_start},${http_end}p" "$NGINX_CONF_DIR/nginx.conf" | grep -n "set \$project_root" | head -1 | cut -d: -f1)
            first_set_line=$((http_start + first_set_line - 1))
            # 删除 http 块内第一个 set 指令之后的所有 set 指令
            sed -i "$((first_set_line + 1)),${http_end}{/set \$project_root/d; /#.*项目根目录/d; /#.*project_root/d}" "$NGINX_CONF_DIR/nginx.conf"
            set_in_http=1
        fi
        
        if [ "$set_in_http" -eq 0 ]; then
            # 没有 set 指令，在 http { 后添加
            echo -e "${YELLOW}⚠ 在 http 块内添加 set 指令...${NC}"
            # 使用更安全的方式插入（避免 sed 转义问题）
            # 确保在 http { 行的下一行插入，而不是在同一行
            awk -v start="$http_start" -v project_root="$PROJECT_ROOT_ABS" '
                NR == start {
                    print
                    # 在下一行插入 set 指令
                    print "    # 项目根目录变量"
                    print "    set $project_root \"" project_root "\";"
                    next
                }
                { print }
            ' "$NGINX_CONF_DIR/nginx.conf" > "$NGINX_CONF_DIR/nginx.conf.tmp" && \
            mv "$NGINX_CONF_DIR/nginx.conf.tmp" "$NGINX_CONF_DIR/nginx.conf"
            echo -e "${GREEN}✓ 已添加 set 指令到 http 块内${NC}"
        else
            # 已有 set 指令，确保其值是正确的
            current_value=$(sed -n "${http_start},${http_end}p" "$NGINX_CONF_DIR/nginx.conf" | grep "set \$project_root" | sed 's/.*"\(.*\)".*/\1/' | head -1)
            if [ "$current_value" != "$PROJECT_ROOT_ABS" ]; then
                echo -e "${YELLOW}⚠ 更新 set 指令的值...${NC}"
                # 只在 http 块内替换
                sed -i "${http_start},${http_end}s|set \$project_root \"[^\"]*\"|set \$project_root \"$PROJECT_ROOT_ABS\"|g" "$NGINX_CONF_DIR/nginx.conf"
                echo -e "${GREEN}✓ 已更新 set 指令的值${NC}"
            else
                echo -e "${GREEN}✓ set 指令已在 http 块内且值正确${NC}"
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

