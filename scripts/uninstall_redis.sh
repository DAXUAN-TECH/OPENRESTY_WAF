#!/bin/bash

# Redis 一键卸载脚本
# 用途：卸载 Redis 及其相关配置

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

# 检查是否为 root 用户（使用公共函数）
check_root() {
    if ! check_root_common; then
        echo -e "${RED}错误: 需要 root 权限来卸载${NC}"
        exit 1
    fi
}

# 检测系统类型（使用公共函数）
detect_os() {
    detect_os_simple
}

# 停止服务
stop_service() {
    echo -e "${BLUE}[1/4] 停止 Redis 服务...${NC}"
    
    if systemctl is-active --quiet redis 2>/dev/null; then
        systemctl stop redis
        echo -e "${GREEN}✓ Redis 服务已停止${NC}"
    elif systemctl is-active --quiet redis-server 2>/dev/null; then
        systemctl stop redis-server
        echo -e "${GREEN}✓ Redis 服务已停止${NC}"
    else
        # 尝试通过进程停止
        if pgrep -x redis-server > /dev/null; then
            pkill redis-server
            echo -e "${GREEN}✓ Redis 进程已停止${NC}"
        else
            echo -e "${YELLOW}Redis 服务未运行${NC}"
        fi
    fi
}

# 禁用服务
disable_service() {
    echo -e "${BLUE}[2/4] 禁用开机自启...${NC}"
    
    if systemctl is-enabled --quiet redis 2>/dev/null; then
        systemctl disable redis
        echo -e "${GREEN}✓ 已禁用开机自启${NC}"
    elif systemctl is-enabled --quiet redis-server 2>/dev/null; then
        systemctl disable redis-server
        echo -e "${GREEN}✓ 已禁用开机自启${NC}"
    else
        echo -e "${YELLOW}服务未设置开机自启${NC}"
    fi
}

# 卸载 Redis
uninstall_redis() {
    echo -e "${BLUE}[3/4] 卸载 Redis...${NC}"
    
    detect_os
    
    case $OS in
        centos|rhel|fedora|rocky|almalinux|oraclelinux|amazonlinux)
            if command -v dnf &> /dev/null; then
                dnf remove -y redis 2>/dev/null || true
            elif command -v yum &> /dev/null; then
                yum remove -y redis 2>/dev/null || true
            fi
            ;;
        ubuntu|debian|linuxmint|raspbian|kali)
            if command -v apt-get &> /dev/null; then
                apt-get remove -y redis-server redis-tools 2>/dev/null || true
                apt-get purge -y redis-server redis-tools 2>/dev/null || true
                apt-get autoremove -y 2>/dev/null || true
            fi
            ;;
        opensuse*|sles)
            if command -v zypper &> /dev/null; then
                zypper remove -y redis 2>/dev/null || true
            fi
            ;;
        arch|manjaro)
            if command -v pacman &> /dev/null; then
                pacman -R --noconfirm redis 2>/dev/null || true
            fi
            ;;
        alpine)
            if command -v apk &> /dev/null; then
                apk del redis 2>/dev/null || true
            fi
            ;;
        gentoo)
            if command -v emerge &> /dev/null; then
                emerge --unmerge dev-db/redis 2>/dev/null || true
            fi
            ;;
    esac
    
    # 删除源码编译安装的文件
    if [ -f /usr/local/bin/redis-server ]; then
        rm -f /usr/local/bin/redis-server
        rm -f /usr/local/bin/redis-cli
        echo -e "${GREEN}✓ 已删除源码编译的文件${NC}"
    fi
    
    echo -e "${GREEN}✓ Redis 卸载完成${NC}"
}

# 检查依赖 Redis 的服务
check_dependent_services() {
    echo -e "${BLUE}检查依赖 Redis 的服务...${NC}"
    
    local affected_apps=()
    
    # 检查是否有应用连接到 Redis
    if command -v lsof &> /dev/null; then
        if lsof -i :6379 2>/dev/null | grep -qv "redis-server"; then
            affected_apps+=("连接到 Redis 6379 端口的应用")
        fi
    fi
    
    # 检查是否有其他服务使用 Redis
    if systemctl list-units --type=service --state=running 2>/dev/null | grep -qiE "celery|django|laravel|symfony"; then
        affected_apps+=("可能使用 Redis 的应用框架（Celery/Django/Laravel/Symfony）")
    fi
    
    if [ ${#affected_apps[@]} -gt 0 ]; then
        echo -e "${YELLOW}⚠ 检测到可能依赖 Redis 的服务或应用：${NC}"
        for app in "${affected_apps[@]}"; do
            echo -e "${YELLOW}  - $app${NC}"
        done
        echo ""
        return 1
    else
        echo -e "${GREEN}✓ 未检测到依赖 Redis 的服务${NC}"
        return 0
    fi
}

# 清理配置和数据目录（可选）
cleanup_data() {
    echo -e "${BLUE}[4/4] 清理配置和数据目录...${NC}"
    
    # 检查依赖服务
    if ! check_dependent_services; then
        echo -e "${YELLOW}⚠ 删除 Redis 数据可能影响上述服务${NC}"
    fi
    
    # 如果从命令行传入参数，使用参数值，否则询问用户
    if [ -n "$1" ]; then
        DELETE_DATA="$1"
    else
        echo ""
        echo -e "${YELLOW}请选择清理选项：${NC}"
        echo "  1. 仅卸载软件，保留所有数据和配置（推荐，可重新安装）"
        echo "  2. 卸载软件并删除配置文件，但保留数据目录"
        echo "  3. 完全删除（卸载软件、删除所有数据、配置和日志）"
        read -p "请选择 [1-3]: " CLEANUP_CHOICE
        
        case "$CLEANUP_CHOICE" in
            1)
                DELETE_DATA="keep_all"
                ;;
            2)
                DELETE_DATA="keep_data"
                ;;
            3)
                DELETE_DATA="delete_all"
                ;;
            *)
                DELETE_DATA="keep_all"
                echo -e "${YELLOW}无效选择，默认保留所有数据${NC}"
                ;;
        esac
    fi
    
    case "$DELETE_DATA" in
        keep_all)
            echo -e "${GREEN}✓ 保留所有数据和配置${NC}"
            echo -e "${BLUE}数据目录位置: /var/lib/redis${NC}"
            echo -e "${BLUE}配置文件位置: /etc/redis/redis.conf 或 /etc/redis.conf${NC}"
            echo ""
            echo -e "${YELLOW}提示: 重新安装 Redis 后，数据将自动恢复${NC}"
            ;;
        keep_data)
            echo -e "${YELLOW}删除配置文件，但保留数据目录...${NC}"
            
            # 删除配置文件
            CONFIG_FILES=(
                "/etc/redis/redis.conf"
                "/etc/redis.conf"
                "/usr/local/etc/redis.conf"
            )
            
            for file in "${CONFIG_FILES[@]}"; do
                if [ -f "$file" ]; then
                    rm -f "$file"
                    echo -e "${GREEN}✓ 已删除: $file${NC}"
                fi
            done
            
            # 删除日志文件（但保留日志目录）
            if [ -d "/var/log/redis" ]; then
                rm -rf "/var/log/redis"/*
                echo -e "${GREEN}✓ 已清理日志目录: /var/log/redis${NC}"
            fi
            
            echo -e "${GREEN}✓ 配置文件已删除，数据目录已保留${NC}"
            ;;
        delete_all|y|Y)
            echo -e "${RED}警告: 将删除所有 Redis 数据、配置和日志！${NC}"
            
            # 再次确认
            if [ "$DELETE_DATA" != "delete_all" ]; then
                read -p "确认删除所有数据？[y/N]: " CONFIRM_DELETE
                CONFIRM_DELETE="${CONFIRM_DELETE:-N}"
                if [[ ! "$CONFIRM_DELETE" =~ ^[Yy]$ ]]; then
                    echo -e "${GREEN}取消删除，保留数据目录${NC}"
                    DELETE_DATA="keep_all"
                    return 0
                fi
            fi
            
            # 删除配置文件
            CONFIG_FILES=(
                "/etc/redis/redis.conf"
                "/etc/redis.conf"
                "/usr/local/etc/redis.conf"
            )
            
            for file in "${CONFIG_FILES[@]}"; do
                if [ -f "$file" ]; then
                    rm -f "$file"
                    echo -e "${GREEN}✓ 已删除: $file${NC}"
                fi
            done
            
            # 删除数据目录
            DATA_DIRS=(
                "/var/lib/redis"
                "/var/db/redis"
            )
            
            for dir in "${DATA_DIRS[@]}"; do
                if [ -d "$dir" ]; then
                    rm -rf "$dir"
                    echo -e "${GREEN}✓ 已删除: $dir${NC}"
                fi
            done
            
            # 删除日志目录
            LOG_DIRS=(
                "/var/log/redis"
            )
            
            for dir in "${LOG_DIRS[@]}"; do
                if [ -d "$dir" ]; then
                    rm -rf "$dir"
                    echo -e "${GREEN}✓ 已删除: $dir${NC}"
                fi
            done
            
            # 删除 systemd 服务文件
            if [ -f /etc/systemd/system/redis.service ]; then
                rm -f /etc/systemd/system/redis.service
                systemctl daemon-reload
                echo -e "${GREEN}✓ 已删除服务文件${NC}"
            fi
            
            # 删除 redis 用户（如果存在且没有其他用途）
            if id redis &>/dev/null; then
                read -p "是否删除 redis 用户？[y/N]: " DELETE_USER
                DELETE_USER="${DELETE_USER:-N}"
                if [[ "$DELETE_USER" =~ ^[Yy]$ ]]; then
                    userdel redis 2>/dev/null || true
                    echo -e "${GREEN}✓ 已删除 redis 用户${NC}"
                fi
            fi
            
            echo -e "${GREEN}✓ 所有数据、配置和日志已删除${NC}"
            ;;
        *)
            echo -e "${YELLOW}保留配置和数据目录${NC}"
            echo -e "${YELLOW}数据目录位置: /var/lib/redis${NC}"
            echo -e "${YELLOW}配置文件位置: /etc/redis/redis.conf 或 /etc/redis.conf${NC}"
            ;;
    esac
}

# 主函数
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Redis 一键卸载脚本${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    check_root
    
    stop_service
    disable_service
    uninstall_redis
    cleanup_data "$1"  # 传递命令行参数
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}卸载完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # 根据清理选项显示不同的提示
    if [ "$DELETE_DATA" = "keep_all" ]; then
        echo -e "${GREEN}数据保留情况：${NC}"
        echo "  ✓ 数据目录已保留"
        echo "  ✓ 配置文件已保留"
        echo ""
        echo -e "${BLUE}重新安装 Redis 后，数据将自动恢复${NC}"
    elif [ "$DELETE_DATA" = "keep_data" ]; then
        echo -e "${GREEN}数据保留情况：${NC}"
        echo "  ✓ 数据目录已保留"
        echo "  ✗ 配置文件已删除"
        echo ""
        echo -e "${BLUE}重新安装 Redis 后，需要重新配置${NC}"
    else
        echo -e "${YELLOW}数据清理情况：${NC}"
        echo "  ✗ 所有数据已删除"
        echo "  ✗ 所有配置已删除"
        echo "  ✗ 所有日志已删除"
        echo ""
        echo -e "${BLUE}如需重新安装 Redis，请运行安装脚本${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}后续操作建议：${NC}"
    echo "  1. 如果保留了数据，重新安装 Redis 后数据会自动恢复"
    echo "  2. 如果删除了数据，需要重新配置 Redis"
    echo "  3. 检查依赖 Redis 的应用是否需要重新配置"
    echo ""
}

# 执行主函数
main "$@"

