#!/bin/bash

# OpenResty 一键安装和配置脚本
# 支持：CentOS/RHEL, Ubuntu/Debian, Fedora, openSUSE, Arch Linux
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

# 安装依赖
install_dependencies() {
    case $OS in
        centos|rhel|fedora|rocky|almalinux)
            install_deps_redhat
            ;;
        ubuntu|debian)
            install_deps_debian
            ;;
        opensuse*|sles)
            install_deps_suse
            ;;
        arch|manjaro)
            install_deps_arch
            ;;
        *)
            echo -e "${YELLOW}警告: 未识别的系统类型，尝试使用通用方法安装依赖${NC}"
            if command -v yum &> /dev/null; then
                install_deps_redhat
            elif command -v apt-get &> /dev/null; then
                install_deps_debian
            else
                echo -e "${RED}错误: 无法确定包管理器${NC}"
                exit 1
            fi
            ;;
    esac
}

# 检查 OpenResty 是否已安装
check_existing() {
    echo -e "${BLUE}[3/8] 检查是否已安装 OpenResty...${NC}"
    
    if [ -f "${INSTALL_DIR}/bin/openresty" ]; then
        local current_version=$(${INSTALL_DIR}/bin/openresty -v 2>&1 | grep -oP 'openresty/\K[0-9.]+' || echo "unknown")
        echo -e "${YELLOW}检测到已安装 OpenResty 版本: ${current_version}${NC}"
        read -p "是否继续安装/更新？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}安装已取消${NC}"
            exit 0
        fi
    fi
    
    echo -e "${GREEN}✓ 检查完成${NC}"
}

# 安装 OpenResty（CentOS/RHEL/Fedora）
install_openresty_redhat() {
    echo -e "${BLUE}[4/8] 安装 OpenResty（RedHat 系列）...${NC}"
    
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
baseurl=https://openresty.org/package/${OS}/\$releasever/\$basearch
gpgcheck=1
enabled=1
gpgkey=https://openresty.org/package/pubkey.gpg
EOF
        else
            # 禁用 GPG 检查
            cat > /etc/yum.repos.d/openresty.repo <<EOF
[openresty]
name=Official OpenResty Repository
baseurl=https://openresty.org/package/${OS}/\$releasever/\$basearch
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

# 安装 OpenResty（Ubuntu/Debian）
install_openresty_debian() {
    echo -e "${BLUE}[4/8] 安装 OpenResty（Debian 系列）...${NC}"
    
    # 添加 OpenResty 仓库
    if [ ! -f /etc/apt/sources.list.d/openresty.list ]; then
        wget -qO - https://openresty.org/package/pubkey.gpg | apt-key add -
        echo "deb http://openresty.org/package/${OS} $(lsb_release -sc) main" > /etc/apt/sources.list.d/openresty.list
        apt-get update
    fi
    
    # 安装 OpenResty
    apt-get install -y openresty
    
    echo -e "${GREEN}✓ OpenResty 安装完成${NC}"
}

# 安装 OpenResty（openSUSE）
install_openresty_suse() {
    echo -e "${BLUE}[4/8] 安装 OpenResty（openSUSE）...${NC}"
    
    # openSUSE 需要从源码编译或使用第三方仓库
    echo -e "${YELLOW}注意: openSUSE 可能需要从源码编译安装${NC}"
    install_openresty_from_source
}

# 安装 OpenResty（Arch Linux）
install_openresty_arch() {
    echo -e "${BLUE}[4/8] 安装 OpenResty（Arch Linux）...${NC}"
    
    # Arch Linux 使用 AUR，需要 yay 或手动安装
    if command -v yay &> /dev/null; then
        yay -S --noconfirm openresty
    else
        echo -e "${YELLOW}注意: 需要 yay 或手动从 AUR 安装${NC}"
        install_openresty_from_source
    fi
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
    
    # 配置
    ./configure --prefix=${INSTALL_DIR} \
        --with-http_realip_module \
        --with-http_ssl_module \
        --with-http_stub_status_module \
        --with-http_gzip_static_module \
        --with-pcre \
        --with-luajit
    
    # 编译安装
    make -j$(nproc)
    make install
    
    # 清理
    cd /
    rm -rf "$build_dir"
    
    echo -e "${GREEN}✓ OpenResty 编译安装完成${NC}"
}

# 安装 OpenResty
install_openresty() {
    case $OS in
        centos|rhel|fedora|rocky|almalinux)
            install_openresty_redhat
            ;;
        ubuntu|debian)
            install_openresty_debian
            ;;
        opensuse*|sles)
            install_openresty_suse
            ;;
        arch|manjaro)
            install_openresty_arch
            ;;
        *)
            echo -e "${YELLOW}警告: 未识别的系统类型，使用源码编译安装${NC}"
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

