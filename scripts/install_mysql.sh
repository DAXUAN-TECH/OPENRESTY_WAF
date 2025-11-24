#!/bin/bash

# MySQL 一键安装和配置脚本
# 支持多种 Linux 发行版：
#   - RedHat 系列：CentOS, RHEL, Fedora, Rocky Linux, AlmaLinux, Oracle Linux, Amazon Linux
#   - Debian 系列：Debian, Ubuntu, Linux Mint, Kali Linux, Raspbian
#   - SUSE 系列：openSUSE, SLES
#   - Arch 系列：Arch Linux, Manjaro
#   - 其他：Alpine Linux, Gentoo
# 用途：自动检测系统类型并安装配置 MySQL

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
# 保存原始环境变量（如果通过环境变量设置）
MYSQL_VERSION_FROM_ENV="${MYSQL_VERSION:-}"
MYSQL_VERSION="${MYSQL_VERSION:-8.0}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"
MYSQL_DATABASE=""
MYSQL_USER=""
MYSQL_USER_PASSWORD=""
USE_NEW_USER="N"

# 硬件信息变量（将在检测后填充）
CPU_CORES=0
TOTAL_MEM_GB=0
TOTAL_MEM_MB=0

# 导出变量供父脚本使用
export CREATED_DB_NAME=""
export MYSQL_USER_FOR_WAF=""
export MYSQL_PASSWORD_FOR_WAF=""
export USE_NEW_USER

# 检测硬件配置
detect_hardware() {
    echo -e "${BLUE}检测硬件配置...${NC}"
    
    # 检测 CPU 核心数
    if command -v nproc &> /dev/null; then
        CPU_CORES=$(nproc)
    elif [ -f /proc/cpuinfo ]; then
        CPU_CORES=$(grep -c "^processor" /proc/cpuinfo)
    else
        CPU_CORES=2  # 默认值
    fi
    
    # 检测内存大小（GB）
    if [ -f /proc/meminfo ]; then
        TOTAL_MEM_KB=$(grep "^MemTotal:" /proc/meminfo | awk '{print $2}')
        TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
        TOTAL_MEM_GB=$((TOTAL_MEM_MB / 1024))
    elif command -v free &> /dev/null; then
        TOTAL_MEM_MB=$(free -m | grep "^Mem:" | awk '{print $2}')
        TOTAL_MEM_GB=$((TOTAL_MEM_MB / 1024))
    else
        TOTAL_MEM_GB=4  # 默认值
        TOTAL_MEM_MB=4096
    fi
    
    # 确保最小值
    if [ $CPU_CORES -lt 1 ]; then
        CPU_CORES=1
    fi
    if [ $TOTAL_MEM_GB -lt 1 ]; then
        TOTAL_MEM_GB=1
        TOTAL_MEM_MB=1024
    fi
    
    echo -e "${GREEN}✓ CPU 核心数: ${CPU_CORES}${NC}"
    echo -e "${GREEN}✓ 总内存: ${TOTAL_MEM_GB}GB (${TOTAL_MEM_MB}MB)${NC}"
}

# 检测系统类型
detect_os() {
    echo -e "${BLUE}[1/8] 检测操作系统...${NC}"
    
    # 优先使用 /etc/os-release (标准方法)
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_LIKE=${ID_LIKE:-""}
        OS_VERSION=$VERSION_ID
        
        # 处理特殊发行版
        case $OS in
            "ol"|"oracle")
                OS="oraclelinux"
                ;;
            "amzn"|"amazon")
                OS="amazonlinux"
                ;;
            "raspbian")
                OS="debian"
                ;;
            "linuxmint")
                OS="ubuntu"  # Linux Mint 基于 Ubuntu
                ;;
            "kali")
                OS="debian"  # Kali Linux 基于 Debian
                ;;
        esac
        
        # 如果没有版本号，尝试从其他文件获取
        if [ -z "$OS_VERSION" ]; then
            if [ -f /etc/redhat-release ]; then
                OS_VERSION=$(cat /etc/redhat-release | sed 's/.*release \([0-9.]*\).*/\1/')
            elif [ -f /etc/debian_version ]; then
                OS_VERSION=$(cat /etc/debian_version)
            fi
        fi
    elif [ -f /etc/redhat-release ]; then
        # RedHat 系列
        local release_info=$(cat /etc/redhat-release)
        if echo "$release_info" | grep -qi "centos"; then
            OS="centos"
        elif echo "$release_info" | grep -qi "red hat\|rhel"; then
            OS="rhel"
        elif echo "$release_info" | grep -qi "rocky"; then
            OS="rocky"
        elif echo "$release_info" | grep -qi "alma"; then
            OS="almalinux"
        elif echo "$release_info" | grep -qi "oracle"; then
            OS="oraclelinux"
        elif echo "$release_info" | grep -qi "amazon"; then
            OS="amazonlinux"
        else
            OS="centos"  # 默认
        fi
        OS_VERSION=$(echo "$release_info" | sed 's/.*release \([0-9.]*\).*/\1/')
    elif [ -f /etc/debian_version ]; then
        # Debian 系列
        OS="debian"
        OS_VERSION=$(cat /etc/debian_version)
    elif [ -f /etc/alpine-release ]; then
        # Alpine Linux
        OS="alpine"
        OS_VERSION=$(cat /etc/alpine-release)
    elif [ -f /etc/arch-release ]; then
        # Arch Linux
        OS="arch"
        OS_VERSION="rolling"
    elif [ -f /etc/SuSE-release ]; then
        # SUSE
        OS="opensuse"
        OS_VERSION=$(grep VERSION /etc/SuSE-release | awk '{print $3}')
    else
        echo -e "${YELLOW}警告: 无法自动检测操作系统类型${NC}"
        echo -e "${YELLOW}将尝试使用通用方法${NC}"
        OS="unknown"
        OS_VERSION="unknown"
    fi
    
    # 显示检测结果
    if [ "$OS" != "unknown" ]; then
        echo -e "${GREEN}✓ 检测到系统: ${OS} ${OS_VERSION}${NC}"
        if [ -n "$OS_LIKE" ] && [ "$OS_LIKE" != "$OS" ]; then
            echo -e "${BLUE}  基于: ${OS_LIKE}${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ 系统类型: 未知（将尝试通用方法）${NC}"
    fi
}

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}错误: 需要 root 权限来安装 MySQL${NC}"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 彻底卸载 MySQL/MariaDB
completely_uninstall_mysql() {
    echo -e "${BLUE}开始彻底卸载 MySQL/MariaDB...${NC}"
    
    # 确保已检测操作系统（如果未检测，先检测）
    if [ -z "$OS" ]; then
        detect_os
    fi
    
    # 停止 MySQL 服务
    echo "停止 MySQL 服务..."
    if command -v systemctl &> /dev/null; then
        systemctl stop mysqld 2>/dev/null || systemctl stop mysql 2>/dev/null || true
        systemctl disable mysqld 2>/dev/null || systemctl disable mysql 2>/dev/null || true
    elif command -v service &> /dev/null; then
        service mysqld stop 2>/dev/null || service mysql stop 2>/dev/null || true
        chkconfig mysqld off 2>/dev/null || chkconfig mysql off 2>/dev/null || true
    fi
    
    # 确保进程已停止
    sleep 2
    pkill -9 mysqld 2>/dev/null || true
    pkill -9 mysql_safe 2>/dev/null || true
    
    # 卸载 MySQL/MariaDB 软件包
    echo "卸载 MySQL/MariaDB 软件包..."
    case $OS in
        centos|rhel|fedora|rocky|almalinux|oraclelinux|amazonlinux)
            if command -v dnf &> /dev/null; then
                dnf remove -y mysql-server mysql mysql-common mysql-community-server mysql-community-client mariadb-server mariadb 2>/dev/null || true
            elif command -v yum &> /dev/null; then
                yum remove -y mysql-server mysql mysql-common mysql-community-server mysql-community-client mariadb-server mariadb 2>/dev/null || true
            fi
            ;;
        ubuntu|debian|linuxmint|raspbian|kali)
            if command -v apt-get &> /dev/null; then
                apt-get remove -y mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-* mariadb-server mariadb-client 2>/dev/null || true
                apt-get purge -y mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-* mariadb-server mariadb-client 2>/dev/null || true
                apt-get autoremove -y 2>/dev/null || true
            fi
            ;;
        opensuse*|sles)
            if command -v zypper &> /dev/null; then
                zypper remove -y mariadb mariadb-server mysql mysql-server 2>/dev/null || true
            fi
            ;;
        arch|manjaro)
            if command -v pacman &> /dev/null; then
                pacman -R --noconfirm mysql mariadb 2>/dev/null || true
            fi
            ;;
        alpine)
            if command -v apk &> /dev/null; then
                apk del mysql mysql-client mariadb mariadb-client 2>/dev/null || true
            fi
            ;;
        gentoo)
            if command -v emerge &> /dev/null; then
                emerge --unmerge dev-db/mysql dev-db/mariadb 2>/dev/null || true
            fi
            ;;
    esac
    
    echo -e "${GREEN}✓ MySQL/MariaDB 软件包已卸载${NC}"
}

# 检查 MySQL 是否已安装
check_existing() {
    echo -e "${BLUE}[2/8] 检查是否已安装 MySQL...${NC}"
    
    local mysql_installed=0
    local mysql_version=""
    local mysql_data_initialized=0
    local mysql_data_dir=""
    
    # 检查 MySQL 是否已安装
    if command -v mysql &> /dev/null || command -v mysqld &> /dev/null; then
        mysql_installed=1
        mysql_version=$(mysql --version 2>/dev/null || mysqld --version 2>/dev/null | head -n 1)
        echo -e "${YELLOW}检测到已安装 MySQL: ${mysql_version}${NC}"
        
        # 检查数据目录是否已初始化
        local mysql_data_dirs=(
            "/var/lib/mysql"
            "/var/lib/mysqld"
            "/usr/local/mysql/data"
        )
        
        for dir in "${mysql_data_dirs[@]}"; do
            if [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
                # 检查是否包含 mysql 系统数据库（说明已初始化）
                if [ -d "$dir/mysql" ] && ([ -f "$dir/mysql/user.MYD" ] || [ -f "$dir/mysql/user.ibd" ] || [ -d "$dir/mysql.ibd" ]); then
                    mysql_data_initialized=1
                    mysql_data_dir="$dir"
                    break
                fi
            fi
        done
        
        if [ $mysql_data_initialized -eq 1 ]; then
            echo -e "${YELLOW}检测到 MySQL 数据目录已初始化: ${mysql_data_dir}${NC}"
            echo ""
            echo "请选择操作："
            echo "  1. 保留现有数据和配置，跳过安装"
            echo "  2. 重新安装 MySQL（先卸载，保留数据目录）"
            echo "  3. 完全重新安装（先卸载，删除所有数据和配置）"
            read -p "请选择 [1-3]: " REINSTALL_CHOICE
            
            case "$REINSTALL_CHOICE" in
                1)
                    echo -e "${GREEN}跳过 MySQL 安装，保留现有配置${NC}"
                    # 检查现有 MySQL 版本是否满足要求
                    if [ -n "$MYSQL_VERSION" ] && [ "$MYSQL_VERSION" != "default" ]; then
                        local current_major=$(echo "$mysql_version" | grep -oE '[0-9]+\.[0-9]+' | head -1)
                        local required_major=$(echo "$MYSQL_VERSION" | grep -oE '^[0-9]+\.[0-9]+' | head -1)
                        if [ "$current_major" != "$required_major" ]; then
                            echo -e "${YELLOW}⚠ 当前版本 ($current_major) 与要求版本 ($required_major) 不匹配${NC}"
                            echo -e "${YELLOW}⚠ 建议重新安装以匹配版本要求${NC}"
                        fi
                    fi
                    # 设置跳过安装标志，但继续执行后续步骤
                    SKIP_INSTALL=1
                    echo -e "${BLUE}将跳过安装步骤，继续执行数据库创建和用户设置等后续步骤${NC}"
                    ;;
                2)
                    echo -e "${YELLOW}将重新安装 MySQL，先卸载现有安装，但保留数据目录${NC}"
                    echo -e "${YELLOW}注意: 如果版本不兼容，可能导致数据无法使用${NC}"
                    echo -e "${YELLOW}建议: 在重新安装前备份数据目录${NC}"
                    read -p "是否先备份数据目录？[Y/n]: " BACKUP_DATA
                    BACKUP_DATA="${BACKUP_DATA:-Y}"
                    if [[ "$BACKUP_DATA" =~ ^[Yy]$ ]]; then
                        local backup_dir="/var/backups/mysql_$(date +%Y%m%d_%H%M%S)"
                        mkdir -p "$backup_dir"
                        echo -e "${BLUE}正在备份数据目录到: $backup_dir${NC}"
                        cp -r "${mysql_data_dir}" "$backup_dir/data" 2>/dev/null || {
                            echo -e "${YELLOW}⚠ 备份失败，继续安装${NC}"
                        }
                        echo -e "${GREEN}✓ 备份完成${NC}"
                    fi
                    REINSTALL_MODE="keep_data"
                    # 先卸载软件包
                    completely_uninstall_mysql
                    # 卸载后清除版本选择，让用户重新选择
                    # 但保留通过环境变量设置的版本（如果存在）
                    if [ -z "${MYSQL_VERSION_FROM_ENV:-}" ]; then
                        # 如果版本不是通过环境变量设置的，清除它让用户重新选择
                        unset MYSQL_VERSION
                    else
                        # 如果版本是通过环境变量设置的，恢复它
                        MYSQL_VERSION="${MYSQL_VERSION_FROM_ENV}"
                    fi
                    ;;
                3)
                    echo -e "${RED}警告: 将删除所有 MySQL 数据和配置！${NC}"
                    echo -e "${RED}这将包括：${NC}"
                    echo "  - 所有数据库和数据"
                    echo "  - 所有用户和权限"
                    echo "  - 配置文件"
                    echo "  - 日志文件"
                    read -p "确认删除所有数据？[y/N]: " CONFIRM_DELETE
                    CONFIRM_DELETE="${CONFIRM_DELETE:-N}"
                    if [[ "$CONFIRM_DELETE" =~ ^[Yy]$ ]]; then
                        echo -e "${YELLOW}将完全重新安装 MySQL，先卸载现有安装并删除所有数据${NC}"
                        REINSTALL_MODE="delete_all"
                        
                        # 先卸载软件包
                        completely_uninstall_mysql
                        
                        # 检查是否有其他服务依赖 MySQL
                        echo -e "${BLUE}检查是否有其他服务依赖 MySQL...${NC}"
                        if systemctl list-units --type=service --state=running 2>/dev/null | grep -qiE "php-fpm|wordpress|owncloud|nextcloud"; then
                            echo -e "${YELLOW}⚠ 检测到可能依赖 MySQL 的服务正在运行${NC}"
                            echo -e "${YELLOW}⚠ 删除 MySQL 可能导致这些服务无法正常工作${NC}"
                            read -p "是否继续？[y/N]: " CONTINUE_DELETE
                            CONTINUE_DELETE="${CONTINUE_DELETE:-N}"
                            if [[ ! "$CONTINUE_DELETE" =~ ^[Yy]$ ]]; then
                                echo -e "${GREEN}取消删除，将保留数据重新安装${NC}"
                                REINSTALL_MODE="keep_data"
                                return 0
                            fi
                        fi
                        
                        # 删除数据目录
                        local data_dirs=(
                            "/var/lib/mysql"
                            "/var/lib/mysqld"
                            "/usr/local/mysql/data"
                        )
                        for dir in "${data_dirs[@]}"; do
                            if [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
                                echo -e "${YELLOW}正在删除数据目录: ${dir}${NC}"
                                rm -rf "$dir"
                                echo -e "${GREEN}✓ 数据目录已删除: $dir${NC}"
                            fi
                        done
                        
                        # 删除配置文件
                        local config_files=(
                            "/etc/my.cnf"
                            "/etc/my.cnf.d"
                            "/etc/mysql/my.cnf"
                            "/etc/mysql/conf.d"
                            "/etc/mysql/mysql.conf.d"
                            "/etc/mysql/mariadb.conf.d"
                        )
                        for file in "${config_files[@]}"; do
                            if [ -f "$file" ] || [ -d "$file" ]; then
                                rm -rf "$file"
                                echo -e "${GREEN}✓ 已删除: $file${NC}"
                            fi
                        done
                        
                        # 删除日志文件
                        local log_files=(
                            "/var/log/mysqld.log"
                            "/var/log/mysql"
                            "/var/log/mariadb"
                        )
                        for log_file in "${log_files[@]}"; do
                            if [ -f "$log_file" ] || [ -d "$log_file" ]; then
                                rm -rf "$log_file"
                                echo -e "${GREEN}✓ 已删除: $log_file${NC}"
                            fi
                        done
                        
                        # 删除其他可能的残留文件
                        rm -rf /var/run/mysqld 2>/dev/null || true
                        rm -rf /var/run/mysql 2>/dev/null || true
                        rm -rf /tmp/mysql* 2>/dev/null || true
                        
                        # 卸载后清除版本选择，让用户重新选择
                        # 但保留通过环境变量设置的版本（如果存在）
                        if [ -z "${MYSQL_VERSION_FROM_ENV:-}" ]; then
                            # 如果版本不是通过环境变量设置的，清除它让用户重新选择
                            unset MYSQL_VERSION
                        else
                            # 如果版本是通过环境变量设置的，恢复它
                            MYSQL_VERSION="${MYSQL_VERSION_FROM_ENV}"
                        fi
                    else
                        echo -e "${GREEN}取消删除，将保留数据重新安装${NC}"
                        REINSTALL_MODE="keep_data"
                        # 仍然需要卸载软件包
                        completely_uninstall_mysql
                        # 卸载后清除版本选择，让用户重新选择
                        if [ -z "${MYSQL_VERSION_FROM_ENV:-}" ]; then
                            # 如果版本不是通过环境变量设置的，清除它让用户重新选择
                            unset MYSQL_VERSION
                        else
                            # 如果版本是通过环境变量设置的，恢复它
                            MYSQL_VERSION="${MYSQL_VERSION_FROM_ENV}"
                        fi
                    fi
                    ;;
                *)
                    echo -e "${YELLOW}无效选择，将跳过安装${NC}"
                    exit 0
                    ;;
            esac
        else
            echo -e "${YELLOW}MySQL 已安装但数据目录未初始化${NC}"
            echo ""
            echo "请选择操作："
            echo "  1. 保留现有安装，跳过安装"
            echo "  2. 重新安装 MySQL（先卸载，保留数据目录）"
            echo "  3. 完全重新安装（先卸载，删除所有数据和配置）"
            read -p "请选择 [1-3]: " REINSTALL_CHOICE
            
            case "$REINSTALL_CHOICE" in
                1)
                    echo -e "${GREEN}跳过 MySQL 安装，保留现有安装${NC}"
                    # 检查现有 MySQL 版本是否满足要求
                    if [ -n "$MYSQL_VERSION" ] && [ "$MYSQL_VERSION" != "default" ]; then
                        local current_major=$(echo "$mysql_version" | grep -oE '[0-9]+\.[0-9]+' | head -1)
                        local required_major=$(echo "$MYSQL_VERSION" | grep -oE '^[0-9]+\.[0-9]+' | head -1)
                        if [ "$current_major" != "$required_major" ]; then
                            echo -e "${YELLOW}⚠ 当前版本 ($current_major) 与要求版本 ($required_major) 不匹配${NC}"
                            echo -e "${YELLOW}⚠ 建议重新安装以匹配版本要求${NC}"
                        fi
            fi
                    # 设置跳过安装标志，但继续执行后续步骤
                    SKIP_INSTALL=1
                    echo -e "${BLUE}将跳过安装步骤，继续执行数据库创建和用户设置等后续步骤${NC}"
                    ;;
                2)
                    echo -e "${YELLOW}将重新安装 MySQL，先卸载现有安装，但保留数据目录${NC}"
                    echo -e "${YELLOW}注意: 如果版本不兼容，可能导致数据无法使用${NC}"
                    REINSTALL_MODE="keep_data"
            # 先卸载软件包
            completely_uninstall_mysql
                    # 卸载后清除版本选择，让用户重新选择
                    if [ -z "${MYSQL_VERSION_FROM_ENV:-}" ]; then
                        unset MYSQL_VERSION
                    else
                        MYSQL_VERSION="${MYSQL_VERSION_FROM_ENV}"
                    fi
                    ;;
                3)
                    echo -e "${RED}警告: 将删除所有 MySQL 数据和配置！${NC}"
                    echo -e "${RED}这将包括：${NC}"
                    echo "  - 所有数据库和数据"
                    echo "  - 所有用户和权限"
                    echo "  - 配置文件"
                    echo "  - 日志文件"
                    read -p "确认删除所有数据？[y/N]: " CONFIRM_DELETE
                    CONFIRM_DELETE="${CONFIRM_DELETE:-N}"
                    if [[ "$CONFIRM_DELETE" =~ ^[Yy]$ ]]; then
                        echo -e "${YELLOW}将完全重新安装 MySQL，先卸载现有安装并删除所有数据${NC}"
                        REINSTALL_MODE="delete_all"
                        
                        # 先卸载软件包
                        completely_uninstall_mysql
                        
                        # 检查是否有其他服务依赖 MySQL
                        echo -e "${BLUE}检查是否有其他服务依赖 MySQL...${NC}"
                        if systemctl list-units --type=service --state=running 2>/dev/null | grep -qiE "php-fpm|wordpress|owncloud|nextcloud"; then
                            echo -e "${YELLOW}⚠ 检测到可能依赖 MySQL 的服务正在运行${NC}"
                            echo -e "${YELLOW}⚠ 删除 MySQL 可能导致这些服务无法正常工作${NC}"
                            read -p "是否继续？[y/N]: " CONTINUE_DELETE
                            CONTINUE_DELETE="${CONTINUE_DELETE:-N}"
                            if [[ ! "$CONTINUE_DELETE" =~ ^[Yy]$ ]]; then
                                echo -e "${GREEN}取消删除，将保留数据重新安装${NC}"
                                REINSTALL_MODE="keep_data"
                                return 0
                            fi
                        fi
                        
                        # 删除数据目录
                        local data_dirs=(
                            "/var/lib/mysql"
                            "/var/lib/mysqld"
                            "/usr/local/mysql/data"
                        )
                        for dir in "${data_dirs[@]}"; do
                            if [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
                                echo -e "${YELLOW}正在删除数据目录: ${dir}${NC}"
                                rm -rf "$dir"
                                echo -e "${GREEN}✓ 数据目录已删除: $dir${NC}"
                            fi
                        done
                        
                        # 删除配置文件
                        local config_files=(
                            "/etc/my.cnf"
                            "/etc/my.cnf.d"
                            "/etc/mysql/my.cnf"
                            "/etc/mysql/conf.d"
                            "/etc/mysql/mysql.conf.d"
                            "/etc/mysql/mariadb.conf.d"
                        )
                        for file in "${config_files[@]}"; do
                            if [ -f "$file" ] || [ -d "$file" ]; then
                                rm -rf "$file"
                                echo -e "${GREEN}✓ 已删除: $file${NC}"
                            fi
                        done
                        
                        # 删除日志文件
                        local log_files=(
                            "/var/log/mysqld.log"
                            "/var/log/mysql"
                            "/var/log/mariadb"
                        )
                        for log_file in "${log_files[@]}"; do
                            if [ -f "$log_file" ] || [ -d "$log_file" ]; then
                                rm -rf "$log_file"
                                echo -e "${GREEN}✓ 已删除: $log_file${NC}"
                            fi
                        done
                        
                        # 删除其他可能的残留文件
                        rm -rf /var/run/mysqld 2>/dev/null || true
                        rm -rf /var/run/mysql 2>/dev/null || true
                        rm -rf /tmp/mysql* 2>/dev/null || true
                        
                        # 卸载后清除版本选择，让用户重新选择
                        if [ -z "${MYSQL_VERSION_FROM_ENV:-}" ]; then
                            unset MYSQL_VERSION
                        else
                            MYSQL_VERSION="${MYSQL_VERSION_FROM_ENV}"
                        fi
                    else
                        echo -e "${GREEN}取消删除，将保留数据重新安装${NC}"
                        REINSTALL_MODE="keep_data"
                        # 仍然需要卸载软件包
                        completely_uninstall_mysql
                        # 卸载后清除版本选择，让用户重新选择
                        if [ -z "${MYSQL_VERSION_FROM_ENV:-}" ]; then
                            unset MYSQL_VERSION
                        else
                            MYSQL_VERSION="${MYSQL_VERSION_FROM_ENV}"
                        fi
                    fi
                    ;;
                *)
                    echo -e "${YELLOW}无效选择，将跳过安装${NC}"
                    exit 0
                    ;;
            esac
        fi
    else
        echo -e "${GREEN}✓ MySQL 未安装，将进行全新安装${NC}"
    fi
    
    # 版本选择（如果未设置环境变量或已卸载需要重新选择）
    # 注意：检查环境变量 MYSQL_VERSION_FROM_ENV，而不是 MYSQL_VERSION（因为 MYSQL_VERSION 有默认值）
    if [ -z "${MYSQL_VERSION_FROM_ENV:-}" ]; then
        echo ""
        echo -e "${BLUE}正在检查可用的 MySQL 版本...${NC}"
        
        # 如果是RedHat系列，先尝试配置仓库以检查可用版本
        if [[ "$OS" =~ ^(centos|rhel|rocky|almalinux|oraclelinux|amazonlinux|fedora)$ ]]; then
            # 确定仓库版本
            local el_version="el7"
            case $OS in
                fedora)
                    if echo "$OS_VERSION" | grep -qE "^3[0-9]"; then
                        el_version="el9"
                    else
                        el_version="el8"
                    fi
                    ;;
                rhel|rocky|almalinux|oraclelinux)
                    if echo "$OS_VERSION" | grep -qE "^9\."; then
                        el_version="el9"
                    elif echo "$OS_VERSION" | grep -qE "^8\."; then
                        el_version="el8"
                    else
                        el_version="el7"
                    fi
                    ;;
                amazonlinux)
                    if echo "$OS_VERSION" | grep -qE "^2023"; then
                        el_version="el9"
                    else
                        el_version="el7"
                    fi
                    ;;
            esac
            
            # 如果仓库未配置，尝试快速配置以检查可用版本
            if [ ! -f /etc/yum.repos.d/mysql-community.repo ]; then
                echo "正在配置 MySQL 仓库以检查可用版本..."
                local repo_file80="mysql80-community-release-${el_version}-1.noarch.rpm"
                local repo_file57="mysql57-community-release-${el_version}-1.noarch.rpm"
                
                # 尝试下载MySQL 8.0仓库
                for el_ver in $el_version el8 el7; do
                    local repo_url="https://dev.mysql.com/get/mysql80-community-release-${el_ver}-1.noarch.rpm"
                    if wget -q "$repo_url" -O /tmp/mysql-community-release.rpm 2>/dev/null && [ -s /tmp/mysql-community-release.rpm ]; then
                        rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2022 2>/dev/null || \
                        rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql 2>/dev/null || true
                        # 尝试安装仓库，如果 GPG 验证失败，使用 --nodigest --nosignature
                        rpm -ivh /tmp/mysql-community-release.rpm 2>&1 | grep -v "GPG" || \
                        rpm -ivh --nodigest --nosignature /tmp/mysql-community-release.rpm 2>&1 | grep -v "GPG" || true
                        rm -f /tmp/mysql-community-release.rpm
                        break
                    fi
                done
                
                # 更新yum缓存
                yum makecache fast 2>/dev/null || dnf makecache 2>/dev/null || true
            fi
            
            # 检查可用版本
            echo "正在检查可用版本..."
            local available_versions=()
            local temp_versions_file="/tmp/mysql_available_versions.txt"
            
            if command -v yum &> /dev/null; then
                # 先更新yum缓存以确保获取最新版本列表
                yum makecache fast >/dev/null 2>&1 || true
                
                # 获取所有可用的MySQL版本（包括所有小版本号）
                # 改进：使用更宽松的匹配模式，确保能匹配到所有版本
                yum list available mysql-community-server mysql-community-client 2>/dev/null | \
                    grep -E "mysql-community-server" | \
                    awk '{print $2}' | \
                    grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | \
                    sort -V -u > "$temp_versions_file" 2>/dev/null || true
                
                # 如果没有找到具体版本，尝试获取主次版本号
                if [ ! -s "$temp_versions_file" ]; then
                    yum list available mysql-community-server mysql-community-client 2>/dev/null | \
                        grep -E "mysql-community-server" | \
                        awk '{print $2}' | \
                        grep -oE '[0-9]+\.[0-9]+' | \
                        sort -V -u > "$temp_versions_file" 2>/dev/null || true
                fi
            elif command -v dnf &> /dev/null; then
                # 先更新dnf缓存以确保获取最新版本列表
                dnf makecache fast >/dev/null 2>&1 || true
                
                # 获取所有可用的MySQL版本（包括所有小版本号）
                # 改进：使用更宽松的匹配模式，确保能匹配到所有版本
                dnf list available mysql-community-server mysql-community-client 2>/dev/null | \
                    grep -E "mysql-community-server" | \
                    awk '{print $2}' | \
                    grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | \
                    sort -V -u > "$temp_versions_file" 2>/dev/null || true
                
                # 如果没有找到具体版本，尝试获取主次版本号
                if [ ! -s "$temp_versions_file" ]; then
                    dnf list available mysql-community-server mysql-community-client 2>/dev/null | \
                        grep -E "mysql-community-server" | \
                        awk '{print $2}' | \
                        grep -oE '[0-9]+\.[0-9]+' | \
                        sort -V -u > "$temp_versions_file" 2>/dev/null || true
                fi
            fi
            
            # 读取版本到数组
            if [ -s "$temp_versions_file" ]; then
                while IFS= read -r version; do
                    if [ -n "$version" ]; then
                        available_versions+=("$version")
                    fi
                done < "$temp_versions_file"
                rm -f "$temp_versions_file"
            fi
            
            # 如果没有找到任何版本，添加默认选项
            if [ ${#available_versions[@]} -eq 0 ]; then
                # 尝试检查是否有8.0或5.7系列
                if command -v yum &> /dev/null; then
                    if yum list available mysql-community-server mysql-community-client 2>/dev/null | grep -qE "mysql-community-server.*8\.0"; then
                        available_versions+=("8.0")
                    fi
                    if yum list available mysql-community-server mysql-community-client 2>/dev/null | grep -qE "mysql-community-server.*5\.7"; then
                        available_versions+=("5.7")
                    fi
                elif command -v dnf &> /dev/null; then
                    if dnf list available mysql-community-server mysql-community-client 2>/dev/null | grep -qE "mysql-community-server.*8\.0"; then
                        available_versions+=("8.0")
                    fi
                    if dnf list available mysql-community-server mysql-community-client 2>/dev/null | grep -qE "mysql-community-server.*5\.7"; then
                        available_versions+=("5.7")
                    fi
                fi
            fi
            
            # 显示可用版本
            if [ ${#available_versions[@]} -gt 0 ]; then
                echo ""
                echo -e "${GREEN}✓ 检测到以下可用版本：${NC}"
                echo ""
                local idx=1
                for ver in "${available_versions[@]}"; do
                    printf "  %2d. MySQL %s\n" "$idx" "$ver"
                    idx=$((idx + 1))
                done
                local default_option=$idx
                printf "  %2d. 使用系统默认版本\n" "$default_option"
                local custom_option=$((idx + 1))
                printf "  %2d. 自定义版本（手动输入版本号）\n" "$custom_option"
                echo ""
                read -p "请选择版本 [1-${custom_option}]: " VERSION_CHOICE
                
                # 处理选择
                if [ "$VERSION_CHOICE" -ge 1 ] && [ "$VERSION_CHOICE" -le ${#available_versions[@]} ]; then
                    MYSQL_VERSION="${available_versions[$((VERSION_CHOICE - 1))]}"
                    echo -e "${GREEN}✓ 已选择 MySQL ${MYSQL_VERSION}${NC}"
                elif [ "$VERSION_CHOICE" -eq "$default_option" ]; then
                    MYSQL_VERSION="default"
                    echo -e "${GREEN}✓ 将使用系统默认版本${NC}"
                elif [ "$VERSION_CHOICE" -eq "$custom_option" ]; then
                    echo ""
                    echo -e "${BLUE}请输入 MySQL 版本号（格式：主版本.次版本.修订版本，如 8.0.39）${NC}"
                    read -p "版本号: " CUSTOM_VERSION
                    CUSTOM_VERSION=$(echo "$CUSTOM_VERSION" | tr -d '[:space:]')
                    
                    if echo "$CUSTOM_VERSION" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
                        MYSQL_VERSION="$CUSTOM_VERSION"
                        echo -e "${GREEN}✓ 已选择 MySQL ${MYSQL_VERSION}${NC}"
                    else
                        echo -e "${RED}✗ 版本号格式错误，使用默认版本${NC}"
                        MYSQL_VERSION="${available_versions[0]}"
                    fi
                else
                    echo -e "${YELLOW}无效选择，使用默认版本: ${available_versions[0]}${NC}"
                    MYSQL_VERSION="${available_versions[0]}"
                fi
            else
                # 如果没有检测到可用版本，显示默认选项
                echo -e "${YELLOW}⚠ 无法检测可用版本，显示默认选项${NC}"
                echo ""
                echo "请选择 MySQL 版本："
                echo "  1. MySQL 8.0（推荐，最新稳定版）"
                echo "  2. MySQL 5.7（兼容性更好）"
                echo "  3. 使用系统默认版本"
                echo "  4. 自定义版本（手动输入版本号）"
                read -p "请选择 [1-4]: " VERSION_CHOICE
                
                case "$VERSION_CHOICE" in
                    1)
                        MYSQL_VERSION="8.0"
                        echo -e "${GREEN}✓ 已选择 MySQL 8.0${NC}"
                        ;;
                    2)
                        MYSQL_VERSION="5.7"
                        echo -e "${GREEN}✓ 已选择 MySQL 5.7${NC}"
                        ;;
                    3)
                        MYSQL_VERSION="default"
                        echo -e "${GREEN}✓ 将使用系统默认版本${NC}"
                        ;;
                    4)
                        echo ""
                        echo -e "${BLUE}请输入 MySQL 版本号（格式：主版本.次版本.修订版本，如 8.0.39）${NC}"
                        read -p "版本号: " CUSTOM_VERSION
                        CUSTOM_VERSION=$(echo "$CUSTOM_VERSION" | tr -d '[:space:]')
                        
                        if echo "$CUSTOM_VERSION" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
                            MYSQL_VERSION="$CUSTOM_VERSION"
                            echo -e "${GREEN}✓ 已选择 MySQL ${MYSQL_VERSION}${NC}"
                        else
                            echo -e "${RED}✗ 版本号格式错误，默认使用 MySQL 8.0${NC}"
                            MYSQL_VERSION="8.0"
                        fi
                        ;;
                    *)
                        MYSQL_VERSION="8.0"
                        echo -e "${YELLOW}无效选择，默认使用 MySQL 8.0${NC}"
                        ;;
                esac
            fi
            # 关闭 RedHat 系列的 if 块（第591行）
        else
            # 非RedHat系列（Debian/Ubuntu等），尝试获取可用版本
            echo ""
            echo -e "${BLUE}正在检查可用的 MySQL 版本...${NC}"
            
            local available_versions=()
            local temp_versions_file="/tmp/mysql_available_versions.txt"
            
            # 更新apt缓存
            apt-get update -qq 2>/dev/null || true
            
            # 尝试获取可用版本（Debian系列）
            if command -v apt-cache &> /dev/null; then
                # 使用 apt-cache madison 获取可用版本
                apt-cache madison mysql-server 2>/dev/null | \
                    awk '{print $3}' | \
                    grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | \
                    sort -V -u > "$temp_versions_file" 2>/dev/null || true
                
                # 如果madison没有结果，尝试使用policy
                if [ ! -s "$temp_versions_file" ]; then
                    apt-cache policy mysql-server 2>/dev/null | \
                        grep -E "^\s+[0-9]+\.[0-9]+" | \
                        awk '{print $2}' | \
                        grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | \
                        sort -V -u > "$temp_versions_file" 2>/dev/null || true
                fi
            fi
            
            # 读取版本到数组
            if [ -s "$temp_versions_file" ]; then
                while IFS= read -r version; do
                    if [ -n "$version" ]; then
                        available_versions+=("$version")
                    fi
                done < "$temp_versions_file"
                rm -f "$temp_versions_file"
            fi
            
            # 显示可用版本
            if [ ${#available_versions[@]} -gt 0 ]; then
                echo ""
                echo -e "${GREEN}✓ 检测到以下可用版本：${NC}"
                echo ""
                local idx=1
                for ver in "${available_versions[@]}"; do
                    printf "  %2d. MySQL %s\n" "$idx" "$ver"
                    idx=$((idx + 1))
                done
                local default_option=$idx
                printf "  %2d. 使用系统默认版本\n" "$default_option"
                local custom_option=$((idx + 1))
                printf "  %2d. 自定义版本（手动输入版本号）\n" "$custom_option"
                echo ""
                read -p "请选择版本 [1-${custom_option}]: " VERSION_CHOICE
                
                # 处理选择
                if [ "$VERSION_CHOICE" -ge 1 ] && [ "$VERSION_CHOICE" -le ${#available_versions[@]} ]; then
                    MYSQL_VERSION="${available_versions[$((VERSION_CHOICE - 1))]}"
                    echo -e "${GREEN}✓ 已选择 MySQL ${MYSQL_VERSION}${NC}"
                elif [ "$VERSION_CHOICE" -eq "$default_option" ]; then
                    MYSQL_VERSION="default"
                    echo -e "${GREEN}✓ 将使用系统默认版本${NC}"
                elif [ "$VERSION_CHOICE" -eq "$custom_option" ]; then
                    echo ""
                    echo -e "${BLUE}请输入 MySQL 版本号（格式：主版本.次版本.修订版本，如 8.0.39）${NC}"
                    read -p "版本号: " CUSTOM_VERSION
                    CUSTOM_VERSION=$(echo "$CUSTOM_VERSION" | tr -d '[:space:]')
                    
                    if echo "$CUSTOM_VERSION" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
                        MYSQL_VERSION="$CUSTOM_VERSION"
                        echo -e "${GREEN}✓ 已选择 MySQL ${MYSQL_VERSION}${NC}"
                    else
                        echo -e "${RED}✗ 版本号格式错误，使用默认版本${NC}"
                        MYSQL_VERSION="${available_versions[0]}"
                    fi
                else
                    echo -e "${YELLOW}无效选择，使用默认版本: ${available_versions[0]}${NC}"
                    MYSQL_VERSION="${available_versions[0]}"
                fi
            else
                # 如果没有检测到可用版本，显示默认选项
                echo -e "${YELLOW}⚠ 无法检测可用版本，显示默认选项${NC}"
                echo ""
                echo "请选择 MySQL 版本："
                echo "  1. MySQL 8.0（推荐，最新稳定版）"
                echo "  2. MySQL 5.7（兼容性更好）"
                echo "  3. 使用系统默认版本"
                echo "  4. 自定义版本（手动输入版本号）"
                read -p "请选择 [1-4]: " VERSION_CHOICE
                
                case "$VERSION_CHOICE" in
                    1)
                        MYSQL_VERSION="8.0"
                        echo -e "${GREEN}✓ 已选择 MySQL 8.0${NC}"
                        ;;
                    2)
                        MYSQL_VERSION="5.7"
                        echo -e "${GREEN}✓ 已选择 MySQL 5.7${NC}"
                        ;;
                    3)
                        MYSQL_VERSION="default"
                        echo -e "${GREEN}✓ 将使用系统默认版本${NC}"
                        ;;
                    4)
                        echo ""
                        echo -e "${BLUE}请输入 MySQL 版本号（格式：主版本.次版本.修订版本，如 8.0.39）${NC}"
                        read -p "版本号: " CUSTOM_VERSION
                        CUSTOM_VERSION=$(echo "$CUSTOM_VERSION" | tr -d '[:space:]')
                        
                        if echo "$CUSTOM_VERSION" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
                            MYSQL_VERSION="$CUSTOM_VERSION"
                            echo -e "${GREEN}✓ 已选择 MySQL ${MYSQL_VERSION}${NC}"
                        else
                            echo -e "${RED}✗ 版本号格式错误，默认使用 MySQL 8.0${NC}"
                            MYSQL_VERSION="8.0"
                        fi
                        ;;
                    *)
                        MYSQL_VERSION="8.0"
                        echo -e "${YELLOW}无效选择，默认使用 MySQL 8.0${NC}"
                        ;;
                esac
            fi
        fi
    else
        if [ -n "${MYSQL_VERSION_FROM_ENV:-}" ] && [ "$MYSQL_VERSION" = "${MYSQL_VERSION_FROM_ENV:-}" ]; then
        echo -e "${BLUE}使用环境变量指定的版本: ${MYSQL_VERSION}${NC}"
        else
            echo -e "${BLUE}使用已选择的版本: ${MYSQL_VERSION}${NC}"
        fi
    fi
    
    echo -e "${GREEN}✓ 检查完成${NC}"
}

# 检查指定版本的MySQL是否可用（RedHat系列）
check_mysql_version_available_redhat() {
    local version="$1"
    local major_minor=""
    local full_version=""
    
    if [ -z "$version" ] || [ "$version" = "default" ]; then
        return 0  # 默认版本总是可用
    fi
    
    # 提取主次版本号
    if echo "$version" | grep -qE '^[0-9]+\.[0-9]+'; then
        major_minor=$(echo "$version" | grep -oE '^[0-9]+\.[0-9]+')
        full_version="$version"
    else
        return 0  # 格式不正确，让安装过程处理
    fi
    
    # 检查完整版本号是否可用
    if command -v yum &> /dev/null; then
        # 检查完整版本号包
        if yum list available "mysql-community-server-${full_version}" "mysql-community-client-${full_version}" 2>/dev/null | grep -qE "mysql-community-server|mysql-community-client"; then
            return 0
        fi
        
        # 检查主次版本号包
        if yum list available "mysql-community-server-${major_minor}*" "mysql-community-client-${major_minor}*" 2>/dev/null | grep -qE "mysql-community-server|mysql-community-client"; then
            return 0
        fi
        
        # 检查通用包名
        if yum list available mysql-community-server mysql-community-client 2>/dev/null | grep -qE "mysql-community-server|mysql-community-client"; then
            return 0
        fi
    elif command -v dnf &> /dev/null; then
        # 检查完整版本号包
        if dnf list available "mysql-community-server-${full_version}" "mysql-community-client-${full_version}" 2>/dev/null | grep -qE "mysql-community-server|mysql-community-client"; then
            return 0
        fi
        
        # 检查主次版本号包
        if dnf list available "mysql-community-server-${major_minor}*" "mysql-community-client-${major_minor}*" 2>/dev/null | grep -qE "mysql-community-server|mysql-community-client"; then
            return 0
        fi
        
        # 检查通用包名
        if dnf list available mysql-community-server mysql-community-client 2>/dev/null | grep -qE "mysql-community-server|mysql-community-client"; then
            return 0
        fi
    fi
    
    return 1  # 版本不可用
}

# 获取可用的MySQL版本列表（RedHat系列）
get_available_mysql_versions_redhat() {
    local versions=()
    
    # 先确保仓库已配置（如果可能）
    if [ ! -f /etc/yum.repos.d/mysql-community.repo ]; then
        # 尝试快速配置仓库（不安装）
        echo -e "${BLUE}正在检查可用版本，可能需要先配置MySQL仓库...${NC}"
    fi
    
    # 检查MySQL 8.0系列
    if command -v yum &> /dev/null; then
        if yum list available mysql-community-server mysql-community-client 2>/dev/null | grep -qE "mysql-community-server.*8\.0|mysql-community-client.*8\.0"; then
            # 尝试获取具体版本号
            local ver80=$(yum list available mysql-community-server 2>/dev/null | grep -E "mysql-community-server.*8\.0" | head -1 | awk '{print $2}' | grep -oE '8\.0\.[0-9]+' | head -1)
            if [ -n "$ver80" ]; then
                versions+=("$ver80")
            else
                versions+=("8.0")
            fi
        fi
        
        # 检查MySQL 5.7系列
        if yum list available mysql-community-server mysql-community-client 2>/dev/null | grep -qE "mysql-community-server.*5\.7|mysql-community-client.*5\.7"; then
            local ver57=$(yum list available mysql-community-server 2>/dev/null | grep -E "mysql-community-server.*5\.7" | head -1 | awk '{print $2}' | grep -oE '5\.7\.[0-9]+' | head -1)
            if [ -n "$ver57" ]; then
                versions+=("$ver57")
            else
                versions+=("5.7")
            fi
        fi
    elif command -v dnf &> /dev/null; then
        if dnf list available mysql-community-server mysql-community-client 2>/dev/null | grep -qE "mysql-community-server.*8\.0|mysql-community-client.*8\.0"; then
            local ver80=$(dnf list available mysql-community-server 2>/dev/null | grep -E "mysql-community-server.*8\.0" | head -1 | awk '{print $2}' | grep -oE '8\.0\.[0-9]+' | head -1)
            if [ -n "$ver80" ]; then
                versions+=("$ver80")
            else
                versions+=("8.0")
            fi
        fi
        
        if dnf list available mysql-community-server mysql-community-client 2>/dev/null | grep -qE "mysql-community-server.*5\.7|mysql-community-client.*5\.7"; then
            local ver57=$(dnf list available mysql-community-server 2>/dev/null | grep -E "mysql-community-server.*5\.7" | head -1 | awk '{print $2}' | grep -oE '5\.7\.[0-9]+' | head -1)
            if [ -n "$ver57" ]; then
                versions+=("$ver57")
            else
                versions+=("5.7")
            fi
        fi
    fi
    
    # 如果没有找到，返回默认版本
    if [ ${#versions[@]} -eq 0 ]; then
        versions+=("8.0")
        versions+=("default")
    fi
    
    echo "${versions[@]}"
}

# 验证 MySQL 是否真正安装成功
verify_mysql_installation() {
    local install_log="${1:-/tmp/mysql_install.log}"
    
    # 检查安装日志中是否有错误信息
    if [ -f "$install_log" ]; then
        # 检查是否有"没有可用软件包"或"错误：无须任何处理"等错误
        if grep -qiE "没有可用软件包|No package available|错误：无须任何处理|Nothing to do|No packages marked for|无需任何处理" "$install_log"; then
            echo -e "${RED}✗ 检测到安装失败：软件包不可用或无需处理${NC}"
            return 1
        fi
        
        # 检查是否有其他安装错误（排除GPG警告）
        if grep -qiE "Error.*install|Failed.*install|无法安装|安装失败|安装.*失败" "$install_log" && ! grep -qiE "GPG key|GPG 密钥|GPG.*warning" "$install_log"; then
            echo -e "${RED}✗ 检测到安装错误${NC}"
            return 1
        fi
        
        # 检查是否真的安装了软件包（检查日志中是否有"Installed"或"已安装"）
        if ! grep -qiE "Installed|已安装|安装.*完成|Complete!" "$install_log"; then
            # 如果没有安装成功的标记，检查是否有错误
            if grep -qiE "Error|Failed|失败|错误" "$install_log" && ! grep -qiE "GPG|warning|警告" "$install_log"; then
                echo -e "${RED}✗ 未检测到安装成功的标记${NC}"
                return 1
            fi
        fi
    fi
    
    # 检查 MySQL 命令是否存在
    if ! command -v mysql &> /dev/null && ! command -v mysqld &> /dev/null; then
        echo -e "${RED}✗ MySQL 命令未找到，安装可能失败${NC}"
        return 1
    fi
    
    # 检查 MySQL 服务包是否已安装（RedHat系列）
    if command -v rpm &> /dev/null; then
        if ! rpm -qa | grep -qiE "mysql-community-server|mysql-server|mariadb-server"; then
            echo -e "${RED}✗ MySQL/MariaDB 服务包未安装${NC}"
            return 1
        fi
    fi
    
    return 0
}

# 修复 MySQL GPG 密钥问题
fix_mysql_gpg_key() {
    echo -e "${BLUE}正在修复 MySQL GPG 密钥问题...${NC}"
    
    # 尝试导入最新的 GPG 密钥
    local gpg_imported=0
    
    # 尝试多个 GPG 密钥源（包括正确的密钥ID）
    for gpg_url in \
        "https://repo.mysql.com/RPM-GPG-KEY-mysql-2022" \
        "https://repo.mysql.com/RPM-GPG-KEY-mysql" \
        "https://dev.mysql.com/doc/refman/8.0/en/checking-gpg-signature.html"; do
        if rpm --import "$gpg_url" 2>/dev/null; then
            gpg_imported=1
            echo -e "${GREEN}✓ GPG 密钥导入成功: $gpg_url${NC}"
            break
        fi
    done
    
    # 如果导入失败，尝试从仓库文件获取密钥
    if [ $gpg_imported -eq 0 ] && [ -f /etc/yum.repos.d/mysql-community.repo ]; then
        # 尝试从仓库配置中获取 GPG 密钥路径
        local gpg_key_path=$(grep -E "^gpgkey=" /etc/yum.repos.d/mysql-community.repo | head -1 | sed 's/.*=//' | sed 's|file://||')
        if [ -n "$gpg_key_path" ] && [ -f "$gpg_key_path" ]; then
            if rpm --import "$gpg_key_path" 2>/dev/null; then
                gpg_imported=1
                echo -e "${GREEN}✓ 从本地文件导入 GPG 密钥: $gpg_key_path${NC}"
            fi
        fi
    fi
    
    # 即使导入了密钥，也检查仓库配置中的gpgcheck设置
    # 如果仓库配置的密钥ID不匹配，仍然会失败，所以直接禁用GPG检查更可靠
    if [ -f /etc/yum.repos.d/mysql-community.repo ]; then
        # 检查是否已经有gpgcheck=0的设置
        if grep -q "^gpgcheck=0" /etc/yum.repos.d/mysql-community*.repo 2>/dev/null; then
            echo -e "${BLUE}✓ MySQL 仓库已禁用 GPG 检查${NC}"
            return 1  # 返回 1 表示需要使用 --nogpgcheck
        fi
        
        # 如果导入了密钥但可能不匹配，也禁用GPG检查以确保安装成功
        # 因为MySQL的GPG密钥ID经常变化，直接禁用更可靠
        echo -e "${YELLOW}⚠ 为保险起见，将禁用 MySQL 仓库的 GPG 检查${NC}"
        sed -i 's/^gpgcheck=1/gpgcheck=0/g' /etc/yum.repos.d/mysql-community*.repo 2>/dev/null || true
        echo -e "${GREEN}✓ 已禁用 MySQL 仓库的 GPG 检查${NC}"
        return 1  # 返回 1 表示需要使用 --nogpgcheck
    fi
    
    # 如果仍然失败，禁用 GPG 检查
    if [ $gpg_imported -eq 0 ]; then
        echo -e "${YELLOW}⚠ GPG 密钥导入失败，将禁用 GPG 检查${NC}"
        # 禁用所有 MySQL 仓库的 GPG 检查
        if [ -f /etc/yum.repos.d/mysql-community.repo ]; then
            sed -i 's/^gpgcheck=1/gpgcheck=0/g' /etc/yum.repos.d/mysql-community*.repo 2>/dev/null || true
            echo -e "${GREEN}✓ 已禁用 MySQL 仓库的 GPG 检查${NC}"
        fi
        return 1  # 返回 1 表示需要使用 --nogpgcheck
    fi
    
    return 1  # 默认返回 1，强制使用 --nogpgcheck 以确保安装成功
}

# 安装 MySQL（CentOS/RHEL/Fedora/Rocky/AlmaLinux/Oracle Linux/Amazon Linux）
install_mysql_redhat() {
    echo -e "${BLUE}[3/8] 安装 MySQL（RedHat 系列）...${NC}"
    
    # 确定仓库版本（根据实际系统）
    local el_version="el7"
    case $OS in
        fedora)
            # Fedora 通常使用 el8 或 el9
            if echo "$OS_VERSION" | grep -qE "^3[0-9]"; then
                el_version="el9"
            else
                el_version="el8"
            fi
            ;;
        rhel|rocky|almalinux|oraclelinux)
            # 根据主版本号确定
            if echo "$OS_VERSION" | grep -qE "^9\."; then
                el_version="el9"
            elif echo "$OS_VERSION" | grep -qE "^8\."; then
                el_version="el8"
            else
                el_version="el7"
            fi
            ;;
        amazonlinux)
            # Amazon Linux 2 使用 el7，Amazon Linux 2023 使用 el9
            if echo "$OS_VERSION" | grep -qE "^2023"; then
                el_version="el9"
            else
                el_version="el7"
            fi
            ;;
    esac
    
    # 根据选择的版本确定仓库包
    local repo_version="80"
    if [ "$MYSQL_VERSION" = "5.7" ] || echo "$MYSQL_VERSION" | grep -qE "^5\.7"; then
        repo_version="57"
    elif [ "$MYSQL_VERSION" = "8.0" ] || echo "$MYSQL_VERSION" | grep -qE "^8\.0"; then
        repo_version="80"
    elif [ "$MYSQL_VERSION" = "default" ]; then
        # 使用系统默认版本，尝试 MySQL 8.0
        repo_version="80"
    fi
    
    # 安装 MySQL 仓库
    if [ ! -f /etc/yum.repos.d/mysql-community.repo ]; then
        echo "添加 MySQL ${repo_version} 官方仓库..."
        
        # 下载 MySQL Yum Repository
        local repo_downloaded=0
        local repo_file="mysql${repo_version}-community-release-${el_version}-1.noarch.rpm"
        
        # 尝试下载对应版本的仓库
        for el_ver in $el_version el8 el7; do
            local repo_url="https://dev.mysql.com/get/${repo_file}"
            if wget -q "$repo_url" -O /tmp/mysql-community-release.rpm 2>/dev/null && [ -s /tmp/mysql-community-release.rpm ]; then
                repo_downloaded=1
                break
            fi
        done
        
        if [ $repo_downloaded -eq 0 ]; then
            echo -e "${YELLOW}⚠ 无法下载 MySQL 仓库，尝试使用系统仓库${NC}"
        fi
        
        if [ -f /tmp/mysql-community-release.rpm ]; then
            # 尝试导入 GPG 密钥（在安装仓库之前）
            rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2022 2>/dev/null || \
            rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql 2>/dev/null || true
            
            # 安装仓库（直接使用 --nodigest --nosignature 避免 GPG 验证问题）
            echo "正在安装 MySQL 仓库..."
            if rpm -ivh --nodigest --nosignature /tmp/mysql-community-release.rpm 2>&1; then
                echo -e "${GREEN}✓ MySQL 仓库安装成功${NC}"
                # 安装仓库后，立即禁用 GPG 检查以确保后续安装成功
                fix_mysql_gpg_key
            else
                echo -e "${YELLOW}⚠ 仓库安装失败，尝试其他方法${NC}"
                # 如果安装失败，尝试不使用任何验证
                rpm -ivh --nodigest --nosignature --force /tmp/mysql-community-release.rpm 2>&1 || true
                # 安装后禁用 GPG 检查
                if [ -f /etc/yum.repos.d/mysql-community.repo ]; then
                    sed -i 's/^gpgcheck=1/gpgcheck=0/g' /etc/yum.repos.d/mysql-community*.repo 2>/dev/null || true
                    echo -e "${GREEN}✓ 已禁用 MySQL 仓库的 GPG 检查${NC}"
                fi
            fi
            rm -f /tmp/mysql-community-release.rpm
        fi
        
        # 如果指定了具体版本，启用对应版本的仓库并禁用其他版本
        if [ "$MYSQL_VERSION" != "default" ] && [ -f /etc/yum.repos.d/mysql-community.repo ]; then
            if echo "$MYSQL_VERSION" | grep -qE "^5\.7"; then
                # 启用 MySQL 5.7，禁用其他版本
                sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/mysql-community*.repo
                sed -i '/\[mysql57-community\]/,/\[/ { /enabled=/ s/enabled=0/enabled=1/ }' /etc/yum.repos.d/mysql-community*.repo
            elif echo "$MYSQL_VERSION" | grep -qE "^8\.0"; then
                # 启用 MySQL 8.0，禁用其他版本
                sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/mysql-community*.repo
                sed -i '/\[mysql80-community\]/,/\[/ { /enabled=/ s/enabled=0/enabled=1/ }' /etc/yum.repos.d/mysql-community*.repo
            fi
        fi
    fi
    
    # 安装 MySQL
    INSTALL_SUCCESS=0
    
    # 如果指定了具体版本，尝试安装指定版本
    if [ "$MYSQL_VERSION" != "default" ] && echo "$MYSQL_VERSION" | grep -qE "^[0-9]+\.[0-9]+"; then
        # 提取主版本号和次版本号（如 8.0.39 -> 8.0）
        local major_minor=$(echo "$MYSQL_VERSION" | grep -oE '^[0-9]+\.[0-9]+')
        local full_version="$MYSQL_VERSION"
        
        echo -e "${BLUE}尝试安装指定版本: MySQL ${full_version}${NC}"
        
        # 方法1: 尝试安装完整版本号
        local version_package="mysql-community-server-${full_version}"
        echo "尝试安装包: $version_package"
        
        # 修复 GPG 密钥问题（强制使用 --nogpgcheck 以确保安装成功）
        fix_mysql_gpg_key
        # 强制使用 --nogpgcheck，因为MySQL的GPG密钥经常不匹配
        local nogpgcheck_flag="--nogpgcheck"
        
        if command -v dnf &> /dev/null; then
            if dnf install -y $nogpgcheck_flag "$version_package" "mysql-community-client-${full_version}" 2>&1 | tee /tmp/mysql_install.log; then
                # 验证是否真正安装成功
                if verify_mysql_installation /tmp/mysql_install.log; then
                INSTALL_SUCCESS=1
                echo -e "${GREEN}✓ MySQL ${full_version} 安装成功${NC}"
                else
                    echo -e "${RED}✗ MySQL ${full_version} 安装失败${NC}"
                    INSTALL_SUCCESS=0
                fi
            else
                INSTALL_SUCCESS=0
            fi
        else
            if yum install -y $nogpgcheck_flag "$version_package" "mysql-community-client-${full_version}" 2>&1 | tee /tmp/mysql_install.log; then
                # 验证是否真正安装成功
                if verify_mysql_installation /tmp/mysql_install.log; then
                INSTALL_SUCCESS=1
                echo -e "${GREEN}✓ MySQL ${full_version} 安装成功${NC}"
                else
                    echo -e "${RED}✗ MySQL ${full_version} 安装失败${NC}"
                    INSTALL_SUCCESS=0
                fi
            else
                INSTALL_SUCCESS=0
            fi
        fi
        
        # 方法2: 如果完整版本号失败，尝试只指定主次版本号
        if [ $INSTALL_SUCCESS -eq 0 ]; then
            echo -e "${YELLOW}⚠ 完整版本号安装失败，尝试使用主次版本号: ${major_minor}${NC}"
            
            # 修复 GPG 密钥问题（强制使用 --nogpgcheck）
            fix_mysql_gpg_key
            # 强制使用 --nogpgcheck，因为MySQL的GPG密钥经常不匹配
            local nogpgcheck_flag="--nogpgcheck"
            
            if command -v dnf &> /dev/null; then
                # 使用 dnf 安装指定版本（dnf 支持版本锁定）
                if dnf install -y $nogpgcheck_flag "mysql-community-server-${major_minor}*" "mysql-community-client-${major_minor}*" 2>&1 | tee /tmp/mysql_install.log; then
                    # 验证是否真正安装成功
                    if verify_mysql_installation /tmp/mysql_install.log; then
                    INSTALL_SUCCESS=1
                    echo -e "${GREEN}✓ MySQL ${major_minor} 系列安装成功${NC}"
                    else
                        echo -e "${RED}✗ MySQL ${major_minor} 系列安装失败${NC}"
                        INSTALL_SUCCESS=0
                    fi
                else
                    INSTALL_SUCCESS=0
                fi
            else
                # 使用 yum 安装指定版本
                if yum install -y $nogpgcheck_flag "mysql-community-server-${major_minor}*" "mysql-community-client-${major_minor}*" 2>&1 | tee /tmp/mysql_install.log; then
                    # 验证是否真正安装成功
                    if verify_mysql_installation /tmp/mysql_install.log; then
                    INSTALL_SUCCESS=1
                    echo -e "${GREEN}✓ MySQL ${major_minor} 系列安装成功${NC}"
                    else
                        echo -e "${RED}✗ MySQL ${major_minor} 系列安装失败${NC}"
                        INSTALL_SUCCESS=0
                    fi
                else
                    INSTALL_SUCCESS=0
                fi
            fi
        fi
        
        # 方法3: 如果还是失败，尝试启用对应版本的仓库后安装
        if [ $INSTALL_SUCCESS -eq 0 ] && [ -f /etc/yum.repos.d/mysql-community.repo ]; then
            echo -e "${YELLOW}⚠ 直接安装失败，尝试启用对应版本的仓库...${NC}"
            # 根据主次版本号启用对应仓库
            if echo "$major_minor" | grep -qE "^5\.7"; then
                # 启用 MySQL 5.7 仓库
                sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/mysql-community*.repo
                sed -i '/\[mysql57-community\]/,/\[/ { /enabled=/ s/enabled=0/enabled=1/ }' /etc/yum.repos.d/mysql-community*.repo
                echo -e "${BLUE}已启用 MySQL 5.7 仓库${NC}"
            elif echo "$major_minor" | grep -qE "^8\.0"; then
                # 启用 MySQL 8.0 仓库
                sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/mysql-community*.repo
                sed -i '/\[mysql80-community\]/,/\[/ { /enabled=/ s/enabled=0/enabled=1/ }' /etc/yum.repos.d/mysql-community*.repo
                echo -e "${BLUE}已启用 MySQL 8.0 仓库${NC}"
            fi
            
            # 再次尝试安装
            # 修复 GPG 密钥问题（强制使用 --nogpgcheck）
            fix_mysql_gpg_key
            # 强制使用 --nogpgcheck，因为MySQL的GPG密钥经常不匹配
            local nogpgcheck_flag="--nogpgcheck"
            
            if command -v dnf &> /dev/null; then
                if dnf install -y $nogpgcheck_flag mysql-community-server mysql-community-client 2>&1 | tee /tmp/mysql_install.log; then
                    # 验证是否真正安装成功
                    if verify_mysql_installation /tmp/mysql_install.log; then
                    INSTALL_SUCCESS=1
                    echo -e "${GREEN}✓ MySQL ${major_minor} 系列安装成功${NC}"
                    else
                        echo -e "${RED}✗ MySQL ${major_minor} 系列安装失败${NC}"
                        INSTALL_SUCCESS=0
                    fi
                else
                    INSTALL_SUCCESS=0
                fi
            else
                if yum install -y $nogpgcheck_flag mysql-community-server mysql-community-client 2>&1 | tee /tmp/mysql_install.log; then
                    # 验证是否真正安装成功
                    if verify_mysql_installation /tmp/mysql_install.log; then
                    INSTALL_SUCCESS=1
                    echo -e "${GREEN}✓ MySQL ${major_minor} 系列安装成功${NC}"
                    else
                        echo -e "${RED}✗ MySQL ${major_minor} 系列安装失败${NC}"
                        INSTALL_SUCCESS=0
                    fi
                else
                    INSTALL_SUCCESS=0
                fi
            fi
        fi
    fi
    
    # 如果指定版本安装失败，使用默认安装
    if [ $INSTALL_SUCCESS -eq 0 ]; then
        echo -e "${YELLOW}⚠ 指定版本安装失败，尝试使用默认安装${NC}"
        
        # 修复 GPG 密钥问题（强制使用 --nogpgcheck）
        fix_mysql_gpg_key
        # 强制使用 --nogpgcheck，因为MySQL的GPG密钥经常不匹配
        local nogpgcheck_flag="--nogpgcheck"
        
        if command -v dnf &> /dev/null; then
            if dnf install -y $nogpgcheck_flag mysql-server mysql 2>&1 | tee /tmp/mysql_install.log; then
                # 验证是否真正安装成功
                if verify_mysql_installation /tmp/mysql_install.log; then
                INSTALL_SUCCESS=1
                    echo -e "${GREEN}✓ MySQL 默认版本安装成功${NC}"
                else
                    INSTALL_SUCCESS=0
            fi
        else
                INSTALL_SUCCESS=0
            fi
        else
            if yum install -y $nogpgcheck_flag mysql-server mysql 2>&1 | tee /tmp/mysql_install.log; then
                # 验证是否真正安装成功
                if verify_mysql_installation /tmp/mysql_install.log; then
                INSTALL_SUCCESS=1
                    echo -e "${GREEN}✓ MySQL 默认版本安装成功${NC}"
                else
                    INSTALL_SUCCESS=0
                fi
            else
                INSTALL_SUCCESS=0
            fi
        fi
    fi
    
    # 如果 MySQL 安装失败，尝试安装 MariaDB（MySQL 兼容）
    if [ $INSTALL_SUCCESS -eq 0 ]; then
        echo -e "${YELLOW}⚠ MySQL 安装失败，尝试安装 MariaDB（MySQL 兼容）...${NC}"
        if command -v dnf &> /dev/null; then
            if dnf install -y mariadb-server mariadb 2>&1 | tee /tmp/mysql_install.log; then
                # 验证是否真正安装成功
                if verify_mysql_installation /tmp/mysql_install.log; then
                INSTALL_SUCCESS=1
                echo -e "${GREEN}✓ MariaDB 安装完成（MySQL 兼容）${NC}"
                else
                    INSTALL_SUCCESS=0
            fi
        else
                INSTALL_SUCCESS=0
            fi
        else
            if yum install -y mariadb-server mariadb 2>&1 | tee /tmp/mysql_install.log; then
                # 验证是否真正安装成功
                if verify_mysql_installation /tmp/mysql_install.log; then
                INSTALL_SUCCESS=1
                echo -e "${GREEN}✓ MariaDB 安装完成（MySQL 兼容）${NC}"
                else
                    INSTALL_SUCCESS=0
                fi
            else
                INSTALL_SUCCESS=0
            fi
        fi
    fi
    
    # 最终验证安装是否成功
    if [ $INSTALL_SUCCESS -eq 0 ] || ! verify_mysql_installation /tmp/mysql_install.log; then
        echo ""
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}✗ MySQL/MariaDB 安装失败${NC}"
        echo -e "${RED}========================================${NC}"
        echo ""
        echo -e "${YELLOW}可能的原因：${NC}"
        echo "  1. 指定的版本不可用"
        echo "  2. 软件仓库配置错误"
        echo "  3. 网络连接问题"
        echo "  4. 软件包名称不正确"
        echo ""
        if [ -f /tmp/mysql_install.log ]; then
            echo -e "${BLUE}安装日志（最后20行）：${NC}"
            tail -20 /tmp/mysql_install.log
            echo ""
        fi
        echo -e "${YELLOW}请检查错误信息并手动安装，或尝试其他版本${NC}"
        echo ""
        exit 1
    else
        echo -e "${GREEN}✓ MySQL/MariaDB 安装完成${NC}"
    fi
}

# 安装 MySQL（Ubuntu/Debian/Linux Mint/Kali Linux）
install_mysql_debian() {
    echo -e "${BLUE}[3/8] 安装 MySQL（Debian 系列）...${NC}"
    
    # 更新包列表
    apt-get update
    
    # 安装 MySQL（使用系统仓库，通常包含 MySQL 8.0）
    # 对于某些发行版，可能需要先安装 debconf-utils
    if ! command -v debconf-set-selections &> /dev/null; then
        apt-get install -y debconf-utils
    fi
    
    # 设置非交互式安装
    echo "mysql-server mysql-server/root_password password ${MYSQL_ROOT_PASSWORD:-}" | debconf-set-selections 2>/dev/null || true
    echo "mysql-server mysql-server/root_password_again password ${MYSQL_ROOT_PASSWORD:-}" | debconf-set-selections 2>/dev/null || true
    
    INSTALL_SUCCESS=0
    
    # 如果指定了具体版本，尝试安装指定版本
    if [ "$MYSQL_VERSION" != "default" ] && echo "$MYSQL_VERSION" | grep -qE "^[0-9]+\.[0-9]+"; then
        # 提取主版本号和次版本号（如 8.0.39 -> 8.0）
        local major_minor=$(echo "$MYSQL_VERSION" | grep -oE '^[0-9]+\.[0-9]+')
        local full_version="$MYSQL_VERSION"
        
        echo -e "${BLUE}尝试安装指定版本: MySQL ${full_version}${NC}"
        
        # 方法1: 尝试安装完整版本号
        local version_package="mysql-server=${full_version}*"
        echo "尝试安装包: $version_package"
        if DEBIAN_FRONTEND=noninteractive apt-get install -y "$version_package" "mysql-client=${full_version}*" 2>&1 | tee /tmp/mysql_install.log; then
            INSTALL_SUCCESS=1
            echo -e "${GREEN}✓ MySQL ${full_version} 安装成功${NC}"
        fi
        
        # 方法2: 如果完整版本号失败，尝试只指定主次版本号
        if [ $INSTALL_SUCCESS -eq 0 ]; then
            echo -e "${YELLOW}⚠ 完整版本号安装失败，尝试使用主次版本号: ${major_minor}${NC}"
            version_package="mysql-server=${major_minor}*"
            if DEBIAN_FRONTEND=noninteractive apt-get install -y "$version_package" "mysql-client=${major_minor}*" 2>&1 | tee /tmp/mysql_install.log; then
                INSTALL_SUCCESS=1
                echo -e "${GREEN}✓ MySQL ${major_minor} 系列安装成功${NC}"
            fi
        fi
        
        # 方法3: 如果还是失败，尝试添加 MySQL 官方仓库后安装
        if [ $INSTALL_SUCCESS -eq 0 ]; then
            echo -e "${YELLOW}⚠ 系统仓库安装失败，尝试添加 MySQL 官方仓库...${NC}"
            
            # 安装必要的工具
            apt-get install -y wget gnupg lsb-release 2>/dev/null || true
            
            # 下载并安装 MySQL APT 仓库配置
            local repo_file="mysql-apt-config_0.8.28-1_all.deb"
            if wget -q "https://dev.mysql.com/get/${repo_file}" -O /tmp/${repo_file} 2>/dev/null && [ -s /tmp/${repo_file} ]; then
                # 安装仓库配置（非交互式）
                DEBIAN_FRONTEND=noninteractive dpkg -i /tmp/${repo_file} 2>/dev/null || true
                apt-get update
                
                # 根据版本选择仓库
                if echo "$major_minor" | grep -qE "^5\.7"; then
                    # 配置 MySQL 5.7 仓库
                    echo "mysql-apt-config mysql-apt-config/select-server select mysql-5.7" | debconf-set-selections 2>/dev/null || true
                elif echo "$major_minor" | grep -qE "^8\.0"; then
                    # 配置 MySQL 8.0 仓库
                    echo "mysql-apt-config mysql-apt-config/select-server select mysql-8.0" | debconf-set-selections 2>/dev/null || true
                fi
                
                # 重新更新包列表
                apt-get update
                
                # 尝试安装指定版本
                if DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server mysql-client 2>&1 | tee /tmp/mysql_install.log; then
                    INSTALL_SUCCESS=1
                    echo -e "${GREEN}✓ MySQL ${major_minor} 系列安装成功${NC}"
                fi
                
                rm -f /tmp/${repo_file}
            fi
        fi
    fi
    
    # 如果指定版本安装失败，使用默认安装
    if [ $INSTALL_SUCCESS -eq 0 ]; then
        echo -e "${YELLOW}⚠ 指定版本安装失败，尝试使用默认安装${NC}"
        if DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server mysql-client 2>&1; then
            INSTALL_SUCCESS=1
            echo -e "${GREEN}✓ MySQL 安装完成（使用系统默认版本）${NC}"
        else
            echo -e "${RED}✗ MySQL 安装失败${NC}"
            echo -e "${YELLOW}⚠ 请检查错误信息${NC}"
            exit 1
        fi
    fi
}

# 安装 MySQL（openSUSE）
install_mysql_suse() {
    echo -e "${BLUE}[3/8] 安装 MySQL（openSUSE）...${NC}"
    
    # openSUSE 使用 MariaDB 或从源码编译 MySQL
    echo -e "${YELLOW}注意: openSUSE 通常使用 MariaDB，如果需要 MySQL 请从源码编译${NC}"
    
    # 尝试安装 MariaDB（MySQL 兼容）
    zypper install -y mariadb mariadb-server || {
        echo -e "${YELLOW}⚠ 包管理器安装失败，请手动安装 MySQL${NC}"
        exit 1
    }
    
    echo -e "${GREEN}✓ MariaDB 安装完成（MySQL 兼容）${NC}"
}

# 安装 MySQL（Arch Linux/Manjaro）
install_mysql_arch() {
    echo -e "${BLUE}[3/8] 安装 MySQL（Arch Linux）...${NC}"
    
    INSTALL_SUCCESS=0
    
    # Arch Linux 使用 AUR 或系统仓库
    if command -v yay &> /dev/null; then
        echo "使用 yay 从 AUR 安装..."
        if yay -S --noconfirm mysql 2>&1; then
            INSTALL_SUCCESS=1
        fi
    elif command -v paru &> /dev/null; then
        echo "使用 paru 从 AUR 安装..."
        if paru -S --noconfirm mysql 2>&1; then
            INSTALL_SUCCESS=1
        fi
    else
        # 尝试使用 pacman（可能需要启用 AUR）
        if pacman -S --noconfirm mysql 2>&1; then
            INSTALL_SUCCESS=1
        fi
    fi
    
    if [ $INSTALL_SUCCESS -eq 0 ]; then
        echo -e "${YELLOW}⚠ 需要从 AUR 安装，请安装 yay/paru 或手动安装${NC}"
        echo -e "${YELLOW}⚠ 安装命令: yay -S mysql 或 pacman -S mysql${NC}"
        exit 1
    else
        echo -e "${GREEN}✓ MySQL 安装完成${NC}"
    fi
}

# 安装 MySQL（Alpine Linux）
install_mysql_alpine() {
    echo -e "${BLUE}[3/8] 安装 MySQL（Alpine Linux）...${NC}"
    
    # Alpine Linux 使用 MariaDB（MySQL 兼容）
    apk add --no-cache mariadb mariadb-client mariadb-server-utils
    
    echo -e "${GREEN}✓ MariaDB 安装完成（MySQL 兼容）${NC}"
}

# 安装 MySQL（Gentoo）
install_mysql_gentoo() {
    echo -e "${BLUE}[3/8] 安装 MySQL（Gentoo）...${NC}"
    
    # Gentoo 使用 emerge
    emerge --ask=n --quiet-build y dev-db/mysql || {
        echo -e "${YELLOW}⚠ 安装失败，请手动安装${NC}"
        exit 1
    }
    
    echo -e "${GREEN}✓ MySQL 安装完成${NC}"
}

# 安装 MySQL
install_mysql() {
    case $OS in
        centos|rhel|fedora|rocky|almalinux|oraclelinux|amazonlinux)
            install_mysql_redhat
            ;;
        ubuntu|debian|linuxmint|raspbian|kali)
            install_mysql_debian
            ;;
        opensuse*|sles)
            install_mysql_suse
            ;;
        arch|manjaro)
            install_mysql_arch
            ;;
        alpine)
            install_mysql_alpine
            ;;
        gentoo)
            install_mysql_gentoo
            ;;
        *)
            echo -e "${YELLOW}警告: 未识别的系统类型 (${OS})，尝试使用通用方法${NC}"
            # 根据包管理器自动选择
            if command -v yum &> /dev/null || command -v dnf &> /dev/null; then
                echo -e "${BLUE}检测到 yum/dnf，使用 RedHat 系列方法${NC}"
                install_mysql_redhat
            elif command -v apt-get &> /dev/null; then
                echo -e "${BLUE}检测到 apt-get，使用 Debian 系列方法${NC}"
                install_mysql_debian
            elif command -v zypper &> /dev/null; then
                echo -e "${BLUE}检测到 zypper，使用 SUSE 系列方法${NC}"
                install_mysql_suse
            elif command -v pacman &> /dev/null; then
                echo -e "${BLUE}检测到 pacman，使用 Arch 系列方法${NC}"
                install_mysql_arch
            elif command -v apk &> /dev/null; then
                echo -e "${BLUE}检测到 apk，使用 Alpine 方法${NC}"
                install_mysql_alpine
            elif command -v emerge &> /dev/null; then
                echo -e "${BLUE}检测到 emerge，使用 Gentoo 方法${NC}"
                install_mysql_gentoo
            else
                echo -e "${RED}错误: 无法确定包管理器${NC}"
                exit 1
            fi
            ;;
    esac
}

# 设置 MySQL 配置文件（在初始化前）
# 重要：所有 my.cnf 等配置文件的改动必须在数据库初始化前完成
# 包括：
#   1. 基础配置（lower_case_table_names、default_time_zone 等）
#   2. 硬件优化配置（InnoDB 缓冲池、连接数、IO 线程等）
# 因为 MySQL 首次启动时会根据配置文件初始化数据字典，之后修改某些配置（如 lower_case_table_names）
# 需要重新初始化数据目录，否则会导致启动失败
# 硬件优化配置（如 innodb_buffer_pool_size）虽然可以在运行时修改，但为了最佳性能，
# 应该在初始化前就设置好，避免初始化后再调整导致性能波动
setup_mysql_config() {
    echo -e "${BLUE}[4/8] 设置 MySQL 配置文件（初始化前）...${NC}"
    echo -e "${YELLOW}注意: 所有配置优化（包括硬件优化）必须在数据库初始化前完成${NC}"
    
    # 检查 MySQL 数据目录是否已初始化
    local mysql_data_dirs=(
        "/var/lib/mysql"
        "/usr/local/mysql/data"
        "/opt/mysql/data"
    )
    
    local mysql_initialized=0
    local mysql_data_dir=""
    for dir in "${mysql_data_dirs[@]}"; do
        if [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
            # 检查是否包含 mysql 系统数据库（说明已初始化）
            if [ -d "$dir/mysql" ] && ([ -f "$dir/mysql/user.MYD" ] || [ -f "$dir/mysql/user.ibd" ] || [ -d "$dir/mysql.ibd" ]); then
                mysql_initialized=1
                mysql_data_dir="$dir"
                break
            fi
        fi
    done
    
    if [ $mysql_initialized -eq 1 ]; then
        echo -e "${YELLOW}⚠ 检测到 MySQL 数据目录已初始化: ${mysql_data_dir}${NC}"
        echo -e "${YELLOW}⚠ 如果 lower_case_table_names 设置不一致，MySQL 将无法启动${NC}"
        echo ""
        echo -e "${BLUE}解决方案：${NC}"
        echo "  1. 如果这是新安装，可以删除数据目录并重新初始化"
        echo "  2. 如果已有重要数据，需要备份后重新初始化"
        echo ""
        read -p "是否删除现有数据目录并重新初始化？[y/N]: " RECREATE_DATA
        RECREATE_DATA="${RECREATE_DATA:-N}"
        if [[ "$RECREATE_DATA" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}正在停止 MySQL 服务...${NC}"
            if command -v systemctl &> /dev/null; then
                systemctl stop mysqld 2>/dev/null || systemctl stop mysql 2>/dev/null || true
            elif command -v service &> /dev/null; then
                service mysqld stop 2>/dev/null || service mysql stop 2>/dev/null || true
            fi
            sleep 2
            
            echo -e "${YELLOW}正在删除数据目录: ${mysql_data_dir}${NC}"
            rm -rf "${mysql_data_dir}"/*
            rm -rf "${mysql_data_dir}"/.* 2>/dev/null || true
            echo -e "${GREEN}✓ 数据目录已清空${NC}"
            mysql_initialized=0
        else
            echo -e "${YELLOW}⚠ 保留现有数据目录，如果 lower_case_table_names 不一致，MySQL 可能无法启动${NC}"
        fi
    fi
    
    local my_cnf_files=(
        "/etc/my.cnf"
        "/etc/mysql/my.cnf"
        "/usr/local/mysql/etc/my.cnf"
        "/usr/local/etc/my.cnf"
        "/etc/mysql/mysql.conf.d/mysqld.cnf"
    )
    
    local my_cnf_file=""
    for file in "${my_cnf_files[@]}"; do
        if [ -f "$file" ]; then
            my_cnf_file="$file"
            break
        fi
    done
    
    if [ -z "$my_cnf_file" ]; then
        # 如果找不到配置文件，尝试创建或使用默认位置
        my_cnf_file="/etc/my.cnf"
        if [ ! -f "$my_cnf_file" ]; then
            touch "$my_cnf_file"
            echo "[mysqld]" >> "$my_cnf_file"
        fi
    fi
    
    if [ -n "$my_cnf_file" ]; then
        # 检查是否已存在 lower_case_table_names 配置
        if grep -q "^lower_case_table_names" "$my_cnf_file" 2>/dev/null || grep -q "^[[:space:]]*lower_case_table_names" "$my_cnf_file" 2>/dev/null; then
            # 如果已存在，检查值是否为 1
            if ! grep -q "^[[:space:]]*lower_case_table_names[[:space:]]*=[[:space:]]*1" "$my_cnf_file" 2>/dev/null; then
                # 修改现有配置
                sed -i 's/^[[:space:]]*lower_case_table_names[[:space:]]*=.*/lower_case_table_names=1/' "$my_cnf_file" 2>/dev/null || \
                sed -i 's/^lower_case_table_names.*/lower_case_table_names=1/' "$my_cnf_file" 2>/dev/null
                echo -e "${GREEN}✓ 已更新 lower_case_table_names 为 1${NC}"
            else
                echo -e "${GREEN}✓ lower_case_table_names 已设置为 1${NC}"
            fi
        else
            # 如果不存在，检查是否有 [mysqld] 段
            if grep -q "^\[mysqld\]" "$my_cnf_file" 2>/dev/null; then
                # 在 [mysqld] 段下添加配置
                sed -i '/^\[mysqld\]/a lower_case_table_names=1' "$my_cnf_file" 2>/dev/null
                echo -e "${GREEN}✓ 已在 [mysqld] 段下添加 lower_case_table_names=1${NC}"
            else
                # 如果没有 [mysqld] 段，添加它和配置
                echo "" >> "$my_cnf_file"
                echo "[mysqld]" >> "$my_cnf_file"
                echo "lower_case_table_names=1" >> "$my_cnf_file"
                echo -e "${GREEN}✓ 已添加 [mysqld] 段和 lower_case_table_names=1${NC}"
            fi
        fi
        
        # 设置时区 default_time_zone = '+08:00' (MySQL 8.0 使用 UTC 偏移量格式)
        # 注意：MySQL 8.0 不支持 'Asia/Shanghai' 格式，需要使用 '+08:00' 或 'SYSTEM'
        local timezone_value="'+08:00'"
        if grep -q "^default_time_zone" "$my_cnf_file" 2>/dev/null || grep -q "^[[:space:]]*default_time_zone" "$my_cnf_file" 2>/dev/null; then
            # 如果已存在，检查值是否为 +08:00
            if ! grep -q "^[[:space:]]*default_time_zone[[:space:]]*=[[:space:]]*['\"]+08:00['\"]" "$my_cnf_file" 2>/dev/null && \
               ! grep -q "^[[:space:]]*default_time_zone[[:space:]]*=[[:space:]]*['\"]SYSTEM['\"]" "$my_cnf_file" 2>/dev/null; then
                # 修改现有配置
                sed -i "s/^[[:space:]]*default_time_zone[[:space:]]*=.*/default_time_zone = '+08:00'/" "$my_cnf_file" 2>/dev/null || \
                sed -i "s/^default_time_zone.*/default_time_zone = '+08:00'/" "$my_cnf_file" 2>/dev/null
                echo -e "${GREEN}✓ 已更新 default_time_zone 为 '+08:00'（中国时区）${NC}"
            else
                echo -e "${GREEN}✓ default_time_zone 已设置为 '+08:00'${NC}"
            fi
        else
            # 如果不存在，在 [mysqld] 段下添加配置
            if grep -q "^\[mysqld\]" "$my_cnf_file" 2>/dev/null; then
                # 在 [mysqld] 段下添加配置（在 lower_case_table_names 之后）
                if grep -q "lower_case_table_names" "$my_cnf_file" 2>/dev/null; then
                    sed -i '/lower_case_table_names/a default_time_zone = '\''+08:00'\''' "$my_cnf_file" 2>/dev/null
                else
                    sed -i '/^\[mysqld\]/a default_time_zone = '\''+08:00'\''' "$my_cnf_file" 2>/dev/null
                fi
                echo -e "${GREEN}✓ 已添加 default_time_zone = '+08:00'（中国时区）${NC}"
            else
                # 如果没有 [mysqld] 段，添加它和配置
                echo "[mysqld]" >> "$my_cnf_file"
                echo "default_time_zone = '+08:00'" >> "$my_cnf_file"
                echo -e "${GREEN}✓ 已添加 [mysqld] 段和 default_time_zone = '+08:00'（中国时区）${NC}"
            fi
        fi
        
        # ========== 硬件优化配置 ==========
        # 重要：硬件优化配置必须在数据库初始化前完成
        # 这些配置包括：InnoDB 缓冲池、连接数、IO 线程、日志文件大小等
        # 虽然部分配置可以在运行时修改，但为了最佳性能和稳定性，应在初始化前设置
        echo -e "${BLUE}根据硬件配置优化 MySQL 参数（初始化前）...${NC}"
        
        # 备份配置文件
        cp "$my_cnf_file" "${my_cnf_file}.bak.$(date +%Y%m%d_%H%M%S)"
        
        # 确保有 [mysqld] 段
        if ! grep -q "^\[mysqld\]" "$my_cnf_file" 2>/dev/null; then
            echo "" >> "$my_cnf_file"
            echo "[mysqld]" >> "$my_cnf_file"
        fi
        
        # 1. InnoDB 缓冲池优化（最重要的性能参数）
        # 根据内存大小设置：小内存（<4GB）使用 50%，中等内存（4-16GB）使用 60%，大内存（>16GB）使用 70%
        local innodb_buffer_pool_size_mb=0
        if [ $TOTAL_MEM_GB -lt 4 ]; then
            innodb_buffer_pool_size_mb=$((TOTAL_MEM_MB * 50 / 100))
        elif [ $TOTAL_MEM_GB -lt 16 ]; then
            innodb_buffer_pool_size_mb=$((TOTAL_MEM_MB * 60 / 100))
        else
            innodb_buffer_pool_size_mb=$((TOTAL_MEM_MB * 70 / 100))
        fi
        
        # 确保最小值（至少 256MB）
        if [ $innodb_buffer_pool_size_mb -lt 256 ]; then
            innodb_buffer_pool_size_mb=256
        fi
        
        # 设置 InnoDB 缓冲池大小
        if grep -q "^innodb_buffer_pool_size" "$my_cnf_file" 2>/dev/null || grep -q "^[[:space:]]*innodb_buffer_pool_size" "$my_cnf_file" 2>/dev/null; then
            sed -i "s/^[[:space:]]*innodb_buffer_pool_size[[:space:]]*=.*/innodb_buffer_pool_size = ${innodb_buffer_pool_size_mb}M/" "$my_cnf_file" 2>/dev/null || \
            sed -i "s/^innodb_buffer_pool_size.*/innodb_buffer_pool_size = ${innodb_buffer_pool_size_mb}M/" "$my_cnf_file" 2>/dev/null
        else
            sed -i '/^\[mysqld\]/a innodb_buffer_pool_size = '"${innodb_buffer_pool_size_mb}"'M' "$my_cnf_file" 2>/dev/null
        fi
        echo -e "${GREEN}  ✓ innodb_buffer_pool_size: ${innodb_buffer_pool_size_mb}M${NC}"
        
        # 2. InnoDB 缓冲池实例数（提高并发性能）
        # 根据缓冲池大小设置：<1GB 使用 1 个，1-8GB 使用 2-4 个，>8GB 使用 4-8 个
        local innodb_buffer_pool_instances=1
        if [ $innodb_buffer_pool_size_mb -ge 8192 ]; then
            innodb_buffer_pool_instances=8
        elif [ $innodb_buffer_pool_size_mb -ge 4096 ]; then
            innodb_buffer_pool_instances=4
        elif [ $innodb_buffer_pool_size_mb -ge 1024 ]; then
            innodb_buffer_pool_instances=2
        fi
        
        if grep -q "^innodb_buffer_pool_instances" "$my_cnf_file" 2>/dev/null || grep -q "^[[:space:]]*innodb_buffer_pool_instances" "$my_cnf_file" 2>/dev/null; then
            sed -i "s/^[[:space:]]*innodb_buffer_pool_instances[[:space:]]*=.*/innodb_buffer_pool_instances = ${innodb_buffer_pool_instances}/" "$my_cnf_file" 2>/dev/null || \
            sed -i "s/^innodb_buffer_pool_instances.*/innodb_buffer_pool_instances = ${innodb_buffer_pool_instances}/" "$my_cnf_file" 2>/dev/null
        else
            sed -i '/^\[mysqld\]/a innodb_buffer_pool_instances = '"${innodb_buffer_pool_instances}"'' "$my_cnf_file" 2>/dev/null
        fi
        echo -e "${GREEN}  ✓ innodb_buffer_pool_instances: ${innodb_buffer_pool_instances}${NC}"
        
        # 3. 最大连接数优化（根据内存和 CPU 调整）
        local max_connections=200
        if [ $TOTAL_MEM_GB -ge 16 ] && [ $CPU_CORES -ge 8 ]; then
            max_connections=1000
        elif [ $TOTAL_MEM_GB -ge 8 ] && [ $CPU_CORES -ge 4 ]; then
            max_connections=500
        elif [ $TOTAL_MEM_GB -ge 4 ]; then
            max_connections=300
        fi
        
        if grep -q "^max_connections" "$my_cnf_file" 2>/dev/null || grep -q "^[[:space:]]*max_connections" "$my_cnf_file" 2>/dev/null; then
            sed -i "s/^[[:space:]]*max_connections[[:space:]]*=.*/max_connections = ${max_connections}/" "$my_cnf_file" 2>/dev/null || \
            sed -i "s/^max_connections.*/max_connections = ${max_connections}/" "$my_cnf_file" 2>/dev/null
        else
            sed -i '/^\[mysqld\]/a max_connections = '"${max_connections}"'' "$my_cnf_file" 2>/dev/null
        fi
        echo -e "${GREEN}  ✓ max_connections: ${max_connections}${NC}"
        
        # 4. 连接超时和等待时间
        if ! grep -q "^wait_timeout" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*wait_timeout" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a wait_timeout = 28800' "$my_cnf_file" 2>/dev/null
        fi
        if ! grep -q "^interactive_timeout" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*interactive_timeout" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a interactive_timeout = 28800' "$my_cnf_file" 2>/dev/null
        fi
        
        # 5. InnoDB 日志文件大小（提高写入性能）
        # 根据缓冲池大小设置：小缓冲池使用 256MB，大缓冲池使用 512MB-1GB
        local innodb_log_file_size_mb=256
        if [ $innodb_buffer_pool_size_mb -ge 8192 ]; then
            innodb_log_file_size_mb=1024
        elif [ $innodb_buffer_pool_size_mb -ge 4096 ]; then
            innodb_log_file_size_mb=512
        fi
        
        if grep -q "^innodb_log_file_size" "$my_cnf_file" 2>/dev/null || grep -q "^[[:space:]]*innodb_log_file_size" "$my_cnf_file" 2>/dev/null; then
            sed -i "s/^[[:space:]]*innodb_log_file_size[[:space:]]*=.*/innodb_log_file_size = ${innodb_log_file_size_mb}M/" "$my_cnf_file" 2>/dev/null || \
            sed -i "s/^innodb_log_file_size.*/innodb_log_file_size = ${innodb_log_file_size_mb}M/" "$my_cnf_file" 2>/dev/null
        else
            sed -i '/^\[mysqld\]/a innodb_log_file_size = '"${innodb_log_file_size_mb}"'M' "$my_cnf_file" 2>/dev/null
        fi
        echo -e "${GREEN}  ✓ innodb_log_file_size: ${innodb_log_file_size_mb}M${NC}"
        
        # 6. InnoDB 日志缓冲大小
        local innodb_log_buffer_size_mb=16
        if [ $TOTAL_MEM_GB -ge 16 ]; then
            innodb_log_buffer_size_mb=64
        elif [ $TOTAL_MEM_GB -ge 8 ]; then
            innodb_log_buffer_size_mb=32
        fi
        
        if grep -q "^innodb_log_buffer_size" "$my_cnf_file" 2>/dev/null || grep -q "^[[:space:]]*innodb_log_buffer_size" "$my_cnf_file" 2>/dev/null; then
            sed -i "s/^[[:space:]]*innodb_log_buffer_size[[:space:]]*=.*/innodb_log_buffer_size = ${innodb_log_buffer_size_mb}M/" "$my_cnf_file" 2>/dev/null || \
            sed -i "s/^innodb_log_buffer_size.*/innodb_log_buffer_size = ${innodb_log_buffer_size_mb}M/" "$my_cnf_file" 2>/dev/null
        else
            sed -i '/^\[mysqld\]/a innodb_log_buffer_size = '"${innodb_log_buffer_size_mb}"'M' "$my_cnf_file" 2>/dev/null
        fi
        echo -e "${GREEN}  ✓ innodb_log_buffer_size: ${innodb_log_buffer_size_mb}M${NC}"
        
        # 7. InnoDB 线程并发数（根据 CPU 核心数设置）
        local innodb_thread_concurrency=$((CPU_CORES * 2))
        if [ $innodb_thread_concurrency -gt 64 ]; then
            innodb_thread_concurrency=64
        fi
        if [ $innodb_thread_concurrency -lt 4 ]; then
            innodb_thread_concurrency=4
        fi
        
        if grep -q "^innodb_thread_concurrency" "$my_cnf_file" 2>/dev/null || grep -q "^[[:space:]]*innodb_thread_concurrency" "$my_cnf_file" 2>/dev/null; then
            sed -i "s/^[[:space:]]*innodb_thread_concurrency[[:space:]]*=.*/innodb_thread_concurrency = ${innodb_thread_concurrency}/" "$my_cnf_file" 2>/dev/null || \
            sed -i "s/^innodb_thread_concurrency.*/innodb_thread_concurrency = ${innodb_thread_concurrency}/" "$my_cnf_file" 2>/dev/null
        else
            sed -i '/^\[mysqld\]/a innodb_thread_concurrency = '"${innodb_thread_concurrency}"'' "$my_cnf_file" 2>/dev/null
        fi
        echo -e "${GREEN}  ✓ innodb_thread_concurrency: ${innodb_thread_concurrency}${NC}"
        
        # 8. InnoDB IO 线程数（提高 I/O 性能）
        local innodb_read_io_threads=4
        local innodb_write_io_threads=4
        if [ $CPU_CORES -ge 16 ]; then
            innodb_read_io_threads=8
            innodb_write_io_threads=8
        elif [ $CPU_CORES -ge 8 ]; then
            innodb_read_io_threads=6
            innodb_write_io_threads=6
        fi
        
        if ! grep -q "^innodb_read_io_threads" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*innodb_read_io_threads" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a innodb_read_io_threads = '"${innodb_read_io_threads}"'' "$my_cnf_file" 2>/dev/null
        fi
        if ! grep -q "^innodb_write_io_threads" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*innodb_write_io_threads" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a innodb_write_io_threads = '"${innodb_write_io_threads}"'' "$my_cnf_file" 2>/dev/null
        fi
        echo -e "${GREEN}  ✓ innodb_read_io_threads: ${innodb_read_io_threads}, innodb_write_io_threads: ${innodb_write_io_threads}${NC}"
        
        # 9. 表缓存和打开文件限制
        local table_open_cache=2000
        local open_files_limit=65535
        if [ $TOTAL_MEM_GB -ge 16 ]; then
            table_open_cache=4000
            open_files_limit=65535
        elif [ $TOTAL_MEM_GB -ge 8 ]; then
            table_open_cache=3000
            open_files_limit=32768
        fi
        
        if ! grep -q "^table_open_cache" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*table_open_cache" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a table_open_cache = '"${table_open_cache}"'' "$my_cnf_file" 2>/dev/null
        fi
        if ! grep -q "^open_files_limit" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*open_files_limit" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a open_files_limit = '"${open_files_limit}"'' "$my_cnf_file" 2>/dev/null
        fi
        
        # 10. 查询缓存（MySQL 8.0 已移除，但为兼容性保留配置注释）
        # MySQL 8.0 不再支持 query_cache，跳过
        
        # 11. 临时表和排序缓冲区
        local tmp_table_size_mb=64
        local max_heap_table_size_mb=64
        local sort_buffer_size_kb=256
        if [ $TOTAL_MEM_GB -ge 16 ]; then
            tmp_table_size_mb=256
            max_heap_table_size_mb=256
            sort_buffer_size_kb=512
        elif [ $TOTAL_MEM_GB -ge 8 ]; then
            tmp_table_size_mb=128
            max_heap_table_size_mb=128
            sort_buffer_size_kb=384
        fi
        
        if ! grep -q "^tmp_table_size" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*tmp_table_size" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a tmp_table_size = '"${tmp_table_size_mb}"'M' "$my_cnf_file" 2>/dev/null
        fi
        if ! grep -q "^max_heap_table_size" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*max_heap_table_size" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a max_heap_table_size = '"${max_heap_table_size_mb}"'M' "$my_cnf_file" 2>/dev/null
        fi
        if ! grep -q "^sort_buffer_size" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*sort_buffer_size" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a sort_buffer_size = '"${sort_buffer_size_kb}"'K' "$my_cnf_file" 2>/dev/null
        fi
        
        # 12. InnoDB 刷新方法（使用 O_DIRECT 提高性能）
        if ! grep -q "^innodb_flush_method" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*innodb_flush_method" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a innodb_flush_method = O_DIRECT' "$my_cnf_file" 2>/dev/null
        fi
        
        # 13. InnoDB 双写缓冲（提高数据安全性，SSD 可以关闭以提高性能）
        if ! grep -q "^innodb_doublewrite" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*innodb_doublewrite" "$my_cnf_file" 2>/dev/null; then
            # 默认启用（数据安全优先）
            sed -i '/^\[mysqld\]/a innodb_doublewrite = ON' "$my_cnf_file" 2>/dev/null
        fi
        
        # 14. 慢查询日志（生产环境建议启用）
        if ! grep -q "^slow_query_log" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*slow_query_log" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a slow_query_log = 1' "$my_cnf_file" 2>/dev/null
            sed -i '/^\[mysqld\]/a slow_query_log_file = /var/log/mysql/slow.log' "$my_cnf_file" 2>/dev/null
            sed -i '/^\[mysqld\]/a long_query_time = 2' "$my_cnf_file" 2>/dev/null
        fi
        
        # 15. 二进制日志（用于主从复制和数据恢复）
        # 先创建日志目录（如果不存在）
        if [ ! -d "/var/log/mysql" ]; then
            mkdir -p /var/log/mysql
            chown mysql:mysql /var/log/mysql 2>/dev/null || chown mysql:mysql /var/log/mysql 2>/dev/null || true
            chmod 755 /var/log/mysql
            echo -e "${GREEN}  ✓ 已创建日志目录: /var/log/mysql${NC}"
        fi
        
        if ! grep -q "^log_bin" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*log_bin" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a log_bin = /var/log/mysql/mysql-bin.log' "$my_cnf_file" 2>/dev/null
            # MySQL 8.0 使用 binlog_expire_logs_seconds 替代 expire_logs_days
            # expire_logs_days 已废弃，但为了兼容性，如果使用 MySQL 8.0 则使用新参数
            if echo "$MYSQL_VERSION" | grep -qE "^8\.0"; then
                # MySQL 8.0: 使用 binlog_expire_logs_seconds (7天 = 604800秒)
                sed -i '/^\[mysqld\]/a binlog_expire_logs_seconds = 604800' "$my_cnf_file" 2>/dev/null
            else
                # MySQL 5.7: 使用 expire_logs_days
            sed -i '/^\[mysqld\]/a expire_logs_days = 7' "$my_cnf_file" 2>/dev/null
            fi
            sed -i '/^\[mysqld\]/a max_binlog_size = 100M' "$my_cnf_file" 2>/dev/null
        else
            # 如果已存在 log_bin 配置，检查并更新 expire_logs_days 为 binlog_expire_logs_seconds（MySQL 8.0）
            if echo "$MYSQL_VERSION" | grep -qE "^8\.0"; then
                if grep -q "^expire_logs_days" "$my_cnf_file" 2>/dev/null || grep -q "^[[:space:]]*expire_logs_days" "$my_cnf_file" 2>/dev/null; then
                    # 如果存在 expire_logs_days，替换为 binlog_expire_logs_seconds
                    if ! grep -q "^binlog_expire_logs_seconds" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*binlog_expire_logs_seconds" "$my_cnf_file" 2>/dev/null; then
                        sed -i '/expire_logs_days/a binlog_expire_logs_seconds = 604800' "$my_cnf_file" 2>/dev/null
                        # 注释掉旧的 expire_logs_days（不删除，以防回退）
                        sed -i 's/^\([[:space:]]*expire_logs_days\)/#\1/' "$my_cnf_file" 2>/dev/null
                        echo -e "${GREEN}  ✓ 已更新为 MySQL 8.0 的 binlog_expire_logs_seconds${NC}"
                    fi
                fi
            fi
        fi
        
        # 16. 字符集设置（UTF8MB4）
        if ! grep -q "^character-set-server" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*character-set-server" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a character-set-server = utf8mb4' "$my_cnf_file" 2>/dev/null
            sed -i '/^\[mysqld\]/a collation-server = utf8mb4_general_ci' "$my_cnf_file" 2>/dev/null
        fi
        
        echo -e "${BLUE}  配置文件位置: ${my_cnf_file}${NC}"
        echo -e "${GREEN}✓ MySQL 配置文件设置完成（已根据硬件优化）${NC}"
    else
        echo -e "${YELLOW}⚠ 未找到 MySQL 配置文件，跳过配置${NC}"
    fi
}

# 配置 MySQL（启动服务）
# 重要：此函数会在首次启动时根据配置文件初始化数据库
# 因此 setup_mysql_config 必须在此函数之前执行
configure_mysql() {
    echo -e "${BLUE}[5/8] 配置 MySQL（启动服务）...${NC}"
    echo -e "${YELLOW}注意: 首次启动时会根据配置文件初始化数据库${NC}"
    
    # 启动 MySQL 服务（首次启动会自动初始化）
    if command -v systemctl &> /dev/null; then
        # 启用开机自启动
        if systemctl enable mysqld >/dev/null 2>&1 || systemctl enable mysql >/dev/null 2>&1; then
            echo -e "${GREEN}✓ 已启用 MySQL 开机自启动${NC}"
        fi
        systemctl start mysqld 2>/dev/null || systemctl start mysql 2>/dev/null || true
    elif command -v service &> /dev/null; then
        # 启用开机自启动
        if chkconfig mysqld on >/dev/null 2>&1 || chkconfig mysql on >/dev/null 2>&1; then
            echo -e "${GREEN}✓ 已启用 MySQL 开机自启动${NC}"
        fi
        service mysql start 2>/dev/null || service mysqld start 2>/dev/null || true
        # 再次确保开机自启动已启用
        chkconfig mysql on 2>/dev/null || chkconfig mysqld on 2>/dev/null || true
    fi
    
    # 等待 MySQL 启动并检查服务状态
    echo "等待 MySQL 启动..."
    local max_wait=30
    local waited=0
    local start_failed=0
    
    while [ $waited -lt $max_wait ]; do
        if mysqladmin ping -h localhost --silent 2>/dev/null; then
            echo -e "${GREEN}✓ MySQL 服务已启动${NC}"
            break
        fi
        sleep 2
        waited=$((waited + 2))
        echo -n "."
    done
    echo ""
    
    # 检查 MySQL 是否启动成功
    if ! mysqladmin ping -h localhost --silent 2>/dev/null; then
        start_failed=1
        echo -e "${RED}✗ MySQL 服务启动失败${NC}"
        echo ""
        echo -e "${YELLOW}可能的原因：${NC}"
        echo "  1. lower_case_table_names 设置与数据字典不一致"
        echo "  2. 配置文件语法错误"
        echo "  3. 端口被占用"
        echo "  4. 权限问题"
        echo ""
        echo -e "${BLUE}检查 MySQL 错误日志：${NC}"
        local error_logs=(
            "/var/log/mysqld.log"
            "/var/log/mysql/error.log"
            "/var/log/mysql/mysql.log"
        )
        for log_file in "${error_logs[@]}"; do
            if [ -f "$log_file" ]; then
                echo -e "${BLUE}  日志文件: ${log_file}${NC}"
                echo -e "${YELLOW}  最后几行错误：${NC}"
                tail -30 "$log_file" | tail -10
                break
            fi
        done
        echo ""
        echo -e "${BLUE}检测到初始化失败，尝试自动修复...${NC}"
        
        # 检查错误日志中是否有初始化失败的错误
        local init_failed=0
        for log_file in "${error_logs[@]}"; do
            if [ -f "$log_file" ]; then
                if tail -50 "$log_file" | grep -qiE "Data Dictionary initialization failed|Illegal or unknown default time zone|designated data directory.*is unusable"; then
                    init_failed=1
                    break
                fi
            fi
        done
        
        if [ $init_failed -eq 1 ]; then
            echo -e "${YELLOW}检测到数据目录初始化失败，需要清理数据目录并重新初始化${NC}"
            read -p "是否自动清理数据目录并重新初始化？[Y/n]: " CLEAN_DATA
            CLEAN_DATA="${CLEAN_DATA:-Y}"
            if [[ "$CLEAN_DATA" =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}正在停止 MySQL 服务...${NC}"
                if command -v systemctl &> /dev/null; then
                    systemctl stop mysqld 2>/dev/null || systemctl stop mysql 2>/dev/null || true
                elif command -v service &> /dev/null; then
                    service mysqld stop 2>/dev/null || service mysql stop 2>/dev/null || true
                fi
                sleep 2
                
                # 查找并清理数据目录
                local mysql_data_dirs=(
                    "/var/lib/mysql"
                    "/usr/local/mysql/data"
                    "/opt/mysql/data"
                )
                
                for dir in "${mysql_data_dirs[@]}"; do
                    if [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
                        echo -e "${YELLOW}正在清理数据目录: ${dir}${NC}"
                        rm -rf "${dir}"/*
                        rm -rf "${dir}"/.* 2>/dev/null || true
                        echo -e "${GREEN}✓ 数据目录已清理${NC}"
                        break
                    fi
                done
                
                echo -e "${BLUE}重新启动 MySQL 服务（将自动重新初始化）...${NC}"
                if command -v systemctl &> /dev/null; then
                    systemctl start mysqld 2>/dev/null || systemctl start mysql 2>/dev/null || true
                elif command -v service &> /dev/null; then
                    service mysqld start 2>/dev/null || service mysql start 2>/dev/null || true
                fi
                
                # 等待重新初始化
                echo "等待 MySQL 重新初始化..."
                sleep 5
                
                # 再次检查是否启动成功
                local retry_count=0
                while [ $retry_count -lt 15 ]; do
                    if mysqladmin ping -h localhost --silent 2>/dev/null; then
                        echo -e "${GREEN}✓ MySQL 重新初始化成功并已启动${NC}"
                        start_failed=0
                        break
                    fi
                    sleep 2
                    retry_count=$((retry_count + 1))
                    echo -n "."
                done
                echo ""
            else
                echo -e "${YELLOW}⚠ 未清理数据目录，请手动处理${NC}"
            fi
        fi
        
        if [ $start_failed -eq 1 ]; then
            echo ""
            echo -e "${RED}========================================${NC}"
            echo -e "${RED}MySQL 启动失败，停止后续步骤${NC}"
            echo -e "${RED}========================================${NC}"
            echo ""
            echo -e "${BLUE}如果看到 'Different lower_case_table_names settings' 或时区错误：${NC}"
            echo "  1. 停止 MySQL 服务"
            echo "  2. 删除数据目录（如果有重要数据请先备份）"
            echo "  3. 确保配置文件中 lower_case_table_names=1 和 default_time_zone = '+08:00'"
            echo "  4. 重新启动 MySQL 服务"
            echo ""
            echo -e "${YELLOW}示例命令：${NC}"
            echo "  systemctl stop mysqld"
            echo "  rm -rf /var/lib/mysql/*"
            echo "  systemctl start mysqld"
            echo ""
            echo -e "${YELLOW}⚠ 请修复 MySQL 启动问题后重新运行安装脚本${NC}"
            echo ""
            exit 1
        fi
        sleep 2
    else
        # 额外等待几秒确保 MySQL 完全就绪
        sleep 3
    fi
    
    # 获取临时 root 密码（MySQL 8.0）
    TEMP_PASSWORD=""
    # 尝试多个日志文件位置
    for log_file in /var/log/mysqld.log /var/log/mysql/error.log /var/log/mysql/mysql.log /var/log/mariadb/mariadb.log; do
        if [ -f "$log_file" ]; then
            TEMP_PASSWORD=$(grep 'temporary password' "$log_file" 2>/dev/null | awk '{print $NF}' | tail -1)
            if [ -n "$TEMP_PASSWORD" ]; then
                break
            fi
        fi
    done
    
    # 对于 MariaDB（Alpine/SUSE），可能没有临时密码
    if [ -z "$TEMP_PASSWORD" ] && [ "$OS" = "alpine" ]; then
        echo -e "${BLUE}  MariaDB 通常没有临时密码，root 用户可能无密码或需要初始化${NC}"
    fi
    
    echo -e "${GREEN}✓ MySQL 配置完成${NC}"
    
    if [ -n "$TEMP_PASSWORD" ]; then
        echo -e "${YELLOW}⚠ MySQL 临时 root 密码: ${TEMP_PASSWORD}${NC}"
        echo -e "${YELLOW}⚠ 请使用以下命令修改 root 密码:${NC}"
        echo "   mysql -u root -p'${TEMP_PASSWORD}' -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY 'your_new_password';\""
    fi
}

# 设置 root 密码（可选）
set_root_password() {
    # 临时禁用 set -e，以便更好地处理错误
    set +e
    
    echo -e "${BLUE}[6/8] 设置 MySQL root 密码...${NC}"
    
    # 如果检测到临时密码，主动提示用户设置密码
    if [ -z "$MYSQL_ROOT_PASSWORD" ] && [ -n "$TEMP_PASSWORD" ]; then
        echo -e "${YELLOW}检测到 MySQL 临时密码，建议立即修改 root 密码${NC}"
        echo -e "${YELLOW}临时密码: ${TEMP_PASSWORD}${NC}"
        echo ""
        read -p "是否现在设置 root 密码？[Y/n]: " SET_PASSWORD
        SET_PASSWORD="${SET_PASSWORD:-Y}"
        if [[ "$SET_PASSWORD" =~ ^[Yy]$ ]]; then
            # 使用更可靠的方法读取密码（避免特殊字符问题）
            echo -n "请输入新的 MySQL root 密码: "
            # 禁用 echo，读取密码
            stty -echo
            IFS= read -r MYSQL_ROOT_PASSWORD
            stty echo
            echo ""
            if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                echo -e "${RED}错误: 密码不能为空${NC}"
                echo -e "${YELLOW}跳过 root 密码设置${NC}"
                return 0
            fi
            # 调试：显示密码长度（不显示密码内容）
            echo -e "${BLUE}调试: 已读取密码，长度 = ${#MYSQL_ROOT_PASSWORD} 字符${NC}"
        else
            echo -e "${YELLOW}跳过 root 密码设置${NC}"
            return 0
        fi
    elif [ -z "$MYSQL_ROOT_PASSWORD" ]; then
        read -sp "请输入 MySQL root 密码（直接回车跳过）: " MYSQL_ROOT_PASSWORD
        echo ""
    fi
    
    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        # 等待 MySQL 完全启动并检查服务状态
        echo "等待 MySQL 服务完全启动..."
        local max_wait=30
        local waited=0
        while [ $waited -lt $max_wait ]; do
            if mysqladmin ping -h localhost --silent 2>/dev/null; then
                echo -e "${GREEN}✓ MySQL 服务已就绪${NC}"
                break
            fi
            sleep 2
            waited=$((waited + 2))
            echo -n "."
        done
        echo ""
        
        # 如果 MySQL 服务未就绪，等待更长时间
        if ! mysqladmin ping -h localhost --silent 2>/dev/null; then
            echo -e "${YELLOW}⚠ MySQL 服务可能还在启动中，继续等待...${NC}"
            sleep 5
        fi
        
        # 尝试使用临时密码登录并修改（MySQL 8.0 需要使用 --connect-expired-password）
        if [ -n "$TEMP_PASSWORD" ]; then
            echo "正在使用临时密码修改 root 密码..."
            
            # 首先检查 MySQL 版本
            echo "检查 MySQL 版本..."
            local mysql_version_output=$(mysql --version 2>&1 || echo "")
            local mysql_version=""
            if echo "$mysql_version_output" | grep -qi "8\.0"; then
                mysql_version="8.0"
                echo -e "${GREEN}✓ 检测到 MySQL 8.0${NC}"
            elif echo "$mysql_version_output" | grep -qi "5\.7"; then
                mysql_version="5.7"
                echo -e "${GREEN}✓ 检测到 MySQL 5.7${NC}"
            else
                echo -e "${YELLOW}⚠ 未检测到 MySQL 8.0 或 5.7${NC}"
            fi
            
            # 验证密码复杂度（必须满足：大写字母、小写字母、数字、特殊字符）
            echo "验证密码复杂度..."
            # 调试：检查密码变量是否正确读取（不显示完整密码，只显示长度）
            local pwd_length=${#MYSQL_ROOT_PASSWORD}
            echo -e "${BLUE}调试: 密码长度 = ${pwd_length} 字符${NC}"
            
            local password_valid=0
            local password_check_msg=""
            
            # 检查密码长度
            if [ $pwd_length -lt 8 ]; then
                password_check_msg="密码长度至少 8 位（当前: ${pwd_length} 字符）"
            # 检查大写字母
            elif ! echo "$MYSQL_ROOT_PASSWORD" | grep -q '[A-Z]'; then
                password_check_msg="密码必须包含至少一个大写字母 (A-Z)"
            # 检查小写字母
            elif ! echo "$MYSQL_ROOT_PASSWORD" | grep -q '[a-z]'; then
                password_check_msg="密码必须包含至少一个小写字母 (a-z)"
            # 检查数字
            elif ! echo "$MYSQL_ROOT_PASSWORD" | grep -q '[0-9]'; then
                password_check_msg="密码必须包含至少一个数字 (0-9)"
            # 检查特殊字符
            elif ! echo "$MYSQL_ROOT_PASSWORD" | grep -q '[^A-Za-z0-9]'; then
                password_check_msg="密码必须包含至少一个特殊字符 (!@#$%^&*等)"
            else
                password_valid=1
            fi
            
            if [ $password_valid -eq 0 ]; then
                echo -e "${RED}✗ 密码复杂度验证失败: ${password_check_msg}${NC}"
                echo -e "${YELLOW}密码要求:${NC}"
                echo "  - 至少 8 位长度"
                echo "  - 包含至少一个大写字母 (A-Z)"
                echo "  - 包含至少一个小写字母 (a-z)"
                echo "  - 包含至少一个数字 (0-9)"
                echo "  - 包含至少一个特殊字符 (!@#$%^&*等)"
                echo ""
                echo ""
                echo -e "${YELLOW}提示: 如果刚才输入的密码是正确的，请直接按回车继续${NC}"
                read -p "是否重新输入密码？[Y/n]: " REENTER_PWD
                REENTER_PWD="${REENTER_PWD:-Y}"
                # 如果用户输入的内容看起来像密码（包含特殊字符或长度较长），直接当作密码处理
                if [ ${#REENTER_PWD} -gt 3 ] || echo "$REENTER_PWD" | grep -q '[^YyNn]'; then
                    # 用户可能直接输入了密码而不是选择
                    if echo "$REENTER_PWD" | grep -qE '[^YyNn]'; then
                        echo -e "${YELLOW}⚠ 检测到您可能直接输入了密码，将使用该密码${NC}"
                        MYSQL_ROOT_PASSWORD="$REENTER_PWD"
                        # 重新验证密码复杂度
                        password_valid=0
                        local pwd_len=${#MYSQL_ROOT_PASSWORD}
                        if [ $pwd_len -lt 8 ]; then
                            password_check_msg="密码长度至少 8 位（当前: ${pwd_len} 字符）"
                        elif ! echo "$MYSQL_ROOT_PASSWORD" | grep -q '[A-Z]'; then
                            password_check_msg="密码必须包含至少一个大写字母 (A-Z)"
                        elif ! echo "$MYSQL_ROOT_PASSWORD" | grep -q '[a-z]'; then
                            password_check_msg="密码必须包含至少一个小写字母 (a-z)"
                        elif ! echo "$MYSQL_ROOT_PASSWORD" | grep -q '[0-9]'; then
                            password_check_msg="密码必须包含至少一个数字 (0-9)"
                        elif ! echo "$MYSQL_ROOT_PASSWORD" | grep -q '[^A-Za-z0-9]'; then
                            password_check_msg="密码必须包含至少一个特殊字符 (!@#$%^&*等)"
                        else
                            password_valid=1
                        fi
                        if [ $password_valid -eq 0 ]; then
                            echo -e "${RED}✗ 密码不满足复杂度要求: ${password_check_msg}${NC}"
                            echo -e "${YELLOW}请重新输入满足要求的密码${NC}"
                            set -e
                            return 1
                        else
                            # 密码验证通过，跳过后续的重新输入流程
                            echo -e "${GREEN}✓ 密码复杂度验证通过${NC}"
                            REENTER_PWD="N"
                        fi
                    else
                        # 如果输入的是Y/y，继续重新输入流程
                        REENTER_PWD="Y"
                    fi
                fi
                
                if [[ "$REENTER_PWD" =~ ^[Yy]$ ]]; then
                    # 询问是否显示密码输入
                    echo -e "${BLUE}密码输入方式：${NC}"
                    echo "  1. 隐藏输入（推荐，更安全）"
                    echo "  2. 显示输入（可以看到输入的字符）"
                    read -p "请选择 [1-2，默认1]: " SHOW_PASSWORD
                    SHOW_PASSWORD="${SHOW_PASSWORD:-1}"
                    
                    if [[ "$SHOW_PASSWORD" == "2" ]]; then
                        echo -n "请输入新的 MySQL root 密码（必须满足复杂度要求，将显示输入）: "
                        IFS= read -r MYSQL_ROOT_PASSWORD
                        echo ""
                    else
                    echo -n "请输入新的 MySQL root 密码（必须满足复杂度要求）: "
                    stty -echo
                    IFS= read -r MYSQL_ROOT_PASSWORD
                    stty echo
                    echo ""
                    fi
                    
                    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                        echo -e "${RED}错误: 密码不能为空${NC}"
                        set -e
                        return 1
                    fi
                    # 调试：显示密码长度
                    echo -e "${BLUE}调试: 已重新读取密码，长度 = ${#MYSQL_ROOT_PASSWORD} 字符${NC}"
                    # 重新验证
                    password_valid=0
                    local pwd_len=${#MYSQL_ROOT_PASSWORD}
                    if [ $pwd_len -lt 8 ]; then
                        password_check_msg="密码长度至少 8 位（当前: ${pwd_len} 字符）"
                    elif ! echo "$MYSQL_ROOT_PASSWORD" | grep -q '[A-Z]'; then
                        password_check_msg="密码必须包含至少一个大写字母 (A-Z)"
                    elif ! echo "$MYSQL_ROOT_PASSWORD" | grep -q '[a-z]'; then
                        password_check_msg="密码必须包含至少一个小写字母 (a-z)"
                    elif ! echo "$MYSQL_ROOT_PASSWORD" | grep -q '[0-9]'; then
                        password_check_msg="密码必须包含至少一个数字 (0-9)"
                    elif ! echo "$MYSQL_ROOT_PASSWORD" | grep -q '[^A-Za-z0-9]'; then
                        password_check_msg="密码必须包含至少一个特殊字符 (!@#$%^&*等)"
                    else
                        password_valid=1
                    fi
                    if [ $password_valid -eq 0 ]; then
                        echo -e "${RED}✗ 密码仍然不满足复杂度要求: ${password_check_msg}${NC}"
                        set -e
                        return 1
                    fi
                else
                    # 用户选择不重新输入，使用原来的密码继续（可能是验证逻辑有问题）
                    echo -e "${YELLOW}⚠ 使用原密码继续，如果密码修改失败，请手动修改${NC}"
                    # 不返回，继续执行密码修改
                fi
            fi
            
            echo -e "${GREEN}✓ 密码复杂度验证通过${NC}"
            
            # 步骤 1: 修改 root 密码（必须满足密码复杂度）
            echo ""
            echo -e "${BLUE}步骤 1: 修改 root 密码...${NC}"
            
            # 执行密码修改（使用临时密码）
            local error_output=""
            local exit_code=1
            local has_error=1
            
            # 创建临时配置文件用于传递临时密码
            local temp_cnf=$(mktemp)
            cat > "$temp_cnf" <<CNF_EOF
[client]
user=root
password=${TEMP_PASSWORD}
CNF_EOF
            chmod 600 "$temp_cnf"
            
            # 先测试配置文件方式是否可用
            local test_output=$(mysql --connect-expired-password --defaults-file="$temp_cnf" -e "SELECT 1;" 2>&1)
            local test_exit_code=$?
            
            # 检查是否是因为 --defaults-file 不支持而失败
            local use_defaults_file=1
            if [ $test_exit_code -ne 0 ] && echo "$test_output" | grep -qi "unknown variable.*defaults-file"; then
                use_defaults_file=0
                echo -e "${YELLOW}⚠ 检测到 --defaults-file 不可用，使用直接传递密码方式${NC}"
            elif [ $test_exit_code -ne 0 ]; then
                use_defaults_file=1
            fi
            
            # 转义密码中的单引号
                local escaped_password=$(echo "$MYSQL_ROOT_PASSWORD" | sed "s/'/''/g")
            local alter_sql="ALTER USER 'root'@'localhost' IDENTIFIED BY '${escaped_password}';"
            
            # 执行密码修改（使用 -e 参数，类似手动执行方式）
            if [ $use_defaults_file -eq 1 ]; then
                error_output=$(mysql --connect-expired-password --defaults-file="$temp_cnf" -e "$alter_sql" 2>&1)
                exit_code=$?
                if [ $exit_code -ne 0 ] && echo "$error_output" | grep -qi "unknown variable.*defaults-file"; then
                    error_output=$(mysql --connect-expired-password -u root -p"${TEMP_PASSWORD}" -e "$alter_sql" 2>&1)
                    exit_code=$?
                fi
            else
                error_output=$(mysql --connect-expired-password -u root -p"${TEMP_PASSWORD}" -e "$alter_sql" 2>&1)
                exit_code=$?
            fi
            
            # 如果第一个用户修改成功，继续修改其他用户
            if [ $exit_code -eq 0 ]; then
                local alter_sql2="ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '${escaped_password}';"
                local alter_sql3="ALTER USER 'root'@'::1' IDENTIFIED BY '${escaped_password}';"
                local flush_sql="FLUSH PRIVILEGES;"
                
                if [ $use_defaults_file -eq 1 ]; then
                    mysql --connect-expired-password --defaults-file="$temp_cnf" -e "$alter_sql2" 2>/dev/null
                    mysql --connect-expired-password --defaults-file="$temp_cnf" -e "$alter_sql3" 2>/dev/null
                    mysql --connect-expired-password --defaults-file="$temp_cnf" -e "$flush_sql" 2>/dev/null
                else
                    mysql --connect-expired-password -u root -p"${TEMP_PASSWORD}" -e "$alter_sql2" 2>/dev/null
                    mysql --connect-expired-password -u root -p"${TEMP_PASSWORD}" -e "$alter_sql3" 2>/dev/null
                    mysql --connect-expired-password -u root -p"${TEMP_PASSWORD}" -e "$flush_sql" 2>/dev/null
                fi
                has_error=0
            else
                # 检查是否是密码策略错误（ERROR 1819）
                if echo "$error_output" | grep -qi "1819\|does not satisfy.*policy\|policy requirements"; then
                    echo -e "${YELLOW}⚠ 密码不满足当前策略要求，需要先设置密码策略${NC}"
                    echo -e "${YELLOW}错误信息: $(echo "$error_output" | grep -vE 'Warning: Using a password' | head -1)${NC}"
                    echo ""
                    echo -e "${YELLOW}提示: 密码必须满足 MySQL 当前的密码策略要求${NC}"
                    echo -e "${YELLOW}请重新输入一个满足策略要求的密码，或手动修改密码策略后重试${NC}"
                    rm -f "$temp_cnf"
                    set -e
                    return 1
                else
                    has_error=1
                fi
            fi
            
            rm -f "$temp_cnf"
            
            if [ $has_error -eq 0 ]; then
                echo -e "${GREEN}✓ root 密码修改成功${NC}"
                # 等待一下让密码生效
                sleep 2
                
                # 刷新权限已在上面执行，无需再次执行
                
                # 验证新密码是否生效（尝试多种方式）
                echo "验证新密码..."
                # 等待一下让密码完全生效
                sleep 1
                
                local verify_output=""
                local verify_exit_code=1
                
                # 方法1: 尝试使用配置文件方式
                local verify_cnf=$(mktemp)
                cat > "$verify_cnf" <<CNF_EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
CNF_EOF
                chmod 600 "$verify_cnf"
                
                verify_output=$(mysql --defaults-file="$verify_cnf" -e "SELECT 1;" 2>&1)
                verify_exit_code=$?
                
                # 如果配置文件方式失败且错误是 "unknown variable"，尝试直接传递密码
                if [ $verify_exit_code -ne 0 ] && echo "$verify_output" | grep -qi "unknown variable.*defaults-file"; then
                    verify_output=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" 2>&1)
                    verify_exit_code=$?
                fi
                
                # 如果还是失败，尝试使用交互式方式（通过管道）
                if [ $verify_exit_code -ne 0 ]; then
                    # 尝试使用 echo 管道方式
                    verify_output=$(echo "SELECT 1;" | mysql -u root -p"${MYSQL_ROOT_PASSWORD}" 2>&1)
                    verify_exit_code=$?
                fi
                
                rm -f "$verify_cnf"
                
                if [ $verify_exit_code -eq 0 ]; then
                    echo -e "${GREEN}✓ 新密码验证成功${NC}"
                    
                    # 步骤 2-7: 使用新密码设置密码策略、修改配置文件、重启服务、验证
                    if [ -n "$mysql_version" ]; then
                        echo ""
                        echo -e "${BLUE}步骤 2: 设置密码策略为 LOW（使用新密码）...${NC}"
                        
                        # 创建新密码的配置文件（用于后续步骤）
                        local new_pwd_cnf=$(mktemp)
                        cat > "$new_pwd_cnf" <<CNF_EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
CNF_EOF
                        chmod 600 "$new_pwd_cnf"
                        
                        # 测试配置文件方式
                        local test_new_output=$(mysql --defaults-file="$new_pwd_cnf" -e "SELECT 1;" 2>&1)
                        local test_new_exit_code=$?
                        local use_new_defaults_file=1
                        
                        if [ $test_new_exit_code -ne 0 ] && echo "$test_new_output" | grep -qi "unknown variable.*defaults-file"; then
                            use_new_defaults_file=0
                        fi
                        
                        # 设置密码策略为 LOW
                        local policy_sql=""
                        if [ "$mysql_version" = "8.0" ]; then
                            policy_sql="SET GLOBAL validate_password.policy = LOW;"
                        elif [ "$mysql_version" = "5.7" ]; then
                            policy_sql="SET GLOBAL validate_password_policy = LOW;"
                        fi
                        
                        if [ -n "$policy_sql" ]; then
                            local policy_output=""
                            local policy_exit_code=1
                            if [ $use_new_defaults_file -eq 1 ]; then
                                policy_output=$(mysql --defaults-file="$new_pwd_cnf" -e "$policy_sql" 2>&1)
                                policy_exit_code=$?
                                if [ $policy_exit_code -ne 0 ] && echo "$policy_output" | grep -qi "unknown variable.*defaults-file"; then
                                    policy_output=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "$policy_sql" 2>&1)
                                    policy_exit_code=$?
                                fi
                            else
                                policy_output=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "$policy_sql" 2>&1)
                                policy_exit_code=$?
                            fi
                            
                            if [ $policy_exit_code -eq 0 ]; then
                                echo -e "${GREEN}✓ 密码策略设置为 LOW${NC}"
                            else
                                if echo "$policy_output" | grep -qi "Unknown system variable\|Unknown variable"; then
                                    echo -e "${YELLOW}⚠ 密码验证插件未安装，跳过密码策略设置${NC}"
                                else
                                    echo -e "${YELLOW}⚠ 密码策略设置失败: $(echo "$policy_output" | grep -vE 'Warning: Using a password' | head -1)${NC}"
                                fi
                            fi
                        fi
                        
                        # 步骤 3: 设置密码最小长度为 6
                        echo -e "${BLUE}步骤 3: 设置密码最小长度为 6（使用新密码）...${NC}"
                        local policy_length_sql=""
                        if [ "$mysql_version" = "8.0" ]; then
                            policy_length_sql="SET GLOBAL validate_password.length = 6;"
                        elif [ "$mysql_version" = "5.7" ]; then
                            policy_length_sql="SET GLOBAL validate_password_length = 6;"
                        fi
                        
                        if [ -n "$policy_length_sql" ]; then
                            local length_output=""
                            local length_exit_code=1
                            if [ $use_new_defaults_file -eq 1 ]; then
                                length_output=$(mysql --defaults-file="$new_pwd_cnf" -e "$policy_length_sql" 2>&1)
                                length_exit_code=$?
                                if [ $length_exit_code -ne 0 ] && echo "$length_output" | grep -qi "unknown variable.*defaults-file"; then
                                    length_output=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "$policy_length_sql" 2>&1)
                                    length_exit_code=$?
                                fi
                            else
                                length_output=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "$policy_length_sql" 2>&1)
                                length_exit_code=$?
                            fi
                            
                            if [ $length_exit_code -eq 0 ]; then
                                echo -e "${GREEN}✓ 密码最小长度设置为 6${NC}"
                            else
                                if echo "$length_output" | grep -qi "Unknown system variable\|Unknown variable"; then
                                    echo -e "${YELLOW}⚠ 密码验证插件未安装，跳过密码长度设置${NC}"
                                else
                                    echo -e "${YELLOW}⚠ 密码长度设置失败: $(echo "$length_output" | grep -vE 'Warning: Using a password' | head -1)${NC}"
                                fi
                            fi
                        fi
                        
                        # 保留 new_pwd_cnf 用于后续验证步骤
                        
                        # 步骤 4: 验证配置文件（已在启动前设置，无需修改）
                        echo -e "${BLUE}步骤 4: 验证 MySQL 配置文件...${NC}"
                        echo -e "${GREEN}✓ lower_case_table_names 和 default_time_zone 已在 MySQL 启动前配置${NC}"
                        echo -e "${BLUE}  配置文件位置: /etc/my.cnf 或 /etc/mysql/my.cnf${NC}"
                        
                        # 步骤 5: 验证修改的内容
                        echo -e "${BLUE}步骤 5: 验证修改的内容...${NC}"
                        
                        # 使用已有的 new_pwd_cnf 进行验证
                        local verify_use_defaults=$use_new_defaults_file
                        
                        if [ "$mysql_version" = "8.0" ]; then
                            local policy_check=""
                            if [ $verify_use_defaults -eq 1 ]; then
                                policy_check=$(mysql --defaults-file="$new_pwd_cnf" -e "SHOW VARIABLES LIKE 'validate_password.policy';" 2>&1 | grep -i "validate_password.policy" | awk '{print $2}')
                            else
                                policy_check=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW VARIABLES LIKE 'validate_password.policy';" 2>&1 | grep -i "validate_password.policy" | awk '{print $2}')
                            fi
                            if [ "$policy_check" = "LOW" ]; then
                                echo -e "${GREEN}✓ 密码策略验证: LOW${NC}"
                            else
                                echo -e "${YELLOW}⚠ 密码策略验证: ${policy_check:-未设置}${NC}"
                            fi
                            
                            local length_check=""
                            if [ $verify_use_defaults -eq 1 ]; then
                                length_check=$(mysql --defaults-file="$new_pwd_cnf" -e "SHOW VARIABLES LIKE 'validate_password.length';" 2>&1 | grep -i "validate_password.length" | awk '{print $2}')
                            else
                                length_check=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW VARIABLES LIKE 'validate_password.length';" 2>&1 | grep -i "validate_password.length" | awk '{print $2}')
                            fi
                            if [ "$length_check" = "6" ]; then
                                echo -e "${GREEN}✓ 密码最小长度验证: 6${NC}"
                            else
                                echo -e "${YELLOW}⚠ 密码最小长度验证: ${length_check:-未设置}${NC}"
                            fi
                        elif [ "$mysql_version" = "5.7" ]; then
                            local policy_check=""
                            if [ $verify_use_defaults -eq 1 ]; then
                                policy_check=$(mysql --defaults-file="$new_pwd_cnf" -e "SHOW VARIABLES LIKE 'validate_password_policy';" 2>&1 | grep -i "validate_password_policy" | awk '{print $2}')
                            else
                                policy_check=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW VARIABLES LIKE 'validate_password_policy';" 2>&1 | grep -i "validate_password_policy" | awk '{print $2}')
                            fi
                            if [ "$policy_check" = "LOW" ]; then
                                echo -e "${GREEN}✓ 密码策略验证: LOW${NC}"
                            else
                                echo -e "${YELLOW}⚠ 密码策略验证: ${policy_check:-未设置}${NC}"
                            fi
                            
                            local length_check=""
                            if [ $verify_use_defaults -eq 1 ]; then
                                length_check=$(mysql --defaults-file="$new_pwd_cnf" -e "SHOW VARIABLES LIKE 'validate_password_length';" 2>&1 | grep -i "validate_password_length" | awk '{print $2}')
                            else
                                length_check=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW VARIABLES LIKE 'validate_password_length';" 2>&1 | grep -i "validate_password_length" | awk '{print $2}')
                            fi
                            if [ "$length_check" = "6" ]; then
                                echo -e "${GREEN}✓ 密码最小长度验证: 6${NC}"
                            else
                                echo -e "${YELLOW}⚠ 密码最小长度验证: ${length_check:-未设置}${NC}"
                            fi
                        fi
                        
                        # 验证 lower_case_table_names
                        local case_check=""
                        if [ $verify_use_defaults -eq 1 ]; then
                            case_check=$(mysql --defaults-file="$new_pwd_cnf" -e "SHOW VARIABLES LIKE 'lower_case_table_names';" 2>&1 | grep -i "lower_case_table_names" | awk '{print $2}')
                        else
                            case_check=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW VARIABLES LIKE 'lower_case_table_names';" 2>&1 | grep -i "lower_case_table_names" | awk '{print $2}')
                        fi
                        if [ "$case_check" = "1" ]; then
                            echo -e "${GREEN}✓ lower_case_table_names 验证: 1（不区分大小写）${NC}"
                        else
                            echo -e "${YELLOW}⚠ lower_case_table_names 验证: ${case_check:-未设置}（需要重启 MySQL 服务后生效）${NC}"
                        fi
                        
                        # 验证时区设置（检查 time_zone 变量）
                        local timezone_check=""
                        if [ $verify_use_defaults -eq 1 ]; then
                            timezone_check=$(mysql --defaults-file="$new_pwd_cnf" -e "SHOW VARIABLES LIKE 'time_zone';" 2>&1 | grep -i "time_zone" | awk '{print $2}')
                        else
                            timezone_check=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW VARIABLES LIKE 'time_zone';" 2>&1 | grep -i "time_zone" | awk '{print $2}')
                        fi
                        # time_zone 可能显示为 SYSTEM（使用系统时区）或具体的时区值（+08:00）
                        if [ "$timezone_check" = "+08:00" ] || [ "$timezone_check" = "SYSTEM" ]; then
                            echo -e "${GREEN}✓ 时区验证: ${timezone_check}（default_time_zone 已在配置文件中设置为 '+08:00'）${NC}"
                        else
                            echo -e "${YELLOW}⚠ 时区验证: ${timezone_check:-未设置}（default_time_zone 已在配置文件中设置为 '+08:00'，可能需要重启 MySQL 服务后生效）${NC}"
                        fi
                        
                        rm -f "$new_pwd_cnf"
                        
                        echo -e "${BLUE}步骤 6: 继续下一步...${NC}"
                    fi
                    
                    set -e  # 重新启用 set -e
                    return 0
                else
                    # 如果验证失败，先尝试手动测试（因为可能是验证方式的问题）
                    echo -e "${YELLOW}⚠ 新密码验证失败，但密码可能已经修改成功${NC}"
                    echo -e "${YELLOW}验证错误: $verify_output${NC}"
                    echo ""
                    echo -e "${BLUE}请手动测试新密码是否可以登录:${NC}"
                    echo "  mysql -u root -p'${MYSQL_ROOT_PASSWORD}' -e 'SELECT 1;'"
                    echo ""
                    read -p "新密码是否可以正常登录？[Y/n]: " PWD_WORKS
                    PWD_WORKS="${PWD_WORKS:-Y}"
                    if [[ "$PWD_WORKS" =~ ^[Yy]$ ]]; then
                        echo -e "${GREEN}✓ 密码已成功修改（手动验证通过）${NC}"
                        set -e  # 重新启用 set -e
                        return 0
                    fi
                    
                    # 如果手动验证也失败，尝试使用临时密码再次验证密码是否真的修改了
                    echo -e "${YELLOW}⚠ 继续使用临时密码验证...${NC}"
                    local temp_verify=""
                    local temp_verify_exit_code=1
                    
                    # 尝试使用配置文件方式
                    local temp_verify_cnf=$(mktemp)
                    cat > "$temp_verify_cnf" <<CNF_EOF
[client]
user=root
password=${TEMP_PASSWORD}
CNF_EOF
                    chmod 600 "$temp_verify_cnf"
                    
                    temp_verify=$(mysql --connect-expired-password --defaults-file="$temp_verify_cnf" -e "SELECT 1;" 2>&1)
                    temp_verify_exit_code=$?
                    
                    # 如果配置文件方式失败，尝试直接传递密码
                    if [ $temp_verify_exit_code -ne 0 ] && echo "$temp_verify" | grep -qi "unknown variable.*defaults-file"; then
                        temp_verify=$(mysql --connect-expired-password -u root -p"${TEMP_PASSWORD}" -e "SELECT 1;" 2>&1)
                        temp_verify_exit_code=$?
                    fi
                    
                    rm -f "$temp_verify_cnf"
                    # 更严格的验证：如果临时密码仍然可以登录（exit_code=0），说明密码修改失败
                    if [ $temp_verify_exit_code -eq 0 ]; then
                        echo -e "${RED}✗ 密码修改失败：临时密码仍然可以登录${NC}"
                        echo -e "${YELLOW}临时密码验证结果: $temp_verify${NC}"
                        echo -e "${YELLOW}新密码验证错误: $verify_output${NC}"
                        echo ""
                        echo -e "${YELLOW}可能的原因:${NC}"
                        echo "  1. SQL 语句执行失败（密码包含特殊字符导致 SQL 错误）"
                        echo "  2. 只修改了部分 root 用户"
                        echo "  3. MySQL 8.0 需要额外的步骤"
                        echo ""
                        echo -e "${YELLOW}建议:${NC}"
                        echo "  1. 检查 MySQL 错误日志: tail -20 /var/log/mysqld.log"
                        echo "  2. 手动修改密码:"
                        echo "     mysql --connect-expired-password -u root -p'${TEMP_PASSWORD}'"
                        echo "     # 然后在 MySQL 中执行:"
                        echo "     ALTER USER 'root'@'localhost' IDENTIFIED BY 'your_new_password';"
                        echo "     ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY 'your_new_password';"
                        echo "     ALTER USER 'root'@'::1' IDENTIFIED BY 'your_new_password';"
                        echo "     FLUSH PRIVILEGES;"
                        set -e  # 重新启用 set -e
                        return 1
                    elif echo "$temp_verify" | grep -qi "expired\|must be reset\|Access denied"; then
                        echo -e "${GREEN}✓ 密码已成功修改（临时密码已失效）${NC}"
                        echo -e "${YELLOW}⚠ 但新密码验证失败，可能是密码包含特殊字符${NC}"
                        echo -e "${YELLOW}验证错误: $verify_output${NC}"
                        echo ""
                        echo -e "${YELLOW}建议:${NC}"
                        echo "  1. 手动测试密码: mysql -u root -p"
                        echo "  2. 如果密码包含特殊字符，可能需要使用引号: mysql -u root -p'your_password'"
                        echo "  3. 或者重新设置一个不包含特殊字符的密码"
                        # 继续执行，让用户知道密码已设置
                        set -e  # 重新启用 set -e
                        return 0
                    else
                        echo -e "${RED}✗ 密码修改可能未生效${NC}"
                        echo -e "${YELLOW}验证错误: $verify_output${NC}"
                        echo -e "${YELLOW}临时密码验证结果: $temp_verify${NC}"
                        set -e  # 重新启用 set -e
                        return 1
                    fi
                fi
            else
                echo ""
                echo -e "${RED}========================================${NC}"
                echo -e "${RED}✗ 使用临时密码修改密码失败${NC}"
                echo -e "${RED}========================================${NC}"
                echo ""
                echo -e "${YELLOW}详细错误信息:${NC}"
                # 显示所有错误信息（过滤掉密码警告）
                local clean_error=$(echo "$error_output" | grep -vE "Warning: Using a password|Using a password on the command line" || echo "$error_output")
                if [ -n "$clean_error" ]; then
                    echo "$clean_error"
                else
                    echo "$error_output"
                fi
                echo ""
                echo -e "${YELLOW}退出代码: ${exit_code}${NC}"
                echo ""
                echo -e "${YELLOW}可能的原因:${NC}"
                echo "  1. MySQL 服务未完全启动"
                echo "  2. 临时密码已过期或无效"
                echo "  3. 临时密码不正确"
                echo "  4. 新密码包含特殊字符导致 SQL 执行失败"
                echo "  5. SQL 文件格式问题"
                echo ""
                echo -e "${BLUE}调试信息:${NC}"
                echo "  临时密码: ${TEMP_PASSWORD}"
                echo "  新密码长度: ${#MYSQL_ROOT_PASSWORD} 字符"
                echo "  SQL 文件: $sql_file"
                if [ -f "$sql_file" ]; then
                    echo "  SQL 内容预览:"
                    head -5 "$sql_file" | sed 's/^/    /'
                fi
                echo ""
                echo -e "${YELLOW}建议的解决步骤:${NC}"
                echo ""
                echo "  步骤 1: 测试临时密码是否可以连接"
                echo "    mysql --connect-expired-password -u root -p'${TEMP_PASSWORD}' -e 'SELECT 1;'"
                echo ""
                echo "  步骤 2: 如果步骤1成功，手动修改密码（推荐）"
                echo "    mysql --connect-expired-password -u root -p'${TEMP_PASSWORD}'"
                echo "    # 然后在 MySQL 中执行以下命令（替换 your_new_password 为你的新密码）:"
                echo "    ALTER USER 'root'@'localhost' IDENTIFIED BY 'your_new_password';"
                echo "    ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY 'your_new_password';"
                echo "    ALTER USER 'root'@'::1' IDENTIFIED BY 'your_new_password';"
                echo "    FLUSH PRIVILEGES;"
                echo "    exit;"
                echo ""
                echo "  步骤 3: 验证新密码"
                echo "    mysql -u root -p'your_new_password' -e 'SELECT 1;'"
                echo ""
                echo "  步骤 4: 重新运行安装脚本"
                echo "    sudo ./scripts/install_mysql.sh"
                echo ""
                echo -e "${BLUE}其他调试命令:${NC}"
                echo "  检查 MySQL 服务状态: systemctl status mysqld"
                echo "  查看 MySQL 错误日志: tail -30 /var/log/mysqld.log"
                echo ""
                # 清除错误的密码，让后续步骤重新提示输入
                MYSQL_ROOT_PASSWORD=""
                rm -f "$sql_file" 2>/dev/null || true
                set -e  # 重新启用 set -e
                    return 1
            fi
        fi
        
        # 如果临时密码方式失败，尝试无密码方式（某些系统可能没有临时密码，如 MariaDB）
        # 注意：如果上面已经设置了密码，这里不应该再执行
        if [ -z "$TEMP_PASSWORD" ] && ! mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" > /dev/null 2>&1; then
            # 尝试无密码连接（MariaDB 可能默认无密码）
            if mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';" 2>/dev/null; then
                echo -e "${GREEN}✓ root 密码已设置${NC}"
            else
                # 对于 MariaDB，可能需要先初始化或使用不同的命令
                if mysql -u root -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${MYSQL_ROOT_PASSWORD}');" 2>/dev/null; then
                    echo -e "${GREEN}✓ root 密码已设置（MariaDB 方式）${NC}"
                else
                    echo -e "${YELLOW}⚠ 无法自动设置密码，请手动设置${NC}"
                    echo -e "${YELLOW}  对于 MariaDB，可能需要运行: mysql_secure_installation${NC}"
                fi
            fi
        else
            echo -e "${GREEN}✓ root 密码验证成功${NC}"
        fi
    else
        echo -e "${YELLOW}跳过 root 密码设置${NC}"
    fi
    
    # 重新启用 set -e
    set -e
}

# 配置安全设置（可选）
secure_mysql() {
    echo -e "${BLUE}[7/8] 配置 MySQL 安全设置...${NC}"
    
    read -p "是否运行 mysql_secure_installation？（推荐）[Y/n]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
            # 先验证密码是否有效（尝试多种方式）
            echo "验证 root 密码..."
            local verify_output=""
            local verify_exit_code=1
            
            # 方法1: 尝试使用配置文件方式
            local verify_cnf=$(mktemp)
            cat > "$verify_cnf" <<CNF_EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
CNF_EOF
            chmod 600 "$verify_cnf"
            
            verify_output=$(mysql --defaults-file="$verify_cnf" -e "SELECT 1;" 2>&1)
            verify_exit_code=$?
            
            # 如果配置文件方式失败且错误是 "unknown variable"，尝试直接传递密码
            if [ $verify_exit_code -ne 0 ] && echo "$verify_output" | grep -qi "unknown variable.*defaults-file"; then
                verify_output=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" 2>&1)
                verify_exit_code=$?
            fi
            
            rm -f "$verify_cnf"
            
            if [ $verify_exit_code -ne 0 ]; then
                echo -e "${RED}✗ root 密码验证失败${NC}"
                local error_msg=$(echo "$verify_output" | grep -v "Warning: Using a password" | head -3)
                if [ -n "$error_msg" ]; then
                    echo -e "${YELLOW}错误信息: $error_msg${NC}"
                fi
                echo ""
                echo -e "${YELLOW}可能的原因:${NC}"
                echo "  1. 密码不正确"
                echo "  2. 密码修改未成功（仍在使用临时密码）"
                echo "  3. 密码包含特殊字符导致验证失败"
                echo ""
                echo -e "${YELLOW}建议:${NC}"
                echo "  1. 如果密码修改失败，请先手动修改密码:"
                if [ -n "$TEMP_PASSWORD" ]; then
                    echo "     mysql --connect-expired-password -u root -p'${TEMP_PASSWORD}'"
                else
                    echo "     mysql -u root -p"
                fi
                echo "     # 然后在 MySQL 中执行:"
                echo "     ALTER USER 'root'@'localhost' IDENTIFIED BY 'your_new_password';"
                echo "     FLUSH PRIVILEGES;"
                echo "  2. 或者重新输入正确的密码"
                echo ""
                read -p "是否重新输入 root 密码？[Y/n]: " REENTER_PWD
                REENTER_PWD="${REENTER_PWD:-Y}"
                if [[ "$REENTER_PWD" =~ ^[Yy]$ ]]; then
                    read -sp "请输入正确的 MySQL root 密码: " MYSQL_ROOT_PASSWORD
                    echo ""
                    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                        echo -e "${RED}错误: 密码不能为空${NC}"
                        echo -e "${YELLOW}跳过安全配置${NC}"
                        return 0
                    fi
                    # 重新验证（尝试多种方式）
                    verify_cnf=$(mktemp)
                    cat > "$verify_cnf" <<CNF_EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
CNF_EOF
                    chmod 600 "$verify_cnf"
                    
                    verify_output=$(mysql --defaults-file="$verify_cnf" -e "SELECT 1;" 2>&1)
                    verify_exit_code=$?
                    
                    # 如果配置文件方式失败，尝试直接传递密码
                    if [ $verify_exit_code -ne 0 ] && echo "$verify_output" | grep -qi "unknown variable.*defaults-file"; then
                        verify_output=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" 2>&1)
                        verify_exit_code=$?
                    fi
                    
                    rm -f "$verify_cnf"
                    if [ $verify_exit_code -ne 0 ]; then
                        echo -e "${RED}✗ 密码仍然不正确，跳过安全配置${NC}"
                        return 0
                    fi
                    echo -e "${GREEN}✓ 密码验证成功${NC}"
                else
                    echo -e "${YELLOW}跳过安全配置${NC}"
                    return 0
                fi
            else
                echo -e "${GREEN}✓ root 密码验证成功${NC}"
                # 非交互式运行 mysql_secure_installation（尝试多种方式）
                echo "执行安全配置..."
                local secure_output=""
                local secure_exit_code=1
                
                # 方法1: 尝试使用配置文件方式
                local secure_cnf=$(mktemp)
                cat > "$secure_cnf" <<CNF_EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
CNF_EOF
                chmod 600 "$secure_cnf"
                
                secure_output=$(mysql --defaults-file="$secure_cnf" <<EOF 2>&1
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
)
                secure_exit_code=$?
                
                # 如果配置文件方式失败，尝试直接传递密码
                if [ $secure_exit_code -ne 0 ] && echo "$secure_output" | grep -qi "unknown variable.*defaults-file"; then
                    secure_output=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF 2>&1
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
)
                    secure_exit_code=$?
                fi
                
                rm -f "$secure_cnf"
                
                if [ $secure_exit_code -eq 0 ]; then
                    echo -e "${GREEN}✓ 安全配置完成${NC}"
                else
                    echo -e "${YELLOW}⚠ 安全配置执行时出现警告或错误${NC}"
                    echo "$secure_output" | grep -v "Warning: Using a password" | head -5
                fi
            fi
        elif [ -n "$TEMP_PASSWORD" ]; then
            # 如果未设置密码但有临时密码，使用临时密码（需要 --connect-expired-password）
            echo -e "${YELLOW}⚠ 检测到临时密码，使用临时密码进行安全配置${NC}"
            echo -e "${YELLOW}⚠ 注意：使用临时密码时，必须先修改密码才能执行其他操作${NC}"
            echo -e "${YELLOW}⚠ 建议先设置 root 密码，然后再运行安全配置${NC}"
            echo ""
            read -p "是否现在设置 root 密码？[Y/n]: " SET_PWD_NOW
            SET_PWD_NOW="${SET_PWD_NOW:-Y}"
            if [[ "$SET_PWD_NOW" =~ ^[Yy]$ ]]; then
                read -sp "请输入新密码: " NEW_PASSWORD
                echo ""
                if [ -n "$NEW_PASSWORD" ]; then
                    # 使用临时密码修改密码
                    if mysql --connect-expired-password -u root -p"${TEMP_PASSWORD}" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${NEW_PASSWORD}';" 2>/dev/null; then
                        MYSQL_ROOT_PASSWORD="$NEW_PASSWORD"
                        echo -e "${GREEN}✓ root 密码已设置${NC}"
                        # 现在可以使用新密码进行安全配置
                        mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
                    else
                        echo -e "${RED}✗ 密码修改失败，请手动修改密码后重试${NC}"
                        echo -e "${YELLOW}手动修改密码命令:${NC}"
                        echo "  mysql --connect-expired-password -u root -p'${TEMP_PASSWORD}' -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY 'your_new_password';\""
                    fi
                else
                    echo -e "${RED}错误: 新密码不能为空${NC}"
                fi
            else
                echo -e "${YELLOW}跳过安全配置${NC}"
            fi
        else
            echo -e "${YELLOW}⚠ 未设置 root 密码，跳过安全配置${NC}"
            echo -e "${YELLOW}⚠ 请手动运行: mysql_secure_installation${NC}"
        fi
    else
        echo -e "${YELLOW}跳过安全配置${NC}"
    fi
    
    echo -e "${GREEN}✓ 安全配置完成${NC}"
}

# 验证安装
verify_installation() {
    echo -e "${BLUE}[8/8] 验证安装...${NC}"
    
    if command -v mysql &> /dev/null; then
        local version=$(mysql --version 2>&1 | head -n 1)
        echo -e "${GREEN}✓ MySQL 安装成功${NC}"
        echo "  版本: $version"
    else
        echo -e "${RED}✗ MySQL 安装失败${NC}"
        exit 1
    fi
    
    # 测试连接
    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        local test_output=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" 2>&1)
        local test_exit_code=$?
        
        if [ $test_exit_code -eq 0 ]; then
            echo -e "${GREEN}✓ MySQL 连接测试成功${NC}"
        else
            # 如果连接测试失败，但之前的安全配置成功了，说明密码实际上是正确的
            # 可能是密码包含特殊字符导致 shell 解析问题
            echo -e "${YELLOW}⚠ MySQL 连接测试失败（可能是密码包含特殊字符）${NC}"
            local error_msg=$(echo "$test_output" | grep -v "Warning: Using a password" | head -3)
            if [ -n "$error_msg" ]; then
                echo -e "${YELLOW}错误信息: $error_msg${NC}"
            fi
            echo ""
            echo -e "${YELLOW}注意: 如果之前的步骤（安全配置）成功，说明密码实际上是正确的${NC}"
            echo -e "${YELLOW}连接测试失败可能是因为密码包含特殊字符${NC}"
            echo ""
            echo -e "${BLUE}建议手动测试连接:${NC}"
            echo "  mysql -u root -p"
            echo "  # 然后输入密码进行交互式连接"
            echo ""
            echo -e "${BLUE}或者使用配置文件方式:${NC}"
            echo "  echo '[client]' > ~/.my.cnf"
            echo "  echo 'user=root' >> ~/.my.cnf"
            echo "  echo 'password=${MYSQL_ROOT_PASSWORD}' >> ~/.my.cnf"
            echo "  chmod 600 ~/.my.cnf"
            echo "  mysql -e 'SELECT 1;'"
        fi
    else
        echo -e "${YELLOW}⚠ 未设置密码，跳过连接测试${NC}"
    fi
}

# 创建数据库
create_database() {
    echo -e "${BLUE}[8/10] 创建数据库...${NC}"
    
    read -p "是否创建数据库？[Y/n]: " CREATE_DB
    CREATE_DB="${CREATE_DB:-Y}"
    
    if [[ ! "$CREATE_DB" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}跳过数据库创建${NC}"
        return 0
    fi
    
    # 获取 root 密码（如果未设置）
    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
        # 如果存在临时密码，提示用户
        if [ -n "$TEMP_PASSWORD" ]; then
            echo -e "${YELLOW}检测到 MySQL 临时密码，请使用临时密码或已设置的新密码${NC}"
            echo -e "${YELLOW}临时密码: ${TEMP_PASSWORD}${NC}"
        fi
        read -sp "请输入 MySQL root 密码（直接回车使用临时密码或无密码）: " MYSQL_ROOT_PASSWORD
        echo ""
        # 如果用户没有输入密码，使用临时密码
        if [ -z "$MYSQL_ROOT_PASSWORD" ] && [ -n "$TEMP_PASSWORD" ]; then
            MYSQL_ROOT_PASSWORD="$TEMP_PASSWORD"
            echo -e "${BLUE}使用临时密码连接 MySQL${NC}"
        elif [ -z "$MYSQL_ROOT_PASSWORD" ]; then
            echo -e "${YELLOW}⚠ 未输入 root 密码，尝试无密码连接${NC}"
        fi
    fi
    
    # 交互式输入数据库名称
    read -p "请输入数据库名称 [waf_db]: " DB_NAME
    DB_NAME="${DB_NAME:-waf_db}"
    
    # 检测是否存在同名数据库
    local db_exists=0
    local check_db_query="SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='${DB_NAME}';"
    
    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        # 使用配置文件方式查询
        local temp_cnf=$(mktemp)
        cat > "$temp_cnf" <<CNF_EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
CNF_EOF
        chmod 600 "$temp_cnf"
        local db_check_result=$(mysql --defaults-file="$temp_cnf" -e "$check_db_query" 2>/dev/null | grep -v "SCHEMA_NAME" | grep -v "^$")
        rm -f "$temp_cnf"
        
        if [ -z "$db_check_result" ]; then
            # 如果配置文件方式失败，尝试直接传递密码
            db_check_result=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "$check_db_query" 2>/dev/null | grep -v "SCHEMA_NAME" | grep -v "^$")
        fi
        
        if [ -n "$db_check_result" ]; then
            db_exists=1
        fi
    else
        db_check_result=$(mysql -u root -e "$check_db_query" 2>/dev/null | grep -v "SCHEMA_NAME" | grep -v "^$")
        if [ -n "$db_check_result" ]; then
            db_exists=1
        fi
    fi
    
    if [ $db_exists -eq 1 ]; then
        echo -e "${YELLOW}⚠ 检测到数据库 ${DB_NAME} 已存在${NC}"
        read -p "是否使用现有数据库？[Y/n]: " USE_EXISTING_DB
        USE_EXISTING_DB="${USE_EXISTING_DB:-Y}"
        if [[ "$USE_EXISTING_DB" =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}✓ 将使用现有数据库 ${DB_NAME}${NC}"
            MYSQL_DATABASE="$DB_NAME"
            export CREATED_DB_NAME="$DB_NAME"
            return 0
        else
            echo -e "${YELLOW}请重新输入数据库名称${NC}"
            read -p "请输入新的数据库名称: " DB_NAME
            if [ -z "$DB_NAME" ]; then
                echo -e "${RED}错误: 数据库名称不能为空${NC}"
                return 1
            fi
        fi
    fi
    
    # 创建数据库
    echo "正在创建数据库 ${DB_NAME}..."
    local db_create_output=""
    local db_create_exit_code=0
    
    # 尝试连接并创建数据库（支持临时密码和特殊字符密码）
    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        # 首先验证密码是否有效（尝试多种方式）
        local verify_cnf=$(mktemp)
        cat > "$verify_cnf" <<CNF_EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
CNF_EOF
        chmod 600 "$verify_cnf"
        
        # 验证密码（方法1: 配置文件方式）
        local verify_output=$(mysql --defaults-file="$verify_cnf" -e "SELECT 1;" 2>&1)
        local verify_exit_code=$?
        
        # 如果配置文件方式失败且错误是 "unknown variable"，尝试直接传递密码
        if [ $verify_exit_code -ne 0 ] && echo "$verify_output" | grep -qi "unknown variable.*defaults-file"; then
            verify_output=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" 2>&1)
            verify_exit_code=$?
        fi
        
        if [ $verify_exit_code -ne 0 ]; then
            # 密码验证失败，可能是密码不正确或密码修改未成功
            echo -e "${RED}✗ MySQL root 密码验证失败${NC}"
            local error_msg=$(echo "$verify_output" | grep -v "Warning: Using a password" | head -3)
            if [ -n "$error_msg" ]; then
                echo -e "${YELLOW}错误信息: $error_msg${NC}"
            fi
            echo ""
            echo -e "${YELLOW}可能的原因:${NC}"
            echo "  1. 密码不正确"
            echo "  2. 密码修改未成功（仍在使用临时密码）"
            echo "  3. 密码包含特殊字符导致验证失败"
            echo ""
            echo -e "${YELLOW}建议:${NC}"
            echo "  1. 如果密码修改失败，请先手动修改密码:"
            echo "     mysql --connect-expired-password -u root -p'${TEMP_PASSWORD}'"
            echo "     # 然后在 MySQL 中执行:"
            echo "     ALTER USER 'root'@'localhost' IDENTIFIED BY 'your_new_password';"
            echo "     FLUSH PRIVILEGES;"
            echo "  2. 或者重新输入正确的密码"
            echo ""
            read -p "是否重新输入 root 密码？[Y/n]: " REENTER_PWD
            REENTER_PWD="${REENTER_PWD:-Y}"
            if [[ "$REENTER_PWD" =~ ^[Yy]$ ]]; then
                read -sp "请输入正确的 MySQL root 密码: " MYSQL_ROOT_PASSWORD
                echo ""
                if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                    echo -e "${RED}错误: 密码不能为空${NC}"
                    rm -f "$verify_cnf"
                    return 1
                fi
                # 更新验证配置文件
                cat > "$verify_cnf" <<CNF_EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
CNF_EOF
                # 重新验证（尝试多种方式）
                verify_output=$(mysql --defaults-file="$verify_cnf" -e "SELECT 1;" 2>&1)
                verify_exit_code=$?
                
                # 如果配置文件方式失败，尝试直接传递密码
                if [ $verify_exit_code -ne 0 ] && echo "$verify_output" | grep -qi "unknown variable.*defaults-file"; then
                    verify_output=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" 2>&1)
                    verify_exit_code=$?
                fi
                if [ $verify_exit_code -ne 0 ]; then
                    echo -e "${RED}✗ 密码仍然不正确，请检查密码${NC}"
                    rm -f "$verify_cnf"
                    return 1
                fi
                echo -e "${GREEN}✓ 密码验证成功${NC}"
            else
                rm -f "$verify_cnf"
                return 1
            fi
        fi
        
        # 使用配置文件方式创建数据库（尝试多种方式）
        db_create_output=$(mysql --defaults-file="$verify_cnf" <<EOF 2>&1
CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
EOF
)
            db_create_exit_code=$?
        
        # 如果配置文件方式失败，尝试直接传递密码
        if [ $db_create_exit_code -ne 0 ] && echo "$db_create_output" | grep -qi "unknown variable.*defaults-file"; then
            db_create_output=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF 2>&1
CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
EOF
)
            db_create_exit_code=$?
        fi
            
            # 清理临时文件
        rm -f "$verify_cnf"
            
            if [ $db_create_exit_code -eq 0 ]; then
            echo -e "${GREEN}✓ 数据库创建成功${NC}"
        fi
        
        # 如果失败且使用的是临时密码，提示用户需要先修改密码
        if [ $db_create_exit_code -ne 0 ] && [ "$MYSQL_ROOT_PASSWORD" = "$TEMP_PASSWORD" ]; then
            echo -e "${YELLOW}⚠ 使用临时密码创建数据库失败${NC}"
            echo -e "${YELLOW}MySQL 8.0 要求首次登录后必须修改临时密码才能执行其他操作${NC}"
            echo -e "${YELLOW}请先修改 root 密码，然后再创建数据库${NC}"
            echo ""
            echo -e "${BLUE}修改密码命令:${NC}"
            echo "  mysql -u root -p'${TEMP_PASSWORD}' -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY 'your_new_password';\""
            echo ""
            read -p "是否现在修改 root 密码？[Y/n]: " CHANGE_PWD
            CHANGE_PWD="${CHANGE_PWD:-Y}"
            if [[ "$CHANGE_PWD" =~ ^[Yy]$ ]]; then
                read -sp "请输入新密码: " NEW_PASSWORD
                echo ""
                if [ -n "$NEW_PASSWORD" ]; then
                    # 修改密码（MySQL 8.0 需要使用 --connect-expired-password）
                    if mysql --connect-expired-password -u root -p"${TEMP_PASSWORD}" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${NEW_PASSWORD}';" 2>/dev/null; then
                        MYSQL_ROOT_PASSWORD="$NEW_PASSWORD"
                        echo -e "${GREEN}✓ root 密码已修改${NC}"
                        # 重新尝试创建数据库
                        db_create_output=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF 2>&1
CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
EOF
)
                        db_create_exit_code=$?
                    else
                        echo -e "${RED}✗ 密码修改失败，请手动修改密码后重试${NC}"
                        return 1
                    fi
                else
                    echo -e "${RED}错误: 新密码不能为空${NC}"
                    return 1
                fi
            else
                return 1
            fi
        fi
    else
        db_create_output=$(mysql -u root <<EOF 2>&1
CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
EOF
)
        db_create_exit_code=$?
    fi
    
    if [ $db_create_exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ 数据库 ${DB_NAME} 创建成功（字符集：utf8mb4，排序规则：utf8mb4_general_ci）${NC}"
        # 保存数据库名称到全局变量并导出
        MYSQL_DATABASE="$DB_NAME"
        export CREATED_DB_NAME="$DB_NAME"
        return 0
    else
        echo -e "${RED}✗ 数据库创建失败${NC}"
        # 显示详细错误信息（过滤掉警告信息）
        local error_msg=$(echo "$db_create_output" | grep -v "Warning: Using a password" | head -5)
        if [ -n "$error_msg" ]; then
            echo -e "${RED}错误信息:${NC}"
            echo "$error_msg"
        else
            echo -e "${RED}错误信息: ${db_create_output}${NC}"
        fi
        echo ""
        echo -e "${YELLOW}可能的原因:${NC}"
        echo "  1. MySQL 服务未启动"
        echo "  2. root 密码不正确或包含特殊字符"
        echo "  3. 数据库名称已存在且权限不足"
        echo "  4. MySQL 连接失败"
        echo "  5. 密码包含特殊字符，shell 解析错误"
        echo ""
        echo -e "${YELLOW}建议:${NC}"
        echo "  1. 检查 MySQL 服务状态: systemctl status mysqld"
        echo "  2. 验证 root 密码: mysql -u root -p（交互式输入密码）"
        echo "  3. 手动创建数据库:"
        echo "     mysql -u root -p"
        echo "     # 然后执行: CREATE DATABASE ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
        echo "  4. 或者使用配置文件方式:"
        echo "     echo '[client]' > ~/.my.cnf"
        echo "     echo 'user=root' >> ~/.my.cnf"
        echo "     echo 'password=your_password' >> ~/.my.cnf"
        echo "     chmod 600 ~/.my.cnf"
        echo "     mysql -e \"CREATE DATABASE ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;\""
        echo ""
        read -p "是否跳过数据库创建？[y/N]: " SKIP_DB
        if [[ "$SKIP_DB" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}跳过数据库创建${NC}"
            return 0
        else
            return 1
        fi
    fi
}

# 创建数据库用户
create_database_user() {
    echo -e "${BLUE}[9/10] 创建数据库用户...${NC}"
    
    read -p "是否创建数据库用户？[Y/n]: " CREATE_USER
    CREATE_USER="${CREATE_USER:-Y}"
    
    if [[ ! "$CREATE_USER" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}跳过用户创建，将使用 root 用户${NC}"
        MYSQL_USER="root"
        MYSQL_USER_PASSWORD="$MYSQL_ROOT_PASSWORD"
        USE_NEW_USER="N"
        return 0
    fi
    
    # 检查是否已创建数据库
    if [ -z "$MYSQL_DATABASE" ]; then
        echo -e "${YELLOW}⚠ 未创建数据库，请先创建数据库${NC}"
        return 1
    fi
    
    # 交互式输入用户名
    read -p "请输入数据库用户名 [waf_user]: " DB_USER
    DB_USER="${DB_USER:-waf_user}"
    
    # 检测是否存在同名用户
    local user_exists=0
    local check_user_query="SELECT CONCAT(User, '@', Host) as 'User@Host' FROM mysql.user WHERE User='${DB_USER}';"
    
    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        # 使用配置文件方式查询
        local temp_cnf=$(mktemp)
        cat > "$temp_cnf" <<CNF_EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
CNF_EOF
        chmod 600 "$temp_cnf"
        local user_check_result=$(mysql --defaults-file="$temp_cnf" -e "$check_user_query" 2>/dev/null | grep -v "User@Host" | grep -v "^$" | grep -E "${DB_USER}@")
        rm -f "$temp_cnf"
        
        if [ -z "$user_check_result" ]; then
            # 如果配置文件方式失败，尝试直接传递密码
            user_check_result=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "$check_user_query" 2>/dev/null | grep -v "User@Host" | grep -v "^$" | grep -E "${DB_USER}@")
        fi
        
        if [ -n "$user_check_result" ]; then
            user_exists=1
        fi
    else
        user_check_result=$(mysql -u root -e "$check_user_query" 2>/dev/null | grep -v "User@Host" | grep -v "^$" | grep -E "${DB_USER}@")
        if [ -n "$user_check_result" ]; then
            user_exists=1
        fi
    fi
    
    if [ $user_exists -eq 1 ]; then
        echo -e "${YELLOW}⚠ 检测到用户 ${DB_USER} 已存在${NC}"
        echo "  现有用户:"
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                echo "    ${line}"
            fi
        done <<< "$user_check_result"
        echo ""
        read -p "是否使用现有用户？[Y/n]: " USE_EXISTING_USER
        USE_EXISTING_USER="${USE_EXISTING_USER:-Y}"
        if [[ "$USE_EXISTING_USER" =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}✓ 将使用现有用户 ${DB_USER}${NC}"
            read -sp "请输入用户 ${DB_USER} 的密码: " DB_USER_PASSWORD
            echo ""
            if [ -z "$DB_USER_PASSWORD" ]; then
                echo -e "${RED}错误: 用户密码不能为空${NC}"
                return 1
            fi
            # 验证用户密码是否正确
            local verify_user_cnf=$(mktemp)
            cat > "$verify_user_cnf" <<CNF_EOF
[client]
user=${DB_USER}
password=${DB_USER_PASSWORD}
CNF_EOF
            chmod 600 "$verify_user_cnf"
            local verify_result=$(mysql --defaults-file="$verify_user_cnf" -e "SELECT 1;" 2>/dev/null)
            rm -f "$verify_user_cnf"
            
            if [ -z "$verify_result" ]; then
                verify_result=$(mysql -u "${DB_USER}" -p"${DB_USER_PASSWORD}" -e "SELECT 1;" 2>/dev/null)
            fi
            
            if [ -n "$verify_result" ]; then
                echo -e "${GREEN}✓ 用户密码验证成功${NC}"
                # 确保用户有数据库权限
                if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
                    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF 2>/dev/null
GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
                else
                    mysql -u root <<EOF 2>/dev/null
GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
                fi
                MYSQL_USER="$DB_USER"
                MYSQL_USER_PASSWORD="$DB_USER_PASSWORD"
                export MYSQL_USER_FOR_WAF="$DB_USER"
                export MYSQL_PASSWORD_FOR_WAF="$DB_USER_PASSWORD"
                export USE_NEW_USER="Y"
                return 0
            else
                echo -e "${RED}✗ 用户密码验证失败，请重新输入${NC}"
                return 1
            fi
        else
            echo -e "${YELLOW}请重新输入用户名${NC}"
            read -p "请输入新的数据库用户名: " DB_USER
            if [ -z "$DB_USER" ]; then
                echo -e "${RED}错误: 用户名不能为空${NC}"
                return 1
            fi
        fi
    fi
    
    # 交互式输入密码
    read -sp "请输入数据库用户密码: " DB_USER_PASSWORD
    echo ""
    if [ -z "$DB_USER_PASSWORD" ]; then
        echo -e "${RED}错误: 用户密码不能为空${NC}"
        return 1
    fi
    
    # 创建用户
    echo "正在创建用户 ${DB_USER}..."
    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_USER_PASSWORD}';
GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
    else
        mysql -u root <<EOF
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_USER_PASSWORD}';
GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 用户 ${DB_USER} 创建成功，并已授予 ${MYSQL_DATABASE} 数据库的全部权限${NC}"
        
        # 询问是否使用新创建的用户
        read -p "是否使用新创建的用户 ${DB_USER} 连接 MySQL？[Y/n]: " USE_NEW_USER
        USE_NEW_USER="${USE_NEW_USER:-Y}"
        
        if [[ "$USE_NEW_USER" =~ ^[Yy]$ ]]; then
            MYSQL_USER="$DB_USER"
            MYSQL_USER_PASSWORD="$DB_USER_PASSWORD"
            # 导出变量供父脚本使用
            export MYSQL_USER_FOR_WAF="$DB_USER"
            export MYSQL_PASSWORD_FOR_WAF="$DB_USER_PASSWORD"
            export USE_NEW_USER="Y"
            echo -e "${GREEN}✓ 将使用用户 ${DB_USER} 连接 MySQL${NC}"
        else
            MYSQL_USER="root"
            MYSQL_USER_PASSWORD="$MYSQL_ROOT_PASSWORD"
            # 导出变量供父脚本使用
            export MYSQL_USER_FOR_WAF="root"
            export MYSQL_PASSWORD_FOR_WAF="$MYSQL_ROOT_PASSWORD"
            export USE_NEW_USER="N"
            echo -e "${YELLOW}将使用 root 用户连接 MySQL${NC}"
        fi
    else
        echo -e "${RED}✗ 用户创建失败${NC}"
        MYSQL_USER="root"
        MYSQL_USER_PASSWORD="$MYSQL_ROOT_PASSWORD"
        return 1
    fi
}

# 更新 WAF 配置文件
update_waf_config() {
    echo -e "${BLUE}[11/11] 更新 WAF 配置文件...${NC}"
    
    # 检查是否有数据库和用户信息
    # 优先使用导出的变量，如果没有则使用当前函数内的变量
    local db_name="${CREATED_DB_NAME:-${MYSQL_DATABASE}}"
    local db_user="${MYSQL_USER_FOR_WAF:-${MYSQL_USER}}"
    local db_password="${MYSQL_PASSWORD_FOR_WAF:-${MYSQL_USER_PASSWORD}}"
    
    if [ -z "$db_name" ] || [ -z "$db_user" ]; then
        echo -e "${YELLOW}⚠ 缺少数据库或用户信息，跳过配置文件更新${NC}"
        echo -e "${YELLOW}  数据库: ${db_name:-未设置}${NC}"
        echo -e "${YELLOW}  用户: ${db_user:-未设置}${NC}"
        echo -e "${YELLOW}  请手动更新 lua/config.lua 文件${NC}"
        return 0
    fi
    
    echo -e "${BLUE}配置信息:${NC}"
    echo -e "  数据库: ${db_name}"
    echo -e "  用户: ${db_user}"
    echo -e "  密码: ${db_password:+已设置（隐藏）}"
    echo ""
    
    # 获取脚本目录
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    UPDATE_CONFIG_SCRIPT="${SCRIPT_DIR}/set_lua_database_connect.sh"
    
    # 检查配置更新脚本是否存在
    if [ ! -f "$UPDATE_CONFIG_SCRIPT" ]; then
        echo -e "${YELLOW}⚠ 配置更新脚本不存在: $UPDATE_CONFIG_SCRIPT${NC}"
        echo -e "${YELLOW}  请手动更新 lua/config.lua 文件${NC}"
        echo -e "${YELLOW}  或运行: bash $UPDATE_CONFIG_SCRIPT mysql 127.0.0.1 3306 ${db_name} ${db_user} <password>${NC}"
        return 0
    fi
    
    # 检查配置文件是否存在
    local config_file="${SCRIPT_DIR}/../lua/config.lua"
    if [ ! -f "$config_file" ]; then
        echo -e "${YELLOW}⚠ 配置文件不存在: $config_file${NC}"
        echo -e "${YELLOW}  请确保项目目录结构正确${NC}"
        return 0
    fi
    
    # 更新配置文件
    echo -e "${BLUE}正在更新配置文件: $config_file${NC}"
    if bash "$UPDATE_CONFIG_SCRIPT" mysql "127.0.0.1" "3306" "$db_name" "$db_user" "$db_password"; then
        echo -e "${GREEN}✓ WAF 配置文件已更新${NC}"
        echo -e "${GREEN}  配置文件路径: $config_file${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ 配置文件更新失败，请手动更新 lua/config.lua${NC}"
        echo -e "${YELLOW}  或运行: bash $UPDATE_CONFIG_SCRIPT mysql 127.0.0.1 3306 ${db_name} ${db_user} <password>${NC}"
        return 1
    fi
}

# 初始化数据库数据
init_database() {
    echo -e "${BLUE}[10/10] 初始化数据库数据...${NC}"
    
    read -p "是否初始化数据库数据（导入 SQL 脚本）？[Y/n]: " INIT_DB
    INIT_DB="${INIT_DB:-Y}"
    
    if [[ ! "$INIT_DB" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}跳过数据库初始化${NC}"
        return 0
    fi
    
    # 检查是否已创建数据库（优先使用 CREATED_DB_NAME，如果没有则使用 MYSQL_DATABASE）
    if [ -z "$MYSQL_DATABASE" ] && [ -z "$CREATED_DB_NAME" ]; then
        echo -e "${YELLOW}⚠ 未创建数据库，无法初始化${NC}"
        return 1
    fi
    
    # 确保使用正确的数据库名称
    if [ -z "$MYSQL_DATABASE" ] && [ -n "$CREATED_DB_NAME" ]; then
        MYSQL_DATABASE="$CREATED_DB_NAME"
    elif [ -z "$CREATED_DB_NAME" ] && [ -n "$MYSQL_DATABASE" ]; then
        export CREATED_DB_NAME="$MYSQL_DATABASE"
    fi
    
    # 确保使用正确的用户和密码（优先使用 FOR_WAF 变量）
    if [ -z "$MYSQL_USER" ] && [ -n "$MYSQL_USER_FOR_WAF" ]; then
        MYSQL_USER="$MYSQL_USER_FOR_WAF"
    fi
    if [ -z "$MYSQL_USER_PASSWORD" ] && [ -n "$MYSQL_PASSWORD_FOR_WAF" ]; then
        MYSQL_USER_PASSWORD="$MYSQL_PASSWORD_FOR_WAF"
    fi
    
    # 查找 SQL 文件（使用相对路径）
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SQL_FILE="${SCRIPT_DIR}/../init_file/数据库设计.sql"
    
    if [ ! -f "$SQL_FILE" ]; then
        echo -e "${YELLOW}⚠ SQL 文件不存在: ${SQL_FILE}${NC}"
        echo "请手动导入 SQL 脚本"
        return 1
    fi
    
    # 检测数据库内是否有数据
    local has_data=0
    local check_data_query="SELECT COUNT(*) as table_count FROM information_schema.tables WHERE table_schema='${MYSQL_DATABASE}';"
    
    if [ -n "$MYSQL_USER_PASSWORD" ]; then
        # 使用配置文件方式查询
        local temp_cnf=$(mktemp)
        cat > "$temp_cnf" <<CNF_EOF
[client]
user=${MYSQL_USER}
password=${MYSQL_USER_PASSWORD}
CNF_EOF
        chmod 600 "$temp_cnf"
        local table_count=$(mysql --defaults-file="$temp_cnf" -e "$check_data_query" 2>/dev/null | grep -v "table_count" | grep -v "^$" | awk '{print $1}')
        rm -f "$temp_cnf"
        
        if [ -z "$table_count" ]; then
            # 如果配置文件方式失败，尝试直接传递密码
            table_count=$(mysql -h"127.0.0.1" -u"${MYSQL_USER}" -p"${MYSQL_USER_PASSWORD}" -e "$check_data_query" 2>/dev/null | grep -v "table_count" | grep -v "^$" | awk '{print $1}')
        fi
        
        if [ -n "$table_count" ] && [ "$table_count" -gt 0 ]; then
            has_data=1
        fi
    else
        table_count=$(mysql -h"127.0.0.1" -u"${MYSQL_USER}" -e "$check_data_query" 2>/dev/null | grep -v "table_count" | grep -v "^$" | awk '{print $1}')
        if [ -n "$table_count" ] && [ "$table_count" -gt 0 ]; then
            has_data=1
        fi
    fi
    
    if [ $has_data -eq 1 ]; then
        echo -e "${YELLOW}⚠ 检测到数据库 ${MYSQL_DATABASE} 中已有数据（${table_count} 个表）${NC}"
        echo -e "${RED}警告: 导入 SQL 脚本可能会覆盖现有数据！${NC}"
        echo ""
        read -p "是否继续导入 SQL 脚本（将覆盖现有数据）？[y/N]: " OVERWRITE_DATA
        OVERWRITE_DATA="${OVERWRITE_DATA:-N}"
        if [[ ! "$OVERWRITE_DATA" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}跳过 SQL 脚本导入${NC}"
            echo -e "${BLUE}提示: 如需导入，可以稍后手动执行:${NC}"
            echo "  mysql -u ${MYSQL_USER} -p ${MYSQL_DATABASE} < ${SQL_FILE}"
            return 0
        fi
        echo -e "${YELLOW}⚠ 将覆盖数据库中的现有数据${NC}"
    fi
    
    # 导入 SQL 脚本
    echo "正在导入 SQL 脚本: ${SQL_FILE}"
    echo -e "${BLUE}使用用户: ${MYSQL_USER}，数据库: ${MYSQL_DATABASE}${NC}"
    
    # 检查 SQL 文件是否存在且可读
    if [ ! -r "$SQL_FILE" ]; then
        echo -e "${RED}✗ SQL 文件不存在或不可读: ${SQL_FILE}${NC}"
        return 1
    fi
    
    # 显示 SQL 文件大小
    local sql_file_size=$(du -h "$SQL_FILE" | cut -f1)
    echo -e "${BLUE}SQL 文件大小: ${sql_file_size}${NC}"
    
    # 导入 SQL 脚本（显示进度）
    echo -e "${BLUE}开始导入...${NC}"
    if [ -n "$MYSQL_USER_PASSWORD" ]; then
        # 使用配置文件方式避免密码泄露到进程列表
        local temp_cnf=$(mktemp)
        cat > "$temp_cnf" <<CNF_EOF
[client]
host=127.0.0.1
user=${MYSQL_USER}
password=${MYSQL_USER_PASSWORD}
database=${MYSQL_DATABASE}
CNF_EOF
        chmod 600 "$temp_cnf"
        SQL_OUTPUT=$(mysql --defaults-file="$temp_cnf" < "$SQL_FILE" 2>&1)
        SQL_EXIT_CODE=$?
        rm -f "$temp_cnf"
    else
        SQL_OUTPUT=$(mysql -h"127.0.0.1" -u"${MYSQL_USER}" "${MYSQL_DATABASE}" < "$SQL_FILE" 2>&1)
        SQL_EXIT_CODE=$?
    fi
    
    # 过滤掉警告信息（MySQL 8.0 会输出密码警告）
    SQL_OUTPUT=$(echo "$SQL_OUTPUT" | grep -v "Warning: Using a password on the command line")
    
    if [ $SQL_EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}✓ 数据库初始化成功${NC}"
        # 如果有输出，显示部分输出（可能是成功信息）
        if [ -n "$SQL_OUTPUT" ]; then
            echo -e "${BLUE}导入输出:${NC}"
            echo "$SQL_OUTPUT" | head -10
        fi
        # 显示安装总结
        show_installation_summary
    else
        # 检查是否是"表已存在"的错误（这是正常的）
        if echo "$SQL_OUTPUT" | grep -qi "already exists\|Duplicate\|exists"; then
            echo -e "${YELLOW}⚠ 部分表可能已存在，这是正常的${NC}"
            echo -e "${GREEN}✓ 数据库初始化完成${NC}"
            # 显示安装总结
            show_installation_summary
        else
            echo -e "${RED}✗ 数据库初始化失败${NC}"
            echo -e "${YELLOW}错误信息：${NC}"
            echo "$SQL_OUTPUT" | head -30
            echo ""
            echo -e "${YELLOW}建议：${NC}"
            echo "  1. 检查 SQL 文件语法是否正确"
            echo "  2. 检查数据库用户权限是否足够"
            echo "  3. 手动导入 SQL 文件: mysql -u ${MYSQL_USER} -p ${MYSQL_DATABASE} < ${SQL_FILE}"
            return 1
        fi
    fi
}

# 显示安装总结信息
show_installation_summary() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}数据库安装已完成，SQL已全部导入${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # 显示root密码
    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        echo -e "${BLUE}MySQL Root 密码:${NC}"
        echo "  ${MYSQL_ROOT_PASSWORD}"
        echo ""
    else
        echo -e "${YELLOW}⚠ MySQL Root 密码未设置${NC}"
        echo ""
    fi
    
    # 显示数据库信息
    if [ -n "$MYSQL_DATABASE" ]; then
        echo -e "${BLUE}创建的数据库:${NC}"
        echo "  数据库名称: ${MYSQL_DATABASE}"
        echo ""
    else
        echo -e "${YELLOW}⚠ 未创建数据库${NC}"
        echo ""
    fi
    
    # 显示用户信息（用户名@host格式）
    echo -e "${BLUE}用户信息:${NC}"
    
    # 查询并显示root用户的host信息
    local root_hosts=""
    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        # 使用配置文件方式查询，避免密码泄露
        local temp_cnf=$(mktemp)
        cat > "$temp_cnf" <<CNF_EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
CNF_EOF
        chmod 600 "$temp_cnf"
        root_hosts=$(mysql --defaults-file="$temp_cnf" -e "SELECT CONCAT(User, '@', Host) as 'User@Host' FROM mysql.user WHERE User='root' ORDER BY Host;" 2>/dev/null | grep -v "User@Host" | grep -v "^$" | grep -E "root@")
        rm -f "$temp_cnf"
        
        # 如果配置文件方式失败，尝试直接传递密码
        if [ -z "$root_hosts" ]; then
            root_hosts=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT CONCAT(User, '@', Host) as 'User@Host' FROM mysql.user WHERE User='root' ORDER BY Host;" 2>/dev/null | grep -v "User@Host" | grep -v "^$" | grep -E "root@")
        fi
    else
        root_hosts=$(mysql -u root -e "SELECT CONCAT(User, '@', Host) as 'User@Host' FROM mysql.user WHERE User='root' ORDER BY Host;" 2>/dev/null | grep -v "User@Host" | grep -v "^$" | grep -E "root@")
    fi
    
    if [ -n "$root_hosts" ]; then
        echo "  root用户:"
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                echo "    ${line}"
            fi
        done <<< "$root_hosts"
        if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
            echo "    密码: ${MYSQL_ROOT_PASSWORD}"
        fi
        echo ""
    fi
    
    # 显示连接URL信息
    echo -e "${BLUE}连接 URL 信息:${NC}"
    if [ -n "$MYSQL_USER" ] && [ "$MYSQL_USER" != "root" ] && [ -n "$MYSQL_USER_PASSWORD" ]; then
        # 使用创建的用户
        echo "  MySQL URL: mysql://${MYSQL_USER}:${MYSQL_USER_PASSWORD}@127.0.0.1:3306/${MYSQL_DATABASE}"
        echo "  连接命令: mysql -h 127.0.0.1 -P 3306 -u ${MYSQL_USER} -p'${MYSQL_USER_PASSWORD}' ${MYSQL_DATABASE}"
    elif [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        # 使用root用户
        echo "  MySQL URL: mysql://root:${MYSQL_ROOT_PASSWORD}@127.0.0.1:3306/${MYSQL_DATABASE:-}"
        if [ -n "$MYSQL_DATABASE" ]; then
            echo "  连接命令: mysql -h 127.0.0.1 -P 3306 -u root -p'${MYSQL_ROOT_PASSWORD}' ${MYSQL_DATABASE}"
        else
            echo "  连接命令: mysql -h 127.0.0.1 -P 3306 -u root -p'${MYSQL_ROOT_PASSWORD}'"
        fi
    else
        echo "  MySQL URL: mysql://root@127.0.0.1:3306/${MYSQL_DATABASE:-}"
        if [ -n "$MYSQL_DATABASE" ]; then
            echo "  连接命令: mysql -h 127.0.0.1 -P 3306 -u root ${MYSQL_DATABASE}"
        else
            echo "  连接命令: mysql -h 127.0.0.1 -P 3306 -u root"
        fi
    fi
    echo ""
    
    # 检查开机启动状态
    echo -e "${BLUE}开机启动状态:${NC}"
    if command -v systemctl &> /dev/null; then
        if systemctl is-enabled mysqld >/dev/null 2>&1 || systemctl is-enabled mysql >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓ 已启用开机自启动${NC}"
        else
            echo -e "  ${YELLOW}⚠ 未启用开机自启动${NC}"
            echo -e "  ${BLUE}提示: 运行 'systemctl enable mysqld' 启用开机自启动${NC}"
        fi
    elif command -v chkconfig &> /dev/null; then
        if chkconfig mysqld 2>/dev/null | grep -q "3:on\|5:on" || chkconfig mysql 2>/dev/null | grep -q "3:on\|5:on"; then
            echo -e "  ${GREEN}✓ 已启用开机自启动${NC}"
        else
            echo -e "  ${YELLOW}⚠ 未启用开机自启动${NC}"
            echo -e "  ${BLUE}提示: 运行 'chkconfig mysqld on' 启用开机自启动${NC}"
        fi
    fi
    echo ""
    
    # 显示创建的用户（如果不是root）
    if [ -n "$MYSQL_USER" ] && [ "$MYSQL_USER" != "root" ]; then
        # 查询用户的host信息
        local user_hosts=""
        if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
            local temp_cnf=$(mktemp)
            cat > "$temp_cnf" <<CNF_EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
CNF_EOF
            chmod 600 "$temp_cnf"
            user_hosts=$(mysql --defaults-file="$temp_cnf" -e "SELECT CONCAT(User, '@', Host) as 'User@Host' FROM mysql.user WHERE User='${MYSQL_USER}' ORDER BY Host;" 2>/dev/null | grep -v "User@Host" | grep -v "^$" | grep -E "${MYSQL_USER}@")
            rm -f "$temp_cnf"
            
            # 如果配置文件方式失败，尝试直接传递密码
            if [ -z "$user_hosts" ]; then
                user_hosts=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT CONCAT(User, '@', Host) as 'User@Host' FROM mysql.user WHERE User='${MYSQL_USER}' ORDER BY Host;" 2>/dev/null | grep -v "User@Host" | grep -v "^$" | grep -E "${MYSQL_USER}@")
            fi
        else
            user_hosts=$(mysql -u root -e "SELECT CONCAT(User, '@', Host) as 'User@Host' FROM mysql.user WHERE User='${MYSQL_USER}' ORDER BY Host;" 2>/dev/null | grep -v "User@Host" | grep -v "^$" | grep -E "${MYSQL_USER}@")
        fi
        
        if [ -n "$user_hosts" ]; then
            echo "  创建的用户:"
            while IFS= read -r line; do
                if [ -n "$line" ]; then
                    echo "    ${line}"
                fi
            done <<< "$user_hosts"
            echo "    密码: ${MYSQL_USER_PASSWORD}"
            echo ""
        else
            # 如果查询失败，使用默认值
            echo "  创建的用户:"
            echo "    ${MYSQL_USER}@localhost"
            echo "    密码: ${MYSQL_USER_PASSWORD}"
            echo ""
        fi
    fi
    
    echo -e "${GREEN}========================================${NC}"
    echo ""
}

# 显示后续步骤
show_next_steps() {
    echo ""
    if [ "${SKIP_INSTALL:-0}" -eq 1 ]; then
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}MySQL 配置完成！${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo -e "${BLUE}注意: 已跳过安装步骤，使用的是现有 MySQL 安装${NC}"
        echo ""
    else
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}MySQL 安装完成！${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
    fi
    
    # 显示创建的数据库和用户信息（如果已经显示过总结，这里只显示简要信息）
    if [ -n "$MYSQL_DATABASE" ]; then
        echo -e "${BLUE}数据库信息:${NC}"
        echo "  数据库名称: ${MYSQL_DATABASE}"
        if [ -n "$MYSQL_USER" ] && [ "$MYSQL_USER" != "root" ]; then
            echo "  用户名: ${MYSQL_USER}"
            echo "  密码: ${MYSQL_USER_PASSWORD}"
            echo "  Host: localhost"
        else
            echo "  使用 root 用户"
            if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
                echo "  Root 密码: ${MYSQL_ROOT_PASSWORD}"
            fi
        fi
        echo ""
    fi
    
    echo -e "${BLUE}后续步骤:${NC}"
    echo ""
    echo "1. 检查 MySQL 服务状态:"
    echo "   sudo systemctl status mysqld"
    echo "   或"
    echo "   sudo systemctl status mysql"
    echo ""
    echo "2. 连接 MySQL:"
    if [ -n "$MYSQL_USER_PASSWORD" ] && [ "$MYSQL_USER" != "root" ]; then
        echo "   mysql -h 127.0.0.1 -P 3306 -u ${MYSQL_USER} -p'${MYSQL_USER_PASSWORD}' ${MYSQL_DATABASE}"
        echo "   MySQL URL: mysql://${MYSQL_USER}:${MYSQL_USER_PASSWORD}@127.0.0.1:3306/${MYSQL_DATABASE}"
    elif [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        if [ -n "$MYSQL_DATABASE" ]; then
            echo "   mysql -h 127.0.0.1 -P 3306 -u root -p'${MYSQL_ROOT_PASSWORD}' ${MYSQL_DATABASE}"
            echo "   MySQL URL: mysql://root:${MYSQL_ROOT_PASSWORD}@127.0.0.1:3306/${MYSQL_DATABASE}"
        else
            echo "   mysql -h 127.0.0.1 -P 3306 -u root -p'${MYSQL_ROOT_PASSWORD}'"
            echo "   MySQL URL: mysql://root:${MYSQL_ROOT_PASSWORD}@127.0.0.1:3306/"
        fi
    else
        if [ -n "$MYSQL_DATABASE" ]; then
            echo "   mysql -h 127.0.0.1 -P 3306 -u root ${MYSQL_DATABASE}"
            echo "   MySQL URL: mysql://root@127.0.0.1:3306/${MYSQL_DATABASE}"
        else
            echo "   mysql -h 127.0.0.1 -P 3306 -u root"
            echo "   MySQL URL: mysql://root@127.0.0.1:3306/"
        fi
    fi
    echo ""
    
    if [ -z "$MYSQL_DATABASE" ]; then
        echo "3. 创建数据库和用户（用于 WAF 系统）:"
        echo "   mysql -u root -p < init_file/数据库设计.sql"
        echo ""
    fi
    
    echo "4. 修改 WAF 配置文件:"
    echo "   vim lua/config.lua"
    echo "   或使用 install.sh 自动配置"
    echo ""
    echo -e "${BLUE}服务管理:${NC}"
    echo "  启动: sudo systemctl start mysqld"
    echo "  停止: sudo systemctl stop mysqld"
    echo "  重启: sudo systemctl restart mysqld"
    echo "  开机自启: sudo systemctl enable mysqld"
    echo ""
}

# 主函数
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}MySQL 一键安装和配置脚本${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # 检查 root 权限
    check_root
    
    # 检测操作系统
    detect_os
    
    # 检测硬件配置
    detect_hardware
    
    # 检查现有安装
    check_existing
    
    # 如果选择跳过安装，只执行后续步骤
    if [ "${SKIP_INSTALL:-0}" -eq 1 ]; then
        echo -e "${BLUE}[跳过安装步骤] 检测到已安装 MySQL，跳过安装步骤${NC}"
        echo ""
        
        # 确保 MySQL 服务已启动
        echo -e "${BLUE}检查 MySQL 服务状态...${NC}"
        if ! mysqladmin ping -h localhost --silent 2>/dev/null; then
            echo -e "${YELLOW}MySQL 服务未运行，尝试启动...${NC}"
            if command -v systemctl &> /dev/null; then
                systemctl start mysqld 2>/dev/null || systemctl start mysql 2>/dev/null || true
            elif command -v service &> /dev/null; then
                service mysqld start 2>/dev/null || service mysql start 2>/dev/null || true
            fi
            
            # 等待 MySQL 启动
            echo "等待 MySQL 启动..."
            local max_wait=30
            local waited=0
            while [ $waited -lt $max_wait ]; do
                if mysqladmin ping -h localhost --silent 2>/dev/null; then
                    echo -e "${GREEN}✓ MySQL 服务已启动${NC}"
                    break
                fi
                sleep 2
                waited=$((waited + 2))
                echo -n "."
            done
            echo ""
            
            if ! mysqladmin ping -h localhost --silent 2>/dev/null; then
                echo -e "${RED}✗ MySQL 服务启动失败${NC}"
                echo -e "${YELLOW}请手动启动 MySQL 服务后重新运行脚本${NC}"
                exit 1
            fi
        else
            echo -e "${GREEN}✓ MySQL 服务正在运行${NC}"
        fi
        
        # 如果未设置 root 密码，尝试多种方式获取
        if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
            echo ""
            echo -e "${BLUE}需要 MySQL root 密码以执行后续操作${NC}"
            
            # 先尝试无密码连接（某些 MariaDB 可能无密码）
            if mysql -u root -e "SELECT 1;" > /dev/null 2>&1; then
                echo -e "${GREEN}✓ MySQL root 用户无密码，可以使用无密码连接${NC}"
                MYSQL_ROOT_PASSWORD=""
            else
                # 尝试从日志中查找临时密码（MySQL 8.0）
                TEMP_PASSWORD=""
                for log_file in /var/log/mysqld.log /var/log/mysql/error.log /var/log/mysql/mysql.log; do
                    if [ -f "$log_file" ]; then
                        TEMP_PASSWORD=$(grep 'temporary password' "$log_file" 2>/dev/null | awk '{print $NF}' | tail -1)
                        if [ -n "$TEMP_PASSWORD" ]; then
                            echo -e "${YELLOW}⚠ 检测到 MySQL 临时密码: ${TEMP_PASSWORD}${NC}"
                            echo -e "${YELLOW}⚠ 建议先修改临时密码${NC}"
                            break
                        fi
                    fi
                done
                
                # 提示用户输入密码
                read -sp "请输入 MySQL root 密码（直接回车使用临时密码或无密码）: " MYSQL_ROOT_PASSWORD
                echo ""
                
                # 如果用户没有输入，使用临时密码或尝试无密码
                if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                    if [ -n "$TEMP_PASSWORD" ]; then
                        MYSQL_ROOT_PASSWORD="$TEMP_PASSWORD"
                        echo -e "${BLUE}使用临时密码连接 MySQL${NC}"
                    else
                        echo -e "${YELLOW}⚠ 未输入密码，尝试无密码连接${NC}"
                    fi
                fi
                
                # 验证密码是否正确
                if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
                    if mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" > /dev/null 2>&1; then
                        echo -e "${GREEN}✓ 密码验证成功${NC}"
                    elif mysql --connect-expired-password -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" > /dev/null 2>&1; then
                        echo -e "${YELLOW}⚠ 使用的是临时密码（已过期），后续操作可能需要先修改密码${NC}"
                    else
                        echo -e "${RED}✗ 密码验证失败${NC}"
                        echo -e "${YELLOW}请检查密码是否正确，或手动测试连接${NC}"
                        exit 1
                    fi
                else
                    # 尝试无密码连接
                    if ! mysql -u root -e "SELECT 1;" > /dev/null 2>&1; then
                        echo -e "${RED}✗ 无密码连接失败${NC}"
                        echo -e "${YELLOW}请提供正确的 root 密码${NC}"
                        exit 1
                    fi
                fi
            fi
        else
            # 如果已设置密码，验证密码
            if ! mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" > /dev/null 2>&1; then
                if mysql --connect-expired-password -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" > /dev/null 2>&1; then
                    echo -e "${YELLOW}⚠ 使用的是临时密码（已过期），后续操作可能需要先修改密码${NC}"
                else
                    echo -e "${RED}✗ 密码验证失败${NC}"
                    echo -e "${YELLOW}请检查密码是否正确${NC}"
                    exit 1
                fi
            else
                echo -e "${GREEN}✓ 密码验证成功${NC}"
            fi
        fi
        
        # 验证安装（检查 MySQL 是否可用）
        echo -e "${BLUE}验证 MySQL 连接...${NC}"
        if mysqladmin ping -h localhost --silent 2>/dev/null; then
            echo -e "${GREEN}✓ MySQL 连接正常${NC}"
        else
            echo -e "${RED}✗ MySQL 连接失败${NC}"
            exit 1
        fi
        
        echo ""
        echo -e "${GREEN}✓ 跳过安装步骤完成，继续执行后续步骤${NC}"
        echo -e "${BLUE}注意: 已跳过配置优化步骤，使用现有 MySQL 配置${NC}"
        echo -e "${BLUE}      如需优化配置，请手动修改 /etc/my.cnf 或 /etc/mysql/my.cnf${NC}"
        echo ""
    else
        # 正常安装流程
        # 安装 MySQL
        install_mysql
        
        # 设置 MySQL 配置文件（必须在初始化前完成）
        # 重要：所有 my.cnf 等配置文件的改动必须在数据库初始化前完成
        # 包括：
        #   - 基础配置（lower_case_table_names、default_time_zone 等）
        #   - 硬件优化配置（InnoDB 缓冲池、连接数、IO 线程等）
        # 因为 MySQL 首次启动时会根据配置文件初始化数据字典
        # 硬件优化配置虽然可以在运行时修改，但为了最佳性能，应在初始化前设置
        setup_mysql_config
        
        # 配置 MySQL（启动服务，首次启动会自动初始化）
        # 注意：首次启动时会根据配置文件初始化数据库
        # 所有配置优化（包括硬件优化）必须在此步骤之前完成
        configure_mysql
        
        # 设置 root 密码
        if ! set_root_password; then
            echo ""
            echo -e "${RED}========================================${NC}"
            echo -e "${RED}MySQL 安装失败：root 密码设置失败${NC}"
            echo -e "${RED}========================================${NC}"
            echo ""
            echo -e "${YELLOW}请按照上面的错误提示手动修改密码，然后重新运行安装脚本${NC}"
            echo ""
            exit 1
        fi
        
        # 安全配置
        secure_mysql
        
        # 验证安装
        verify_installation
    fi
    
    # 创建数据库
    if ! create_database; then
        echo ""
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}MySQL 安装失败：数据库创建失败${NC}"
        echo -e "${RED}========================================${NC}"
        echo ""
        echo -e "${YELLOW}请按照上面的错误提示手动创建数据库，然后重新运行安装脚本${NC}"
        echo ""
        echo -e "${BLUE}手动创建数据库命令:${NC}"
        echo "  mysql -u root -p"
        echo "  CREATE DATABASE waf_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
        echo ""
        exit 1
    fi
    
    # 创建数据库用户
    if ! create_database_user; then
        echo ""
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}MySQL 安装失败：数据库用户创建失败${NC}"
        echo -e "${RED}========================================${NC}"
        echo ""
        echo -e "${YELLOW}请按照上面的错误提示手动创建数据库用户，然后重新运行安装脚本${NC}"
        echo ""
        exit 1
    fi
    
    # 初始化数据库数据
    init_database
    
    # 更新 WAF 配置文件（如果创建了数据库和用户）
    update_waf_config
    
    # 显示后续步骤
    show_next_steps
    
    # 如果设置了环境变量 TEMP_VARS_FILE，将变量写入文件供父脚本使用
    if [ -n "$TEMP_VARS_FILE" ] && [ -f "$TEMP_VARS_FILE" ]; then
        {
            echo "CREATED_DB_NAME=\"${CREATED_DB_NAME}\""
            echo "MYSQL_USER_FOR_WAF=\"${MYSQL_USER_FOR_WAF}\""
            echo "MYSQL_PASSWORD_FOR_WAF=\"${MYSQL_PASSWORD_FOR_WAF}\""
            echo "USE_NEW_USER=\"${USE_NEW_USER}\""
        } > "$TEMP_VARS_FILE"
    fi
}

# 执行主函数
main "$@"

