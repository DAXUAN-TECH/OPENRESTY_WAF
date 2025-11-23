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
MYSQL_VERSION="${MYSQL_VERSION:-8.0}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"
MYSQL_DATABASE=""
MYSQL_USER=""
MYSQL_USER_PASSWORD=""
USE_NEW_USER="N"

# 导出变量供父脚本使用
export CREATED_DB_NAME=""
export MYSQL_USER_FOR_WAF=""
export MYSQL_PASSWORD_FOR_WAF=""
export USE_NEW_USER

# 检测系统类型
detect_os() {
    echo -e "${BLUE}[1/7] 检测操作系统...${NC}"
    
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

# 检查 MySQL 是否已安装
check_existing() {
    echo -e "${BLUE}[2/7] 检查是否已安装 MySQL...${NC}"
    
    if command -v mysql &> /dev/null || command -v mysqld &> /dev/null; then
        local mysql_version=$(mysql --version 2>/dev/null || mysqld --version 2>/dev/null | head -n 1)
        echo -e "${YELLOW}检测到已安装 MySQL: ${mysql_version}${NC}"
        read -p "是否继续安装/更新？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}安装已取消${NC}"
            exit 0
        fi
    fi
    
    echo -e "${GREEN}✓ 检查完成${NC}"
}

# 安装 MySQL（CentOS/RHEL/Fedora/Rocky/AlmaLinux/Oracle Linux/Amazon Linux）
install_mysql_redhat() {
    echo -e "${BLUE}[3/7] 安装 MySQL（RedHat 系列）...${NC}"
    
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
    
    # 安装 MySQL 仓库（MySQL 8.0）
    if [ ! -f /etc/yum.repos.d/mysql-community.repo ]; then
        echo "添加 MySQL 官方仓库..."
        
        # 下载 MySQL Yum Repository
        local repo_downloaded=0
        
        # 尝试下载对应版本的仓库
        for el_ver in $el_version el8 el7; do
            if wget -q "https://dev.mysql.com/get/mysql80-community-release-${el_ver}-1.noarch.rpm" -O /tmp/mysql80-community-release.rpm 2>/dev/null && [ -s /tmp/mysql80-community-release.rpm ]; then
                repo_downloaded=1
                break
            fi
        done
        
        if [ $repo_downloaded -eq 0 ]; then
            echo -e "${YELLOW}⚠ 无法下载 MySQL 仓库，尝试使用系统仓库${NC}"
        fi
        
        if [ -f /tmp/mysql80-community-release.rpm ]; then
            # 尝试导入 GPG 密钥
            rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2022 2>/dev/null || \
            rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql 2>/dev/null || \
            echo -e "${YELLOW}⚠ GPG 密钥导入失败，将禁用 GPG 检查${NC}"
            
            # 安装仓库
            if rpm -ivh /tmp/mysql80-community-release.rpm 2>&1; then
                # 如果 GPG 检查失败，禁用 GPG 检查
                if ! yum install -y mysql-server 2>&1 | grep -q "GPG"; then
                    : # 安装成功
                else
                    echo -e "${YELLOW}⚠ 检测到 GPG 问题，禁用 GPG 检查${NC}"
                    sed -i 's/gpgcheck=1/gpgcheck=0/' /etc/yum.repos.d/mysql-community*.repo 2>/dev/null || true
                fi
            fi
            rm -f /tmp/mysql80-community-release.rpm
        fi
    fi
    
    # 安装 MySQL
    INSTALL_SUCCESS=0
    
    if command -v dnf &> /dev/null; then
        if dnf install -y mysql-server mysql 2>&1; then
            INSTALL_SUCCESS=1
        fi
    else
        if yum install -y mysql-server mysql 2>&1; then
            INSTALL_SUCCESS=1
        fi
    fi
    
    # 如果 MySQL 安装失败，尝试安装 MariaDB（MySQL 兼容）
    if [ $INSTALL_SUCCESS -eq 0 ]; then
        echo -e "${YELLOW}⚠ MySQL 安装失败，尝试安装 MariaDB（MySQL 兼容）...${NC}"
        if command -v dnf &> /dev/null; then
            if dnf install -y mariadb-server mariadb 2>&1; then
                INSTALL_SUCCESS=1
                echo -e "${GREEN}✓ MariaDB 安装完成（MySQL 兼容）${NC}"
            fi
        else
            if yum install -y mariadb-server mariadb 2>&1; then
                INSTALL_SUCCESS=1
                echo -e "${GREEN}✓ MariaDB 安装完成（MySQL 兼容）${NC}"
            fi
        fi
    fi
    
    if [ $INSTALL_SUCCESS -eq 0 ]; then
        echo -e "${RED}✗ MySQL/MariaDB 安装失败${NC}"
        echo -e "${YELLOW}请检查错误信息并手动安装${NC}"
        exit 1
    else
        echo -e "${GREEN}✓ MySQL/MariaDB 安装完成${NC}"
    fi
}

# 安装 MySQL（Ubuntu/Debian/Linux Mint/Kali Linux）
install_mysql_debian() {
    echo -e "${BLUE}[3/7] 安装 MySQL（Debian 系列）...${NC}"
    
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
    
    # 安装 MySQL
    if DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server mysql-client 2>&1; then
        echo -e "${GREEN}✓ MySQL 安装完成${NC}"
    else
        echo -e "${YELLOW}⚠ 包管理器安装失败，请检查错误信息${NC}"
        exit 1
    fi
}

# 安装 MySQL（openSUSE）
install_mysql_suse() {
    echo -e "${BLUE}[3/7] 安装 MySQL（openSUSE）...${NC}"
    
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
    echo -e "${BLUE}[3/7] 安装 MySQL（Arch Linux）...${NC}"
    
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
    echo -e "${BLUE}[3/7] 安装 MySQL（Alpine Linux）...${NC}"
    
    # Alpine Linux 使用 MariaDB（MySQL 兼容）
    apk add --no-cache mariadb mariadb-client mariadb-server-utils
    
    echo -e "${GREEN}✓ MariaDB 安装完成（MySQL 兼容）${NC}"
}

# 安装 MySQL（Gentoo）
install_mysql_gentoo() {
    echo -e "${BLUE}[3/7] 安装 MySQL（Gentoo）...${NC}"
    
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

# 配置 MySQL
configure_mysql() {
    echo -e "${BLUE}[4/7] 配置 MySQL...${NC}"
    
    # 启动 MySQL 服务
    if command -v systemctl &> /dev/null; then
        systemctl enable mysqld 2>/dev/null || systemctl enable mysql 2>/dev/null || true
        systemctl start mysqld 2>/dev/null || systemctl start mysql 2>/dev/null || true
    elif command -v service &> /dev/null; then
        service mysql start 2>/dev/null || service mysqld start 2>/dev/null || true
        chkconfig mysql on 2>/dev/null || chkconfig mysqld on 2>/dev/null || true
    fi
    
    # 等待 MySQL 启动并检查服务状态
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
    
    # 额外等待几秒确保 MySQL 完全就绪
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        sleep 3
    else
        echo -e "${YELLOW}⚠ MySQL 服务可能还在启动中，继续等待...${NC}"
        sleep 5
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
    echo -e "${BLUE}[5/7] 设置 MySQL root 密码...${NC}"
    
    # 如果检测到临时密码，主动提示用户设置密码
    if [ -z "$MYSQL_ROOT_PASSWORD" ] && [ -n "$TEMP_PASSWORD" ]; then
        echo -e "${YELLOW}检测到 MySQL 临时密码，建议立即修改 root 密码${NC}"
        echo -e "${YELLOW}临时密码: ${TEMP_PASSWORD}${NC}"
        echo ""
        read -p "是否现在设置 root 密码？[Y/n]: " SET_PASSWORD
        SET_PASSWORD="${SET_PASSWORD:-Y}"
        if [[ "$SET_PASSWORD" =~ ^[Yy]$ ]]; then
            read -sp "请输入新的 MySQL root 密码: " MYSQL_ROOT_PASSWORD
            echo ""
            if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                echo -e "${RED}错误: 密码不能为空${NC}"
                echo -e "${YELLOW}跳过 root 密码设置${NC}"
                return 0
            fi
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
            # 创建临时配置文件用于传递临时密码（避免特殊字符问题）
            local temp_cnf=$(mktemp)
            cat > "$temp_cnf" <<CNF_EOF
[client]
user=root
password=${TEMP_PASSWORD}
CNF_EOF
            chmod 600 "$temp_cnf"
            
            # 使用临时配置文件连接并修改密码（MySQL 8.0 必须使用 --connect-expired-password）
            # 使用 Python 安全地生成 SQL（转义单引号，避免 SQL 注入和 shell 解析问题）
            local sql_file=$(mktemp)
            if command -v python3 &> /dev/null; then
                # 使用 Python 安全地转义密码并生成 SQL
                NEW_MYSQL_PASSWORD="$MYSQL_ROOT_PASSWORD" python3 <<'PYTHON_EOF' > "$sql_file"
import os
import sys
new_password = os.environ.get('NEW_MYSQL_PASSWORD', '')
# 转义 SQL 中的单引号（将 ' 替换为 ''）
escaped_password = new_password.replace("'", "''")
# 生成修改所有 root 用户密码的 SQL
sql = f"""ALTER USER 'root'@'localhost' IDENTIFIED BY '{escaped_password}';
ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '{escaped_password}';
ALTER USER 'root'@'::1' IDENTIFIED BY '{escaped_password}';
FLUSH PRIVILEGES;"""
print(sql)
PYTHON_EOF
            else
                # 如果没有 Python，使用 sed 转义单引号
                local escaped_password=$(echo "$MYSQL_ROOT_PASSWORD" | sed "s/'/''/g")
                cat > "$sql_file" <<SQL_EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${escaped_password}';
ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '${escaped_password}';
ALTER USER 'root'@'::1' IDENTIFIED BY '${escaped_password}';
FLUSH PRIVILEGES;
SQL_EOF
            fi
            
            # 使用 SQL 文件执行密码修改（避免 heredoc 中的 shell 解析问题）
            local error_output=$(mysql --connect-expired-password --defaults-file="$temp_cnf" < "$sql_file" 2>&1)
            local exit_code=$?
            
            # 检查错误输出中是否包含真正的错误（不仅仅是警告）
            local has_error=0
            if [ $exit_code -ne 0 ]; then
                has_error=1
            elif echo "$error_output" | grep -qiE "error|failed|denied|syntax" && ! echo "$error_output" | grep -qi "Warning: Using a password"; then
                has_error=1
            fi
            
            rm -f "$sql_file"
            
            # 清理临时配置文件
            rm -f "$temp_cnf"
            
            if [ $has_error -eq 0 ]; then
                echo -e "${GREEN}✓ root 密码修改命令执行成功${NC}"
                # 等待一下让密码生效
                sleep 2
                
                # 刷新权限已在上面执行，无需再次执行
                
                # 验证新密码是否生效（使用配置文件方式，避免特殊字符问题）
                echo "验证新密码..."
                local verify_cnf=$(mktemp)
                cat > "$verify_cnf" <<CNF_EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
CNF_EOF
                chmod 600 "$verify_cnf"
                
                local verify_output=$(mysql --defaults-file="$verify_cnf" -e "SELECT 1;" 2>&1)
                local verify_exit_code=$?
                rm -f "$verify_cnf"
                
                if [ $verify_exit_code -eq 0 ]; then
                    echo -e "${GREEN}✓ 新密码验证成功${NC}"
                    return 0
                else
                    # 如果验证失败，尝试使用临时密码再次验证密码是否真的修改了
                    echo -e "${YELLOW}⚠ 新密码验证失败，尝试使用临时密码验证...${NC}"
                    local temp_verify_cnf=$(mktemp)
                    cat > "$temp_verify_cnf" <<CNF_EOF
[client]
user=root
password=${TEMP_PASSWORD}
CNF_EOF
                    chmod 600 "$temp_verify_cnf"
                    
                    local temp_verify=$(mysql --connect-expired-password --defaults-file="$temp_verify_cnf" -e "SELECT 1;" 2>&1)
                    local temp_verify_exit_code=$?
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
                        return 0
                    else
                        echo -e "${RED}✗ 密码修改可能未生效${NC}"
                        echo -e "${YELLOW}验证错误: $verify_output${NC}"
                        echo -e "${YELLOW}临时密码验证结果: $temp_verify${NC}"
                        return 1
                    fi
                fi
            else
                echo -e "${RED}✗ 使用临时密码修改密码失败${NC}"
                echo -e "${YELLOW}错误信息:${NC}"
                echo "$error_output" | grep -v "Warning: Using a password" || echo "$error_output"
                echo ""
                echo -e "${YELLOW}可能的原因:${NC}"
                echo "  1. MySQL 服务未完全启动"
                echo "  2. 临时密码已过期或无效"
                echo "  3. 临时密码不正确"
                echo "  4. 新密码包含特殊字符导致 SQL 执行失败"
                echo ""
                echo -e "${YELLOW}建议:${NC}"
                echo "  1. 检查 MySQL 服务状态: systemctl status mysqld"
                echo "  2. 检查 MySQL 日志: tail -f /var/log/mysqld.log"
                echo "  3. 手动修改密码（推荐）:"
                echo "     mysql --connect-expired-password -u root -p'${TEMP_PASSWORD}'"
                echo "     # 然后在 MySQL 中执行:"
                echo "     ALTER USER 'root'@'localhost' IDENTIFIED BY 'your_new_password';"
                echo "     ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY 'your_new_password';"
                echo "     ALTER USER 'root'@'::1' IDENTIFIED BY 'your_new_password';"
                echo "     FLUSH PRIVILEGES;"
                echo ""
                read -p "是否继续尝试其他方式？[y/N]: " CONTINUE_TRY
                if [[ ! "$CONTINUE_TRY" =~ ^[Yy]$ ]]; then
                    # 清除错误的密码，让后续步骤重新提示输入
                    MYSQL_ROOT_PASSWORD=""
                    return 1
                fi
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
}

# 配置安全设置（可选）
secure_mysql() {
    echo -e "${BLUE}[6/7] 配置 MySQL 安全设置...${NC}"
    
    read -p "是否运行 mysql_secure_installation？（推荐）[Y/n]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
            # 先验证密码是否有效（使用配置文件方式，避免特殊字符问题）
            echo "验证 root 密码..."
            local verify_cnf=$(mktemp)
            cat > "$verify_cnf" <<CNF_EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
CNF_EOF
            chmod 600 "$verify_cnf"
            
            local verify_output=$(mysql --defaults-file="$verify_cnf" -e "SELECT 1;" 2>&1)
            local verify_exit_code=$?
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
                    # 重新验证
                    verify_cnf=$(mktemp)
                    cat > "$verify_cnf" <<CNF_EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
CNF_EOF
                    chmod 600 "$verify_cnf"
                    verify_output=$(mysql --defaults-file="$verify_cnf" -e "SELECT 1;" 2>&1)
                    verify_exit_code=$?
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
                # 非交互式运行 mysql_secure_installation（使用配置文件方式，避免特殊字符问题）
                echo "执行安全配置..."
                local secure_cnf=$(mktemp)
                cat > "$secure_cnf" <<CNF_EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
CNF_EOF
                chmod 600 "$secure_cnf"
                
                local secure_output=$(mysql --defaults-file="$secure_cnf" <<EOF 2>&1
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
)
                local secure_exit_code=$?
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
    echo -e "${BLUE}[7/7] 验证安装...${NC}"
    
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
    
    # 创建数据库
    echo "正在创建数据库 ${DB_NAME}..."
    local db_create_output=""
    local db_create_exit_code=0
    
    # 尝试连接并创建数据库（支持临时密码和特殊字符密码）
    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        # 首先验证密码是否有效（使用配置文件方式，避免特殊字符问题）
        local verify_cnf=$(mktemp)
        cat > "$verify_cnf" <<CNF_EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
CNF_EOF
        chmod 600 "$verify_cnf"
        
        # 验证密码
        local verify_output=$(mysql --defaults-file="$verify_cnf" -e "SELECT 1;" 2>&1)
        local verify_exit_code=$?
        
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
                # 重新验证
                verify_output=$(mysql --defaults-file="$verify_cnf" -e "SELECT 1;" 2>&1)
                verify_exit_code=$?
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
        
        # 使用配置文件方式创建数据库（避免特殊字符问题）
        db_create_output=$(mysql --defaults-file="$verify_cnf" <<EOF 2>&1
CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
EOF
)
        db_create_exit_code=$?
        
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

# 初始化数据库数据
init_database() {
    echo -e "${BLUE}[10/10] 初始化数据库数据...${NC}"
    
    read -p "是否初始化数据库数据（导入 SQL 脚本）？[Y/n]: " INIT_DB
    INIT_DB="${INIT_DB:-Y}"
    
    if [[ ! "$INIT_DB" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}跳过数据库初始化${NC}"
        return 0
    fi
    
    # 检查是否已创建数据库
    if [ -z "$MYSQL_DATABASE" ]; then
        echo -e "${YELLOW}⚠ 未创建数据库，无法初始化${NC}"
        return 1
    fi
    
    # 查找 SQL 文件
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    SQL_FILE="${PROJECT_ROOT}/init_file/数据库设计.sql"
    
    if [ ! -f "$SQL_FILE" ]; then
        echo -e "${YELLOW}⚠ SQL 文件不存在: ${SQL_FILE}${NC}"
        echo "请手动导入 SQL 脚本"
        return 1
    fi
    
    # 导入 SQL 脚本
    echo "正在导入 SQL 脚本: ${SQL_FILE}"
    if [ -n "$MYSQL_USER_PASSWORD" ]; then
        SQL_OUTPUT=$(mysql -h"127.0.0.1" -u"${MYSQL_USER}" -p"${MYSQL_USER_PASSWORD}" "${MYSQL_DATABASE}" < "$SQL_FILE" 2>&1)
    else
        SQL_OUTPUT=$(mysql -h"127.0.0.1" -u"${MYSQL_USER}" "${MYSQL_DATABASE}" < "$SQL_FILE" 2>&1)
    fi
    
    SQL_EXIT_CODE=$?
    
    if [ $SQL_EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}✓ 数据库初始化成功${NC}"
    else
        # 检查是否是"表已存在"的错误（这是正常的）
        if echo "$SQL_OUTPUT" | grep -qi "already exists\|Duplicate\|exists"; then
            echo -e "${YELLOW}⚠ 部分表可能已存在，这是正常的${NC}"
            echo -e "${GREEN}✓ 数据库初始化完成${NC}"
        else
            echo -e "${YELLOW}⚠ 数据库初始化可能有问题，请检查错误信息${NC}"
            echo "错误信息："
            echo "$SQL_OUTPUT" | head -20
        fi
    fi
}

# 显示后续步骤
show_next_steps() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}MySQL 安装完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # 显示创建的数据库和用户信息
    if [ -n "$MYSQL_DATABASE" ]; then
        echo -e "${BLUE}数据库信息:${NC}"
        echo "  数据库名称: ${MYSQL_DATABASE}"
        if [ -n "$MYSQL_USER" ] && [ "$MYSQL_USER" != "root" ]; then
            echo "  用户名: ${MYSQL_USER}"
            echo "  密码: ${MYSQL_USER_PASSWORD}"
        else
            echo "  使用 root 用户"
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
        echo "   mysql -u ${MYSQL_USER} -p'${MYSQL_USER_PASSWORD}' ${MYSQL_DATABASE}"
    elif [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        echo "   mysql -u root -p'${MYSQL_ROOT_PASSWORD}'"
    else
        echo "   mysql -u root -p"
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
    
    # 检查现有安装
    check_existing
    
    # 安装 MySQL
    install_mysql
    
    # 配置 MySQL
    configure_mysql
    
    # 设置 root 密码
    set_root_password
    
    # 安全配置
    secure_mysql
    
    # 验证安装
    verify_installation
    
    # 创建数据库
    create_database
    
    # 创建数据库用户
    create_database_user
    
    # 初始化数据库数据
    init_database
    
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

