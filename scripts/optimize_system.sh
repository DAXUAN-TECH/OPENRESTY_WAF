#!/bin/bash

# OpenResty WAF 系统优化脚本
# 用途：根据硬件信息自动优化系统和 OpenResty 配置，提高负载并发能力

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

# OpenResty 安装目录
OPENRESTY_PREFIX="${OPENRESTY_PREFIX:-/usr/local/openresty}"
NGINX_CONF_DIR="${OPENRESTY_PREFIX}/nginx/conf"

# 备份目录（相对于脚本位置）
BACKUP_DIR="${SCRIPT_DIR}/../backup/optimize_$(date +%Y%m%d_%H%M%S)"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}OpenResty WAF 系统优化脚本${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 需要 root 权限来优化系统${NC}"
    echo "请使用: sudo $0"
    exit 1
fi

# ============================================
# 1. 检测硬件信息
# ============================================
echo -e "${BLUE}[1/6] 检测硬件信息...${NC}"

# CPU 核心数
CPU_CORES=$(nproc)
echo "  CPU 核心数: $CPU_CORES"

# 物理内存（MB）
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
echo "  总内存: ${TOTAL_MEM}MB"

# 可用内存（MB）
AVAIL_MEM=$(free -m | awk '/^Mem:/{print $7}')
echo "  可用内存: ${AVAIL_MEM}MB"

# 系统架构
ARCH=$(uname -m)
echo "  系统架构: $ARCH"

# 内核版本
KERNEL=$(uname -r)
echo "  内核版本: $KERNEL"

# 操作系统
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME="$NAME"
    OS_VERSION="$VERSION_ID"
    echo "  操作系统: $OS_NAME $OS_VERSION"
fi

echo -e "${GREEN}✓ 硬件信息检测完成${NC}"
echo ""

# ============================================
# 2. 计算优化参数
# ============================================
echo -e "${BLUE}[2/6] 计算优化参数...${NC}"

# Worker 进程数（建议等于 CPU 核心数）
WORKER_PROCESSES=$CPU_CORES
echo "  Worker 进程数: $WORKER_PROCESSES"

# 每个 Worker 的连接数（根据内存自动调整，上限 65535）
# 参考 docs/性能优化指南.md 中的低/中/高并发建议：
# - 低内存（<2GB）：低并发配置，worker_connections=10240
# - 中等内存（2GB-8GB）：中并发配置，worker_connections=32768
# - 高内存（>=8GB）：高并发配置，worker_connections=65535
if [ "$TOTAL_MEM" -lt 2048 ]; then
    WORKER_CONNECTIONS=10240
elif [ "$TOTAL_MEM" -lt 8192 ]; then
    WORKER_CONNECTIONS=32768
else
    WORKER_CONNECTIONS=65535
fi
echo "  每个 Worker 连接数: $WORKER_CONNECTIONS (根据内存自动计算)"

# 理论最大并发连接数
MAX_CONNECTIONS=$((WORKER_PROCESSES * WORKER_CONNECTIONS))
echo "  理论最大并发连接数: $MAX_CONNECTIONS"

# 文件描述符限制（建议为最大并发数的 2 倍，但不超过系统能力）
ULIMIT_NOFILE=$((MAX_CONNECTIONS * 2))
# 理论上限 100 万，避免过大
if [ "$ULIMIT_NOFILE" -gt 1000000 ]; then
    ULIMIT_NOFILE=1000000
fi

# 如果支持，读取当前系统 fs.nr_open 作为硬上限，进一步裁剪
if [ -r /proc/sys/fs/nr_open ]; then
    SYS_NR_OPEN=$(cat /proc/sys/fs/nr_open 2>/dev/null || echo 0)
    if [ "$SYS_NR_OPEN" -gt 0 ] && [ "$ULIMIT_NOFILE" -gt "$SYS_NR_OPEN" ]; then
        ULIMIT_NOFILE="$SYS_NR_OPEN"
    fi
fi

echo "  文件描述符限制: $ULIMIT_NOFILE"

# 共享内存大小（根据内存计算）
# WAF 缓存：10MB
# 日志缓冲区：50MB
# 其他：根据总内存的 1% 计算，最小 100MB，最大 500MB
SHARED_MEM_SIZE=$((TOTAL_MEM / 100))
if [ $SHARED_MEM_SIZE -lt 100 ]; then
    SHARED_MEM_SIZE=100
elif [ $SHARED_MEM_SIZE -gt 500 ]; then
    SHARED_MEM_SIZE=500
fi
echo "  共享内存大小: ${SHARED_MEM_SIZE}MB"

# Keepalive 连接数（建议为 worker_connections 的 1/4）
KEEPALIVE_CONNECTIONS=$((WORKER_CONNECTIONS / 4))
if [ $KEEPALIVE_CONNECTIONS -gt 1024 ]; then
    KEEPALIVE_CONNECTIONS=1024
fi
echo "  Keepalive 连接数: $KEEPALIVE_CONNECTIONS"

echo -e "${GREEN}✓ 优化参数计算完成${NC}"
echo ""

# ============================================
# 3. 创建备份
# ============================================
echo -e "${BLUE}[3/6] 创建备份...${NC}"
mkdir -p "$BACKUP_DIR"

# 备份系统配置文件
if [ -f /etc/security/limits.conf ]; then
    cp /etc/security/limits.conf "$BACKUP_DIR/limits.conf.bak"
fi

if [ -f /etc/sysctl.conf ]; then
    cp /etc/sysctl.conf "$BACKUP_DIR/sysctl.conf.bak"
fi

# 备份 Nginx 配置
if [ -f "$NGINX_CONF_DIR/nginx.conf" ]; then
    cp "$NGINX_CONF_DIR/nginx.conf" "$BACKUP_DIR/nginx.conf.bak"
fi

if [ -f "${SCRIPT_DIR}/../conf.d/http_set/performance.conf" ]; then
    cp "${SCRIPT_DIR}/../conf.d/http_set/performance.conf" "$BACKUP_DIR/performance.conf.bak"
fi

echo -e "${GREEN}✓ 备份完成: $BACKUP_DIR${NC}"
echo ""

# ============================================
# 4. 优化系统参数
# ============================================
echo -e "${BLUE}[4/6] 优化系统参数...${NC}"

# 4.1 优化文件描述符限制
echo "  优化文件描述符限制..."

# 检测 OpenResty 运行用户
OPENRESTY_USER="nobody"
if pgrep -f "nginx: master" > /dev/null 2>&1; then
    # 检测 master 进程的用户
    DETECTED_USER=$(ps -o user= -p $(pgrep -f "nginx: master" | head -1) 2>/dev/null | tr -d ' ' || echo "")
    if [ -n "$DETECTED_USER" ]; then
        OPENRESTY_USER="$DETECTED_USER"
        echo "    检测到 OpenResty 运行用户: $OPENRESTY_USER"
    fi
else
    # 检查 systemd 服务文件中的用户配置
    SYSTEMD_SERVICE="/etc/systemd/system/openresty.service"
    if [ -f "$SYSTEMD_SERVICE" ] && grep -q "^User=" "$SYSTEMD_SERVICE"; then
        DETECTED_USER=$(grep "^User=" "$SYSTEMD_SERVICE" | cut -d'=' -f2 | tr -d ' ')
        if [ -n "$DETECTED_USER" ]; then
            OPENRESTY_USER="$DETECTED_USER"
            echo "    从 systemd 服务文件检测到用户: $OPENRESTY_USER"
        fi
    fi
fi

if ! grep -q "# OpenResty WAF Optimization" /etc/security/limits.conf; then
    # 配置不存在，添加新配置
    cat >> /etc/security/limits.conf <<EOF

# OpenResty WAF Optimization
* soft nofile $ULIMIT_NOFILE
* hard nofile $ULIMIT_NOFILE
root soft nofile $ULIMIT_NOFILE
root hard nofile $ULIMIT_NOFILE
nobody soft nofile $ULIMIT_NOFILE
nobody hard nofile $ULIMIT_NOFILE
$OPENRESTY_USER soft nofile $ULIMIT_NOFILE
$OPENRESTY_USER hard nofile $ULIMIT_NOFILE
EOF
    echo -e "    ${GREEN}✓ 已添加文件描述符限制（包含用户: $OPENRESTY_USER）${NC}"
else
    # 配置已存在，检查是否需要添加当前运行用户
    if [ "$OPENRESTY_USER" != "nobody" ] && ! grep -q "^$OPENRESTY_USER soft nofile" /etc/security/limits.conf; then
        # 在 OpenResty WAF Optimization 块末尾添加当前运行用户
        # 找到 OpenResty WAF Optimization 注释行后的最后一个配置行
        optimization_start=$(grep -n "# OpenResty WAF Optimization" /etc/security/limits.conf | cut -d: -f1)
        if [ -n "$optimization_start" ]; then
            # 找到该块内的最后一行配置（非注释、非空行，包含nofile）
            last_config_line=$(awk -v start="$optimization_start" '
                NR >= start && !/^#/ && !/^$/ && /nofile/ {
                    last = NR
                }
                END {
                    print last
                }
            ' /etc/security/limits.conf)
            
            if [ -n "$last_config_line" ]; then
                # 在最后一行配置后添加新用户配置
                sed -i "${last_config_line}a $OPENRESTY_USER soft nofile $ULIMIT_NOFILE\n$OPENRESTY_USER hard nofile $ULIMIT_NOFILE" /etc/security/limits.conf
                echo -e "    ${GREEN}✓ 已添加缺失的用户 $OPENRESTY_USER 到文件描述符限制${NC}"
            else
                # 如果找不到配置行，直接在注释行后添加
                sed -i "${optimization_start}a $OPENRESTY_USER soft nofile $ULIMIT_NOFILE\n$OPENRESTY_USER hard nofile $ULIMIT_NOFILE" /etc/security/limits.conf
                echo -e "    ${GREEN}✓ 已添加缺失的用户 $OPENRESTY_USER 到文件描述符限制${NC}"
            fi
        else
            echo -e "    ${YELLOW}⚠ 无法找到 OpenResty WAF Optimization 配置块，请手动添加用户 $OPENRESTY_USER${NC}"
        fi
    else
        if [ "$OPENRESTY_USER" = "nobody" ]; then
            echo -e "    ${BLUE}✓ 文件描述符限制已存在，当前运行用户为 nobody（已包含）${NC}"
        else
            echo -e "    ${BLUE}✓ 文件描述符限制已存在，当前运行用户 $OPENRESTY_USER 已在配置中${NC}"
        fi
    fi
fi

# 4.1.1 更新 systemd 服务文件中的 LimitNOFILE
echo "  更新 systemd 服务文件..."
SYSTEMD_SERVICE="/etc/systemd/system/openresty.service"
if [ -f "$SYSTEMD_SERVICE" ]; then
    # 确保 [Service] 段存在
    if ! grep -q "^\[Service\]" "$SYSTEMD_SERVICE"; then
        echo -e "    ${YELLOW}⚠ 服务文件中未找到 [Service] 段，跳过 LimitNOFILE 更新${NC}"
    else
        # 更新或插入 LimitNOFILE
        if grep -q "^LimitNOFILE=" "$SYSTEMD_SERVICE"; then
            sed -i "s/^LimitNOFILE=.*/LimitNOFILE=$ULIMIT_NOFILE/" "$SYSTEMD_SERVICE"
            echo -e "    ${GREEN}✓ 已更新 systemd 服务文件中的 LimitNOFILE=${NC}"
        else
            # 在 [Service] 行之后插入 LimitNOFILE
            sed -i "/^\[Service\]/a LimitNOFILE=$ULIMIT_NOFILE" "$SYSTEMD_SERVICE"
            echo -e "    ${GREEN}✓ 已添加 LimitNOFILE=$ULIMIT_NOFILE 到 systemd 服务文件${NC}"
        fi
        
        # 重新加载 systemd 配置
        if command -v systemctl >/dev/null 2>&1; then
            if systemctl daemon-reload 2>/dev/null; then
                echo -e "    ${GREEN}✓ 已重新加载 systemd 配置${NC}"
            else
                echo -e "    ${YELLOW}⚠ 无法执行 systemctl daemon-reload，请手动运行${NC}"
            fi
        fi
    fi
else
    echo -e "    ${YELLOW}⚠ 未找到 systemd 服务文件，跳过 LimitNOFILE 更新${NC}"
fi

# 4.2 优化内核参数
echo "  优化内核参数..."

# 检测内核版本（用于判断是否支持某些参数）
KERNEL_MAJOR=$(uname -r | cut -d. -f1)
KERNEL_MINOR=$(uname -r | cut -d. -f2)
KERNEL_VERSION_NUM=$((KERNEL_MAJOR * 100 + KERNEL_MINOR))

# 检测系统是否支持某些参数
check_sysctl_param() {
    local param="$1"
    if sysctl "$param" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# 检测 nf_conntrack 模块是否加载
NF_CONNTRACK_AVAILABLE=0
if check_sysctl_param "net.netfilter.nf_conntrack_max"; then
    NF_CONNTRACK_AVAILABLE=1
fi

# 检测 fs.nr_open 的最大值（如果系统支持）
FS_NR_OPEN_MAX=0
if [ -r /proc/sys/fs/nr_open ]; then
    FS_NR_OPEN_MAX=$(cat /proc/sys/fs/nr_open 2>/dev/null || echo 0)
fi

# 确保 fs.nr_open 不超过系统支持的最大值
if [ "$FS_NR_OPEN_MAX" -gt 0 ] && [ "$ULIMIT_NOFILE" -gt "$FS_NR_OPEN_MAX" ]; then
    echo -e "    ${YELLOW}⚠ fs.nr_open 值 ($ULIMIT_NOFILE) 超过系统最大值 ($FS_NR_OPEN_MAX)，调整为 $FS_NR_OPEN_MAX${NC}"
    FS_NR_OPEN_VALUE=$FS_NR_OPEN_MAX
else
    FS_NR_OPEN_VALUE=$ULIMIT_NOFILE
fi

if ! grep -q "# OpenResty WAF Optimization" /etc/sysctl.conf; then
    # 构建内核参数配置（根据系统支持情况动态生成）
    SYSCTL_CONFIG="# OpenResty WAF Optimization
# 网络优化
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 32768
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
"
    
    # tcp_tw_recycle 在 Linux 4.12+ 中已移除，只在不支持时添加
    if [ "$KERNEL_VERSION_NUM" -lt 412 ]; then
        if check_sysctl_param "net.ipv4.tcp_tw_recycle"; then
            SYSCTL_CONFIG="${SYSCTL_CONFIG}net.ipv4.tcp_tw_recycle = 0
"
        fi
    fi
    
    SYSCTL_CONFIG="${SYSCTL_CONFIG}net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 15
"
    
    # 连接跟踪优化（仅在模块加载时添加）
    if [ "$NF_CONNTRACK_AVAILABLE" -eq 1 ]; then
        SYSCTL_CONFIG="${SYSCTL_CONFIG}
# 连接跟踪优化
net.netfilter.nf_conntrack_max = 1000000
net.netfilter.nf_conntrack_tcp_timeout_established = 1200
"
    fi
    
    SYSCTL_CONFIG="${SYSCTL_CONFIG}
# 内存优化
vm.overcommit_memory = 1
vm.swappiness = 10

# 文件系统优化
fs.file-max = $ULIMIT_NOFILE
"
    
    # fs.nr_open 仅在系统支持时添加
    if [ "$FS_NR_OPEN_MAX" -gt 0 ]; then
        SYSCTL_CONFIG="${SYSCTL_CONFIG}fs.nr_open = $FS_NR_OPEN_VALUE
"
    fi
    
    SYSCTL_CONFIG="${SYSCTL_CONFIG}
# IP 转发（如果需要）
# net.ipv4.ip_forward = 1
"
    
    # 写入配置
    echo "$SYSCTL_CONFIG" >> /etc/sysctl.conf
    echo -e "    ${GREEN}✓ 已添加内核参数优化${NC}"
    
    if [ "$NF_CONNTRACK_AVAILABLE" -eq 0 ]; then
        echo -e "    ${YELLOW}⚠ 注意: nf_conntrack 模块未加载，已跳过连接跟踪优化参数${NC}"
    fi
    
    if [ "$FS_NR_OPEN_MAX" -eq 0 ]; then
        echo -e "    ${YELLOW}⚠ 注意: 系统不支持 fs.nr_open，已跳过该参数${NC}"
    fi
else
    echo -e "    ${YELLOW}⚠ 内核参数优化已存在，跳过${NC}"
fi

# 应用内核参数（带详细错误检查）
echo "  验证并应用内核参数..."
SYSCTL_ERROR_OUTPUT=$(sysctl -p 2>&1)
SYSCTL_EXIT_CODE=$?

if [ $SYSCTL_EXIT_CODE -eq 0 ]; then
    echo -e "    ${GREEN}✓ 已应用内核参数${NC}"
else
    # 检查是否有严重错误（可能导致系统启动失败）
    if echo "$SYSCTL_ERROR_OUTPUT" | grep -qiE "unknown key|invalid argument|permission denied|read-only"; then
        echo -e "    ${RED}✗ 内核参数应用失败，存在严重错误！${NC}"
        echo -e "    ${RED}   这可能导致系统启动失败！${NC}"
        echo ""
        echo -e "    ${YELLOW}错误详情:${NC}"
        echo "$SYSCTL_ERROR_OUTPUT" | head -10
        echo ""
        echo -e "    ${YELLOW}建议操作:${NC}"
        echo "    1. 检查 /etc/sysctl.conf 中的错误参数"
        echo "    2. 从备份恢复: cp $BACKUP_DIR/sysctl.conf.bak /etc/sysctl.conf"
        echo "    3. 或手动修复错误参数后重新运行脚本"
        echo ""
        echo -e "    ${RED}警告: 如果系统无法启动，请使用恢复模式修复 /etc/sysctl.conf${NC}"
        exit 1
    else
        # 非严重错误（如某些参数不支持，但不影响系统启动）
        echo -e "    ${YELLOW}⚠ 内核参数应用时出现警告（非严重错误）${NC}"
        echo -e "    ${YELLOW}   某些参数可能不被当前内核支持，但不影响系统启动${NC}"
        if [ -n "$SYSCTL_ERROR_OUTPUT" ]; then
            echo -e "    ${BLUE}警告信息:${NC}"
            echo "$SYSCTL_ERROR_OUTPUT" | head -5
        fi
    fi
fi

# 4.3 优化网络参数（临时生效）
echo "  优化网络参数（临时生效）..."
sysctl -w net.core.somaxconn=65535 > /dev/null 2>&1 || true
sysctl -w net.core.netdev_max_backlog=32768 > /dev/null 2>&1 || true
sysctl -w net.ipv4.tcp_max_syn_backlog=8192 > /dev/null 2>&1 || true
sysctl -w fs.file-max=$ULIMIT_NOFILE > /dev/null 2>&1 || true

echo -e "${GREEN}✓ 系统参数优化完成${NC}"
echo ""

# ============================================
# 5. 优化 OpenResty/Nginx 配置
# ============================================
echo -e "${BLUE}[5/6] 优化 OpenResty/Nginx 配置...${NC}"

# 5.1 优化 nginx.conf
if [ -f "$NGINX_CONF_DIR/nginx.conf" ]; then
    echo "  优化 nginx.conf..."
    
    # 更新 worker_processes
    if grep -q "^worker_processes" "$NGINX_CONF_DIR/nginx.conf"; then
        sed -i "s/^worker_processes.*/worker_processes $WORKER_PROCESSES;/" "$NGINX_CONF_DIR/nginx.conf"
    else
        # 在 user 行后添加
        sed -i "/^user/a worker_processes $WORKER_PROCESSES;" "$NGINX_CONF_DIR/nginx.conf"
    fi
    
    # 更新 worker_connections
    if grep -q "worker_connections" "$NGINX_CONF_DIR/nginx.conf"; then
        sed -i "s/worker_connections.*/worker_connections  $WORKER_CONNECTIONS;/" "$NGINX_CONF_DIR/nginx.conf"
    fi
    
    echo -e "    ${GREEN}✓ nginx.conf 已优化（worker_processes=$WORKER_PROCESSES, worker_connections=$WORKER_CONNECTIONS）${NC}"
fi

# 5.2 优化 performance.conf
if [ -f "${SCRIPT_DIR}/../conf.d/http_set/performance.conf" ]; then
    echo "  优化 performance.conf..."
    
    # 更新 keepalive 连接数
    if grep -q "keepalive " "${SCRIPT_DIR}/../conf.d/http_set/performance.conf"; then
        sed -i "s/keepalive [0-9]*;/keepalive $KEEPALIVE_CONNECTIONS;/" "${SCRIPT_DIR}/../conf.d/http_set/performance.conf"
    fi
    
    echo -e "    ${GREEN}✓ performance.conf 已优化${NC}"
fi

# 5.3 优化 upstream.conf
if [ -f "${SCRIPT_DIR}/../conf.d/http_set/upstream.conf" ]; then
    echo "  优化 upstream.conf..."
    
    # 更新 keepalive
    if grep -q "keepalive " "${SCRIPT_DIR}/../conf.d/http_set/upstream.conf"; then
        sed -i "s/keepalive [0-9]*;/keepalive $KEEPALIVE_CONNECTIONS;/" "${SCRIPT_DIR}/../conf.d/http_set/upstream.conf"
    fi
    
    echo -e "    ${GREEN}✓ upstream.conf 已优化${NC}"
fi

# 5.4 优化 waf.conf 共享内存（HTTP块）
if [ -f "${SCRIPT_DIR}/../conf.d/http_set/waf.conf" ]; then
    echo "  优化 http_set/waf.conf 共享内存..."
    
    # 更新 waf_cache（10MB）
    if grep -q "lua_shared_dict waf_cache" "${SCRIPT_DIR}/../conf.d/http_set/waf.conf"; then
        sed -i "s/lua_shared_dict waf_cache [0-9]*m;/lua_shared_dict waf_cache 10m;/" "${SCRIPT_DIR}/../conf.d/http_set/waf.conf"
    fi
    
    # 更新 waf_log_buffer（50MB）
    if grep -q "lua_shared_dict waf_log_buffer" "${SCRIPT_DIR}/../conf.d/http_set/waf.conf"; then
        sed -i "s/lua_shared_dict waf_log_buffer [0-9]*m;/lua_shared_dict waf_log_buffer 50m;/" "${SCRIPT_DIR}/../conf.d/http_set/waf.conf"
    fi
fi

# 5.5 优化 waf.conf 共享内存（Stream块）
if [ -f "${SCRIPT_DIR}/../conf.d/stream_set/waf.conf" ]; then
    echo "  优化 stream_set/waf.conf 共享内存..."
    
    # 更新 waf_cache（10MB）
    if grep -q "lua_shared_dict waf_cache" "${SCRIPT_DIR}/../conf.d/stream_set/waf.conf"; then
        sed -i "s/lua_shared_dict waf_cache [0-9]*m;/lua_shared_dict waf_cache 10m;/" "${SCRIPT_DIR}/../conf.d/stream_set/waf.conf"
    fi
    
    # 更新 waf_log_buffer（50MB）
    if grep -q "lua_shared_dict waf_log_buffer" "${SCRIPT_DIR}/../conf.d/stream_set/waf.conf"; then
        sed -i "s/lua_shared_dict waf_log_buffer [0-9]*m;/lua_shared_dict waf_log_buffer 50m;/" "${SCRIPT_DIR}/../conf.d/stream_set/waf.conf"
    fi
    
    echo -e "    ${GREEN}✓ waf.conf 已优化${NC}"
fi

echo -e "${GREEN}✓ OpenResty/Nginx 配置优化完成${NC}"
echo ""

# ============================================
# 6. 验证和总结
# ============================================
echo -e "${BLUE}[6/6] 验证配置...${NC}"

# 验证文件描述符限制
CURRENT_ULIMIT=$(ulimit -n)
echo "  当前文件描述符限制: $CURRENT_ULIMIT"

# 验证内核参数
CURRENT_SOMAXCONN=$(sysctl -n net.core.somaxconn)
echo "  当前 somaxconn: $CURRENT_SOMAXCONN"

# 验证 Nginx 配置
if [ -f "$NGINX_CONF_DIR/nginx.conf" ]; then
    if $OPENRESTY_PREFIX/bin/openresty -t > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓ Nginx 配置语法正确${NC}"
    else
        echo -e "  ${RED}✗ Nginx 配置语法错误，请检查${NC}"
        echo "  运行以下命令查看错误："
        echo "    $OPENRESTY_PREFIX/bin/openresty -t"
    fi
fi

echo -e "${GREEN}✓ 验证完成${NC}"
echo ""

# ============================================
# 输出优化总结
# ============================================
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}系统优化完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "优化参数总结:"
echo "  - Worker 进程数: $WORKER_PROCESSES"
echo "  - 每个 Worker 连接数: $WORKER_CONNECTIONS"
echo "  - 理论最大并发: $MAX_CONNECTIONS"
echo "  - 文件描述符限制: $ULIMIT_NOFILE"
echo "  - Keepalive 连接数: $KEEPALIVE_CONNECTIONS"
echo ""
echo "备份位置: $BACKUP_DIR"
echo ""
echo "下一步操作:"
echo "  1. 重新登录或运行 'ulimit -n $ULIMIT_NOFILE' 使文件描述符限制生效"
echo "  2. 测试 Nginx 配置: $OPENRESTY_PREFIX/bin/openresty -t"
echo "  3. 重启 OpenResty 使配置生效:"
echo "     systemctl restart openresty"
echo "     或"
echo "     $OPENRESTY_PREFIX/bin/openresty -s reload"
echo ""
echo -e "${YELLOW}重要提示:${NC}"
echo "  - 文件描述符限制需要重新登录才能完全生效"
echo "  - 或者运行以下命令临时生效（当前会话）:"
echo "     ulimit -n $ULIMIT_NOFILE"
echo "  - 内核参数优化已写入 /etc/sysctl.conf，重启后自动生效"
echo "  - 如需恢复，备份文件在: $BACKUP_DIR"
echo ""

