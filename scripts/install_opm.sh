#!/bin/bash

# opm (OpenResty Package Manager) 安装和验证脚本
# 用途：安装 opm 并验证安装是否成功

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# 查找 opm
find_opm() {
    local opm_path=""
    
    # 首先尝试使用 command -v 查找（会检查 PATH）
    if command -v opm &> /dev/null; then
        opm_path=$(command -v opm)
        if [ -n "$opm_path" ] && [ -f "$opm_path" ] && [ -x "$opm_path" ]; then
            echo "$opm_path"
            return 0
        fi
    fi
    
    # 如果通过包管理器安装，尝试查询包文件列表
    if command -v rpm &> /dev/null; then
        local rpm_opm=$(rpm -ql openresty-resty 2>/dev/null | grep -E "/opm$" | head -1)
        if [ -n "$rpm_opm" ] && [ -f "$rpm_opm" ] && [ -x "$rpm_opm" ]; then
            echo "$rpm_opm"
            return 0
        fi
    elif command -v dpkg &> /dev/null; then
        local dpkg_opm=$(dpkg -L openresty-resty 2>/dev/null | grep -E "/opm$" | head -1)
        if [ -n "$dpkg_opm" ] && [ -f "$dpkg_opm" ] && [ -x "$dpkg_opm" ]; then
            echo "$dpkg_opm"
            return 0
        fi
    fi
    
    # 检查多个可能的位置
    local possible_paths=(
        "/usr/local/openresty/bin/opm"
        "/usr/local/bin/opm"
        "/usr/bin/opm"
        "/opt/openresty/bin/opm"
    )
    
    for path in "${possible_paths[@]}"; do
        if [ -n "$path" ] && [ -f "$path" ] && [ -x "$path" ]; then
            opm_path="$path"
            break
        fi
    done
    
    # 如果还是找不到，尝试使用 find 命令搜索
    if [ -z "$opm_path" ]; then
        local found_opm=$(find /usr /opt /usr/local -name "opm" -type f -executable 2>/dev/null | head -1)
        if [ -n "$found_opm" ]; then
            opm_path="$found_opm"
        fi
    fi
    
    echo "$opm_path"
}

# 检查 OpenResty 是否已安装
check_openresty() {
    echo -e "${BLUE}[1/4] 检查 OpenResty 是否已安装...${NC}"
    
    local openresty_path=""
    if command -v openresty &> /dev/null; then
        openresty_path=$(command -v openresty)
    elif [ -f "/usr/local/openresty/bin/openresty" ]; then
        openresty_path="/usr/local/openresty/bin/openresty"
    fi
    
    if [ -n "$openresty_path" ] && [ -f "$openresty_path" ]; then
        local version=$($openresty_path -v 2>&1 | head -n 1)
        echo -e "${GREEN}✓ OpenResty 已安装${NC}"
        echo "  路径: $openresty_path"
        echo "  版本: $version"
        return 0
    else
        echo -e "${RED}✗ OpenResty 未安装${NC}"
        echo -e "${YELLOW}请先安装 OpenResty${NC}"
        echo "  运行: sudo ./scripts/install_openresty.sh"
        return 1
    fi
}

# 检查 opm 是否已安装
check_opm() {
    echo -e "${BLUE}[2/4] 检查 opm 是否已安装...${NC}"
    
    local opm_path=$(find_opm)
    
    if [ -n "$opm_path" ] && [ -f "$opm_path" ] && [ -x "$opm_path" ]; then
        echo -e "${GREEN}✓ opm 已安装${NC}"
        echo "  路径: $opm_path"
        
        # 显示版本信息
        if "$opm_path" --version &>/dev/null; then
            local version=$("$opm_path" --version 2>&1 | head -n 1)
            echo "  版本: $version"
        fi
        
        return 0
    else
        echo -e "${YELLOW}⚠ opm 未找到${NC}"
        return 1
    fi
}

# 安装 opm
install_opm() {
    echo -e "${BLUE}[3/4] 安装 opm...${NC}"
    
    detect_os
    
    local install_success=0
    
    # RedHat 系列
    if [[ "$OS" =~ ^(centos|rhel|fedora|rocky|almalinux|oraclelinux|amazonlinux)$ ]]; then
        echo "检测到 RedHat 系列系统，使用 yum/dnf 安装..."
        
        if command -v dnf &> /dev/null; then
            echo "使用 dnf 安装 openresty-resty..."
            if dnf install -y openresty-resty 2>&1 | tee /tmp/opm_install.log; then
                if grep -qiE "已安装|installed|complete|Nothing to do|无需" /tmp/opm_install.log; then
                    install_success=1
                    echo -e "${GREEN}✓ openresty-resty 安装成功${NC}"
                fi
            fi
        elif command -v yum &> /dev/null; then
            echo "使用 yum 安装 openresty-resty..."
            if yum install -y openresty-resty 2>&1 | tee /tmp/opm_install.log; then
                if grep -qiE "已安装|installed|complete|Nothing to do|无需" /tmp/opm_install.log; then
                    install_success=1
                    echo -e "${GREEN}✓ openresty-resty 安装成功${NC}"
                fi
            fi
        fi
        
    # Debian 系列
    elif [[ "$OS" =~ ^(ubuntu|debian|linuxmint|raspbian|kali)$ ]]; then
        echo "检测到 Debian 系列系统，使用 apt-get 安装..."
        
        if command -v apt-get &> /dev/null; then
            echo "更新软件包列表..."
            apt-get update -qq
            
            echo "使用 apt-get 安装 openresty-resty..."
            if apt-get install -y openresty-resty 2>&1 | tee /tmp/opm_install.log; then
                if grep -qiE "已安装|installed|complete|Setting up|已经是最新版本" /tmp/opm_install.log; then
                    install_success=1
                    echo -e "${GREEN}✓ openresty-resty 安装成功${NC}"
                fi
            fi
        fi
    else
        echo -e "${YELLOW}⚠ 未识别的系统类型，尝试通用方法...${NC}"
        
        if command -v yum &> /dev/null || command -v dnf &> /dev/null; then
            if command -v dnf &> /dev/null; then
                dnf install -y openresty-resty && install_success=1
            else
                yum install -y openresty-resty && install_success=1
            fi
        elif command -v apt-get &> /dev/null; then
            apt-get update -qq
            apt-get install -y openresty-resty && install_success=1
        fi
    fi
    
    rm -f /tmp/opm_install.log 2>/dev/null || true
    
    if [ $install_success -eq 1 ]; then
        # 刷新命令缓存
        hash -r 2>/dev/null || true
        
        # 重新查找 opm
        local opm_path=$(find_opm)
        if [ -n "$opm_path" ]; then
            echo -e "${GREEN}✓ opm 安装成功，路径: ${opm_path}${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠ 包安装成功但未找到 opm，尝试查询包文件列表...${NC}"
            
            # 查询包文件列表
            if command -v rpm &> /dev/null; then
                local opm_files=$(rpm -ql openresty-resty 2>/dev/null | grep -E "/opm$")
                if [ -n "$opm_files" ]; then
                    for opm_file in $opm_files; do
                        if [ -f "$opm_file" ] && [ -x "$opm_file" ]; then
                            echo -e "${GREEN}✓ 找到 opm: ${opm_file}${NC}"
                            return 0
                        fi
                    done
                fi
            elif command -v dpkg &> /dev/null; then
                local opm_files=$(dpkg -L openresty-resty 2>/dev/null | grep -E "/opm$")
                if [ -n "$opm_files" ]; then
                    for opm_file in $opm_files; do
                        if [ -f "$opm_file" ] && [ -x "$opm_file" ]; then
                            echo -e "${GREEN}✓ 找到 opm: ${opm_file}${NC}"
                            return 0
                        fi
                    done
                fi
            fi
            
            echo -e "${RED}✗ 无法找到 opm，请手动检查${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ openresty-resty 安装失败${NC}"
        return 1
    fi
}

# 验证 opm 安装
verify_opm() {
    echo -e "${BLUE}[4/4] 验证 opm 安装...${NC}"
    
    local opm_path=$(find_opm)
    
    if [ -z "$opm_path" ] || [ ! -f "$opm_path" ] || [ ! -x "$opm_path" ]; then
        echo -e "${RED}✗ opm 未找到或不可执行${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ opm 路径: ${opm_path}${NC}"
    
    # 测试 opm 命令
    echo "测试 opm 命令..."
    
    # 1. 检查版本
    if "$opm_path" --version &>/dev/null; then
        local version=$("$opm_path" --version 2>&1 | head -n 1)
        echo -e "${GREEN}  ✓ 版本信息: ${version}${NC}"
    else
        echo -e "${YELLOW}  ⚠ 无法获取版本信息${NC}"
    fi
    
    # 2. 测试 help 命令
    if "$opm_path" --help &>/dev/null; then
        echo -e "${GREEN}  ✓ help 命令正常${NC}"
    else
        echo -e "${YELLOW}  ⚠ help 命令异常${NC}"
    fi
    
    # 3. 测试 list 命令（列出已安装的包）
    if "$opm_path" list &>/dev/null; then
        echo -e "${GREEN}  ✓ list 命令正常${NC}"
        local installed_count=$("$opm_path" list 2>/dev/null | wc -l)
        echo "  已安装包数量: $installed_count"
    else
        echo -e "${YELLOW}  ⚠ list 命令异常${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ opm 安装验证成功！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}使用方法:${NC}"
    echo "  安装 Lua 模块:"
    echo "    $opm_path get openresty/lua-resty-mysql"
    echo "    $opm_path get openresty/lua-resty-redis"
    echo ""
    echo "  查看已安装的包:"
    echo "    $opm_path list"
    echo ""
    echo "  查看帮助:"
    echo "    $opm_path --help"
    echo ""
    
    return 0
}

# 主函数
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}opm (OpenResty Package Manager) 安装脚本${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}错误: 需要 root 权限${NC}"
        echo "请使用: sudo $0"
        exit 1
    fi
    
    # 检查 OpenResty
    if ! check_openresty; then
        exit 1
    fi
    
    # 检查 opm
    if check_opm; then
        echo ""
        echo -e "${GREEN}opm 已安装，开始验证...${NC}"
        verify_opm
    else
        echo ""
        echo -e "${YELLOW}opm 未安装，开始安装...${NC}"
        if install_opm; then
            echo ""
            verify_opm
        else
            echo ""
            echo -e "${RED}========================================${NC}"
            echo -e "${RED}✗ opm 安装失败${NC}"
            echo -e "${RED}========================================${NC}"
            echo ""
            echo -e "${BLUE}手动安装方法:${NC}"
            echo ""
            echo "1. RedHat 系列 (CentOS/RHEL/Fedora):"
            echo "   sudo yum install -y openresty-resty"
            echo "   或"
            echo "   sudo dnf install -y openresty-resty"
            echo ""
            echo "2. Debian 系列 (Ubuntu/Debian):"
            echo "   sudo apt-get update"
            echo "   sudo apt-get install -y openresty-resty"
            echo ""
            echo "3. 安装后查找 opm:"
            echo "   find /usr /opt /usr/local -name opm -type f 2>/dev/null"
            echo ""
            exit 1
        fi
    fi
}

# 执行主函数
main "$@"

