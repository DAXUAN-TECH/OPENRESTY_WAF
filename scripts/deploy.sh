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

# 创建 waf 用户（如果不存在）
WAF_USER="waf"
WAF_GROUP="waf"
echo -e "${GREEN}[0/5] 检查并创建 waf 用户...${NC}"

# 检查 waf 组是否存在
if ! getent group "$WAF_GROUP" > /dev/null 2>&1; then
    echo -e "${YELLOW}  创建 waf 组...${NC}"
    groupadd -r "$WAF_GROUP" 2>/dev/null || {
        echo -e "${RED}✗ 无法创建 waf 组${NC}"
        exit 1
    }
    echo -e "${GREEN}  ✓ 已创建 waf 组${NC}"
else
    echo -e "${BLUE}  ✓ waf 组已存在${NC}"
fi

# 检查 waf 用户是否存在
if ! id "$WAF_USER" > /dev/null 2>&1; then
    echo -e "${YELLOW}  创建 waf 用户...${NC}"
    # 查找 nologin shell（不同系统可能在不同位置）
    NOLOGIN_SHELL="/sbin/nologin"
    if [ ! -f "$NOLOGIN_SHELL" ]; then
        NOLOGIN_SHELL="/usr/sbin/nologin"
    fi
    if [ ! -f "$NOLOGIN_SHELL" ]; then
        NOLOGIN_SHELL="/bin/false"
    fi
    
    useradd -r -g "$WAF_GROUP" -s "$NOLOGIN_SHELL" -d /nonexistent -c "OpenResty WAF Service User" "$WAF_USER" 2>/dev/null || {
        echo -e "${RED}✗ 无法创建 waf 用户${NC}"
        exit 1
    }
    echo -e "${GREEN}  ✓ 已创建 waf 用户（shell: $NOLOGIN_SHELL，禁止登录）${NC}"
else
    echo -e "${BLUE}  ✓ waf 用户已存在${NC}"
    # 确保用户属于 waf 组
    CURRENT_GROUP=$(id -gn "$WAF_USER" 2>/dev/null)
    if [ "$CURRENT_GROUP" != "$WAF_GROUP" ]; then
        echo -e "${YELLOW}  更新 waf 用户的主组为 waf...${NC}"
        usermod -g "$WAF_GROUP" "$WAF_USER" 2>/dev/null || {
            echo -e "${YELLOW}  ⚠ 无法更新用户主组，继续执行...${NC}"
        }
    fi
    # 确保用户不能登录
    CURRENT_SHELL=$(getent passwd "$WAF_USER" | cut -d: -f7)
    if [ "$CURRENT_SHELL" != "/sbin/nologin" ] && [ "$CURRENT_SHELL" != "/usr/sbin/nologin" ] && [ "$CURRENT_SHELL" != "/bin/false" ]; then
        echo -e "${YELLOW}  设置 waf 用户禁止登录...${NC}"
        NOLOGIN_SHELL="/sbin/nologin"
        if [ ! -f "$NOLOGIN_SHELL" ]; then
            NOLOGIN_SHELL="/usr/sbin/nologin"
        fi
        if [ ! -f "$NOLOGIN_SHELL" ]; then
            NOLOGIN_SHELL="/bin/false"
        fi
        usermod -s "$NOLOGIN_SHELL" "$WAF_USER" 2>/dev/null || {
            echo -e "${YELLOW}  ⚠ 无法更新用户 shell，继续执行...${NC}"
        }
    fi
fi

echo -e "${GREEN}✓ waf 用户检查完成${NC}"
echo ""

# 尝试更新 OpenResty 的 systemd 启动用户和环境（如果存在 openresty.service）
echo -e "${GREEN}[0.1/5] 检查并更新 OpenResty systemd 服务用户和环境变量...${NC}"

# 优先使用 /etc/systemd/system，其次是常见的系统路径
OPENRESTY_SERVICE_FILE=""
for candidate in \
    "/etc/systemd/system/openresty.service" \
    "/lib/systemd/system/openresty.service" \
    "/usr/lib/systemd/system/openresty.service"
do
    if [ -f "$candidate" ]; then
        OPENRESTY_SERVICE_FILE="$candidate"
        break
    fi
done

if [ -n "$OPENRESTY_SERVICE_FILE" ]; then
    echo -e "${YELLOW}  检测到 OpenResty systemd 服务文件: $OPENRESTY_SERVICE_FILE${NC}"

    # 确保 [Service] 段存在
    if ! grep -q "^\[Service\]" "$OPENRESTY_SERVICE_FILE"; then
        echo -e "${YELLOW}  ⚠ 服务文件中未找到 [Service] 段，跳过用户/环境更新${NC}"
    else
        # 更新或插入 User=waf
        if grep -q "^User=" "$OPENRESTY_SERVICE_FILE"; then
            sed -i "s/^User=.*/User=$WAF_USER/" "$OPENRESTY_SERVICE_FILE"
        else
            # 在 [Service] 行之后插入 User
            sed -i "/^\[Service\]/a User=$WAF_USER" "$OPENRESTY_SERVICE_FILE"
        fi

        # 更新或插入 Group=waf
        if grep -q "^Group=" "$OPENRESTY_SERVICE_FILE"; then
            sed -i "s/^Group=.*/Group=$WAF_GROUP/" "$OPENRESTY_SERVICE_FILE"
        else
            sed -i "/^\[Service\]/a Group=$WAF_GROUP" "$OPENRESTY_SERVICE_FILE"
        fi

        # 为非 root 的 OpenResty 进程授予绑定 80/443 等低端口的能力
        # 使用 systemd 的 CapabilityBoundingSet 和 AmbientCapabilities
        if grep -q "^CapabilityBoundingSet=" "$OPENRESTY_SERVICE_FILE"; then
            sed -i "s/^CapabilityBoundingSet=.*/CapabilityBoundingSet=CAP_NET_BIND_SERVICE/" "$OPENRESTY_SERVICE_FILE"
        else
            sed -i "/^\[Service\]/a CapabilityBoundingSet=CAP_NET_BIND_SERVICE" "$OPENRESTY_SERVICE_FILE"
        fi

        if grep -q "^AmbientCapabilities=" "$OPENRESTY_SERVICE_FILE"; then
            sed -i "s/^AmbientCapabilities=.*/AmbientCapabilities=CAP_NET_BIND_SERVICE/" "$OPENRESTY_SERVICE_FILE"
        else
            sed -i "/^\[Service\]/a AmbientCapabilities=CAP_NET_BIND_SERVICE" "$OPENRESTY_SERVICE_FILE"
        fi

        # 部分发行版在启用 AmbientCapabilities 时需要显式关闭 NoNewPrivileges
        if grep -q "^NoNewPrivileges=" "$OPENRESTY_SERVICE_FILE"; then
            sed -i "s/^NoNewPrivileges=.*/NoNewPrivileges=false/" "$OPENRESTY_SERVICE_FILE"
        else
            sed -i "/^\[Service\]/a NoNewPrivileges=false" "$OPENRESTY_SERVICE_FILE"
        fi

        # 设置 Environment=OPENRESTY_PREFIX（供 Lua 层 find_openresty_binary 使用）
        if grep -q "^Environment=OPENRESTY_PREFIX=" "$OPENRESTY_SERVICE_FILE"; then
            sed -i "s|^Environment=OPENRESTY_PREFIX=.*|Environment=OPENRESTY_PREFIX=$OPENRESTY_PREFIX|" "$OPENRESTY_SERVICE_FILE"
        else
            sed -i "/^\[Service\]/a Environment=OPENRESTY_PREFIX=$OPENRESTY_PREFIX" "$OPENRESTY_SERVICE_FILE"
        fi

        echo -e "${GREEN}  ✓ 已将 OpenResty 服务用户和环境变量设置为: User=$WAF_USER, Group=$WAF_GROUP, OPENRESTY_PREFIX=$OPENRESTY_PREFIX${NC}"

        # 重新加载 systemd 配置
        if command -v systemctl >/dev/null 2>&1; then
            if systemctl daemon-reload 2>/dev/null; then
                echo -e "${GREEN}  ✓ 已执行 systemctl daemon-reload${NC}"
            else
                echo -e "${YELLOW}  ⚠ 无法执行 systemctl daemon-reload，请手动运行: systemctl daemon-reload${NC}"
            fi
        else
            echo -e "${YELLOW}  ⚠ 未检测到 systemctl 命令，可能不是 systemd 系统，跳过重载${NC}"
        fi

        echo -e "${BLUE}  说明: 之后请使用 systemd 管理 OpenResty，例如: systemctl restart openresty${NC}"
        echo -e "${BLUE}        master 和 worker 进程将以 waf 用户运行，配合 Lua 中的 openresty -s reload 实现自动热重载${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠ 未找到 openresty.service（可能是手动安装或使用其它方式启动），跳过 systemd 用户配置${NC}"
    echo -e "${YELLOW}    如需自动重载与 waf 用户配合，建议使用 install_openresty.sh 安装或手动创建 openresty.service${NC}"
fi

# 创建必要的目录（如果不存在）
echo -e "${GREEN}[1/5] 检查并创建目录...${NC}"
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

if [ ! -d "${PROJECT_ROOT}/conf.d/upstream" ]; then
    mkdir -p "${PROJECT_ROOT}/conf.d/upstream"
    echo -e "${GREEN}✓ 已创建: conf.d/upstream/${NC}"
else
    echo -e "${BLUE}✓ 已存在: conf.d/upstream/${NC}"
fi

if [ ! -d "${PROJECT_ROOT}/conf.d/upstream/http_https" ]; then
    mkdir -p "${PROJECT_ROOT}/conf.d/upstream/http_https"
    echo -e "${GREEN}✓ 已创建: conf.d/upstream/http_https/${NC}"
else
    echo -e "${BLUE}✓ 已存在: conf.d/upstream/http_https/${NC}"
fi

if [ ! -d "${PROJECT_ROOT}/conf.d/upstream/tcp_udp" ]; then
    mkdir -p "${PROJECT_ROOT}/conf.d/upstream/tcp_udp"
    echo -e "${GREEN}✓ 已创建: conf.d/upstream/tcp_udp/${NC}"
else
    echo -e "${BLUE}✓ 已存在: conf.d/upstream/tcp_udp/${NC}"
fi


if [ ! -d "${PROJECT_ROOT}/conf.d/vhost_conf/http_https" ]; then
    mkdir -p "${PROJECT_ROOT}/conf.d/vhost_conf/http_https"
    echo -e "${GREEN}✓ 已创建: conf.d/vhost_conf/http_https/${NC}"
else
    echo -e "${BLUE}✓ 已存在: conf.d/vhost_conf/http_https/${NC}"
fi

if [ ! -d "${PROJECT_ROOT}/conf.d/vhost_conf/tcp_udp" ]; then
    mkdir -p "${PROJECT_ROOT}/conf.d/vhost_conf/tcp_udp"
    echo -e "${GREEN}✓ 已创建: conf.d/vhost_conf/tcp_udp/${NC}"
else
    echo -e "${BLUE}✓ 已存在: conf.d/vhost_conf/tcp_udp/${NC}"
fi
echo -e "${GREEN}✓ 目录检查完成${NC}"

# 复制 nginx.conf（只复制主配置文件）
echo -e "${GREEN}[2/5] 复制并配置主配置文件...${NC}"

# 步骤1: 先删除旧文件，确保干净开始
if [ -f "$NGINX_CONF_DIR/nginx.conf" ]; then
    echo -e "${YELLOW}  删除旧配置文件: $NGINX_CONF_DIR/nginx.conf${NC}"
    rm -f "$NGINX_CONF_DIR/nginx.conf"
fi

# 步骤2: 复制模板文件到目标位置（不进行任何替换）
echo -e "${YELLOW}  复制模板文件: ${PROJECT_ROOT}/init_file/nginx.conf -> $NGINX_CONF_DIR/nginx.conf${NC}"
cp "${PROJECT_ROOT}/init_file/nginx.conf" "$NGINX_CONF_DIR/nginx.conf"

# 步骤3: 获取项目目录并修改配置（替换路径占位符）
echo -e "${YELLOW}  替换路径占位符...${NC}"
# 替换 error.log 路径（必须使用绝对路径，因为 error_log 不支持变量）
sed -i "s|/path/to/project/logs/error.log|$PROJECT_ROOT_ABS/logs/error.log|g" "$NGINX_CONF_DIR/nginx.conf"

# 替换所有 /path/to/project 路径占位符为实际项目路径
# 注意：使用全局替换，确保所有路径都被替换，包括子目录路径
sed -i "s|/path/to/project|$PROJECT_ROOT_ABS|g" "$NGINX_CONF_DIR/nginx.conf"

echo -e "${GREEN}  ✓ 已替换所有路径占位符${NC}"
echo -e "${BLUE}    替换的路径包括：${NC}"
echo -e "${BLUE}    - logs/error.log${NC}"
echo -e "${BLUE}    - conf.d/http_set/*.conf${NC}"
echo -e "${BLUE}    - conf.d/stream_set/*.conf${NC}"
echo -e "${BLUE}    - conf.d/vhost_conf/waf.conf${NC}"
echo -e "${BLUE}    - conf.d/vhost_conf/http_https/proxy_http_*.conf${NC}"
echo -e "${BLUE}    - conf.d/vhost_conf/tcp_udp/proxy_stream_*.conf${NC}"
echo -e "${BLUE}    - conf.d/upstream/http_https/http_upstream_*.conf${NC}"
echo -e "${BLUE}    - conf.d/upstream/tcp_udp/stream_upstream_*.conf${NC}"

# 删除 set $project_root 指令（某些 OpenResty 版本不支持在 http 块中使用 set）
# 我们会在子配置文件中直接替换 $project_root 为实际路径
sed -i '/set \$project_root/d' "$NGINX_CONF_DIR/nginx.conf"
# 删除相关的注释行（如果存在）
sed -i '/项目根目录变量/d' "$NGINX_CONF_DIR/nginx.conf"
sed -i '/此变量必须在 http 块的最开始设置/d' "$NGINX_CONF_DIR/nginx.conf"

# 替换子配置文件中的 $project_root 变量为实际路径
# 注意：由于某些 OpenResty 版本不支持在 http 块中使用 set 指令
# 我们直接在子配置文件中替换 $project_root 为实际路径
# 注意：只替换 conf.d/http_set 和 conf.d/vhost_conf 目录下的配置文件
echo -e "${YELLOW}  替换子配置文件中的 \$project_root 变量...${NC}"

# 需要替换的文件列表（明确指定，避免误替换）
REPLACE_FILES=(
    "$PROJECT_ROOT_ABS/conf.d/http_set/lua.conf"
    "$PROJECT_ROOT_ABS/conf.d/http_set/log.conf"
)

# 替换指定文件
for file in "${REPLACE_FILES[@]}"; do
    if [ -f "$file" ]; then
        # 检查文件是否包含 $project_root 变量
        if grep -q "\$project_root" "$file"; then
            # 只替换 $project_root 变量，不替换其他内容
            sed -i "s|\$project_root|$PROJECT_ROOT_ABS|g" "$file"
            echo -e "${GREEN}  ✓ 已替换: $(basename $file)${NC}"
        else
            echo -e "${BLUE}  - 跳过: $(basename $file) (不包含 \$project_root)${NC}"
        fi
        
    else
        echo -e "${YELLOW}  ⚠ 文件不存在: $(basename $file)${NC}"
    fi
done

# 替换 conf.d/vhost_conf 目录下可能使用 $project_root 的配置文件（包括子目录）
if [ -d "$PROJECT_ROOT_ABS/conf.d/vhost_conf" ]; then
    find "$PROJECT_ROOT_ABS/conf.d/vhost_conf" -name "*.conf" -type f | while read -r file; do
        if grep -q "\$project_root" "$file"; then
            # 获取相对路径用于显示
            relative_path="${file#$PROJECT_ROOT_ABS/conf.d/vhost_conf/}"
            if [ "$relative_path" = "$(basename $file)" ]; then
                # 文件在 vhost_conf 根目录
                display_path="vhost_conf/$(basename $file)"
            else
                # 文件在子目录中
                display_path="vhost_conf/$relative_path"
            fi
            sed -i "s|\$project_root|$PROJECT_ROOT_ABS|g" "$file"
            echo -e "${GREEN}  ✓ 已替换: $display_path${NC}"
        fi
    done
fi

echo -e "${GREEN}✓ 已替换子配置文件中的变量${NC}"

# 步骤3.5: 检查配置文件完整性（不进行截取，保留 stream 块）
# 验证文件行数是否与模板一致
template_lines=$(wc -l < "${PROJECT_ROOT}/init_file/nginx.conf" 2>/dev/null | tr -d ' ')
deployed_lines=$(wc -l < "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null | tr -d ' ')

if [ -n "$template_lines" ] && [ -n "$deployed_lines" ]; then
    if [ "$deployed_lines" -ne "$template_lines" ]; then
        echo -e "${YELLOW}⚠ 警告: 部署后的文件行数 ($deployed_lines) 与模板文件 ($template_lines) 不一致${NC}"
        echo -e "${BLUE}  这可能是正常的，如果模板文件已更新${NC}"
    fi
fi

# 步骤4: 检查 http 块后是否有不应该存在的内容（保留 stream 块）
# 找到 http 块结束位置
http_start_line=$(grep -n "^http {" "$NGINX_CONF_DIR/nginx.conf" | cut -d: -f1 | head -1)
if [ -n "$http_start_line" ]; then
    http_end_line=$(awk -v start="$http_start_line" '
        BEGIN { brace_count = 0; found_start = 0 }
        NR >= start {
            if (!found_start) found_start = 1
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
    ' "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null)
    
    if [ -n "$http_end_line" ]; then
        # 检查 http 块后的内容
        after_http_start=$((http_end_line + 1))
        
        # 检查是否有 stream 块（应该保留）
        stream_start_line=$(grep -n "^stream {" "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null | cut -d: -f1 | head -1)
        
        if [ -n "$stream_start_line" ] && [ "$stream_start_line" -gt "$http_end_line" ]; then
            # 有 stream 块，检查 http 块和 stream 块之间是否有不应该存在的内容
            if [ "$stream_start_line" -gt $((http_end_line + 1)) ]; then
                # http 块和 stream 块之间有内容，检查是否是注释或空行
                between_content=$(sed -n "$((http_end_line + 1)),$((stream_start_line - 1))p" "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null)
                # 检查是否包含不应该存在的指令（set、include，但不是注释）
                if echo "$between_content" | grep -qE "^\s*(set|include)"; then
                    echo -e "${YELLOW}⚠ 检测到 http 块和 stream 块之间有重复的配置指令，正在清理...${NC}"
                    # 保留 http 块、空行、stream 块及其后的所有内容
                    head -n "$http_end_line" "$NGINX_CONF_DIR/nginx.conf" > "$NGINX_CONF_DIR/nginx.conf.tmp"
                    echo "" >> "$NGINX_CONF_DIR/nginx.conf.tmp"
                    tail -n +$stream_start_line "$NGINX_CONF_DIR/nginx.conf" >> "$NGINX_CONF_DIR/nginx.conf.tmp"
                    mv "$NGINX_CONF_DIR/nginx.conf.tmp" "$NGINX_CONF_DIR/nginx.conf"
                    echo -e "${GREEN}✓ 已清理重复内容，保留 stream 块${NC}"
                else
                    # 只有注释或空行，保留
                    echo -e "${GREEN}✓ http 块和 stream 块之间只有注释或空行（正确）${NC}"
                fi
            else
                # http 块和 stream 块之间没有内容（或只有空行），这是正常的
                echo -e "${GREEN}✓ http 块后直接是 stream 块（正确）${NC}"
            fi
        else
            # 没有 stream 块，检查 http 块后是否有不应该存在的内容
            after_http_content=$(sed -n "${after_http_start},\$p" "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null | head -5)
            if [ -n "$after_http_content" ]; then
                # 检查是否有不应该存在的内容（如重复的 set、include 指令）
                if echo "$after_http_content" | grep -qE "^\s*(set|include)"; then
                    echo -e "${YELLOW}⚠ 检测到 http 块后有重复的配置指令，正在清理...${NC}"
                    # 清理所有 http 块后的内容（因为没有 stream 块）
                    head -n "$http_end_line" "$NGINX_CONF_DIR/nginx.conf" > "$NGINX_CONF_DIR/nginx.conf.tmp"
                    mv "$NGINX_CONF_DIR/nginx.conf.tmp" "$NGINX_CONF_DIR/nginx.conf"
                    echo -e "${GREEN}✓ 已清理重复内容${NC}"
                fi
            fi
        fi
    fi
fi

# 步骤5: 验证文件完整性（不强制截取，保留 stream 块）
template_lines=$(wc -l < "${PROJECT_ROOT}/init_file/nginx.conf" 2>/dev/null | tr -d ' ')
deployed_lines=$(wc -l < "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null | tr -d ' ')

if [ -n "$template_lines" ] && [ -n "$deployed_lines" ]; then
    if [ "$deployed_lines" -ne "$template_lines" ]; then
        echo -e "${YELLOW}⚠ 警告: 部署后的文件行数 ($deployed_lines) 与模板文件 ($template_lines) 不一致${NC}"
        echo -e "${BLUE}  如果模板文件包含 stream 块，这是正常的${NC}"
    else
        echo -e "${GREEN}✓ 文件行数与模板一致${NC}"
    fi
fi

# 步骤6: 确保文件以换行符结尾
if [ -f "$NGINX_CONF_DIR/nginx.conf" ]; then
    if ! tail -c 1 "$NGINX_CONF_DIR/nginx.conf" | grep -q '^$'; then
        echo "" >> "$NGINX_CONF_DIR/nginx.conf"
    fi
fi

echo -e "${GREEN}✓ 主配置文件已复制并配置${NC}"
echo -e "${YELLOW}  注意: conf.d、lua、logs、cert 目录保持在项目目录，使用相对路径引用${NC}"

# 验证配置文件
echo -e "${GREEN}[3/5] 验证配置...${NC}"

# 最终验证：检查配置文件结构（保留 stream 块）
echo -e "${YELLOW}  执行最终验证检查...${NC}"
template_lines=$(wc -l < "${PROJECT_ROOT}/init_file/nginx.conf" 2>/dev/null | tr -d ' ')
final_lines=$(wc -l < "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null | tr -d ' ')

# 检查是否包含 stream 块
if grep -q "^stream {" "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null; then
    echo -e "${GREEN}✓ 配置文件包含 stream 块${NC}"
    
    # 验证 stream 块是否完整
    stream_start_line=$(grep -n "^stream {" "$NGINX_CONF_DIR/nginx.conf" | cut -d: -f1 | head -1)
    if [ -n "$stream_start_line" ]; then
        stream_end_line=$(awk -v start="$stream_start_line" '
            BEGIN { brace_count = 0; found_start = 0 }
            NR >= start {
                if (!found_start) found_start = 1
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
        ' "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null)
        
        if [ -n "$stream_end_line" ]; then
            echo -e "${GREEN}✓ stream 块完整（第 $stream_start_line-$stream_end_line 行）${NC}"
        else
            echo -e "${YELLOW}⚠ 无法确定 stream 块结束位置${NC}"
        fi
    fi
else
    echo -e "${YELLOW}⚠ 配置文件不包含 stream 块（如果模板文件有 stream 块，这可能是问题）${NC}"
fi

# 验证文件行数
if [ -n "$template_lines" ] && [ -n "$final_lines" ]; then
    if [ "$final_lines" -eq "$template_lines" ]; then
        echo -e "${GREEN}✓ 文件行数与模板一致（$final_lines 行）${NC}"
    else
        echo -e "${YELLOW}⚠ 文件行数 ($final_lines) 与模板 ($template_lines) 不一致${NC}"
        echo -e "${BLUE}  如果模板文件包含 stream 块，这是正常的${NC}"
    fi
fi

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
            # 显示 http 块和 set 指令周围的内容
            http_start=$(grep -n "^http {" "$NGINX_CONF_DIR/nginx.conf" | cut -d: -f1 | head -1)
            if [ -n "$http_start" ]; then
                # 找到 http 块结束位置
                http_end=$(awk -v start="$http_start" '
                    BEGIN { brace_count = 0; found_start = 0 }
                    NR >= start {
                        if (!found_start) found_start = 1
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
                ' "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null)
                
                if [ -n "$http_end" ]; then
                    # 只显示 http 块内的内容
                    sed -n "${http_start},${http_end}p" "$NGINX_CONF_DIR/nginx.conf" || true
                else
                    # 如果无法找到结束位置，显示前15行
                    sed -n "${http_start},$((http_start + 15))p" "$NGINX_CONF_DIR/nginx.conf" || true
                fi
                
                # 检查是否有重复的 set 指令
                set_count=$(grep -c "set \$project_root" "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null || echo "0")
                # 清理 set_count 中的换行符和空格
                set_count=$(echo "$set_count" | tr -d '\n\r ' | head -1)
                if [ -n "$set_count" ] && [ "$set_count" -gt 1 ] 2>/dev/null; then
                    echo ""
                    echo -e "${RED}⚠ 检测到重复的 set \$project_root 指令（共 $set_count 个）${NC}"
                    echo "所有 set \$project_root 指令位置："
                    grep -n "set \$project_root" "$NGINX_CONF_DIR/nginx.conf" || true
                fi
            fi
            echo ""
            echo -e "${BLUE}配置文件总行数：$(wc -l < "$NGINX_CONF_DIR/nginx.conf")${NC}"
            echo -e "${BLUE}http 块开始行：${http_start}${NC}"
            if [ -n "$http_end" ]; then
                echo -e "${BLUE}http 块结束行：${http_end}${NC}"
            fi
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
    "${PROJECT_ROOT}/conf.d/http_set"
    "${PROJECT_ROOT}/conf.d/stream_set"
    "${PROJECT_ROOT}/conf.d/vhost_conf"
    "${PROJECT_ROOT}/conf.d/vhost_conf/http_https"
    "${PROJECT_ROOT}/conf.d/vhost_conf/tcp_udp"
    "${PROJECT_ROOT}/conf.d/upstream/http_https"
    "${PROJECT_ROOT}/conf.d/upstream/tcp_udp"
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

# 6. 检查配置文件语法和完整性（已在步骤3中完成，这里只是最终确认）
echo -e "${GREEN}[6/6] 最终确认...${NC}"

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
    "${PROJECT_ROOT}/conf.d/http_set/waf.conf"
    "${PROJECT_ROOT}/conf.d/http_set/lua.conf"
    "${PROJECT_ROOT}/conf.d/stream_set/waf.conf"
    "${PROJECT_ROOT}/conf.d/stream_set/lua.conf"
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

# 5. 设置权限
echo -e "${GREEN}[5/6] 设置文件权限...${NC}"

# 设置项目根目录的所有者为 waf:waf（但排除 .git 目录）
# 注意：.git 目录应该保持为 root 所有，避免 Git 安全警告
echo -e "${YELLOW}  设置项目目录所有者为 waf:waf（排除 .git 目录）...${NC}"

# 先设置整个项目目录为 waf:waf
chown -R "$WAF_USER:$WAF_GROUP" "${PROJECT_ROOT}" 2>/dev/null || {
    echo -e "${YELLOW}  ⚠ 无法设置项目目录所有者，继续执行...${NC}"
}

# 然后将 .git 目录改回 root，避免 Git 安全警告
# Git 2.35.2+ 版本会检查仓库所有者，如果所有者与当前用户不匹配会拒绝操作
if [ -d "${PROJECT_ROOT}/.git" ]; then
    echo -e "${YELLOW}  将 .git 目录所有者改回 root，避免 Git 安全警告...${NC}"
    chown -R root:root "${PROJECT_ROOT}/.git" 2>/dev/null || {
        echo -e "${YELLOW}  ⚠ 无法设置 .git 目录所有者，继续执行...${NC}"
    }
    echo -e "${GREEN}  ✓ .git 目录所有者已设置为 root:root${NC}"
    echo -e "${BLUE}    说明: .git 目录保持为 root 所有，项目文件为 waf:waf 所有${NC}"
fi

# 设置日志目录权限
chown -R "$WAF_USER:$WAF_GROUP" "${PROJECT_ROOT}/logs" 2>/dev/null || true
chmod 755 "${PROJECT_ROOT}/logs"
chmod 644 "$NGINX_CONF_DIR/nginx.conf"

# 设置 OpenResty 系统日志目录权限（/usr/local/openresty/nginx/logs）
# 说明：这里的 error.log 和 nginx.pid 是 OpenResty 自带目录，必须确保 waf 用户可读写
if [ -d "${OPENRESTY_PREFIX}/nginx/logs" ]; then
    echo -e "${YELLOW}  设置 OpenResty 系统日志目录所有者为 waf:waf...${NC}"
    chown -R "$WAF_USER:$WAF_GROUP" "${OPENRESTY_PREFIX}/nginx/logs" 2>/dev/null || {
        echo -e "${YELLOW}  ⚠ 无法设置 ${OPENRESTY_PREFIX}/nginx/logs 所有者，可能影响 error.log/nginx.pid 访问权限${NC}"
    }
    chmod 755 "${OPENRESTY_PREFIX}/nginx/logs" 2>/dev/null || true
fi

# conf.d 保持在项目目录，设置项目目录权限
# 重要：确保 nginx worker 进程（waf 用户）可以写入配置文件
chown -R "$WAF_USER:$WAF_GROUP" "${PROJECT_ROOT}/conf.d" 2>/dev/null || true
chmod -R 755 "${PROJECT_ROOT}/conf.d" 2>/dev/null || true
find "${PROJECT_ROOT}/conf.d" -type f -name "*.conf" -exec chmod 644 {} \; 2>/dev/null || true

# 特别确保 vhost_conf 和 upstream 目录有写入权限
# 注意：使用 chown -R 递归处理，确保目录下所有文件（包括 waf.conf、waf_admin_ssl.conf 等）都归属 waf 用户
chown -R "$WAF_USER:$WAF_GROUP" "${PROJECT_ROOT}/conf.d/vhost_conf" 2>/dev/null || true
chmod -R 755 "${PROJECT_ROOT}/conf.d/vhost_conf" 2>/dev/null || true
# 将所有 .conf 文件权限统一设置为 644（目录权限已在上面设置为 755）
find "${PROJECT_ROOT}/conf.d/vhost_conf" -type f -name "*.conf" -exec chmod 644 {} \; 2>/dev/null || true

# 检查并修复 waf_admin_ssl.conf 文件
# 如果文件包含不完整的 SSL 配置（有 listen 443 ssl 但没有 ssl_certificate），则重置为占位文件
WAF_ADMIN_SSL_CONF="${PROJECT_ROOT}/conf.d/vhost_conf/waf_admin_ssl.conf"
if [ -f "$WAF_ADMIN_SSL_CONF" ]; then
    # 检查文件是否包含 listen 443 ssl 但没有 ssl_certificate
    if grep -q "listen.*443.*ssl" "$WAF_ADMIN_SSL_CONF" 2>/dev/null && ! grep -q "ssl_certificate" "$WAF_ADMIN_SSL_CONF" 2>/dev/null; then
        echo -e "${YELLOW}  检测到 waf_admin_ssl.conf 包含不完整的 SSL 配置，重置为占位文件...${NC}"
        cat > "$WAF_ADMIN_SSL_CONF" << 'EOF'
#
# waf_admin_ssl.conf
# --------------------------------------------
# 管理端 HTTPS 配置占位文件
#
# 说明：
# - 此文件会被 waf.conf 中的 include 指令加载：
#     include $project_root/conf.d/vhost_conf/waf_admin_ssl.conf;
# - 当你在"系统设置 → 管理端SSL/域名"中未启用 SSL 时，
#   后端会保持本文件只包含注释，不生成任何 listen/ssl 配置，
#   因此不会影响管理端通过 HTTP(80) 的访问。
# - 当你在系统设置中启用管理端 SSL 时，
#   后端会自动覆盖本文件，写入：
#     - listen 443 ssl;
#     - server_name ...;
#     - ssl_certificate / ssl_certificate_key 等指令；
#     - 以及可选的 HTTP→HTTPS 301 跳转逻辑（根据 admin_force_https 开关）。
#
# 如果你看到的只是这些注释，说明当前尚未在系统设置中启用管理端 HTTPS。
#

EOF
        chown "$WAF_USER:$WAF_GROUP" "$WAF_ADMIN_SSL_CONF" 2>/dev/null || true
        chmod 644 "$WAF_ADMIN_SSL_CONF" 2>/dev/null || true
        echo -e "${GREEN}  ✓ waf_admin_ssl.conf 已重置为占位文件${NC}"
    fi
fi

chown -R "$WAF_USER:$WAF_GROUP" "${PROJECT_ROOT}/conf.d/vhost_conf/http_https" 2>/dev/null || true
chmod 755 "${PROJECT_ROOT}/conf.d/vhost_conf/http_https" 2>/dev/null || true
chown -R "$WAF_USER:$WAF_GROUP" "${PROJECT_ROOT}/conf.d/vhost_conf/tcp_udp" 2>/dev/null || true
chmod 755 "${PROJECT_ROOT}/conf.d/vhost_conf/tcp_udp" 2>/dev/null || true
chown -R "$WAF_USER:$WAF_GROUP" "${PROJECT_ROOT}/conf.d/upstream/http_https" 2>/dev/null || true
chmod 755 "${PROJECT_ROOT}/conf.d/upstream/http_https" 2>/dev/null || true
chown -R "$WAF_USER:$WAF_GROUP" "${PROJECT_ROOT}/conf.d/upstream/tcp_udp" 2>/dev/null || true
chmod 755 "${PROJECT_ROOT}/conf.d/upstream/tcp_udp" 2>/dev/null || true

# 设置 lua 目录权限（确保 waf 用户可以读取）
chown -R "$WAF_USER:$WAF_GROUP" "${PROJECT_ROOT}/lua" 2>/dev/null || true
chmod -R 755 "${PROJECT_ROOT}/lua" 2>/dev/null || true

echo -e "${GREEN}✓ 权限设置完成${NC}"
echo -e "${YELLOW}  注意: 所有项目目录的所有者已设置为 waf:waf，权限为 755${NC}"
echo -e "${YELLOW}  这确保 nginx worker 进程（waf 用户）可以创建和修改配置文件${NC}"

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
echo "    - http_set/: HTTP参数配置文件"
echo "    - stream_set/: Stream参数配置文件"
echo "    - vhost_conf/: 虚拟主机配置"
echo "      - waf.conf: WAF管理服务配置（手动配置）"
echo "      - http_https/: HTTP/HTTPS代理的server配置（自动生成）"
echo "      - tcp_udp/: TCP/UDP代理的server配置（自动生成）"
echo "    - upstream/: 自动生成的upstream配置"
echo "      - http_https/: HTTP/HTTPS代理的upstream配置"
echo "      - tcp_udp/: TCP/UDP代理的upstream配置"
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

