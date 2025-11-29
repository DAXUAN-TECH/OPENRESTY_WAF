#!/bin/bash

# OpenResty 启动失败诊断脚本
# 用途：诊断 OpenResty 服务启动失败的原因并提供修复建议

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# OpenResty 安装目录
OPENRESTY_PREFIX="${OPENRESTY_PREFIX:-/usr/local/openresty}"
NGINX_CONF_DIR="${OPENRESTY_PREFIX}/nginx/conf"
NGINX_PID_FILE="${OPENRESTY_PREFIX}/nginx/logs/nginx.pid"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}OpenResty 启动失败诊断工具${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}警告: 某些检查需要 root 权限${NC}"
    echo "建议使用: sudo $0"
    echo ""
fi

# 错误计数器
ERROR_COUNT=0
WARNING_COUNT=0

# 1. 检查 OpenResty 是否安装
echo -e "${BLUE}[1/10] 检查 OpenResty 安装...${NC}"
if [ -f "${OPENRESTY_PREFIX}/bin/openresty" ]; then
    OPENRESTY_VERSION=$("${OPENRESTY_PREFIX}/bin/openresty" -v 2>&1 | head -1)
    echo -e "${GREEN}✓ OpenResty 已安装${NC}"
    echo -e "  ${OPENRESTY_VERSION}"
else
    echo -e "${RED}✗ OpenResty 未安装或路径不正确${NC}"
    echo -e "  预期路径: ${OPENRESTY_PREFIX}/bin/openresty"
    ((ERROR_COUNT++))
    echo ""
    echo -e "${YELLOW}修复建议:${NC}"
    echo "  运行安装脚本: sudo ./scripts/install_openresty.sh"
    exit 1
fi
echo ""

# 2. 检查配置文件是否存在
echo -e "${BLUE}[2/10] 检查配置文件...${NC}"
if [ -f "${NGINX_CONF_DIR}/nginx.conf" ]; then
    echo -e "${GREEN}✓ 配置文件存在: ${NGINX_CONF_DIR}/nginx.conf${NC}"
else
    echo -e "${RED}✗ 配置文件不存在: ${NGINX_CONF_DIR}/nginx.conf${NC}"
    ((ERROR_COUNT++))
    echo ""
    echo -e "${YELLOW}修复建议:${NC}"
    echo "  运行部署脚本: sudo ./scripts/deploy.sh"
    exit 1
fi
echo ""

# 3. 检查配置文件语法
echo -e "${BLUE}[3/10] 检查配置文件语法...${NC}"
CONFIG_TEST_OUTPUT=$("${OPENRESTY_PREFIX}/bin/openresty" -t 2>&1)
if echo "$CONFIG_TEST_OUTPUT" | grep -q "syntax is ok"; then
    echo -e "${GREEN}✓ 配置文件语法正确${NC}"
    if echo "$CONFIG_TEST_OUTPUT" | grep -q "test is successful"; then
        echo -e "${GREEN}✓ 配置文件测试通过${NC}"
    fi
else
    echo -e "${RED}✗ 配置文件语法错误${NC}"
    ((ERROR_COUNT++))
    echo ""
    echo -e "${YELLOW}错误详情:${NC}"
    echo "$CONFIG_TEST_OUTPUT"
    echo ""
    echo -e "${YELLOW}修复建议:${NC}"
    echo "  1. 检查上述错误信息"
    echo "  2. 检查配置文件: ${NGINX_CONF_DIR}/nginx.conf"
    echo "  3. 检查被引用的子配置文件"
    echo "  4. 修复后重新运行部署脚本: sudo ./scripts/deploy.sh"
    exit 1
fi
echo ""

# 4. 检查 PID 文件路径
echo -e "${BLUE}[4/10] 检查 PID 文件路径...${NC}"
PID_DIR=$(dirname "$NGINX_PID_FILE")
if [ ! -d "$PID_DIR" ]; then
    echo -e "${YELLOW}⚠ PID 文件目录不存在: $PID_DIR${NC}"
    echo -e "${BLUE}  创建目录...${NC}"
    mkdir -p "$PID_DIR"
    chown -R nobody:nobody "$PID_DIR" 2>/dev/null || true
    echo -e "${GREEN}✓ 已创建 PID 文件目录${NC}"
    ((WARNING_COUNT++))
else
    echo -e "${GREEN}✓ PID 文件目录存在: $PID_DIR${NC}"
fi

# 检查 systemd 服务文件中的 PIDFile 路径
if [ -f "/etc/systemd/system/openresty.service" ]; then
    SYSTEMD_PIDFILE=$(grep "^PIDFile=" /etc/systemd/system/openresty.service | cut -d'=' -f2)
    if [ -n "$SYSTEMD_PIDFILE" ]; then
        if [ "$SYSTEMD_PIDFILE" = "$NGINX_PID_FILE" ]; then
            echo -e "${GREEN}✓ systemd 服务文件中的 PIDFile 路径正确${NC}"
        else
            echo -e "${YELLOW}⚠ systemd 服务文件中的 PIDFile 路径不匹配${NC}"
            echo -e "  systemd: $SYSTEMD_PIDFILE"
            echo -e "  nginx.conf: $NGINX_PID_FILE"
            ((WARNING_COUNT++))
        fi
    fi
fi
echo ""

# 5. 检查日志目录
echo -e "${BLUE}[5/10] 检查日志目录...${NC}"
# 从配置文件中提取日志路径
ERROR_LOG_PATH=$(grep "^error_log" "${NGINX_CONF_DIR}/nginx.conf" | head -1 | awk '{print $2}' | tr -d ';')
if [ -n "$ERROR_LOG_PATH" ]; then
    ERROR_LOG_DIR=$(dirname "$ERROR_LOG_PATH")
    if [ ! -d "$ERROR_LOG_DIR" ]; then
        echo -e "${YELLOW}⚠ 错误日志目录不存在: $ERROR_LOG_DIR${NC}"
        echo -e "${BLUE}  创建目录...${NC}"
        mkdir -p "$ERROR_LOG_DIR"
        chown -R nobody:nobody "$ERROR_LOG_DIR" 2>/dev/null || true
        echo -e "${GREEN}✓ 已创建错误日志目录${NC}"
        ((WARNING_COUNT++))
    else
        echo -e "${GREEN}✓ 错误日志目录存在: $ERROR_LOG_DIR${NC}"
    fi
    
    # 检查日志文件权限
    if [ -f "$ERROR_LOG_PATH" ]; then
        if [ -w "$ERROR_LOG_PATH" ] || [ -w "$ERROR_LOG_DIR" ]; then
            echo -e "${GREEN}✓ 日志文件可写${NC}"
        else
            echo -e "${YELLOW}⚠ 日志文件可能不可写${NC}"
            echo -e "${BLUE}  尝试修复权限...${NC}"
            chown -R nobody:nobody "$ERROR_LOG_DIR" 2>/dev/null || true
            chmod -R 755 "$ERROR_LOG_DIR" 2>/dev/null || true
            ((WARNING_COUNT++))
        fi
    fi
else
    echo -e "${YELLOW}⚠ 无法从配置文件中提取错误日志路径${NC}"
    ((WARNING_COUNT++))
fi
echo ""

# 6. 检查端口占用
echo -e "${BLUE}[6/10] 检查端口占用...${NC}"
# 从配置文件中提取监听的端口
LISTEN_PORTS=$(grep -r "listen" "${NGINX_CONF_DIR}/../conf.d" 2>/dev/null | grep -v "^#" | grep "listen" | awk '{print $2}' | tr -d ';' | tr -d 'ssl' | tr -d 'http2' | sort -u)
if [ -n "$LISTEN_PORTS" ]; then
    PORT_CONFLICT=0
    for port in $LISTEN_PORTS; do
        # 清理端口号（去除非数字字符）
        clean_port=$(echo "$port" | grep -oE '[0-9]+' | head -1)
        if [ -n "$clean_port" ]; then
            if command -v netstat &> /dev/null; then
                if netstat -tlnp 2>/dev/null | grep -q ":$clean_port "; then
                    OCCUPIED_PID=$(netstat -tlnp 2>/dev/null | grep ":$clean_port " | awk '{print $7}' | cut -d'/' -f1 | head -1)
                    if [ "$OCCUPIED_PID" != "$$" ] && [ -n "$OCCUPIED_PID" ]; then
                        echo -e "${YELLOW}⚠ 端口 $clean_port 已被占用 (PID: $OCCUPIED_PID)${NC}"
                        PORT_CONFLICT=1
                        ((WARNING_COUNT++))
                    fi
                fi
            elif command -v ss &> /dev/null; then
                if ss -tlnp 2>/dev/null | grep -q ":$clean_port "; then
                    OCCUPIED_PID=$(ss -tlnp 2>/dev/null | grep ":$clean_port " | grep -oE 'pid=[0-9]+' | cut -d'=' -f2 | head -1)
                    if [ "$OCCUPIED_PID" != "$$" ] && [ -n "$OCCUPIED_PID" ]; then
                        echo -e "${YELLOW}⚠ 端口 $clean_port 已被占用 (PID: $OCCUPIED_PID)${NC}"
                        PORT_CONFLICT=1
                        ((WARNING_COUNT++))
                    fi
                fi
            fi
        fi
    done
    if [ $PORT_CONFLICT -eq 0 ]; then
        echo -e "${GREEN}✓ 未发现端口冲突${NC}"
    fi
else
    echo -e "${BLUE}  未找到监听端口配置（可能使用默认配置）${NC}"
fi
echo ""

# 7. 检查 systemd 服务文件
echo -e "${BLUE}[7/10] 检查 systemd 服务文件...${NC}"
if [ -f "/etc/systemd/system/openresty.service" ]; then
    echo -e "${GREEN}✓ systemd 服务文件存在${NC}"
    
    # 检查服务文件中的 ExecStart 路径
    EXEC_START=$(grep "^ExecStart=" /etc/systemd/system/openresty.service | cut -d'=' -f2)
    if [ -n "$EXEC_START" ]; then
        if [ -f "$EXEC_START" ]; then
            echo -e "${GREEN}✓ ExecStart 路径正确: $EXEC_START${NC}"
        else
            echo -e "${RED}✗ ExecStart 路径不存在: $EXEC_START${NC}"
            ((ERROR_COUNT++))
        fi
    fi
    
    # 检查是否需要重新加载 systemd
    if systemctl is-active --quiet openresty 2>/dev/null; then
        echo -e "${BLUE}  服务当前状态: 运行中${NC}"
    elif systemctl is-failed --quiet openresty 2>/dev/null; then
        echo -e "${YELLOW}⚠ 服务当前状态: 失败${NC}"
        ((WARNING_COUNT++))
    else
        echo -e "${BLUE}  服务当前状态: 未运行${NC}"
    fi
else
    echo -e "${YELLOW}⚠ systemd 服务文件不存在${NC}"
    echo -e "${BLUE}  位置: /etc/systemd/system/openresty.service${NC}"
    ((WARNING_COUNT++))
    echo ""
    echo -e "${YELLOW}修复建议:${NC}"
    echo "  运行安装脚本创建服务文件: sudo ./scripts/install_openresty.sh"
fi
echo ""

# 8. 检查依赖服务（MySQL、Redis）
echo -e "${BLUE}[8/10] 检查依赖服务...${NC}"
# 检查 MySQL
if command -v mysql &> /dev/null || command -v systemctl &> /dev/null; then
    if systemctl is-active --quiet mysql 2>/dev/null || systemctl is-active --quiet mysqld 2>/dev/null || systemctl is-active --quiet mariadb 2>/dev/null; then
        echo -e "${GREEN}✓ MySQL/MariaDB 服务运行中${NC}"
    else
        echo -e "${YELLOW}⚠ MySQL/MariaDB 服务未运行（如果使用数据库功能，需要启动）${NC}"
        ((WARNING_COUNT++))
    fi
fi

# 检查 Redis
if command -v redis-cli &> /dev/null || systemctl list-unit-files | grep -q redis; then
    if systemctl is-active --quiet redis 2>/dev/null || systemctl is-active --quiet redis-server 2>/dev/null; then
        echo -e "${GREEN}✓ Redis 服务运行中${NC}"
    else
        echo -e "${BLUE}  Redis 服务未运行（如果使用缓存功能，建议启动）${NC}"
    fi
fi
echo ""

# 9. 检查文件权限
echo -e "${BLUE}[9/10] 检查关键文件权限...${NC}"
# 检查配置文件权限
if [ -r "${NGINX_CONF_DIR}/nginx.conf" ]; then
    echo -e "${GREEN}✓ 配置文件可读${NC}"
else
    echo -e "${RED}✗ 配置文件不可读: ${NGINX_CONF_DIR}/nginx.conf${NC}"
    ((ERROR_COUNT++))
fi

# 检查 OpenResty 可执行文件权限
if [ -x "${OPENRESTY_PREFIX}/bin/openresty" ]; then
    echo -e "${GREEN}✓ OpenResty 可执行文件有执行权限${NC}"
else
    echo -e "${RED}✗ OpenResty 可执行文件无执行权限${NC}"
    ((ERROR_COUNT++))
fi
echo ""

# 10. 查看最近的错误日志
echo -e "${BLUE}[10/10] 查看最近的错误日志...${NC}"
if [ -n "$ERROR_LOG_PATH" ] && [ -f "$ERROR_LOG_PATH" ]; then
    LOG_LINES=$(tail -n 20 "$ERROR_LOG_PATH" 2>/dev/null)
    if [ -n "$LOG_LINES" ]; then
        echo -e "${BLUE}最近 20 行错误日志:${NC}"
        echo "$LOG_LINES"
    else
        echo -e "${BLUE}  错误日志文件为空或无法读取${NC}"
    fi
else
    echo -e "${YELLOW}⚠ 无法读取错误日志文件${NC}"
    ((WARNING_COUNT++))
fi
echo ""

# 总结
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}诊断完成${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
if [ $ERROR_COUNT -eq 0 ] && [ $WARNING_COUNT -eq 0 ]; then
    echo -e "${GREEN}✓ 未发现明显问题${NC}"
    echo ""
    echo -e "${BLUE}建议操作:${NC}"
    echo "  1. 尝试启动服务: sudo systemctl start openresty"
    echo "  2. 查看服务状态: sudo systemctl status openresty"
    echo "  3. 如果仍然失败，查看详细日志: sudo journalctl -u openresty -n 50"
elif [ $ERROR_COUNT -eq 0 ]; then
    echo -e "${YELLOW}发现 $WARNING_COUNT 个警告，但无严重错误${NC}"
    echo ""
    echo -e "${BLUE}建议操作:${NC}"
    echo "  1. 尝试启动服务: sudo systemctl start openresty"
    echo "  2. 如果失败，查看详细日志: sudo journalctl -u openresty -n 50"
else
    echo -e "${RED}发现 $ERROR_COUNT 个错误，$WARNING_COUNT 个警告${NC}"
    echo ""
    echo -e "${YELLOW}必须修复上述错误后才能启动服务${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}其他有用的命令:${NC}"
echo "  - 测试配置: ${OPENRESTY_PREFIX}/bin/openresty -t"
echo "  - 查看服务日志: sudo journalctl -u openresty -f"
echo "  - 重新加载配置: sudo systemctl reload openresty"
echo "  - 重启服务: sudo systemctl restart openresty"

