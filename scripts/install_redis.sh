#!/bin/bash

# Redis 一键安装和配置脚本
# 支持多种 Linux 发行版：
#   - RedHat 系列：CentOS, RHEL, Fedora, Rocky Linux, AlmaLinux, Oracle Linux, Amazon Linux
#   - Debian 系列：Debian, Ubuntu, Linux Mint, Kali Linux, Raspbian
#   - SUSE 系列：openSUSE, SLES
#   - Arch 系列：Arch Linux, Manjaro
#   - 其他：Alpine Linux, Gentoo
# 用途：自动检测系统类型并安装配置 Redis

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
REDIS_VERSION="${REDIS_VERSION:-7.0}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
REDIS_PORT="${REDIS_PORT:-6379}"

# 导出变量供父脚本使用
export REDIS_PASSWORD

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
        echo -e "${YELLOW}将尝试使用通用方法（从源码编译）${NC}"
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
        echo -e "${YELLOW}⚠ 系统类型: 未知（将使用源码编译）${NC}"
    fi
}

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}错误: 需要 root 权限来安装 Redis${NC}"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 检查 Redis 是否已安装
check_existing() {
    echo -e "${BLUE}[2/7] 检查是否已安装 Redis...${NC}"
    
    if command -v redis-server &> /dev/null; then
        local redis_version=$(redis-server --version 2>&1 | head -n 1)
        echo -e "${YELLOW}检测到已安装 Redis: ${redis_version}${NC}"
        read -p "是否继续安装/更新？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}安装已取消${NC}"
            exit 0
        fi
    fi
    
    echo -e "${GREEN}✓ 检查完成${NC}"
}

# 安装依赖
install_dependencies() {
    echo -e "${BLUE}[3/7] 安装依赖包...${NC}"
    
    case $OS in
        centos|rhel|fedora|rocky|almalinux|oraclelinux|amazonlinux)
            if command -v dnf &> /dev/null; then
                dnf install -y gcc gcc-c++ make wget tar || yum install -y gcc gcc-c++ make wget tar
            else
                yum install -y gcc gcc-c++ make wget tar
            fi
            ;;
        ubuntu|debian|linuxmint|raspbian|kali)
            apt-get update
            apt-get install -y build-essential wget tar
            ;;
        opensuse*|sles)
            zypper install -y gcc gcc-c++ make wget tar
            ;;
        arch|manjaro)
            pacman -S --noconfirm base-devel wget tar
            ;;
        alpine)
            apk add --no-cache gcc g++ make wget tar linux-headers
            ;;
        gentoo)
            emerge --ask=n --quiet-build y gcc make wget tar
            ;;
        *)
            echo -e "${YELLOW}警告: 未识别的系统类型，尝试使用通用方法安装依赖${NC}"
            # 根据包管理器自动选择
            if command -v yum &> /dev/null || command -v dnf &> /dev/null; then
                echo -e "${BLUE}检测到 yum/dnf，使用 RedHat 系列方法${NC}"
                if command -v dnf &> /dev/null; then
                    dnf install -y gcc gcc-c++ make wget tar
                else
                    yum install -y gcc gcc-c++ make wget tar
                fi
            elif command -v apt-get &> /dev/null; then
                echo -e "${BLUE}检测到 apt-get，使用 Debian 系列方法${NC}"
                apt-get update
                apt-get install -y build-essential wget tar
            elif command -v zypper &> /dev/null; then
                echo -e "${BLUE}检测到 zypper，使用 SUSE 系列方法${NC}"
                zypper install -y gcc gcc-c++ make wget tar
            elif command -v pacman &> /dev/null; then
                echo -e "${BLUE}检测到 pacman，使用 Arch 系列方法${NC}"
                pacman -S --noconfirm base-devel wget tar
            elif command -v apk &> /dev/null; then
                echo -e "${BLUE}检测到 apk，使用 Alpine 方法${NC}"
                apk add --no-cache gcc g++ make wget tar linux-headers
            elif command -v emerge &> /dev/null; then
                echo -e "${BLUE}检测到 emerge，使用 Gentoo 方法${NC}"
                emerge --ask=n --quiet-build y gcc make wget tar
            else
                echo -e "${YELLOW}⚠ 无法确定包管理器，将尝试从源码编译（需要手动安装依赖）${NC}"
                echo -e "${BLUE}所需依赖: gcc, g++, make, wget, tar${NC}"
            fi
            ;;
    esac
    
    echo -e "${GREEN}✓ 依赖包安装完成${NC}"
}

# 安装 Redis（CentOS/RHEL/Fedora/Rocky/AlmaLinux/Oracle Linux/Amazon Linux）
install_redis_redhat() {
    echo -e "${BLUE}[4/7] 安装 Redis（RedHat 系列）...${NC}"
    
    INSTALL_SUCCESS=0
    
    # 尝试使用 EPEL 仓库安装（某些系统需要）
    if ! rpm -q epel-release &> /dev/null; then
        echo "尝试安装 EPEL 仓库..."
        if command -v dnf &> /dev/null; then
            dnf install -y epel-release 2>/dev/null || yum install -y epel-release 2>/dev/null || true
        else
            yum install -y epel-release 2>/dev/null || true
        fi
    fi
    
    # 尝试使用包管理器安装
    if command -v dnf &> /dev/null; then
        if dnf install -y redis 2>&1; then
            INSTALL_SUCCESS=1
        fi
    else
        if yum install -y redis 2>&1; then
            INSTALL_SUCCESS=1
        fi
    fi
    
    # 如果包管理器安装失败，从源码编译
    if [ $INSTALL_SUCCESS -eq 0 ]; then
        echo -e "${YELLOW}⚠ 包管理器安装失败，从源码编译安装...${NC}"
        install_redis_from_source
    else
        echo -e "${GREEN}✓ Redis 安装完成（包管理器）${NC}"
    fi
}

# 安装 Redis（Ubuntu/Debian/Linux Mint/Kali Linux）
install_redis_debian() {
    echo -e "${BLUE}[4/7] 安装 Redis（Debian 系列）...${NC}"
    
    INSTALL_SUCCESS=0
    
    # 尝试使用包管理器安装
    if apt-get install -y redis-server 2>&1; then
        INSTALL_SUCCESS=1
    fi
    
    # 如果包管理器安装失败，从源码编译
    if [ $INSTALL_SUCCESS -eq 0 ]; then
        echo -e "${YELLOW}⚠ 包管理器安装失败，从源码编译安装...${NC}"
        install_redis_from_source
    else
        echo -e "${GREEN}✓ Redis 安装完成（包管理器）${NC}"
    fi
}

# 安装 Redis（openSUSE）
install_redis_suse() {
    echo -e "${BLUE}[4/7] 安装 Redis（openSUSE）...${NC}"
    
    # 尝试使用包管理器安装
    if zypper install -y redis 2>&1; then
        echo -e "${GREEN}✓ Redis 安装完成（包管理器）${NC}"
        return 0
    fi
    
    # 如果包管理器安装失败，从源码编译
    echo -e "${YELLOW}⚠ 包管理器安装失败，从源码编译安装...${NC}"
    install_redis_from_source
}

# 安装 Redis（Arch Linux/Manjaro）
install_redis_arch() {
    echo -e "${BLUE}[4/7] 安装 Redis（Arch Linux）...${NC}"
    
    INSTALL_SUCCESS=0
    
    # Arch Linux 通常有 Redis 包
    if command -v yay &> /dev/null; then
        if yay -S --noconfirm redis 2>&1; then
            INSTALL_SUCCESS=1
        fi
    elif command -v paru &> /dev/null; then
        if paru -S --noconfirm redis 2>&1; then
            INSTALL_SUCCESS=1
        fi
    else
        if pacman -S --noconfirm redis 2>&1; then
            INSTALL_SUCCESS=1
        fi
    fi
    
    if [ $INSTALL_SUCCESS -eq 0 ]; then
        echo -e "${YELLOW}⚠ 包管理器安装失败，从源码编译安装...${NC}"
        install_redis_from_source
    else
        echo -e "${GREEN}✓ Redis 安装完成${NC}"
    fi
}

# 安装 Redis（Alpine Linux）
install_redis_alpine() {
    echo -e "${BLUE}[4/7] 安装 Redis（Alpine Linux）...${NC}"
    
    # Alpine Linux 使用 apk
    if apk add --no-cache redis 2>&1; then
        echo -e "${GREEN}✓ Redis 安装完成${NC}"
    else
        echo -e "${YELLOW}⚠ 包管理器安装失败，从源码编译安装...${NC}"
        install_redis_from_source
    fi
}

# 安装 Redis（Gentoo）
install_redis_gentoo() {
    echo -e "${BLUE}[4/7] 安装 Redis（Gentoo）...${NC}"
    
    # Gentoo 使用 emerge
    if emerge --ask=n --quiet-build y dev-db/redis 2>&1; then
        echo -e "${GREEN}✓ Redis 安装完成${NC}"
    else
        echo -e "${YELLOW}⚠ 包管理器安装失败，从源码编译安装...${NC}"
        install_redis_from_source
    fi
}

# 从源码编译安装 Redis
install_redis_from_source() {
    echo -e "${BLUE}[4/7] 从源码编译安装 Redis...${NC}"
    
    local build_dir="/tmp/redis-build"
    local version="${REDIS_VERSION}"
    
    mkdir -p "$build_dir"
    cd "$build_dir"
    
    # 下载源码
    if [ ! -f "redis-${version}.tar.gz" ] && [ ! -f "redis-stable.tar.gz" ]; then
        echo "下载 Redis ${version} 源码..."
        if ! wget "https://download.redis.io/releases/redis-${version}.tar.gz" 2>&1; then
            echo -e "${YELLOW}⚠ 无法下载 Redis ${version}，尝试下载最新稳定版${NC}"
            if ! wget "https://download.redis.io/redis-stable.tar.gz" 2>&1; then
                echo -e "${RED}✗ 无法下载 Redis 源码${NC}"
                exit 1
            fi
        fi
    fi
    
    # 解压
    tar -xzf "redis-${version}.tar.gz" || tar -xzf "redis-stable.tar.gz"
    cd redis-* || cd redis-stable
    
    # 编译安装
    make -j$(nproc)
    make install PREFIX=/usr/local
    
    # 创建必要的目录和文件
    mkdir -p /etc/redis
    mkdir -p /var/lib/redis
    mkdir -p /var/log/redis
    
    # 复制配置文件
    if [ ! -f /etc/redis/redis.conf ]; then
        cp redis.conf /etc/redis/redis.conf
    fi
    
    # 创建 systemd 服务文件
    if [ ! -f /etc/systemd/system/redis.service ]; then
        cat > /etc/systemd/system/redis.service <<EOF
[Unit]
Description=Redis In-Memory Data Store
After=network.target

[Service]
User=redis
Group=redis
ExecStart=/usr/local/bin/redis-server /etc/redis/redis.conf
ExecStop=/usr/local/bin/redis-cli shutdown
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    fi
    
    # 创建 redis 用户（如果不存在）
    if ! id redis &>/dev/null; then
        # 根据系统类型使用不同的命令创建用户
        if command -v adduser &> /dev/null && [ "$OS" = "alpine" ]; then
            # Alpine Linux 使用 adduser
            adduser -D -s /bin/false redis
        else
            # 其他系统使用 useradd
            useradd -r -s /bin/false redis
        fi
    fi
    
    # 设置权限
    chown -R redis:redis /var/lib/redis
    chown -R redis:redis /var/log/redis
    chown redis:redis /etc/redis/redis.conf
    
    # 清理
    cd /
    rm -rf "$build_dir"
    
    echo -e "${GREEN}✓ Redis 编译安装完成${NC}"
}

# 安装 Redis
install_redis() {
    case $OS in
        centos|rhel|fedora|rocky|almalinux|oraclelinux|amazonlinux)
            install_redis_redhat
            ;;
        ubuntu|debian|linuxmint|raspbian|kali)
            install_redis_debian
            ;;
        opensuse*|sles)
            install_redis_suse
            ;;
        arch|manjaro)
            install_redis_arch
            ;;
        alpine)
            install_redis_alpine
            ;;
        gentoo)
            install_redis_gentoo
            ;;
        *)
            echo -e "${YELLOW}警告: 未识别的系统类型 (${OS})，使用源码编译安装${NC}"
            install_redis_from_source
            ;;
    esac
}

# 配置 Redis
configure_redis() {
    echo -e "${BLUE}[5/7] 配置 Redis...${NC}"
    
    # 查找 Redis 配置文件（更全面的路径检测）
    REDIS_CONF=""
    # 常见配置文件路径
    local possible_paths=(
        "/etc/redis/redis.conf"
        "/etc/redis.conf"
        "/usr/local/etc/redis.conf"
        "/usr/local/redis/etc/redis.conf"
        "/opt/redis/etc/redis.conf"
        "/var/lib/redis/redis.conf"
    )
    
    for path in "${possible_paths[@]}"; do
        if [ -f "$path" ]; then
            REDIS_CONF="$path"
            echo "找到 Redis 配置文件: $path"
            break
        fi
    done
    
    # 如果仍未找到，尝试使用 find 命令搜索
    if [ -z "$REDIS_CONF" ]; then
        local found_conf=$(find /etc /usr/local /opt -name "redis.conf" -type f 2>/dev/null | head -n 1)
        if [ -n "$found_conf" ]; then
            REDIS_CONF="$found_conf"
            echo "通过搜索找到 Redis 配置文件: $found_conf"
        fi
    fi
    
    if [ -n "$REDIS_CONF" ]; then
        # 备份原配置
        cp "$REDIS_CONF" "${REDIS_CONF}.bak.$(date +%Y%m%d_%H%M%S)"
        
        # 配置端口
        if grep -q "^port " "$REDIS_CONF"; then
            sed -i "s/^port .*/port ${REDIS_PORT}/" "$REDIS_CONF"
        else
            echo "port ${REDIS_PORT}" >> "$REDIS_CONF"
        fi
        
        # 配置密码（如果提供）
        if [ -n "$REDIS_PASSWORD" ]; then
            if grep -q "^requirepass " "$REDIS_CONF"; then
                sed -i "s/^requirepass .*/requirepass ${REDIS_PASSWORD}/" "$REDIS_CONF"
            else
                echo "requirepass ${REDIS_PASSWORD}" >> "$REDIS_CONF"
            fi
        fi
        
        # 配置持久化（启用 RDB）
        sed -i 's/^save 900 1/save 900 1/' "$REDIS_CONF" || echo "save 900 1" >> "$REDIS_CONF"
        sed -i 's/^save 300 10/save 300 10/' "$REDIS_CONF" || echo "save 300 10" >> "$REDIS_CONF"
        sed -i 's/^save 60 10000/save 60 10000/' "$REDIS_CONF" || echo "save 60 10000" >> "$REDIS_CONF"
        
        # 配置数据目录
        if grep -q "^dir " "$REDIS_CONF"; then
            sed -i "s|^dir .*|dir /var/lib/redis|" "$REDIS_CONF"
        else
            echo "dir /var/lib/redis" >> "$REDIS_CONF"
        fi
        
        # 配置日志
        if grep -q "^logfile " "$REDIS_CONF"; then
            sed -i "s|^logfile .*|logfile /var/log/redis/redis-server.log|" "$REDIS_CONF"
        else
            echo "logfile /var/log/redis/redis-server.log" >> "$REDIS_CONF"
        fi
        
        echo -e "${GREEN}✓ Redis 配置完成${NC}"
    else
        echo -e "${YELLOW}⚠ 未找到 Redis 配置文件，使用默认配置${NC}"
    fi
}

# 设置 Redis 密码（可选）
set_redis_password() {
    echo -e "${BLUE}[6/7] 设置 Redis 密码...${NC}"
    
    if [ -z "$REDIS_PASSWORD" ]; then
        read -sp "请输入 Redis 密码（直接回车跳过）: " REDIS_PASSWORD
        echo ""
    fi
    
    if [ -n "$REDIS_PASSWORD" ] && [ -n "$REDIS_CONF" ]; then
        if grep -q "^requirepass " "$REDIS_CONF"; then
            sed -i "s/^requirepass .*/requirepass ${REDIS_PASSWORD}/" "$REDIS_CONF"
        else
            echo "requirepass ${REDIS_PASSWORD}" >> "$REDIS_CONF"
        fi
        echo -e "${GREEN}✓ Redis 密码已设置${NC}"
    else
        echo -e "${YELLOW}跳过 Redis 密码设置${NC}"
    fi
}

# 启动 Redis 服务
start_redis() {
    echo -e "${BLUE}[7/7] 启动 Redis 服务...${NC}"
    
    # 创建必要的目录
    mkdir -p /var/lib/redis
    mkdir -p /var/log/redis
    
    # 创建 redis 用户（如果不存在）
    if ! id redis &>/dev/null; then
        # 根据系统类型使用不同的命令创建用户
        if command -v adduser &> /dev/null && [ "$OS" = "alpine" ]; then
            # Alpine Linux 使用 adduser
            adduser -D -s /bin/false redis
        else
            # 其他系统使用 useradd
            useradd -r -s /bin/false redis
        fi
        chown -R redis:redis /var/lib/redis 2>/dev/null || true
        chown -R redis:redis /var/log/redis 2>/dev/null || true
    fi
    
    # 启动服务
    local service_started=false
    
    if command -v systemctl &> /dev/null; then
        systemctl daemon-reload
        systemctl enable redis 2>/dev/null || systemctl enable redis-server 2>/dev/null || true
        
        if systemctl start redis 2>/dev/null || systemctl start redis-server 2>/dev/null; then
            # 等待服务启动
            sleep 2
            # 检查服务状态
            if systemctl is-active --quiet redis 2>/dev/null || systemctl is-active --quiet redis-server 2>/dev/null; then
                service_started=true
                echo -e "${GREEN}✓ Redis 服务启动成功（systemd）${NC}"
            else
                echo -e "${YELLOW}⚠ systemd 服务启动后状态异常${NC}"
            fi
        else
            echo -e "${YELLOW}⚠ systemd 服务启动失败，尝试直接启动${NC}"
            # 如果服务启动失败，尝试直接启动
            if command -v redis-server &> /dev/null; then
                local redis_conf_path=""
                if [ -n "$REDIS_CONF" ] && [ -f "$REDIS_CONF" ]; then
                    redis_conf_path="$REDIS_CONF"
                elif [ -f /etc/redis/redis.conf ]; then
                    redis_conf_path="/etc/redis/redis.conf"
                elif [ -f /etc/redis.conf ]; then
                    redis_conf_path="/etc/redis.conf"
                fi
                
                if [ -n "$redis_conf_path" ]; then
                    if redis-server "$redis_conf_path" --daemonize yes 2>/dev/null; then
                        sleep 2
                        if redis-cli ping > /dev/null 2>&1; then
                            service_started=true
                            echo -e "${GREEN}✓ Redis 服务启动成功（直接启动）${NC}"
                        fi
                    fi
                fi
            fi
        fi
    elif command -v service &> /dev/null; then
        if service redis start 2>/dev/null || service redis-server start 2>/dev/null; then
            chkconfig redis on 2>/dev/null || chkconfig redis-server on 2>/dev/null || true
            sleep 2
            if pgrep -x redis-server > /dev/null 2>&1; then
                service_started=true
                echo -e "${GREEN}✓ Redis 服务启动成功（service）${NC}"
            fi
        fi
    else
        # 直接启动
        if command -v redis-server &> /dev/null; then
            local redis_conf_path=""
            if [ -n "$REDIS_CONF" ] && [ -f "$REDIS_CONF" ]; then
                redis_conf_path="$REDIS_CONF"
            elif [ -f /etc/redis/redis.conf ]; then
                redis_conf_path="/etc/redis/redis.conf"
            elif [ -f /etc/redis.conf ]; then
                redis_conf_path="/etc/redis.conf"
            fi
            
            if [ -n "$redis_conf_path" ]; then
                if redis-server "$redis_conf_path" --daemonize yes 2>/dev/null; then
                    sleep 2
                    if redis-cli ping > /dev/null 2>&1; then
                        service_started=true
                        echo -e "${GREEN}✓ Redis 服务启动成功（直接启动）${NC}"
                    fi
                fi
            fi
        fi
    fi
    
    if [ "$service_started" = false ]; then
        echo -e "${YELLOW}⚠ Redis 服务启动可能失败，请手动检查${NC}"
        echo -e "${YELLOW}建议:${NC}"
        echo "  1. 检查 Redis 配置文件: $REDIS_CONF"
        echo "  2. 手动启动: redis-server $REDIS_CONF"
        echo "  3. 查看日志: tail -f /var/log/redis/redis-server.log"
    fi
}

# 验证安装
verify_installation() {
    echo -e "${BLUE}[8/8] 验证安装...${NC}"
    
    if command -v redis-server &> /dev/null; then
        local version=$(redis-server --version 2>&1 | head -n 1)
        echo -e "${GREEN}✓ Redis 安装成功${NC}"
        echo "  版本: $version"
    else
        echo -e "${RED}✗ Redis 安装失败${NC}"
        exit 1
    fi
    
    # 测试连接
    if command -v redis-cli &> /dev/null; then
        if [ -n "$REDIS_PASSWORD" ]; then
            if redis-cli -a "${REDIS_PASSWORD}" ping 2>/dev/null | grep -q "PONG"; then
                echo -e "${GREEN}✓ Redis 连接测试成功${NC}"
            else
                echo -e "${YELLOW}⚠ Redis 连接测试失败，请检查密码和服务状态${NC}"
            fi
        else
            if redis-cli ping 2>/dev/null | grep -q "PONG"; then
                echo -e "${GREEN}✓ Redis 连接测试成功${NC}"
            else
                echo -e "${YELLOW}⚠ Redis 连接测试失败，请检查服务状态${NC}"
            fi
        fi
    fi
}

# 显示后续步骤
show_next_steps() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Redis 安装完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}后续步骤:${NC}"
    echo ""
    echo "1. 检查 Redis 服务状态:"
    echo "   sudo systemctl status redis"
    echo "   或"
    echo "   sudo systemctl status redis-server"
    echo ""
    echo "2. 连接 Redis:"
    if [ -n "$REDIS_PASSWORD" ]; then
        echo "   redis-cli -a '${REDIS_PASSWORD}'"
    else
        echo "   redis-cli"
    fi
    echo ""
    echo "3. 测试 Redis:"
    if [ -n "$REDIS_PASSWORD" ]; then
        echo "   redis-cli -a '${REDIS_PASSWORD}' ping"
    else
        echo "   redis-cli ping"
    fi
    echo ""
    echo "4. 修改 WAF 配置文件（如果使用 Redis）:"
    echo "   vim lua/config.lua"
    echo "   或使用 install.sh 自动配置"
    echo ""
    echo -e "${BLUE}服务管理:${NC}"
    echo "  启动: sudo systemctl start redis"
    echo "  停止: sudo systemctl stop redis"
    echo "  重启: sudo systemctl restart redis"
    echo "  开机自启: sudo systemctl enable redis"
    echo ""
    echo -e "${BLUE}配置文件位置:${NC}"
    if [ -f /etc/redis/redis.conf ]; then
        echo "  /etc/redis/redis.conf"
    elif [ -f /etc/redis.conf ]; then
        echo "  /etc/redis.conf"
    fi
    echo ""
}

# 主函数
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Redis 一键安装和配置脚本${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # 检查 root 权限
    check_root
    
    # 检测操作系统
    detect_os
    
    # 检查现有安装
    check_existing
    
    # 安装依赖
    install_dependencies
    
    # 安装 Redis
    install_redis
    
    # 配置 Redis
    configure_redis
    
    # 设置密码
    set_redis_password
    
    # 启动服务
    start_redis
    
    # 验证安装
    verify_installation
    
    # 显示后续步骤
    show_next_steps
    
    # 如果设置了环境变量 TEMP_VARS_FILE，将变量写入文件供父脚本使用
    if [ -n "$TEMP_VARS_FILE" ] && [ -f "$TEMP_VARS_FILE" ]; then
        {
            echo "REDIS_PASSWORD=\"${REDIS_PASSWORD}\""
        } >> "$TEMP_VARS_FILE"
    fi
}

# 执行主函数
main "$@"

