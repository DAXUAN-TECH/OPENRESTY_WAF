#!/bin/bash

# OpenResty WAF 文件描述符限制快速修复脚本
# 用途：快速修复 "worker_connections exceed open file resource limit" 警告

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

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}OpenResty WAF 文件描述符限制快速修复${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 需要 root 权限来修复文件描述符限制${NC}"
    echo "请使用: sudo $0"
    exit 1
fi

# 检测当前配置
echo -e "${BLUE}[1/4] 检测当前配置...${NC}"

# 检测物理内存（MB）
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
echo "  总内存: ${TOTAL_MEM}MB"

# 检测当前nginx配置的worker_connections
NGINX_CONF_DIR="${OPENRESTY_PREFIX:-/usr/local/openresty}/nginx/conf"
if [ -f "$NGINX_CONF_DIR/nginx.conf" ]; then
    WORKER_CONNECTIONS=$(grep -E "^\s*worker_connections" "$NGINX_CONF_DIR/nginx.conf" | awk '{print $2}' | tr -d ';' || echo "65535")
    echo "  Nginx worker_connections: $WORKER_CONNECTIONS"
else
    WORKER_CONNECTIONS=65535
    echo -e "  ${YELLOW}⚠ 未找到nginx.conf，使用默认值: 65535${NC}"
fi

# 检测CPU核心数
CPU_CORES=$(nproc)
echo "  CPU 核心数: $CPU_CORES"

# 计算需要的文件描述符限制
# 公式: worker_processes × worker_connections × 2 (安全系数)
# 最小65535，最大1000000
if [ "$TOTAL_MEM" -lt 2048 ]; then
    CALCULATED_LIMIT=$((CPU_CORES * 10240 * 2))
elif [ "$TOTAL_MEM" -lt 8192 ]; then
    CALCULATED_LIMIT=$((CPU_CORES * 32768 * 2))
else
    CALCULATED_LIMIT=$((CPU_CORES * 65535 * 2))
fi

# 限制最大值为1000000
if [ $CALCULATED_LIMIT -gt 1000000 ]; then
    CALCULATED_LIMIT=1000000
fi

# 最小值为65535
if [ $CALCULATED_LIMIT -lt 65535 ]; then
    CALCULATED_LIMIT=65535
fi

ULIMIT_NOFILE=$CALCULATED_LIMIT
echo "  计算出的文件描述符限制: $ULIMIT_NOFILE"

# 检测当前限制
CURRENT_ULIMIT=$(ulimit -n 2>/dev/null || echo "1024")
echo "  当前系统限制: $CURRENT_ULIMIT"

if [ "$CURRENT_ULIMIT" -ge "$ULIMIT_NOFILE" ]; then
    echo -e "  ${GREEN}✓ 当前限制已满足要求${NC}"
else
    echo -e "  ${RED}✗ 当前限制不足，需要修复${NC}"
fi

echo ""

# 检查limits.conf
echo -e "${BLUE}[2/4] 检查 /etc/security/limits.conf...${NC}"

if [ -f /etc/security/limits.conf ]; then
    if grep -q "# OpenResty WAF" /etc/security/limits.conf; then
        echo -e "  ${YELLOW}⚠ 已存在OpenResty WAF配置，将更新${NC}"
        # 删除旧配置
        sed -i '/# OpenResty WAF/,/^$/d' /etc/security/limits.conf
    fi
else
    echo -e "  ${YELLOW}⚠ limits.conf 不存在，将创建${NC}"
fi

# 添加新配置
cat >> /etc/security/limits.conf <<EOF

# OpenResty WAF 文件描述符限制（自动修复）
* soft nofile $ULIMIT_NOFILE
* hard nofile $ULIMIT_NOFILE
root soft nofile $ULIMIT_NOFILE
root hard nofile $ULIMIT_NOFILE
nobody soft nofile $ULIMIT_NOFILE
nobody hard nofile $ULIMIT_NOFILE
EOF

echo -e "  ${GREEN}✓ 已更新 /etc/security/limits.conf${NC}"
echo ""

# 检查systemd服务文件
echo -e "${BLUE}[3/4] 检查 systemd 服务文件...${NC}"

SYSTEMD_SERVICE="/etc/systemd/system/openresty.service"
if [ -f "$SYSTEMD_SERVICE" ]; then
    if grep -q "LimitNOFILE" "$SYSTEMD_SERVICE"; then
        # 更新现有配置
        sed -i "s/LimitNOFILE=.*/LimitNOFILE=$ULIMIT_NOFILE/" "$SYSTEMD_SERVICE"
        echo -e "  ${GREEN}✓ 已更新 systemd 服务文件中的 LimitNOFILE${NC}"
    else
        # 添加新配置
        if grep -q "\[Service\]" "$SYSTEMD_SERVICE"; then
            sed -i "/\[Service\]/a LimitNOFILE=$ULIMIT_NOFILE" "$SYSTEMD_SERVICE"
        else
            echo "" >> "$SYSTEMD_SERVICE"
            echo "[Service]" >> "$SYSTEMD_SERVICE"
            echo "LimitNOFILE=$ULIMIT_NOFILE" >> "$SYSTEMD_SERVICE"
        fi
        echo -e "  ${GREEN}✓ 已添加 LimitNOFILE 到 systemd 服务文件${NC}"
    fi
    
    # 重新加载systemd配置
    systemctl daemon-reload
    echo -e "  ${GREEN}✓ 已重新加载 systemd 配置${NC}"
else
    echo -e "  ${YELLOW}⚠ 未找到 systemd 服务文件，跳过${NC}"
fi

echo ""

# 应用临时限制（当前会话）
echo -e "${BLUE}[4/4] 应用临时限制...${NC}"
ulimit -n $ULIMIT_NOFILE 2>/dev/null || echo -e "  ${YELLOW}⚠ 无法在当前会话设置临时限制（需要重新登录）${NC}"
echo -e "  ${GREEN}✓ 临时限制已应用（当前会话）${NC}"
echo ""

# 总结
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}修复完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "已完成的修复："
echo "  ✓ 更新了 /etc/security/limits.conf"
if [ -f "$SYSTEMD_SERVICE" ]; then
    echo "  ✓ 更新了 systemd 服务文件"
fi
echo "  ✓ 应用了临时限制（当前会话）"
echo ""
echo -e "${YELLOW}重要提示：${NC}"
echo "1. 文件描述符限制需要重新登录才能完全生效"
echo "2. 或者重启 OpenResty 服务（如果使用 systemd）："
echo "   sudo systemctl restart openresty"
echo "3. 验证修复："
echo "   ulimit -n"
echo "   # 应该显示: $ULIMIT_NOFILE"
echo ""
echo "4. 检查 OpenResty 错误日志，确认警告已消失："
echo "   tail -f /data/OPENRESTY_WAF/logs/error.log"
echo ""

