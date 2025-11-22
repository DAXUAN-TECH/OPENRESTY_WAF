#!/bin/bash

# GeoLite2-City 数据库自动更新脚本
# 用途：定期更新 GeoIP2 数据库（用于 crontab 计划任务）
# 注意：此脚本需要配置文件来存储 Account ID 和 License Key

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.geoip_config"

# GeoIP 数据库目录（项目目录下的 lua/geoip）
GEOIP_DIR="${PROJECT_ROOT}/lua/geoip"
TEMP_DIR="/tmp/geoip_update"
DOWNLOAD_URL="https://download.maxmind.com/geoip/databases/GeoLite2-City/download"

# 日志文件（项目目录下的 logs 文件夹）
LOG_FILE="${PROJECT_ROOT}/logs/geoip_update.log"

# 确保日志目录存在
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

# 日志函数
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
}

log_error() {
    log "ERROR" "$@" >&2
}

log_warn() {
    log "WARN" "$@"
}

# 读取配置文件
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "配置文件不存在: $CONFIG_FILE"
        log_error "请先运行 install_geoip.sh 进行初始安装，或手动创建配置文件"
        exit 1
    fi

    # 读取配置（安全地处理包含特殊字符的值）
    source "$CONFIG_FILE"

    if [ -z "$ACCOUNT_ID" ] || [ -z "$LICENSE_KEY" ]; then
        log_error "配置文件缺少 Account ID 或 License Key"
        log_error "请检查配置文件: $CONFIG_FILE"
        exit 1
    fi

    log_info "已加载配置文件: $CONFIG_FILE"
}

# 检查依赖
check_dependencies() {
    local missing_deps=()

    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi

    if ! command -v tar &> /dev/null; then
        missing_deps+=("tar")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "缺少以下依赖: ${missing_deps[*]}"
        exit 1
    fi
}

# 创建目录
create_directories() {
    mkdir -p "$TEMP_DIR"
    mkdir -p "$GEOIP_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"
}

# 下载数据库
download_database() {
    log_info "开始下载 GeoLite2-City 数据库..."

    local download_file="$TEMP_DIR/GeoLite2-City.tar.gz"
    local url="${DOWNLOAD_URL}?suffix=tar.gz"

    # 使用 Basic Authentication
    if curl -L -f -u "${ACCOUNT_ID}:${LICENSE_KEY}" -o "$download_file" "$url" 2>/dev/null; then
        if [ -f "$download_file" ]; then
            local file_size=$(stat -f%z "$download_file" 2>/dev/null || stat -c%s "$download_file" 2>/dev/null || echo "0")
            local file_content=$(head -c 50 "$download_file" 2>/dev/null || echo "")

            # 检查是否是错误信息
            if echo "$file_content" | grep -qi "Invalid\|Error\|Unauthorized\|Forbidden\|401\|403"; then
                log_error "认证失败或下载失败"
                log_error "返回内容: $file_content"
                rm -f "$download_file"
                exit 1
            fi

            # 检查文件大小（应该大于 1MB）
            if [ "$file_size" -lt 1048576 ]; then
                log_error "下载的文件太小，可能下载失败"
                log_error "文件大小: $file_size 字节"
                rm -f "$download_file"
                exit 1
            fi

            log_info "下载成功 (文件大小: $(du -h "$download_file" | cut -f1))"
        else
            log_error "下载失败，文件不存在"
            exit 1
        fi
    else
        log_error "下载失败，请检查网络连接和认证信息"
        exit 1
    fi
}

# 解压数据库
extract_database() {
    log_info "解压数据库文件..."

    local download_file="$TEMP_DIR/GeoLite2-City.tar.gz"
    local extract_dir="$TEMP_DIR/extract"

    mkdir -p "$extract_dir"

    if tar -xzf "$download_file" -C "$extract_dir" 2>/dev/null; then
        local mmdb_file=$(find "$extract_dir" -name "GeoLite2-City.mmdb" -type f | head -n 1)

        if [ -z "$mmdb_file" ]; then
            log_error "解压后未找到 GeoLite2-City.mmdb 文件"
            exit 1
        fi

        log_info "解压成功，找到文件: $mmdb_file"
    else
        log_error "解压失败"
        exit 1
    fi
}

# 安装数据库
install_database() {
    log_info "安装数据库文件..."

    local extract_dir="$TEMP_DIR/extract"
    local mmdb_file=$(find "$extract_dir" -name "GeoLite2-City.mmdb" -type f | head -n 1)
    local target_file="$GEOIP_DIR/GeoLite2-City.mmdb"

    # 备份旧文件（如果存在）
    if [ -f "$target_file" ]; then
        local backup_file="${target_file}.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "备份旧文件到: $backup_file"
        cp "$target_file" "$backup_file"
        
        # 检查磁盘空间（至少需要 500MB 可用空间）
        local available_space=$(df -m "$GEOIP_DIR" | awk 'NR==2 {print $4}')
        if [ "$available_space" -lt 500 ]; then
            log_warn "磁盘可用空间不足 500MB，将清理旧备份文件"
        fi
        
        # 清理旧备份：保留最近 5 个备份，或总大小超过 1GB 时清理
        local backup_files=($(find "$GEOIP_DIR" -name "GeoLite2-City.mmdb.backup.*" -type f | sort -r))
        local backup_count=${#backup_files[@]}
        local total_backup_size=0
        
        # 计算备份文件总大小
        for backup in "${backup_files[@]}"; do
            local size=$(stat -f%z "$backup" 2>/dev/null || stat -c%s "$backup" 2>/dev/null || echo "0")
            total_backup_size=$((total_backup_size + size))
        done
        
        # 如果备份数量超过 5 个或总大小超过 1GB，清理旧备份
        if [ $backup_count -gt 5 ] || [ $total_backup_size -gt 1073741824 ]; then
            log_info "清理旧备份文件（当前: $backup_count 个，总大小: $(($total_backup_size / 1048576))MB）"
            # 保留最近 5 个备份
            for ((i=5; i<${#backup_files[@]}; i++)); do
                rm -f "${backup_files[$i]}" 2>/dev/null || true
                log_info "已删除旧备份: $(basename "${backup_files[$i]}")"
            done
        fi
    fi

    # 复制新文件
    cp "$mmdb_file" "$target_file"

    # 设置权限
    chown nobody:nobody "$target_file" 2>/dev/null || chown root:root "$target_file"
    chmod 644 "$target_file"

    log_info "安装成功: $target_file"
    log_info "文件大小: $(du -h "$target_file" | cut -f1)"
}

# 清理临时文件
cleanup() {
    log_info "清理临时文件..."
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

# 验证安装
verify_installation() {
    local target_file="$GEOIP_DIR/GeoLite2-City.mmdb"

    if [ -f "$target_file" ]; then
        local file_size=$(stat -f%z "$target_file" 2>/dev/null || stat -c%s "$target_file" 2>/dev/null || echo "0")

        if [ "$file_size" -gt 1048576 ]; then
            log_info "✓ 数据库文件验证通过"
            log_info "  路径: $target_file"
            log_info "  大小: $(du -h "$target_file" | cut -f1)"
            return 0
        else
            log_warn "⚠ 警告: 文件大小异常小，可能有问题"
            return 1
        fi
    else
        log_error "✗ 安装失败: 数据库文件不存在"
        return 1
    fi
}

# 主函数
main() {
    log_info "========================================"
    log_info "GeoLite2-City 数据库自动更新"
    log_info "========================================"

    # 检查 root 权限（可选，如果只是更新文件可能不需要）
    if [ "$EUID" -ne 0 ] && [ ! -w "$GEOIP_DIR" ]; then
        log_error "需要 root 权限来更新数据库文件"
        log_error "请使用: sudo $0"
        exit 1
    fi

    # 读取配置
    load_config

    # 执行更新步骤
    check_dependencies
    create_directories
    download_database
    extract_database
    install_database
    cleanup

    # 验证安装
    if verify_installation; then
        log_info "========================================"
        log_info "更新完成！"
        log_info "========================================"
        
        # 可选：重启 OpenResty 以重新加载数据库（如果需要）
        # systemctl reload openresty 2>/dev/null || true
    else
        log_error "更新失败，请检查日志"
        exit 1
    fi
}

# 执行主函数
main "$@"

