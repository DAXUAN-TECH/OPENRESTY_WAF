#!/bin/bash

# GeoLite2-City 数据库一键安装脚本
# 用途：自动下载、解压并安装 GeoLite2-City 数据库到指定目录

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置变量
ACCOUNT_ID="${1:-}"
LICENSE_KEY="${2:-}"
GEOIP_DIR="/usr/local/openresty/nginx/lua/geoip"
TEMP_DIR="/tmp/geoip_install"
# 使用新的 permalink URL（需要从 MaxMind 账号页面获取）
# 或者使用通用的下载端点（需要 Account ID 和 License Key）
DOWNLOAD_URL="https://download.maxmind.com/geoip/databases/GeoLite2-City/download"

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${YELLOW}警告: 需要 root 权限来安装文件到系统目录${NC}"
        echo "请使用: sudo $0 [LICENSE_KEY]"
        exit 1
    fi
}

# 显示使用说明
show_usage() {
    echo "使用方法:"
    echo "  sudo $0 [ACCOUNT_ID] [LICENSE_KEY]"
    echo "  sudo $0 [PERMALINK_URL]"
    echo ""
    echo "参数说明:"
    echo "  方式 1 - 使用 Account ID 和 License Key:"
    echo "    ACCOUNT_ID   - MaxMind Account ID（可选，如果不提供会提示输入）"
    echo "    LICENSE_KEY  - MaxMind License Key（可选，如果不提供会提示输入）"
    echo ""
    echo "  方式 2 - 使用 Permalink URL:"
    echo "    PERMALINK_URL - 从 MaxMind 账号页面获取的 permalink URL"
    echo ""
    echo "示例:"
    echo "  sudo $0 123456 YOUR_LICENSE_KEY"
    echo "  sudo $0  # 会提示输入 Account ID 和 License Key"
    echo "  sudo $0 'https://download.maxmind.com/geoip/databases/GeoLite2-City/download?suffix=tar.gz'"
    echo ""
    echo "注意："
    echo "  - 根据 MaxMind 最新文档，需要使用 Account ID 和 License Key 进行 Basic Authentication"
    echo "  - 或者从 MaxMind 账号页面获取 permalink URL"
    echo "  - 详细说明：https://dev.maxmind.com/geoip/updating-databases/"
    exit 1
}

# 检查是否是 permalink URL
check_permalink() {
    if [[ "$ACCOUNT_ID" =~ ^https?:// ]]; then
        # 第一个参数是 permalink URL
        PERMALINK_URL="$ACCOUNT_ID"
        USE_PERMALINK=true
        return 0
    fi
    USE_PERMALINK=false
    return 1
}

# 获取 Account ID 和 License Key
get_credentials() {
    if check_permalink; then
        return 0
    fi
    
    if [ -z "$ACCOUNT_ID" ]; then
        echo -e "${YELLOW}请输入 MaxMind Account ID:${NC}"
        echo -e "${YELLOW}(可以在 MaxMind 账号页面找到: https://www.maxmind.com/en/accounts/current)${NC}"
        read -r ACCOUNT_ID
        if [ -z "$ACCOUNT_ID" ]; then
            echo -e "${RED}错误: Account ID 不能为空${NC}"
            exit 1
        fi
    fi
    
    if [ -z "$LICENSE_KEY" ]; then
        echo -e "${YELLOW}请输入 MaxMind License Key:${NC}"
        echo -e "${YELLOW}(可以在 MaxMind 账号页面找到: https://www.maxmind.com/en/accounts/current/license-key)${NC}"
        read -r LICENSE_KEY
        if [ -z "$LICENSE_KEY" ]; then
            echo -e "${RED}错误: License Key 不能为空${NC}"
            exit 1
        fi
    fi
}

# 检查依赖
check_dependencies() {
    echo -e "${GREEN}[1/6] 检查依赖...${NC}"
    
    local missing_deps=()
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if ! command -v tar &> /dev/null; then
        missing_deps+=("tar")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RED}错误: 缺少以下依赖: ${missing_deps[*]}${NC}"
        echo "请先安装这些依赖"
        exit 1
    fi
    
    echo -e "${GREEN}✓ 依赖检查通过${NC}"
}

# 创建目录
create_directories() {
    echo -e "${GREEN}[2/6] 创建目录...${NC}"
    
    # 创建临时目录
    mkdir -p "$TEMP_DIR"
    
    # 创建目标目录
    mkdir -p "$GEOIP_DIR"
    
    echo -e "${GREEN}✓ 目录创建完成${NC}"
}

# 下载数据库
download_database() {
    echo -e "${GREEN}[3/6] 下载 GeoLite2-City 数据库...${NC}"
    
    local download_file="$TEMP_DIR/GeoLite2-City.tar.gz"
    local url=""
    local curl_opts=()
    
    if [ "$USE_PERMALINK" = true ]; then
        # 使用 permalink URL（仍然需要认证）
        url="${PERMALINK_URL}"
        echo "使用 Permalink URL 下载"
        echo "URL: $url"
        echo -e "${YELLOW}注意: Permalink URL 仍然需要 Account ID 和 License Key 认证${NC}"
        echo -e "${YELLOW}如果没有提供，将尝试不使用认证下载（可能会失败）${NC}"
        # 如果提供了 Account ID 和 License Key，使用它们
        if [ -n "$ACCOUNT_ID" ] && [ -n "$LICENSE_KEY" ]; then
            curl_opts=(-u "${ACCOUNT_ID}:${LICENSE_KEY}")
            echo "使用 Account ID 和 License Key 进行认证"
        fi
    else
        # 使用 Account ID 和 License Key（Basic Authentication）
        url="${DOWNLOAD_URL}?suffix=tar.gz"
        echo "使用 Account ID 和 License Key 下载"
        echo "Account ID: $ACCOUNT_ID"
        echo "URL: $url"
        # 使用 Basic Authentication
        curl_opts=(-u "${ACCOUNT_ID}:${LICENSE_KEY}")
    fi
    
    echo "保存到: $download_file"
    
    # 注意：MaxMind 使用 R2 presigned URLs，会重定向
    # 需要确保 curl 跟随重定向（-L 参数）
    # 重定向目标：mm-prod-geoip-databases.a2649acb697e2c09b632799562c076f2.r2.cloudflarestorage.com
    if curl -L -f "${curl_opts[@]}" -o "$download_file" "$url" 2>/dev/null; then
        # 检查文件是否有效（不是错误信息）
        if [ -f "$download_file" ]; then
            local file_size=$(stat -f%z "$download_file" 2>/dev/null || stat -c%s "$download_file" 2>/dev/null || echo "0")
            local file_content=$(head -c 50 "$download_file" 2>/dev/null || echo "")
            
            # 检查是否是错误信息
            if echo "$file_content" | grep -qi "Invalid\|Error\|Unauthorized\|Forbidden\|401\|403"; then
                echo -e "${RED}错误: 认证失败或下载失败${NC}"
                echo "返回内容: $file_content"
                echo ""
                echo -e "${YELLOW}可能的原因:${NC}"
                echo "1. Account ID 或 License Key 不正确"
                echo "2. License Key 已过期或未激活"
                echo "3. 账号权限不足"
                echo ""
                echo -e "${YELLOW}建议:${NC}"
                echo "1. 检查 MaxMind 账号页面确认 Account ID 和 License Key"
                echo "2. 或者从账号页面获取 permalink URL 使用"
                echo "3. 参考文档: https://dev.maxmind.com/geoip/updating-databases/"
                rm -f "$download_file"
                exit 1
            fi
            
            # 检查文件大小（应该大于 1MB）
            if [ "$file_size" -lt 1048576 ]; then
                echo -e "${RED}错误: 下载的文件太小，可能下载失败${NC}"
                echo "文件大小: $file_size 字节"
                echo "文件内容: $file_content"
                rm -f "$download_file"
                exit 1
            fi
            
            echo -e "${GREEN}✓ 下载成功 (文件大小: $(du -h "$download_file" | cut -f1))${NC}"
        else
            echo -e "${RED}错误: 下载失败，文件不存在${NC}"
            exit 1
        fi
    else
        echo -e "${RED}错误: 下载失败，请检查网络连接和 License Key${NC}"
        exit 1
    fi
}

# 解压数据库
extract_database() {
    echo -e "${GREEN}[4/6] 解压数据库文件...${NC}"
    
    local download_file="$TEMP_DIR/GeoLite2-City.tar.gz"
    local extract_dir="$TEMP_DIR/extract"
    
    mkdir -p "$extract_dir"
    
    if tar -xzf "$download_file" -C "$extract_dir" 2>/dev/null; then
        # 查找 .mmdb 文件
        local mmdb_file=$(find "$extract_dir" -name "GeoLite2-City.mmdb" -type f | head -n 1)
        
        if [ -z "$mmdb_file" ]; then
            echo -e "${RED}错误: 解压后未找到 GeoLite2-City.mmdb 文件${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}✓ 解压成功${NC}"
        echo "找到文件: $mmdb_file"
    else
        echo -e "${RED}错误: 解压失败${NC}"
        exit 1
    fi
}

# 安装数据库
install_database() {
    echo -e "${GREEN}[5/6] 安装数据库文件...${NC}"
    
    local extract_dir="$TEMP_DIR/extract"
    local mmdb_file=$(find "$extract_dir" -name "GeoLite2-City.mmdb" -type f | head -n 1)
    local target_file="$GEOIP_DIR/GeoLite2-City.mmdb"
    
    # 备份旧文件（如果存在）
    if [ -f "$target_file" ]; then
        local backup_file="${target_file}.backup.$(date +%Y%m%d_%H%M%S)"
        echo "备份旧文件到: $backup_file"
        cp "$target_file" "$backup_file"
    fi
    
    # 复制新文件
    cp "$mmdb_file" "$target_file"
    
    # 设置权限
    chown nobody:nobody "$target_file" 2>/dev/null || chown $(whoami):$(whoami) "$target_file"
    chmod 644 "$target_file"
    
    echo -e "${GREEN}✓ 安装成功${NC}"
    echo "数据库文件: $target_file"
    echo "文件大小: $(du -h "$target_file" | cut -f1)"
}

# 清理临时文件
cleanup() {
    echo -e "${GREEN}[6/6] 清理临时文件...${NC}"
    
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
    
    echo -e "${GREEN}✓ 清理完成${NC}"
}

# 验证安装
verify_installation() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}安装验证${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    local target_file="$GEOIP_DIR/GeoLite2-City.mmdb"
    
    if [ -f "$target_file" ]; then
        local file_size=$(stat -f%z "$target_file" 2>/dev/null || stat -c%s "$target_file" 2>/dev/null || echo "0")
        echo -e "${GREEN}✓ 数据库文件已安装${NC}"
        echo "  路径: $target_file"
        echo "  大小: $(du -h "$target_file" | cut -f1)"
        
        if [ "$file_size" -gt 1048576 ]; then
            echo -e "${GREEN}✓ 文件大小正常${NC}"
        else
            echo -e "${YELLOW}⚠ 警告: 文件大小异常小，可能有问题${NC}"
        fi
        
        echo ""
        echo -e "${GREEN}下一步:${NC}"
        echo "1. 在 lua/config.lua 中启用地域封控:"
        echo "   _M.geo = {"
        echo "       enable = true,"
        echo "       geoip_db_path = \"$target_file\","
        echo "   }"
        echo ""
        echo "2. 重启 OpenResty 服务"
        echo "3. 添加地域封控规则（参考 08-地域封控使用示例.md）"
    else
        echo -e "${RED}✗ 安装失败: 数据库文件不存在${NC}"
        exit 1
    fi
}

# 主函数
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}GeoLite2-City 数据库一键安装脚本${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # 检查参数
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        show_usage
    fi
    
    # 检查 root 权限
    check_root
    
    # 获取凭证（Account ID 和 License Key 或 Permalink URL）
    get_credentials
    
    # 执行安装步骤
    check_dependencies
    create_directories
    download_database
    extract_database
    install_database
    cleanup
    verify_installation
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}安装完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# 执行主函数
main "$@"

