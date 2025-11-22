#!/bin/bash

# MySQL 一键安装和配置脚本
# 支持：CentOS/RHEL, Ubuntu/Debian, Fedora, openSUSE, Arch Linux
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

# 检测系统类型
detect_os() {
    echo -e "${BLUE}[1/7] 检测操作系统...${NC}"
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
        OS_VERSION=$(cat /etc/redhat-release | sed 's/.*release \([0-9.]*\).*/\1/')
    elif [ -f /etc/debian_version ]; then
        OS="debian"
        OS_VERSION=$(cat /etc/debian_version)
    else
        echo -e "${RED}错误: 无法检测操作系统类型${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ 检测到系统: ${OS} ${OS_VERSION}${NC}"
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

# 安装 MySQL（CentOS/RHEL/Fedora）
install_mysql_redhat() {
    echo -e "${BLUE}[3/7] 安装 MySQL（RedHat 系列）...${NC}"
    
    # 安装 MySQL 仓库（MySQL 8.0）
    if [ ! -f /etc/yum.repos.d/mysql-community.repo ]; then
        echo "添加 MySQL 官方仓库..."
        
        # 下载 MySQL Yum Repository
        if command -v dnf &> /dev/null; then
            # Fedora/RHEL 8+
            wget -q https://dev.mysql.com/get/mysql80-community-release-el8-1.noarch.rpm -O /tmp/mysql80-community-release.rpm 2>/dev/null || \
            wget -q https://dev.mysql.com/get/mysql80-community-release-el7-7.noarch.rpm -O /tmp/mysql80-community-release.rpm 2>/dev/null || \
            echo -e "${YELLOW}⚠ 无法下载 MySQL 仓库，尝试使用系统仓库${NC}"
        else
            # CentOS/RHEL 7
            wget -q https://dev.mysql.com/get/mysql80-community-release-el7-7.noarch.rpm -O /tmp/mysql80-community-release.rpm 2>/dev/null || \
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
    if command -v dnf &> /dev/null; then
        dnf install -y mysql-server mysql || yum install -y mysql-server mysql
    else
        yum install -y mysql-server mysql
    fi
    
    echo -e "${GREEN}✓ MySQL 安装完成${NC}"
}

# 安装 MySQL（Ubuntu/Debian）
install_mysql_debian() {
    echo -e "${BLUE}[3/7] 安装 MySQL（Debian 系列）...${NC}"
    
    # 更新包列表
    apt-get update
    
    # 安装 MySQL（使用系统仓库，通常包含 MySQL 8.0）
    DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server mysql-client
    
    echo -e "${GREEN}✓ MySQL 安装完成${NC}"
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

# 安装 MySQL（Arch Linux）
install_mysql_arch() {
    echo -e "${BLUE}[3/7] 安装 MySQL（Arch Linux）...${NC}"
    
    # Arch Linux 使用 AUR 或系统仓库
    if command -v yay &> /dev/null; then
        yay -S --noconfirm mysql
    else
        # 尝试使用 pacman（可能需要启用 AUR）
        pacman -S --noconfirm mysql || {
            echo -e "${YELLOW}⚠ 需要从 AUR 安装，请安装 yay 或手动安装${NC}"
            exit 1
        }
    fi
    
    echo -e "${GREEN}✓ MySQL 安装完成${NC}"
}

# 安装 MySQL
install_mysql() {
    case $OS in
        centos|rhel|fedora|rocky|almalinux)
            install_mysql_redhat
            ;;
        ubuntu|debian)
            install_mysql_debian
            ;;
        opensuse*|sles)
            install_mysql_suse
            ;;
        arch|manjaro)
            install_mysql_arch
            ;;
        *)
            echo -e "${YELLOW}警告: 未识别的系统类型，尝试使用通用方法${NC}"
            if command -v yum &> /dev/null; then
                install_mysql_redhat
            elif command -v apt-get &> /dev/null; then
                install_mysql_debian
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
    
    # 等待 MySQL 启动
    echo "等待 MySQL 启动..."
    sleep 5
    
    # 获取临时 root 密码（MySQL 8.0）
    TEMP_PASSWORD=""
    if [ -f /var/log/mysqld.log ]; then
        TEMP_PASSWORD=$(grep 'temporary password' /var/log/mysqld.log 2>/dev/null | awk '{print $NF}' | tail -1)
    elif [ -f /var/log/mysql/error.log ]; then
        TEMP_PASSWORD=$(grep 'temporary password' /var/log/mysql/error.log 2>/dev/null | awk '{print $NF}' | tail -1)
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
    
    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
        read -sp "请输入 MySQL root 密码（直接回车跳过）: " MYSQL_ROOT_PASSWORD
        echo ""
    fi
    
    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        # 等待 MySQL 完全启动
        sleep 3
        
        # 尝试使用临时密码登录并修改
        if [ -n "$TEMP_PASSWORD" ]; then
            mysql -u root -p"${TEMP_PASSWORD}" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';" 2>/dev/null && \
            echo -e "${GREEN}✓ root 密码已设置${NC}" || \
            echo -e "${YELLOW}⚠ 使用临时密码设置失败，尝试无密码设置${NC}"
        fi
        
        # 如果临时密码方式失败，尝试无密码方式（某些系统可能没有临时密码）
        if ! mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" > /dev/null 2>&1; then
            mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';" 2>/dev/null && \
            echo -e "${GREEN}✓ root 密码已设置${NC}" || \
            echo -e "${YELLOW}⚠ 无法自动设置密码，请手动设置${NC}"
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
            # 非交互式运行 mysql_secure_installation
            mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
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
        if mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ MySQL 连接测试成功${NC}"
        else
            echo -e "${YELLOW}⚠ MySQL 连接测试失败，请检查密码${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ 未设置密码，跳过连接测试${NC}"
    fi
}

# 显示后续步骤
show_next_steps() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}MySQL 安装完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}后续步骤:${NC}"
    echo ""
    echo "1. 检查 MySQL 服务状态:"
    echo "   sudo systemctl status mysqld"
    echo "   或"
    echo "   sudo systemctl status mysql"
    echo ""
    echo "2. 连接 MySQL:"
    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        echo "   mysql -u root -p'${MYSQL_ROOT_PASSWORD}'"
    else
        echo "   mysql -u root -p"
    fi
    echo ""
    echo "3. 创建数据库和用户（用于 WAF 系统）:"
    echo "   mysql -u root -p < init_file/数据库设计.sql"
    echo ""
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
    
    # 显示后续步骤
    show_next_steps
}

# 执行主函数
main "$@"

