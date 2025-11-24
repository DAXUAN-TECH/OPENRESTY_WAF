#!/bin/bash

# 公共函数库
# 用途：供其他脚本引用的公共函数

# 颜色定义（统一）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取项目根目录（返回相对路径）
get_project_root() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    echo "$script_dir/.."
}

# 检查依赖（通用）
check_dependencies_common() {
    local missing_deps=()
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if ! command -v tar &> /dev/null; then
        missing_deps+=("tar")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "错误: 缺少以下依赖: ${missing_deps[*]}"
        echo "请先安装这些依赖"
        return 1
    fi
    
    return 0
}

# 检查是否为 root 用户
check_root_common() {
    if [ "$EUID" -ne 0 ]; then
        echo "错误: 需要 root 权限"
        echo "请使用: sudo $0"
        return 1
    fi
    return 0
}

# 检测操作系统类型（统一函数）
detect_os_common() {
    local step_info="${1:-[1/8]}"
    echo -e "${BLUE}${step_info} 检测操作系统...${NC}"
    
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
        echo -e "${YELLOW}⚠ 系统类型: 未知${NC}"
    fi
    
    # 导出变量供调用者使用
    export OS OS_VERSION OS_LIKE
}

# 通用下载函数（支持 wget 和 curl，自动验证文件类型）
# 参数: $1=URL, $2=输出文件路径, $3=期望的文件类型（可选，如 "RPM"、"DEB"、"tar.gz"）
# 返回: 0=成功, 1=失败
download_file_common() {
    local url="$1"
    local output_file="$2"
    local expected_type="${3:-}"
    local downloaded=0
    
    # 优先使用 wget
    if command -v wget &> /dev/null; then
        if wget -q "$url" -O "$output_file" 2>/dev/null && [ -s "$output_file" ]; then
            downloaded=1
        fi
    # 如果 wget 不可用，使用 curl
    elif command -v curl &> /dev/null; then
        if curl -L -f -s "$url" -o "$output_file" 2>/dev/null && [ -s "$output_file" ]; then
            downloaded=1
        fi
    else
        echo -e "${RED}✗ 错误: 未找到 wget 或 curl${NC}"
        return 1
    fi
    
    if [ $downloaded -eq 0 ]; then
        return 1
    fi
    
    # 如果指定了期望的文件类型，验证文件
    if [ -n "$expected_type" ]; then
        case "$expected_type" in
            "RPM"|"rpm")
                if ! file "$output_file" 2>/dev/null | grep -qi "RPM\|rpm"; then
                    echo -e "${YELLOW}  下载的文件不是有效的 RPM 包${NC}"
                    rm -f "$output_file"
                    return 1
                fi
                ;;
            "DEB"|"deb")
                if ! file "$output_file" 2>/dev/null | grep -qi "Debian\|deb"; then
                    echo -e "${YELLOW}  下载的文件不是有效的 DEB 包${NC}"
                    rm -f "$output_file"
                    return 1
                fi
                ;;
            "tar.gz"|"TAR.GZ")
                if ! file "$output_file" 2>/dev/null | grep -qi "gzip\|tar"; then
                    echo -e "${YELLOW}  下载的文件不是有效的 tar.gz 包${NC}"
                    rm -f "$output_file"
                    return 1
                fi
                ;;
        esac
    fi
    
    return 0
}

# 尝试下载多个 URL（按顺序尝试，直到成功）
# 参数: $1=输出文件路径, $2=期望的文件类型, $3...=URL列表
# 返回: 0=成功, 1=全部失败
download_file_with_fallback() {
    local output_file="$1"
    local expected_type="$2"
    shift 2
    local urls=("$@")
    local downloaded=0
    
    for url in "${urls[@]}"; do
        echo "尝试下载: $url"
        if download_file_common "$url" "$output_file" "$expected_type"; then
            downloaded=1
            echo -e "${GREEN}✓ 下载成功${NC}"
            break
        else
            echo -e "${YELLOW}  下载失败，尝试下一个...${NC}"
            rm -f "$output_file"
        fi
    done
    
    if [ $downloaded -eq 0 ]; then
        return 1
    fi
    
    return 0
}

# 检测硬件配置（统一函数）
# 返回: 设置全局变量 CPU_CORES, TOTAL_MEM_GB, TOTAL_MEM_MB
detect_hardware_common() {
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
    
    # 导出变量供调用者使用
    export CPU_CORES TOTAL_MEM_GB TOTAL_MEM_MB
}

# 简化的操作系统检测（仅检测基本类型，不显示详细信息）
# 返回: 设置全局变量 OS
detect_os_simple() {
    # 优先使用 /etc/os-release (标准方法)
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        
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
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
    else
        OS="unknown"
    fi
    
    # 导出变量供调用者使用
    export OS
}

