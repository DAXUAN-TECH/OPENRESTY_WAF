#!/bin/bash

# OpenResty 一键安装和配置脚本
# 支持多种 Linux 发行版：
#   - RedHat 系列：CentOS, RHEL, Fedora, Rocky Linux, AlmaLinux, Oracle Linux, Amazon Linux
#   - Debian 系列：Debian, Ubuntu, Linux Mint, Kali Linux, Raspbian
#   - SUSE 系列：openSUSE, SLES
#   - Arch 系列：Arch Linux, Manjaro
#   - 其他：Alpine Linux, Gentoo (从源码编译)
# 用途：自动检测系统类型并安装配置 OpenResty

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
OPENRESTY_VERSION="${OPENRESTY_VERSION:-1.21.4.1}"
INSTALL_DIR="/usr/local/openresty"
NGINX_CONF_DIR="${INSTALL_DIR}/nginx/conf"
NGINX_LUA_DIR="${INSTALL_DIR}/nginx/lua"
NGINX_LOG_DIR="${INSTALL_DIR}/nginx/logs"

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
        echo -e "${RED}错误: 需要 root 权限来安装 OpenResty${NC}"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 安装依赖（CentOS/RHEL/Fedora）
install_deps_redhat() {
    echo -e "${BLUE}[2/8] 安装依赖包（RedHat 系列）...${NC}"
    
    if command -v dnf &> /dev/null; then
        # Fedora
        dnf install -y gcc gcc-c++ pcre-devel zlib-devel openssl-devel perl perl-ExtUtils-Embed readline-devel wget curl
    elif command -v yum &> /dev/null; then
        # CentOS/RHEL
        yum install -y gcc gcc-c++ pcre-devel zlib-devel openssl-devel perl perl-ExtUtils-Embed readline-devel wget curl
    else
        echo -e "${RED}错误: 未找到包管理器（yum/dnf）${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ 依赖包安装完成${NC}"
}

# 安装依赖（Ubuntu/Debian）
install_deps_debian() {
    echo -e "${BLUE}[2/8] 安装依赖包（Debian 系列）...${NC}"
    
    apt-get update
    apt-get install -y build-essential libpcre3-dev zlib1g-dev libssl-dev libreadline-dev wget curl
    
    echo -e "${GREEN}✓ 依赖包安装完成${NC}"
}

# 安装依赖（openSUSE）
install_deps_suse() {
    echo -e "${BLUE}[2/8] 安装依赖包（openSUSE）...${NC}"
    
    zypper install -y gcc gcc-c++ pcre-devel zlib-devel libopenssl-devel perl readline-devel wget curl
    
    echo -e "${GREEN}✓ 依赖包安装完成${NC}"
}

# 安装依赖（Arch Linux）
install_deps_arch() {
    echo -e "${BLUE}[2/8] 安装依赖包（Arch Linux）...${NC}"
    
    pacman -S --noconfirm base-devel pcre zlib openssl perl readline wget curl
    
    echo -e "${GREEN}✓ 依赖包安装完成${NC}"
}

# 安装依赖（Alpine Linux）
install_deps_alpine() {
    echo -e "${BLUE}[2/8] 安装依赖包（Alpine Linux）...${NC}"
    
    apk add --no-cache gcc g++ make pcre-dev zlib-dev openssl-dev perl readline-dev wget curl
    
    echo -e "${GREEN}✓ 依赖包安装完成${NC}"
}

# 安装依赖（Gentoo）
install_deps_gentoo() {
    echo -e "${BLUE}[2/8] 安装依赖包（Gentoo）...${NC}"
    
    emerge --ask=n --quiet-build y gcc make pcre zlib openssl perl readline wget curl
    
    echo -e "${GREEN}✓ 依赖包安装完成${NC}"
}

# 安装依赖
install_dependencies() {
    case $OS in
        centos|rhel|fedora|rocky|almalinux|oraclelinux|amazonlinux)
            install_deps_redhat
            ;;
        ubuntu|debian|linuxmint|raspbian|kali)
            install_deps_debian
            ;;
        opensuse*|sles)
            install_deps_suse
            ;;
        arch|manjaro)
            install_deps_arch
            ;;
        alpine)
            install_deps_alpine
            ;;
        gentoo)
            install_deps_gentoo
            ;;
        *)
            echo -e "${YELLOW}警告: 未识别的系统类型，尝试使用通用方法安装依赖${NC}"
            # 根据包管理器自动选择
            if command -v yum &> /dev/null || command -v dnf &> /dev/null; then
                echo -e "${BLUE}检测到 yum/dnf，使用 RedHat 系列方法${NC}"
                install_deps_redhat
            elif command -v apt-get &> /dev/null; then
                echo -e "${BLUE}检测到 apt-get，使用 Debian 系列方法${NC}"
                install_deps_debian
            elif command -v zypper &> /dev/null; then
                echo -e "${BLUE}检测到 zypper，使用 SUSE 系列方法${NC}"
                install_deps_suse
            elif command -v pacman &> /dev/null; then
                echo -e "${BLUE}检测到 pacman，使用 Arch 系列方法${NC}"
                install_deps_arch
            elif command -v apk &> /dev/null; then
                echo -e "${BLUE}检测到 apk，使用 Alpine 方法${NC}"
                install_deps_alpine
            elif command -v emerge &> /dev/null; then
                echo -e "${BLUE}检测到 emerge，使用 Gentoo 方法${NC}"
                install_deps_gentoo
            else
                echo -e "${YELLOW}⚠ 无法确定包管理器，将尝试从源码编译（需要手动安装依赖）${NC}"
                echo -e "${BLUE}所需依赖: gcc, g++, make, pcre-dev, zlib-dev, openssl-dev, perl, readline-dev${NC}"
            fi
            ;;
    esac
}

# 检查 OpenResty 是否已安装
check_existing() {
    echo -e "${BLUE}[3/8] 检查是否已安装 OpenResty...${NC}"
    
    local openresty_installed=0
    local current_version=""
    local config_deployed=0
    
    if [ -f "${INSTALL_DIR}/bin/openresty" ]; then
        openresty_installed=1
        current_version=$(${INSTALL_DIR}/bin/openresty -v 2>&1 | grep -oP 'openresty/\K[0-9.]+' || echo "unknown")
        echo -e "${YELLOW}检测到已安装 OpenResty 版本: ${current_version}${NC}"
        
        # 检查配置文件是否已部署
        if [ -f "${INSTALL_DIR}/nginx/conf/nginx.conf" ]; then
            if grep -q "project_root\|project_root" "${INSTALL_DIR}/nginx/conf/nginx.conf" 2>/dev/null; then
                config_deployed=1
                echo -e "${YELLOW}检测到配置文件已部署${NC}"
            fi
        fi
        
        echo ""
        echo "请选择操作："
        echo "  1. 保留现有安装和配置，跳过安装"
        echo "  2. 重新安装 OpenResty（保留配置文件）"
        echo "  3. 完全重新安装（删除所有文件和配置）"
        read -p "请选择 [1-3]: " REINSTALL_CHOICE
        
        case "$REINSTALL_CHOICE" in
            1)
                echo -e "${GREEN}跳过 OpenResty 安装，保留现有配置${NC}"
                exit 0
                ;;
            2)
                echo -e "${YELLOW}将重新安装 OpenResty，但保留配置文件${NC}"
                REINSTALL_MODE="keep_config"
                ;;
            3)
                echo -e "${RED}警告: 将删除所有 OpenResty 文件和配置！${NC}"
                read -p "确认删除所有文件？[y/N]: " CONFIRM_DELETE
                CONFIRM_DELETE="${CONFIRM_DELETE:-N}"
                if [[ "$CONFIRM_DELETE" =~ ^[Yy]$ ]]; then
                    echo -e "${YELLOW}将完全重新安装 OpenResty，删除所有文件${NC}"
                    REINSTALL_MODE="delete_all"
                    
                    # 停止服务
                    if command -v systemctl &> /dev/null; then
                        systemctl stop openresty 2>/dev/null || true
                    elif [ -f "${INSTALL_DIR}/nginx/logs/nginx.pid" ]; then
                        ${INSTALL_DIR}/bin/openresty -s quit 2>/dev/null || true
                    fi
                    sleep 2
                    
                    # 删除安装目录
                    if [ -d "$INSTALL_DIR" ]; then
                        echo -e "${YELLOW}正在删除安装目录: ${INSTALL_DIR}${NC}"
                        rm -rf "$INSTALL_DIR"
                        echo -e "${GREEN}✓ 安装目录已删除${NC}"
                    fi
                    
                    # 删除服务文件
                    if [ -f /etc/systemd/system/openresty.service ]; then
                        rm -f /etc/systemd/system/openresty.service
                        systemctl daemon-reload 2>/dev/null || true
                        echo -e "${GREEN}✓ 服务文件已删除${NC}"
                    fi
                    
                    # 删除符号链接
                    rm -f /usr/local/bin/openresty /usr/local/bin/opm /usr/local/bin/resty 2>/dev/null || true
                else
                    echo -e "${GREEN}取消删除，将保留文件重新安装${NC}"
                    REINSTALL_MODE="keep_config"
                fi
                ;;
            *)
                echo -e "${YELLOW}无效选择，将跳过安装${NC}"
                exit 0
                ;;
        esac
    else
        echo -e "${GREEN}✓ OpenResty 未安装，将进行全新安装${NC}"
    fi
    
    # 版本选择（如果未设置环境变量）
    if [ -z "$OPENRESTY_VERSION" ]; then
        echo ""
        echo "请选择 OpenResty 版本："
        echo "  1. OpenResty 1.21.4.1（推荐，最新稳定版）"
        echo "  2. OpenResty 1.19.9.1（兼容性更好）"
        echo "  3. 使用系统默认版本（如果可用）"
        read -p "请选择 [1-3]: " VERSION_CHOICE
        
        case "$VERSION_CHOICE" in
            1)
                OPENRESTY_VERSION="1.21.4.1"
                echo -e "${GREEN}✓ 已选择 OpenResty 1.21.4.1${NC}"
                ;;
            2)
                OPENRESTY_VERSION="1.19.9.1"
                echo -e "${GREEN}✓ 已选择 OpenResty 1.19.9.1${NC}"
                ;;
            3)
                OPENRESTY_VERSION="default"
                echo -e "${GREEN}✓ 将使用系统默认版本${NC}"
                ;;
            *)
                OPENRESTY_VERSION="1.21.4.1"
                echo -e "${YELLOW}无效选择，默认使用 OpenResty 1.21.4.1${NC}"
                ;;
        esac
    else
        echo -e "${BLUE}使用环境变量指定的版本: ${OPENRESTY_VERSION}${NC}"
    fi
    
    echo -e "${GREEN}✓ 检查完成${NC}"
}

# 安装 OpenResty（CentOS/RHEL/Fedora/Rocky/AlmaLinux/Oracle Linux/Amazon Linux）
install_openresty_redhat() {
    echo -e "${BLUE}[4/8] 安装 OpenResty（RedHat 系列）...${NC}"
    
    # 确定仓库名称（根据实际系统）
    local repo_os=$OS
    case $OS in
        oraclelinux|ol)
            repo_os="centos"  # Oracle Linux 使用 CentOS 仓库
            ;;
        amazonlinux|amzn)
            repo_os="amazonlinux"  # Amazon Linux 有专门仓库
            ;;
        rocky|almalinux)
            repo_os="centos"  # Rocky 和 AlmaLinux 使用 CentOS 仓库
            ;;
    esac
    
    # 添加 OpenResty 仓库
    if [ ! -f /etc/yum.repos.d/openresty.repo ]; then
        echo "添加 OpenResty 仓库..."
        
        # 确保目录存在
        mkdir -p /etc/pki/rpm-gpg
        
        # 尝试下载并导入 GPG 密钥（带错误处理）
        echo "下载 GPG 密钥..."
        GPG_CHECK=0
        
        # 方法1：尝试直接使用 rpm --import
        if wget -qO - https://openresty.org/package/pubkey.gpg > /tmp/openresty-pubkey.gpg 2>&1 && [ -s /tmp/openresty-pubkey.gpg ]; then
            # 尝试直接导入到 RPM 密钥环
            if rpm --import /tmp/openresty-pubkey.gpg 2>&1; then
                echo -e "${GREEN}✓ GPG 密钥已导入到 RPM 密钥环${NC}"
                GPG_CHECK=1
            else
                # 方法2：尝试使用 gpg --dearmor 然后导入
                if gpg --dearmor /tmp/openresty-pubkey.gpg -o /etc/pki/rpm-gpg/RPM-GPG-KEY-openresty 2>&1 && [ -s /etc/pki/rpm-gpg/RPM-GPG-KEY-openresty ]; then
                    # 尝试导入到 RPM 密钥环
                    if rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-openresty 2>&1; then
                        echo -e "${GREEN}✓ GPG 密钥已导入到 RPM 密钥环${NC}"
                        GPG_CHECK=1
                    else
                        echo -e "${YELLOW}⚠ GPG 密钥导入到 RPM 密钥环失败，将禁用 GPG 检查${NC}"
                        GPG_CHECK=0
                    fi
                else
                    echo -e "${YELLOW}⚠ GPG 密钥处理失败，将禁用 GPG 检查${NC}"
                    GPG_CHECK=0
                fi
            fi
            rm -f /tmp/openresty-pubkey.gpg
        else
            echo -e "${YELLOW}⚠ 无法下载 GPG 密钥，将禁用 GPG 检查${NC}"
            GPG_CHECK=0
        fi
        
        # 创建仓库配置文件
        # 如果 GPG 检查失败，直接禁用（不设置 gpgkey）
        if [ "$GPG_CHECK" = "1" ]; then
            cat > /etc/yum.repos.d/openresty.repo <<EOF
[openresty]
name=Official OpenResty Repository
baseurl=https://openresty.org/package/${repo_os}/\$releasever/\$basearch
gpgcheck=1
enabled=1
gpgkey=https://openresty.org/package/pubkey.gpg
EOF
        else
            # 禁用 GPG 检查
            cat > /etc/yum.repos.d/openresty.repo <<EOF
[openresty]
name=Official OpenResty Repository
baseurl=https://openresty.org/package/${repo_os}/\$releasever/\$basearch
gpgcheck=0
enabled=1
EOF
            echo -e "${YELLOW}⚠ 已禁用 GPG 检查，继续安装${NC}"
        fi
        
        echo -e "${GREEN}✓ OpenResty 仓库配置完成${NC}"
    else
        # 如果仓库文件已存在，检查是否需要修复
        if grep -q "gpgcheck=1" /etc/yum.repos.d/openresty.repo && ! rpm -q gpg-pubkey-d5edeb74 &> /dev/null; then
            echo "检测到 GPG 检查已启用但密钥未导入，尝试修复..."
            if wget -qO - https://openresty.org/package/pubkey.gpg | rpm --import 2>&1; then
                echo -e "${GREEN}✓ GPG 密钥已导入${NC}"
            else
                echo -e "${YELLOW}⚠ GPG 密钥导入失败，禁用 GPG 检查${NC}"
                sed -i 's/gpgcheck=1/gpgcheck=0/' /etc/yum.repos.d/openresty.repo
                sed -i '/gpgkey=/d' /etc/yum.repos.d/openresty.repo
            fi
        fi
    fi
    
    # 尝试使用包管理器安装
    echo "尝试使用包管理器安装 OpenResty..."
    INSTALL_SUCCESS=0
    
    if command -v dnf &> /dev/null; then
        if dnf install -y openresty openresty-resty 2>&1; then
            INSTALL_SUCCESS=1
        fi
    else
        if yum install -y openresty openresty-resty 2>&1; then
            INSTALL_SUCCESS=1
        fi
    fi
    
    # 如果包管理器安装失败，尝试从源码编译
    if [ "$INSTALL_SUCCESS" -eq 0 ]; then
        echo -e "${YELLOW}⚠ 包管理器安装失败，尝试从源码编译安装...${NC}"
        install_openresty_from_source
    else
        echo -e "${GREEN}✓ OpenResty 安装完成${NC}"
    fi
}

# 安装 OpenResty（Ubuntu/Debian/Linux Mint/Kali Linux）
install_openresty_debian() {
    echo -e "${BLUE}[4/8] 安装 OpenResty（Debian 系列）...${NC}"
    
    # 确定仓库名称（根据实际系统）
    local repo_os=$OS
    case $OS in
        linuxmint)
            repo_os="ubuntu"  # Linux Mint 使用 Ubuntu 仓库
            ;;
        kali|raspbian)
            repo_os="debian"  # Kali 和 Raspbian 使用 Debian 仓库
            ;;
    esac
    
    # 获取发行版代号
    local distro_codename
    if command -v lsb_release &> /dev/null; then
        distro_codename=$(lsb_release -sc)
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        distro_codename=$VERSION_CODENAME
        if [ -z "$distro_codename" ]; then
            # 尝试从 VERSION_ID 推断
            case $OS in
                ubuntu)
                    case $VERSION_ID in
                        20.04) distro_codename="focal" ;;
                        22.04) distro_codename="jammy" ;;
                        18.04) distro_codename="bionic" ;;
                        *) distro_codename="focal" ;;  # 默认
                    esac
                    ;;
                debian)
                    case $VERSION_ID in
                        11) distro_codename="bullseye" ;;
                        12) distro_codename="bookworm" ;;
                        10) distro_codename="buster" ;;
                        *) distro_codename="bullseye" ;;  # 默认
                    esac
                    ;;
            esac
        fi
    fi
    
    if [ -z "$distro_codename" ]; then
        echo -e "${YELLOW}⚠ 无法确定发行版代号，尝试使用通用方法${NC}"
        distro_codename="focal"  # 默认使用 Ubuntu 20.04
    fi
    
    # 添加 OpenResty 仓库
    if [ ! -f /etc/apt/sources.list.d/openresty.list ]; then
        # 尝试使用 apt-key（旧方法）
        if wget -qO - https://openresty.org/package/pubkey.gpg | apt-key add - 2>/dev/null; then
            echo "deb http://openresty.org/package/${repo_os} ${distro_codename} main" > /etc/apt/sources.list.d/openresty.list
        else
            # 使用新方法（apt 2.4+）
            mkdir -p /etc/apt/keyrings
            wget -qO - https://openresty.org/package/pubkey.gpg | gpg --dearmor -o /etc/apt/keyrings/openresty.gpg
            echo "deb [signed-by=/etc/apt/keyrings/openresty.gpg] http://openresty.org/package/${repo_os} ${distro_codename} main" > /etc/apt/sources.list.d/openresty.list
        fi
        apt-get update
    fi
    
    # 安装 OpenResty
    if apt-get install -y openresty 2>&1; then
        echo -e "${GREEN}✓ OpenResty 安装完成${NC}"
    else
        echo -e "${YELLOW}⚠ 包管理器安装失败，尝试从源码编译安装...${NC}"
        install_openresty_from_source
    fi
}

# 安装 OpenResty（openSUSE）
install_openresty_suse() {
    echo -e "${BLUE}[4/8] 安装 OpenResty（openSUSE）...${NC}"
    
    # openSUSE 需要从源码编译或使用第三方仓库
    echo -e "${YELLOW}注意: openSUSE 可能需要从源码编译安装${NC}"
    install_openresty_from_source
}

# 安装 OpenResty（Arch Linux/Manjaro）
install_openresty_arch() {
    echo -e "${BLUE}[4/8] 安装 OpenResty（Arch Linux）...${NC}"
    
    # Arch Linux 使用 AUR，需要 yay 或手动安装
    INSTALL_SUCCESS=0
    
    if command -v yay &> /dev/null; then
        echo "使用 yay 从 AUR 安装..."
        if yay -S --noconfirm openresty 2>&1; then
            INSTALL_SUCCESS=1
        fi
    elif command -v paru &> /dev/null; then
        echo "使用 paru 从 AUR 安装..."
        if paru -S --noconfirm openresty 2>&1; then
            INSTALL_SUCCESS=1
        fi
    fi
    
    if [ "$INSTALL_SUCCESS" -eq 0 ]; then
        echo -e "${YELLOW}注意: 未找到 AUR 助手（yay/paru），从源码编译安装${NC}"
        install_openresty_from_source
    else
        echo -e "${GREEN}✓ OpenResty 安装完成${NC}"
    fi
}

# 安装 OpenResty（Alpine Linux）
install_openresty_alpine() {
    echo -e "${BLUE}[4/8] 安装 OpenResty（Alpine Linux）...${NC}"
    
    # Alpine Linux 没有官方 OpenResty 包，从源码编译
    echo -e "${YELLOW}注意: Alpine Linux 需要从源码编译安装${NC}"
    install_openresty_from_source
}

# 安装 OpenResty（Gentoo）
install_openresty_gentoo() {
    echo -e "${BLUE}[4/8] 安装 OpenResty（Gentoo）...${NC}"
    
    # Gentoo 可能需要从源码编译或使用 overlay
    echo -e "${YELLOW}注意: Gentoo 需要从源码编译安装或使用 overlay${NC}"
    install_openresty_from_source
}

# 从源码编译安装 OpenResty
install_openresty_from_source() {
    echo -e "${BLUE}[4/8] 从源码编译安装 OpenResty...${NC}"
    
    local build_dir="/tmp/openresty-build"
    local version="${OPENRESTY_VERSION}"
    
    mkdir -p "$build_dir"
    cd "$build_dir"
    
    # 下载源码
    if [ ! -f "openresty-${version}.tar.gz" ]; then
        echo "下载 OpenResty ${version} 源码..."
        wget "https://openresty.org/download/openresty-${version}.tar.gz"
    fi
    
    # 解压
    tar -xzf "openresty-${version}.tar.gz"
    cd "openresty-${version}"
    
    # 配置（根据系统调整）
    echo "配置 OpenResty..."
    local configure_opts="--prefix=${INSTALL_DIR} \
        --with-http_realip_module \
        --with-http_ssl_module \
        --with-http_stub_status_module \
        --with-http_gzip_static_module \
        --with-pcre \
        --with-luajit"
    
    # Alpine Linux 使用 musl libc，可能需要特殊配置
    if [ "$OS" = "alpine" ]; then
        echo -e "${BLUE}  检测到 Alpine Linux，使用 musl libc 配置...${NC}"
    fi
    
    if ! ./configure $configure_opts; then
        echo -e "${RED}✗ 配置失败，请检查依赖是否完整${NC}"
        echo -e "${YELLOW}所需依赖: gcc, g++, make, pcre-dev, zlib-dev, openssl-dev, perl, readline-dev${NC}"
        exit 1
    fi
    
    # 编译安装
    echo "编译 OpenResty（这可能需要几分钟）..."
    local cpu_cores=$(nproc 2>/dev/null || echo "1")
    if ! make -j${cpu_cores}; then
        echo -e "${RED}✗ 编译失败${NC}"
        echo -e "${YELLOW}提示: 如果编译失败，请检查错误信息，可能需要安装更多依赖${NC}"
        exit 1
    fi
    
    echo "安装 OpenResty..."
    if ! make install; then
        echo -e "${RED}✗ 安装失败${NC}"
        exit 1
    fi
    
    # 清理
    cd /
    rm -rf "$build_dir"
    
    echo -e "${GREEN}✓ OpenResty 编译安装完成${NC}"
}

# 安装 OpenResty
install_openresty() {
    case $OS in
        centos|rhel|fedora|rocky|almalinux|oraclelinux|amazonlinux)
            install_openresty_redhat
            ;;
        ubuntu|debian|linuxmint|raspbian|kali)
            install_openresty_debian
            ;;
        opensuse*|sles)
            install_openresty_suse
            ;;
        arch|manjaro)
            install_openresty_arch
            ;;
        alpine)
            install_openresty_alpine
            ;;
        gentoo)
            install_openresty_gentoo
            ;;
        *)
            echo -e "${YELLOW}警告: 未识别的系统类型 (${OS})，使用源码编译安装${NC}"
            install_openresty_from_source
            ;;
    esac
}

# 创建目录结构
create_directories() {
    echo -e "${BLUE}[5/8] 创建目录结构...${NC}"
    
    mkdir -p "${NGINX_CONF_DIR}"
    mkdir -p "${NGINX_LUA_DIR}/waf"
    mkdir -p "${NGINX_LUA_DIR}/geoip"
    mkdir -p "${NGINX_LOG_DIR}"
    
    echo -e "${GREEN}✓ 目录创建完成${NC}"
}

# 配置 OpenResty
configure_openresty() {
    echo -e "${BLUE}[6/8] 配置 OpenResty...${NC}"
    
    # 创建 systemd 服务文件
    if [ ! -f /etc/systemd/system/openresty.service ]; then
        cat > /etc/systemd/system/openresty.service <<EOF
[Unit]
Description=OpenResty HTTP Server
After=network.target

[Service]
Type=forking
PIDFile=${INSTALL_DIR}/nginx/logs/nginx.pid
ExecStart=${INSTALL_DIR}/bin/openresty
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s TERM \$MAINPID
PrivateTmp=true
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
    fi
    
    # 创建符号链接（可选，方便使用）
    if [ ! -L /usr/local/bin/openresty ]; then
        ln -sf ${INSTALL_DIR}/bin/openresty /usr/local/bin/openresty
    fi
    
    echo -e "${GREEN}✓ OpenResty 配置完成${NC}"
}

# 安装 Lua 模块
install_lua_modules() {
    echo -e "${BLUE}[7/8] 安装 Lua 模块...${NC}"
    
    # 检查 opm 是否可用
    if [ -f "${INSTALL_DIR}/bin/opm" ]; then
        local critical_modules_failed=0
        
        echo "安装 lua-resty-mysql（关键模块）..."
        if ${INSTALL_DIR}/bin/opm get openresty/lua-resty-mysql 2>&1; then
            echo -e "${GREEN}  ✓ lua-resty-mysql 安装成功${NC}"
        else
            echo -e "${RED}  ✗ lua-resty-mysql 安装失败（关键模块）${NC}"
            critical_modules_failed=1
        fi
        
        echo "安装 lua-resty-redis（可选模块）..."
        if ${INSTALL_DIR}/bin/opm get openresty/lua-resty-redis 2>&1; then
            echo -e "${GREEN}  ✓ lua-resty-redis 安装成功${NC}"
        else
            echo -e "${YELLOW}  ⚠ lua-resty-redis 安装失败（可选，不影响基本功能）${NC}"
        fi
        
        echo "安装 lua-resty-maxminddb（可选模块）..."
        if ${INSTALL_DIR}/bin/opm get anjia0532/lua-resty-maxminddb 2>&1; then
            echo -e "${GREEN}  ✓ lua-resty-maxminddb 安装成功${NC}"
        else
            echo -e "${YELLOW}  ⚠ lua-resty-maxminddb 安装失败（可选，仅影响地域封控功能）${NC}"
        fi
        
        if [ $critical_modules_failed -eq 1 ]; then
            echo ""
            echo -e "${YELLOW}⚠ 关键模块 lua-resty-mysql 安装失败${NC}"
            echo -e "${YELLOW}这将影响 WAF 的数据库连接功能${NC}"
            echo ""
            echo -e "${BLUE}手动安装方法:${NC}"
            echo "1. 使用 opm 手动安装:"
            echo "   ${INSTALL_DIR}/bin/opm get openresty/lua-resty-mysql"
            echo ""
            echo "2. 或从源码安装:"
            echo "   cd /tmp"
            echo "   git clone https://github.com/openresty/lua-resty-mysql.git"
            echo "   cp -r lua-resty-mysql/lib/resty ${INSTALL_DIR}/site/lualib/resty/"
            echo ""
            echo -e "${YELLOW}安装完成后，请重启 OpenResty 服务${NC}"
        fi
    else
        echo -e "${YELLOW}警告: opm 未找到，跳过 Lua 模块安装${NC}"
        echo -e "${YELLOW}请手动安装 Lua 模块或使用源码编译方式${NC}"
    fi
    
    echo -e "${GREEN}✓ Lua 模块安装完成${NC}"
}

# 验证安装
verify_installation() {
    echo -e "${BLUE}[8/8] 验证安装...${NC}"
    
    if [ -f "${INSTALL_DIR}/bin/openresty" ]; then
        local version=$(${INSTALL_DIR}/bin/openresty -v 2>&1 | head -n 1)
        echo -e "${GREEN}✓ OpenResty 安装成功${NC}"
        echo "  版本: $version"
        echo "  安装路径: ${INSTALL_DIR}"
        echo "  配置文件: ${NGINX_CONF_DIR}/nginx.conf"
        echo "  Lua 脚本: ${NGINX_LUA_DIR}"
    else
        echo -e "${RED}✗ OpenResty 安装失败${NC}"
        exit 1
    fi
    
    # 测试配置文件
    if [ -f "${NGINX_CONF_DIR}/nginx.conf" ]; then
        if ${INSTALL_DIR}/bin/openresty -t 2>&1 | grep -q "syntax is ok"; then
            echo -e "${GREEN}✓ 配置文件语法正确${NC}"
        else
            echo -e "${YELLOW}⚠ 配置文件可能有语法错误，请检查${NC}"
        fi
    fi
}

# 显示后续步骤
show_next_steps() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}安装完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}后续步骤:${NC}"
    echo ""
    echo "1. 启动 OpenResty 服务:"
    echo "   sudo systemctl start openresty"
    echo ""
    echo "2. 设置开机自启:"
    echo "   sudo systemctl enable openresty"
    echo ""
    echo "3. 检查服务状态:"
    echo "   sudo systemctl status openresty"
    echo ""
    echo "4. 测试配置文件:"
    echo "   ${INSTALL_DIR}/bin/openresty -t"
    echo ""
    echo "5. 重新加载配置（不中断服务）:"
    echo "   sudo systemctl reload openresty"
    echo ""
    echo "6. 查看日志:"
    echo "   tail -f ${NGINX_LOG_DIR}/error.log"
    echo "   tail -f ${NGINX_LOG_DIR}/access.log"
    echo ""
    echo -e "${BLUE}配置文件位置:${NC}"
    echo "  主配置: ${NGINX_CONF_DIR}/nginx.conf"
    echo "  Lua 脚本: ${NGINX_LUA_DIR}"
    echo ""
    echo -e "${BLUE}项目文件部署:${NC}"
    echo "  1. 复制配置文件到 ${NGINX_CONF_DIR}/"
    echo "  2. 复制 Lua 脚本到 ${NGINX_LUA_DIR}/"
    echo "  3. 创建数据库并导入 SQL 文件"
    echo "  4. 修改 ${NGINX_LUA_DIR}/config.lua 中的数据库配置"
    echo "  5. 运行安装脚本安装 GeoIP2 数据库（可选）"
    echo ""
}

# 主函数
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}OpenResty 一键安装和配置脚本${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # 检查 root 权限
    check_root
    
    # 检测操作系统
    detect_os
    
    # 安装依赖
    install_dependencies
    
    # 检查现有安装
    check_existing
    
    # 安装 OpenResty
    install_openresty
    
    # 创建目录
    create_directories
    
    # 配置 OpenResty
    configure_openresty
    
    # 安装 Lua 模块
    install_lua_modules
    
    # 验证安装
    verify_installation
    
    # 显示后续步骤
    show_next_steps
}

# 执行主函数
main "$@"

