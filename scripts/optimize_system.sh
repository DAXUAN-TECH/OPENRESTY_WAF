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

# 每个 Worker 的连接数（最大 65535）
WORKER_CONNECTIONS=65535
echo "  每个 Worker 连接数: $WORKER_CONNECTIONS"

# 理论最大并发连接数
MAX_CONNECTIONS=$((WORKER_PROCESSES * WORKER_CONNECTIONS))
echo "  理论最大并发连接数: $MAX_CONNECTIONS"

# 文件描述符限制（建议为最大并发数的 2 倍）
ULIMIT_NOFILE=$((MAX_CONNECTIONS * 2))
if [ $ULIMIT_NOFILE -gt 1000000 ]; then
    ULIMIT_NOFILE=1000000  # 最大限制为 100 万
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

if [ -f "${SCRIPT_DIR}/../conf.d/set_conf/performance.conf" ]; then
    cp "${SCRIPT_DIR}/../conf.d/set_conf/performance.conf" "$BACKUP_DIR/performance.conf.bak"
fi

echo -e "${GREEN}✓ 备份完成: $BACKUP_DIR${NC}"
echo ""

# ============================================
# 4. 优化系统参数
# ============================================
echo -e "${BLUE}[4/6] 优化系统参数...${NC}"

# 4.1 优化文件描述符限制
echo "  优化文件描述符限制..."
if ! grep -q "# OpenResty WAF Optimization" /etc/security/limits.conf; then
    cat >> /etc/security/limits.conf <<EOF

# OpenResty WAF Optimization
* soft nofile $ULIMIT_NOFILE
* hard nofile $ULIMIT_NOFILE
root soft nofile $ULIMIT_NOFILE
root hard nofile $ULIMIT_NOFILE
nobody soft nofile $ULIMIT_NOFILE
nobody hard nofile $ULIMIT_NOFILE
EOF
    echo -e "    ${GREEN}✓ 已添加文件描述符限制${NC}"
else
    echo -e "    ${YELLOW}⚠ 文件描述符限制已存在，跳过${NC}"
fi

# 4.2 优化内核参数
echo "  优化内核参数..."
if ! grep -q "# OpenResty WAF Optimization" /etc/sysctl.conf; then
    cat >> /etc/sysctl.conf <<EOF

# OpenResty WAF Optimization
# 网络优化
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 32768
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 15

# 连接跟踪优化
net.netfilter.nf_conntrack_max = 1000000
net.netfilter.nf_conntrack_tcp_timeout_established = 1200

# 内存优化
vm.overcommit_memory = 1
vm.swappiness = 10

# 文件系统优化
fs.file-max = $ULIMIT_NOFILE
fs.nr_open = $ULIMIT_NOFILE

# IP 转发（如果需要）
# net.ipv4.ip_forward = 1
EOF
    echo -e "    ${GREEN}✓ 已添加内核参数优化${NC}"
else
    echo -e "    ${YELLOW}⚠ 内核参数优化已存在，跳过${NC}"
fi

# 应用内核参数
if sysctl -p > /dev/null 2>&1; then
    echo -e "    ${GREEN}✓ 已应用内核参数${NC}"
else
    echo -e "    ${YELLOW}⚠ 内核参数应用失败，请检查 /etc/sysctl.conf 语法${NC}"
    echo -e "    ${YELLOW}  运行 'sysctl -p' 查看详细错误信息${NC}"
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
    
    echo -e "    ${GREEN}✓ nginx.conf 已优化${NC}"
fi

# 5.2 优化 performance.conf
if [ -f "${SCRIPT_DIR}/../conf.d/set_conf/performance.conf" ]; then
    echo "  优化 performance.conf..."
    
    # 更新 keepalive 连接数
    if grep -q "keepalive " "${SCRIPT_DIR}/../conf.d/set_conf/performance.conf"; then
        sed -i "s/keepalive [0-9]*;/keepalive $KEEPALIVE_CONNECTIONS;/" "${SCRIPT_DIR}/../conf.d/set_conf/performance.conf"
    fi
    
    echo -e "    ${GREEN}✓ performance.conf 已优化${NC}"
fi

# 5.3 优化 upstream.conf
if [ -f "${SCRIPT_DIR}/../conf.d/set_conf/upstream.conf" ]; then
    echo "  优化 upstream.conf..."
    
    # 更新 keepalive
    if grep -q "keepalive " "${SCRIPT_DIR}/../conf.d/set_conf/upstream.conf"; then
        sed -i "s/keepalive [0-9]*;/keepalive $KEEPALIVE_CONNECTIONS;/" "${SCRIPT_DIR}/../conf.d/set_conf/upstream.conf"
    fi
    
    echo -e "    ${GREEN}✓ upstream.conf 已优化${NC}"
fi

# 5.4 优化 waf.conf 共享内存
if [ -f "${SCRIPT_DIR}/../conf.d/set_conf/waf.conf" ]; then
    echo "  优化 waf.conf 共享内存..."
    
    # 更新 waf_cache（10MB）
    if grep -q "lua_shared_dict waf_cache" "${SCRIPT_DIR}/../conf.d/set_conf/waf.conf"; then
        sed -i "s/lua_shared_dict waf_cache [0-9]*m;/lua_shared_dict waf_cache 10m;/" "${SCRIPT_DIR}/../conf.d/set_conf/waf.conf"
    fi
    
    # 更新 waf_log_buffer（50MB）
    if grep -q "lua_shared_dict waf_log_buffer" "${SCRIPT_DIR}/../conf.d/set_conf/waf.conf"; then
        sed -i "s/lua_shared_dict waf_log_buffer [0-9]*m;/lua_shared_dict waf_log_buffer 50m;/" "${SCRIPT_DIR}/../conf.d/set_conf/waf.conf"
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

