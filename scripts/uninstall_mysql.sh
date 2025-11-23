#!/bin/bash

# MySQL 一键卸载脚本
# 用途：卸载 MySQL 及其相关配置

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误: 需要 root 权限来卸载${NC}"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 检测系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
    else
        OS="unknown"
    fi
}

# 停止服务
stop_service() {
    echo -e "${BLUE}[1/4] 停止 MySQL 服务...${NC}"
    
    # 尝试停止 mysqld (CentOS/RHEL)
    if systemctl is-active --quiet mysqld 2>/dev/null; then
        systemctl stop mysqld
        echo -e "${GREEN}✓ MySQL 服务已停止${NC}"
    # 尝试停止 mysql (Ubuntu/Debian)
    elif systemctl is-active --quiet mysql 2>/dev/null; then
        systemctl stop mysql
        echo -e "${GREEN}✓ MySQL 服务已停止${NC}"
    else
        echo -e "${YELLOW}MySQL 服务未运行${NC}"
    fi
}

# 禁用服务
disable_service() {
    echo -e "${BLUE}[2/4] 禁用开机自启...${NC}"
    
    if systemctl is-enabled --quiet mysqld 2>/dev/null; then
        systemctl disable mysqld
        echo -e "${GREEN}✓ 已禁用开机自启${NC}"
    elif systemctl is-enabled --quiet mysql 2>/dev/null; then
        systemctl disable mysql
        echo -e "${GREEN}✓ 已禁用开机自启${NC}"
    else
        echo -e "${YELLOW}服务未设置开机自启${NC}"
    fi
}

# 卸载 MySQL
uninstall_mysql() {
    echo -e "${BLUE}[3/4] 卸载 MySQL...${NC}"
    
    detect_os
    
    case $OS in
        centos|rhel|fedora|rocky|almalinux|oraclelinux|amazonlinux)
            if command -v dnf &> /dev/null; then
                dnf remove -y mysql-server mysql mysql-common 2>/dev/null || true
            elif command -v yum &> /dev/null; then
                yum remove -y mysql-server mysql mysql-common 2>/dev/null || true
            fi
            ;;
        ubuntu|debian|linuxmint|raspbian|kali)
            if command -v apt-get &> /dev/null; then
                apt-get remove -y mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-* 2>/dev/null || true
                apt-get purge -y mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-* 2>/dev/null || true
                apt-get autoremove -y 2>/dev/null || true
            fi
            ;;
        opensuse*|sles)
            if command -v zypper &> /dev/null; then
                zypper remove -y mariadb mariadb-server 2>/dev/null || true
            fi
            ;;
        arch|manjaro)
            if command -v pacman &> /dev/null; then
                pacman -R --noconfirm mysql 2>/dev/null || true
            fi
            ;;
        alpine)
            if command -v apk &> /dev/null; then
                apk del mysql mysql-client 2>/dev/null || true
            fi
            ;;
        gentoo)
            if command -v emerge &> /dev/null; then
                emerge --unmerge dev-db/mysql 2>/dev/null || true
            fi
            ;;
    esac
    
    echo -e "${GREEN}✓ MySQL 卸载完成${NC}"
}

# 检查依赖 MySQL 的服务
check_dependent_services() {
    echo -e "${BLUE}检查依赖 MySQL 的服务...${NC}"
    
    local dependent_services=()
    local affected_apps=()
    
    # 检查常见的依赖 MySQL 的服务
    if systemctl list-units --type=service --state=running 2>/dev/null | grep -qiE "php-fpm|php.*fpm"; then
        dependent_services+=("php-fpm")
        affected_apps+=("PHP 应用")
    fi
    
    if systemctl list-units --type=service --state=running 2>/dev/null | grep -qiE "wordpress|owncloud|nextcloud|drupal|joomla"; then
        affected_apps+=("CMS 应用（WordPress/ownCloud/Nextcloud/Drupal/Joomla）")
    fi
    
    # 检查是否有应用连接到 MySQL
    if command -v lsof &> /dev/null; then
        if lsof -i :3306 2>/dev/null | grep -qv "mysqld\|mysql"; then
            affected_apps+=("连接到 MySQL 3306 端口的应用")
        fi
    fi
    
    # 检查是否有其他数据库用户
    if [ -d "/var/lib/mysql" ] && [ -n "$(ls -A /var/lib/mysql 2>/dev/null)" ]; then
        # 检查是否有非系统数据库
        local user_databases=$(find /var/lib/mysql -mindepth 1 -maxdepth 1 -type d ! -name "mysql" ! -name "sys" ! -name "information_schema" ! -name "performance_schema" 2>/dev/null | wc -l)
        if [ "$user_databases" -gt 0 ]; then
            affected_apps+=("用户数据库（$user_databases 个）")
        fi
    fi
    
    if [ ${#dependent_services[@]} -gt 0 ] || [ ${#affected_apps[@]} -gt 0 ]; then
        echo -e "${YELLOW}⚠ 检测到可能依赖 MySQL 的服务或应用：${NC}"
        for service in "${dependent_services[@]}"; do
            echo -e "${YELLOW}  - $service${NC}"
        done
        for app in "${affected_apps[@]}"; do
            echo -e "${YELLOW}  - $app${NC}"
        done
        echo ""
        return 1
    else
        echo -e "${GREEN}✓ 未检测到依赖 MySQL 的服务${NC}"
        return 0
    fi
}

# 清理数据目录（可选）
cleanup_data() {
    echo -e "${BLUE}[4/4] 清理数据目录...${NC}"
    
    # 检查依赖服务
    if ! check_dependent_services; then
        echo -e "${YELLOW}⚠ 删除 MySQL 数据可能影响上述服务${NC}"
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
            echo -e "${BLUE}数据目录位置:${NC}"
            echo "  - /var/lib/mysql"
            echo "  - /var/lib/mysqld"
            echo -e "${BLUE}配置文件位置:${NC}"
            echo "  - /etc/my.cnf"
            echo "  - /etc/mysql/my.cnf"
            echo ""
            echo -e "${YELLOW}提示: 重新安装 MySQL 后，数据将自动恢复${NC}"
            ;;
        keep_data)
            echo -e "${YELLOW}删除配置文件，但保留数据目录...${NC}"
            
            # 删除配置文件
            CONFIG_FILES=(
                "/etc/my.cnf"
                "/etc/mysql/my.cnf"
                "/etc/mysql/conf.d"
                "/etc/mysql/mysql.conf.d"
            )
            
            for file in "${CONFIG_FILES[@]}"; do
                if [ -f "$file" ] || [ -d "$file" ]; then
                    rm -rf "$file"
                    echo -e "${GREEN}✓ 已删除: $file${NC}"
                fi
            done
            
            # 删除日志文件（但保留日志目录）
            if [ -f "/var/log/mysqld.log" ]; then
                rm -f "/var/log/mysqld.log"
                echo -e "${GREEN}✓ 已删除日志文件: /var/log/mysqld.log${NC}"
            fi
            
            if [ -d "/var/log/mysql" ]; then
                rm -rf "/var/log/mysql"/*
                echo -e "${GREEN}✓ 已清理日志目录: /var/log/mysql${NC}"
            fi
            
            echo -e "${GREEN}✓ 配置文件已删除，数据目录已保留${NC}"
            echo -e "${BLUE}数据目录位置:${NC}"
            echo "  - /var/lib/mysql"
            echo "  - /var/lib/mysqld"
            ;;
        delete_all|y|Y)
            echo -e "${RED}警告: 将删除所有 MySQL 数据、配置和日志！${NC}"
            
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
            
            # 常见的数据目录位置
            DATA_DIRS=(
                "/var/lib/mysql"
                "/var/lib/mysqld"
                "/usr/local/mysql/data"
            )
            
            for dir in "${DATA_DIRS[@]}"; do
                if [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
                    echo -e "${YELLOW}正在删除数据目录: $dir${NC}"
                    rm -rf "$dir"
                    echo -e "${GREEN}✓ 已删除: $dir${NC}"
                fi
            done
            
            # 删除配置文件
            CONFIG_FILES=(
                "/etc/my.cnf"
                "/etc/mysql/my.cnf"
                "/etc/mysql/conf.d"
                "/etc/mysql/mysql.conf.d"
            )
            
            for file in "${CONFIG_FILES[@]}"; do
                if [ -f "$file" ] || [ -d "$file" ]; then
                    rm -rf "$file"
                    echo -e "${GREEN}✓ 已删除: $file${NC}"
                fi
            done
            
            # 删除日志目录
            LOG_DIRS=(
                "/var/log/mysqld.log"
                "/var/log/mysql"
            )
            
            for dir in "${LOG_DIRS[@]}"; do
                if [ -d "$dir" ] || [ -f "$dir" ]; then
                    rm -rf "$dir"
                    echo -e "${GREEN}✓ 已删除: $dir${NC}"
                fi
            done
            
            # 删除 MySQL 用户（如果存在且没有其他用途）
            if id mysql &>/dev/null; then
                read -p "是否删除 mysql 用户？[y/N]: " DELETE_USER
                DELETE_USER="${DELETE_USER:-N}"
                if [[ "$DELETE_USER" =~ ^[Yy]$ ]]; then
                    userdel mysql 2>/dev/null || true
                    echo -e "${GREEN}✓ 已删除 mysql 用户${NC}"
                fi
            fi
            
            echo -e "${GREEN}✓ 所有数据、配置和日志已删除${NC}"
            ;;
        *)
            echo -e "${YELLOW}保留数据目录${NC}"
            echo -e "${YELLOW}数据目录位置: /var/lib/mysql 或 /var/lib/mysqld${NC}"
            ;;
    esac
}

# 主函数
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}MySQL 一键卸载脚本${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    check_root
    
    stop_service
    disable_service
    uninstall_mysql
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
        echo -e "${BLUE}重新安装 MySQL 后，数据将自动恢复${NC}"
    elif [ "$DELETE_DATA" = "keep_data" ]; then
        echo -e "${GREEN}数据保留情况：${NC}"
        echo "  ✓ 数据目录已保留"
        echo "  ✗ 配置文件已删除"
        echo ""
        echo -e "${BLUE}重新安装 MySQL 后，需要重新配置${NC}"
    else
        echo -e "${YELLOW}数据清理情况：${NC}"
        echo "  ✗ 所有数据已删除"
        echo "  ✗ 所有配置已删除"
        echo "  ✗ 所有日志已删除"
        echo ""
        echo -e "${BLUE}如需重新安装 MySQL，请运行安装脚本${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}后续操作建议：${NC}"
    echo "  1. 如果保留了数据，重新安装 MySQL 后数据会自动恢复"
    echo "  2. 如果删除了数据，需要重新创建数据库和用户"
    echo "  3. 检查依赖 MySQL 的应用是否需要重新配置"
    echo ""
}

# 执行主函数
main "$@"

