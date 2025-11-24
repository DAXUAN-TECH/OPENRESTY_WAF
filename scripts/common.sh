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

# ============================================
# 日志函数
# ============================================

# 基础日志函数
# 参数: $1=日志级别, $2...=日志消息
# 如果设置了 LOG_FILE 环境变量，会同时写入文件
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[${timestamp}] [${level}] ${message}"
    
    # 根据级别选择颜色
    case "$level" in
        "INFO")
            echo -e "${BLUE}${log_entry}${NC}"
            ;;
        "ERROR")
            echo -e "${RED}${log_entry}${NC}" >&2
            ;;
        "WARN"|"WARNING")
            echo -e "${YELLOW}${log_entry}${NC}"
            ;;
        "SUCCESS")
            echo -e "${GREEN}${log_entry}${NC}"
            ;;
        *)
            echo "${log_entry}"
            ;;
    esac
    
    # 如果设置了 LOG_FILE，写入文件
    if [ -n "$LOG_FILE" ]; then
        echo "${log_entry}" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# 信息日志
log_info() {
    log "INFO" "$@"
}

# 错误日志
log_error() {
    log "ERROR" "$@"
}

# 警告日志
log_warn() {
    log "WARN" "$@"
}

# 成功日志
log_success() {
    log "SUCCESS" "$@"
}

# ============================================
# 服务管理函数
# ============================================

# 启动服务
# 参数: $1=服务名（可以是多个，用空格分隔）
# 返回: 0=成功, 1=失败
service_start() {
    local service_names=("$@")
    local started=0
    
    for service_name in "${service_names[@]}"; do
        if command -v systemctl &> /dev/null; then
            if systemctl start "$service_name" 2>/dev/null; then
                started=1
                echo -e "${GREEN}✓ 服务 ${service_name} 启动成功（systemd）${NC}"
                break
            fi
        elif command -v service &> /dev/null; then
            if service "$service_name" start 2>/dev/null; then
                started=1
                echo -e "${GREEN}✓ 服务 ${service_name} 启动成功（service）${NC}"
                break
            fi
        fi
    done
    
    if [ $started -eq 0 ]; then
        echo -e "${YELLOW}⚠ 服务启动失败，请手动检查${NC}"
        return 1
    fi
    
    return 0
}

# 停止服务
# 参数: $1=服务名（可以是多个，用空格分隔）
# 返回: 0=成功, 1=失败
service_stop() {
    local service_names=("$@")
    local stopped=0
    
    for service_name in "${service_names[@]}"; do
        if command -v systemctl &> /dev/null; then
            if systemctl is-active --quiet "$service_name" 2>/dev/null; then
                systemctl stop "$service_name" 2>/dev/null && stopped=1
                echo -e "${GREEN}✓ 服务 ${service_name} 已停止${NC}"
                break
            fi
        elif command -v service &> /dev/null; then
            if service "$service_name" status 2>/dev/null | grep -q "running"; then
                service "$service_name" stop 2>/dev/null && stopped=1
                echo -e "${GREEN}✓ 服务 ${service_name} 已停止${NC}"
                break
            fi
        fi
    done
    
    if [ $stopped -eq 0 ]; then
        echo -e "${YELLOW}服务未运行或已停止${NC}"
    fi
    
    return 0
}

# 重启服务
# 参数: $1=服务名（可以是多个，用空格分隔）
# 返回: 0=成功, 1=失败
service_restart() {
    local service_names=("$@")
    
    for service_name in "${service_names[@]}"; do
        if command -v systemctl &> /dev/null; then
            if systemctl restart "$service_name" 2>/dev/null; then
                echo -e "${GREEN}✓ 服务 ${service_name} 重启成功${NC}"
                return 0
            fi
        elif command -v service &> /dev/null; then
            if service "$service_name" restart 2>/dev/null; then
                echo -e "${GREEN}✓ 服务 ${service_name} 重启成功${NC}"
                return 0
            fi
        fi
    done
    
    echo -e "${YELLOW}⚠ 服务重启失败${NC}"
    return 1
}

# 检查服务状态
# 参数: $1=服务名（可以是多个，用空格分隔）
# 返回: 0=运行中, 1=未运行
service_status() {
    local service_names=("$@")
    
    for service_name in "${service_names[@]}"; do
        if command -v systemctl &> /dev/null; then
            if systemctl is-active --quiet "$service_name" 2>/dev/null; then
                return 0
            fi
        elif command -v service &> /dev/null; then
            if service "$service_name" status 2>/dev/null | grep -q "running"; then
                return 0
            fi
        fi
    done
    
    return 1
}

# 等待服务启动
# 参数: $1=服务名, $2=检查命令（可选，默认使用 service_status）, $3=最大等待时间（秒，默认30）
# 返回: 0=成功, 1=超时
wait_for_service() {
    local service_name="$1"
    local check_cmd="${2:-}"
    local max_wait="${3:-30}"
    local waited=0
    
    # 如果没有提供检查命令，使用默认的 service_status
    if [ -z "$check_cmd" ]; then
        check_cmd="service_status ${service_name}"
    fi
    
    echo -e "${BLUE}等待服务 ${service_name} 启动...${NC}"
    while [ $waited -lt $max_wait ]; do
        if eval "$check_cmd" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ 服务 ${service_name} 已启动${NC}"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
        echo -n "."
    done
    echo ""
    
    echo -e "${RED}✗ 服务 ${service_name} 启动超时（等待了 ${max_wait} 秒）${NC}"
    return 1
}

# ============================================
# 备份函数
# ============================================

# 备份文件（带时间戳）
# 参数: $1=源文件路径
# 返回: 备份文件路径（如果成功）
backup_file_with_timestamp() {
    local source_file="$1"
    
    if [ ! -f "$source_file" ]; then
        echo -e "${YELLOW}⚠ 文件不存在，跳过备份: ${source_file}${NC}"
        return 1
    fi
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${source_file}.bak.${timestamp}"
    
    if cp "$source_file" "$backup_file" 2>/dev/null; then
        echo -e "${GREEN}✓ 已备份到: ${backup_file}${NC}"
        echo "$backup_file"
        return 0
    else
        echo -e "${RED}✗ 备份失败: ${source_file}${NC}"
        return 1
    fi
}

# 备份文件（简单备份，覆盖已有备份）
# 参数: $1=源文件路径, $2=备份文件路径（可选，默认添加 .bak）
backup_file() {
    local source_file="$1"
    local backup_file="${2:-${source_file}.bak}"
    
    if [ ! -f "$source_file" ]; then
        echo -e "${YELLOW}⚠ 文件不存在，跳过备份: ${source_file}${NC}"
        return 1
    fi
    
    if cp "$source_file" "$backup_file" 2>/dev/null; then
        echo -e "${GREEN}✓ 已备份到: ${backup_file}${NC}"
        return 0
    else
        echo -e "${RED}✗ 备份失败: ${source_file}${NC}"
        return 1
    fi
}

# ============================================
# 交互式输入函数
# ============================================

# 确认操作（是/否）
# 参数: $1=提示信息, $2=默认值（Y/n，默认Y）
# 返回: 0=是, 1=否
confirm() {
    local prompt="$1"
    local default="${2:-Y}"
    local reply
    
    if [ "$default" = "Y" ]; then
        read -p "${prompt} [Y/n]: " reply
        reply="${reply:-Y}"
    else
        read -p "${prompt} [y/N]: " reply
        reply="${reply:-N}"
    fi
    
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# 选择操作（从选项列表中选择）
# 参数: $1=提示信息, $2=选项数组（用空格分隔或作为多个参数）
# 返回: 选择的序号（从1开始）
prompt_choice() {
    local prompt="$1"
    shift
    local options=("$@")
    local choice
    
    echo -e "${BLUE}${prompt}${NC}"
    for i in "${!options[@]}"; do
        echo "  $((i+1)). ${options[$i]}"
    done
    
    while true; do
        read -p "请选择 [1-${#options[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
            echo "$choice"
            return 0
        else
            echo -e "${YELLOW}无效选择，请输入 1-${#options[@]} 之间的数字${NC}"
        fi
    done
}

# 输入文本
# 参数: $1=提示信息, $2=默认值（可选）
# 返回: 用户输入的内容
prompt_input() {
    local prompt="$1"
    local default="${2:-}"
    local input
    
    if [ -n "$default" ]; then
        read -p "${prompt} [${default}]: " input
        echo "${input:-$default}"
    else
        read -p "${prompt}: " input
        echo "$input"
    fi
}

# ============================================
# 文件操作函数
# ============================================

# 确保目录存在（如果不存在则创建）
# 参数: $1=目录路径
# 返回: 0=成功, 1=失败
ensure_directory() {
    local dir_path="$1"
    
    if [ ! -d "$dir_path" ]; then
        if mkdir -p "$dir_path" 2>/dev/null; then
            echo -e "${GREEN}✓ 已创建目录: ${dir_path}${NC}"
            return 0
        else
            echo -e "${RED}✗ 创建目录失败: ${dir_path}${NC}"
            return 1
        fi
    else
        echo -e "${BLUE}✓ 目录已存在: ${dir_path}${NC}"
        return 0
    fi
}

# 检查文件是否存在
# 参数: $1=文件路径
# 返回: 0=存在, 1=不存在
file_exists() {
    local file_path="$1"
    [ -f "$file_path" ]
}

# 清理临时文件/目录
# 参数: $1=文件或目录路径
# 返回: 0=成功, 1=失败
cleanup_temp() {
    local path="$1"
    
    if [ -d "$path" ]; then
        rm -rf "$path" 2>/dev/null && return 0
    elif [ -f "$path" ]; then
        rm -f "$path" 2>/dev/null && return 0
    fi
    
    return 1
}

# ============================================
# 包管理器检测函数
# ============================================

# 检测包管理器
# 返回: 包管理器名称（yum/dnf/apt-get/zypper/pacman/apk/emerge）
detect_package_manager() {
    if command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v apt-get &> /dev/null; then
        echo "apt-get"
    elif command -v zypper &> /dev/null; then
        echo "zypper"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    elif command -v apk &> /dev/null; then
        echo "apk"
    elif command -v emerge &> /dev/null; then
        echo "emerge"
    else
        echo "unknown"
        return 1
    fi
    
    return 0
}

# 获取包管理器（根据操作系统）
# 返回: 包管理器名称
get_package_manager() {
    # 如果 OS 变量已设置，根据 OS 选择
    if [ -n "$OS" ]; then
        case "$OS" in
            centos|rhel|fedora|rocky|almalinux|oraclelinux|amazonlinux)
                if command -v dnf &> /dev/null; then
                    echo "dnf"
                elif command -v yum &> /dev/null; then
                    echo "yum"
                else
                    echo "unknown"
                    return 1
                fi
                ;;
            ubuntu|debian|linuxmint|raspbian|kali)
                if command -v apt-get &> /dev/null; then
                    echo "apt-get"
                else
                    echo "unknown"
                    return 1
                fi
                ;;
            opensuse*|sles)
                if command -v zypper &> /dev/null; then
                    echo "zypper"
                else
                    echo "unknown"
                    return 1
                fi
                ;;
            arch|manjaro)
                if command -v pacman &> /dev/null; then
                    echo "pacman"
                else
                    echo "unknown"
                    return 1
                fi
                ;;
            alpine)
                if command -v apk &> /dev/null; then
                    echo "apk"
                else
                    echo "unknown"
                    return 1
                fi
                ;;
            gentoo)
                if command -v emerge &> /dev/null; then
                    echo "emerge"
                else
                    echo "unknown"
                    return 1
                fi
                ;;
            *)
                # 未知系统，尝试自动检测
                detect_package_manager
                ;;
        esac
    else
        # OS 未设置，尝试自动检测
        detect_package_manager
    fi
}

# ============================================
# 检查结果函数（用于检查脚本）
# ============================================

# 初始化检查计数器（必须在脚本开始时调用）
# 返回: 设置全局变量 ERRORS=0, WARNINGS=0
init_check_counters() {
    ERRORS=0
    WARNINGS=0
    export ERRORS WARNINGS
}

# 检查错误（增加错误计数）
# 参数: $1=错误消息
check_error() {
    echo -e "${RED}✗ $1${NC}"
    ((ERRORS++))
    export ERRORS
}

# 检查警告（增加警告计数）
# 参数: $1=警告消息
check_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
    ((WARNINGS++))
    export WARNINGS
}

# 检查成功（不增加计数）
# 参数: $1=成功消息
check_ok() {
    echo -e "${GREEN}✓ $1${NC}"
}

# ============================================
# 脚本路径获取函数
# ============================================

# 获取脚本目录（统一方法）
# 返回: 脚本目录的绝对路径
get_script_dir() {
    local script_path="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
    echo "$(cd "$(dirname "$script_path")" && pwd)"
}

# 获取项目根目录（统一方法）
# 返回: 项目根目录的绝对路径
get_project_root_abs() {
    local script_dir=$(get_script_dir)
    echo "$(cd "$script_dir/.." && pwd)"
}

# ============================================
# 重试函数
# ============================================

# 重试执行命令
# 参数: $1=最大重试次数, $2=重试间隔（秒）, $3...=要执行的命令
# 返回: 最后一次执行的退出码
retry_command() {
    local max_retries="$1"
    local retry_interval="$2"
    shift 2
    local cmd=("$@")
    local retry_count=0
    local exit_code=1
    
    while [ $retry_count -lt $max_retries ]; do
        if "${cmd[@]}"; then
            exit_code=0
            break
        else
            exit_code=$?
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                echo -e "${YELLOW}⚠ 命令执行失败，${retry_interval} 秒后重试 (${retry_count}/${max_retries})...${NC}"
                sleep "$retry_interval"
            fi
        fi
    done
    
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}✗ 命令执行失败，已重试 ${max_retries} 次${NC}"
    fi
    
    return $exit_code
}

# ============================================
# 验证函数
# ============================================

# 验证命令是否存在
# 参数: $1=命令名
# 返回: 0=存在, 1=不存在
verify_command() {
    local cmd="$1"
    if command -v "$cmd" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# 验证文件是否存在且可读
# 参数: $1=文件路径
# 返回: 0=存在且可读, 1=不存在或不可读
verify_file_readable() {
    local file_path="$1"
    if [ -f "$file_path" ] && [ -r "$file_path" ]; then
        return 0
    else
        return 1
    fi
}

# 验证目录是否存在且可写
# 参数: $1=目录路径
# 返回: 0=存在且可写, 1=不存在或不可写
verify_dir_writable() {
    local dir_path="$1"
    if [ -d "$dir_path" ] && [ -w "$dir_path" ]; then
        return 0
    else
        return 1
    fi
}

