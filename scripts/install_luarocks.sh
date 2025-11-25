#!/bin/bash

# LuaRocks 安装脚本
# 功能：为 OpenResty 安装 LuaRocks，用于安装 lua-resty-bcrypt 等模块
# 注意：此脚本配置 LuaRocks 使用 OpenResty 的 LuaJIT

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

# 配置变量
OPENRESTY_PREFIX="${OPENRESTY_PREFIX:-/usr/local/openresty}"
LUAROCKS_VERSION="${LUAROCKS_VERSION:-3.11.1}"
LUAROCKS_URL="https://luarocks.org/releases/luarocks-${LUAROCKS_VERSION}.tar.gz"
INSTALL_PREFIX="/usr/local"

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误: 需要 root 权限来安装 LuaRocks${NC}"
        exit 1
    fi
}

# 检查 OpenResty 是否安装
check_openresty() {
    if [ ! -d "$OPENRESTY_PREFIX" ]; then
        echo -e "${RED}错误: OpenResty 未安装或路径不正确: $OPENRESTY_PREFIX${NC}"
        echo -e "${YELLOW}提示: 请先安装 OpenResty${NC}"
        exit 1
    fi
    
    if [ ! -f "$OPENRESTY_PREFIX/luajit/bin/luajit" ]; then
        echo -e "${RED}错误: 未找到 LuaJIT: $OPENRESTY_PREFIX/luajit/bin/luajit${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ 检测到 OpenResty: $OPENRESTY_PREFIX${NC}"
}

# 检测系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif [ -f /etc/redhat-release ]; then
        OS=$(cat /etc/redhat-release | tr '[:upper:]' '[:lower:]' | sed 's/^\([^ ]*\).*/\1/')
    else
        OS="unknown"
    fi
    
    echo -e "${BLUE}检测到系统: $OS${NC}"
}

# 安装依赖
install_dependencies() {
    echo -e "${BLUE}[2/5] 安装依赖包...${NC}"
    
    case $OS in
        centos|rhel|fedora|rocky|almalinux|oraclelinux|amazonlinux)
            if command -v dnf &> /dev/null; then
                dnf install -y wget gcc make unzip || yum install -y wget gcc make unzip
            else
                yum install -y wget gcc make unzip
            fi
            ;;
        ubuntu|debian|linuxmint|raspbian|kali)
            apt-get update
            apt-get install -y wget build-essential unzip
            ;;
        opensuse*|sles)
            zypper install -y wget gcc make unzip
            ;;
        arch|manjaro)
            pacman -S --noconfirm wget gcc make unzip
            ;;
        alpine)
            apk add --no-cache wget gcc make unzip linux-headers
            ;;
        *)
            echo -e "${YELLOW}警告: 未识别的系统类型，尝试安装基本依赖${NC}"
            if command -v yum &> /dev/null; then
                yum install -y wget gcc make unzip || true
            elif command -v apt-get &> /dev/null; then
                apt-get update && apt-get install -y wget gcc make unzip || true
            fi
            ;;
    esac
    
    echo -e "${GREEN}✓ 依赖包安装完成${NC}"
}

# 下载 LuaRocks
download_luarocks() {
    echo -e "${BLUE}[3/5] 下载 LuaRocks...${NC}"
    
    local download_dir="/tmp/luarocks_install"
    mkdir -p "$download_dir"
    cd "$download_dir"
    
    if [ -f "luarocks-${LUAROCKS_VERSION}.tar.gz" ]; then
        echo -e "${YELLOW}已存在下载文件，跳过下载${NC}"
    else
        echo -e "${BLUE}下载地址: $LUAROCKS_URL${NC}"
        if ! wget -q --show-progress "$LUAROCKS_URL" -O "luarocks-${LUAROCKS_VERSION}.tar.gz"; then
            echo -e "${RED}✗ 下载失败${NC}"
            return 1
        fi
    fi
    
    if [ -d "luarocks-${LUAROCKS_VERSION}" ]; then
        rm -rf "luarocks-${LUAROCKS_VERSION}"
    fi
    
    tar -xzf "luarocks-${LUAROCKS_VERSION}.tar.gz"
    cd "luarocks-${LUAROCKS_VERSION}"
    
    echo -e "${GREEN}✓ 下载完成${NC}"
}

# 配置和编译 LuaRocks
configure_luarocks() {
    echo -e "${BLUE}[4/5] 配置和编译 LuaRocks...${NC}"
    
    local download_dir="/tmp/luarocks_install/luarocks-${LUAROCKS_VERSION}"
    cd "$download_dir"
    
    # 配置 LuaRocks 使用 OpenResty 的 LuaJIT
    local luajit_bin="$OPENRESTY_PREFIX/luajit/bin/luajit"
    local luajit_include="$OPENRESTY_PREFIX/luajit/include/luajit-2.1"
    
    echo -e "${BLUE}配置参数:${NC}"
    echo "  --prefix=$INSTALL_PREFIX"
    echo "  --with-lua=$OPENRESTY_PREFIX/luajit"
    echo "  --with-lua-include=$luajit_include"
    echo ""
    
    if ! ./configure \
        --prefix="$INSTALL_PREFIX" \
        --with-lua="$OPENRESTY_PREFIX/luajit" \
        --with-lua-include="$luajit_include" \
        --lua-suffix=jit \
        --with-lua-interpreter=luajit; then
        echo -e "${RED}✗ 配置失败${NC}"
        return 1
    fi
    
    if ! make; then
        echo -e "${RED}✗ 编译失败${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ 编译完成${NC}"
}

# 安装 LuaRocks
install_luarocks() {
    echo -e "${BLUE}[5/5] 安装 LuaRocks...${NC}"
    
    local download_dir="/tmp/luarocks_install/luarocks-${LUAROCKS_VERSION}"
    cd "$download_dir"
    
    if ! make install; then
        echo -e "${RED}✗ 安装失败${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ 安装完成${NC}"
}

# 验证安装
verify_installation() {
    echo -e "${BLUE}验证安装...${NC}"
    
    if command -v luarocks &> /dev/null; then
        local version=$(luarocks --version | head -n 1)
        echo -e "${GREEN}✓ LuaRocks 安装成功: $version${NC}"
        
        # 测试 LuaRocks 是否能正常工作
        if luarocks list &> /dev/null; then
            echo -e "${GREEN}✓ LuaRocks 工作正常${NC}"
        else
            echo -e "${YELLOW}⚠ LuaRocks 可能配置不正确${NC}"
        fi
    else
        echo -e "${RED}✗ LuaRocks 未找到，可能安装失败${NC}"
        return 1
    fi
}

# 显示安装信息
show_info() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}LuaRocks 安装完成${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "${BLUE}安装信息:${NC}"
    echo "  LuaRocks 路径: $(which luarocks)"
    echo "  LuaRocks 版本: $(luarocks --version | head -n 1)"
    echo "  LuaJIT 路径: $OPENRESTY_PREFIX/luajit/bin/luajit"
    echo ""
    echo -e "${BLUE}下一步:${NC}"
    echo "  安装 lua-resty-bcrypt:"
    echo "    luarocks install lua-resty-bcrypt"
    echo ""
    echo -e "${YELLOW}注意:${NC}"
    echo "  - LuaRocks 已配置为使用 OpenResty 的 LuaJIT"
    echo "  - 安装的模块将位于: $OPENRESTY_PREFIX/site/lualib/"
    echo "  - 如果安装失败，请检查网络连接和依赖包"
    echo ""
}

# 主函数
main() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}LuaRocks 安装脚本${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    check_root
    detect_os
    check_openresty
    
    install_dependencies
    download_luarocks
    configure_luarocks
    install_luarocks
    verify_installation
    show_info
}

# 运行主函数
main

