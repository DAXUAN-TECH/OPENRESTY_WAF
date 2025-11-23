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

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# GeoIP 数据库目录（相对于脚本位置：../lua/geoip）
GEOIP_DIR="${SCRIPT_DIR}/../lua/geoip"
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
        echo ""
        echo -e "${YELLOW}重要提示: Permalink URL 仍然需要 Account ID 和 License Key 进行 Basic Authentication${NC}"
        echo -e "${YELLOW}根据 MaxMind 文档，即使使用 Permalink URL，也需要提供认证信息${NC}"
        echo ""
        
        # 如果提供了 Account ID 和 License Key，使用它们
        if [ -n "$ACCOUNT_ID" ] && [ -n "$LICENSE_KEY" ]; then
            curl_opts=(-u "${ACCOUNT_ID}:${LICENSE_KEY}")
            echo -e "${GREEN}✓ 使用 Account ID 和 License Key 进行认证${NC}"
        else
            echo -e "${RED}✗ 错误: 使用 Permalink URL 时必须提供 Account ID 和 License Key${NC}"
            echo -e "${YELLOW}请重新运行脚本并提供认证信息:${NC}"
            echo "  sudo $0 [ACCOUNT_ID] [LICENSE_KEY]"
            echo "  或"
            echo "  sudo $0 [PERMALINK_URL] [ACCOUNT_ID] [LICENSE_KEY]"
            exit 1
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

# 保存配置到文件（用于后续自动更新）
save_config() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local config_file="${script_dir}/.geoip_config"
    
    # 只有在使用 Account ID 和 License Key 时才保存配置
    if [ "$USE_PERMALINK" != true ] && [ -n "$ACCOUNT_ID" ] && [ -n "$LICENSE_KEY" ]; then
        cat > "$config_file" <<EOF
# GeoIP2 数据库更新配置
# 此文件由 install_geoip.sh 自动生成
# 用于 update_geoip.sh 自动更新脚本
# 请妥善保管此文件，不要泄露 Account ID 和 License Key

ACCOUNT_ID="$ACCOUNT_ID"
LICENSE_KEY="$LICENSE_KEY"
EOF
        chmod 600 "$config_file"
        echo -e "${GREEN}✓ 配置已保存到: $config_file${NC}"
        echo -e "${YELLOW}  注意: 此文件包含敏感信息，已设置权限为 600${NC}"
    fi
}

# 设置 crontab 计划任务
setup_crontab() {
    # 只有在使用 Account ID 和 License Key 时才设置 crontab（需要配置文件）
    if [ "$USE_PERMALINK" = true ]; then
        echo -e "${YELLOW}⚠ 使用 Permalink URL，无法自动设置计划任务${NC}"
        echo -e "${YELLOW}  请手动配置 crontab 或使用 Account ID + License Key 重新安装${NC}"
        return 0
    fi

    if [ -z "$ACCOUNT_ID" ] || [ -z "$LICENSE_KEY" ]; then
        echo -e "${YELLOW}⚠ 未提供 Account ID 或 License Key，跳过 crontab 设置${NC}"
        return 0
    fi

    # 获取脚本目录和更新脚本路径
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local update_script="${script_dir}/update_geoip.sh"
    
    # 检查更新脚本是否存在
    if [ ! -f "$update_script" ]; then
        echo -e "${YELLOW}⚠ 更新脚本不存在: $update_script${NC}"
        echo -e "${YELLOW}  跳过 crontab 设置${NC}"
        return 0
    fi

    # 确保更新脚本有执行权限
    chmod +x "$update_script" 2>/dev/null || true

    # 构建 crontab 任务（每周一凌晨 2 点更新）
    # 日志文件放在项目目录的 logs 文件夹（相对于脚本位置）
    local log_file="${SCRIPT_DIR}/../logs/geoip_update.log"
    local cron_job="0 2 * * 1 ${update_script} >> ${log_file} 2>&1"
    
    # 检查是否已存在相同的任务
    if crontab -l 2>/dev/null | grep -qF "$update_script"; then
        echo -e "${YELLOW}⚠ 计划任务已存在，跳过添加${NC}"
        echo -e "${GREEN}  现有任务:${NC}"
        crontab -l 2>/dev/null | grep "$update_script" | sed 's/^/    /'
        return 0
    fi

    # 询问用户是否要添加计划任务
    echo ""
    echo -e "${YELLOW}是否要自动配置计划任务（每周一凌晨 2 点更新数据库）？${NC}"
    echo -e "${YELLOW}输入 y/yes 确认，其他任意键跳过:${NC}"
    read -r response
    
    if [[ ! "$response" =~ ^[Yy][Ee][Ss]?$ ]]; then
        echo -e "${YELLOW}已跳过 crontab 设置${NC}"
        echo -e "${YELLOW}如需手动配置，请运行:${NC}"
        echo "  sudo crontab -e"
        echo "  # 添加以下行:"
        echo "  $cron_job"
        return 0
    fi

    # 添加 crontab 任务
    local temp_cron=$(mktemp)
    crontab -l 2>/dev/null > "$temp_cron" || true
    
    # 添加新任务
    echo "$cron_job" >> "$temp_cron"
    
    # 安装新的 crontab
    if crontab "$temp_cron" 2>/dev/null; then
        rm -f "$temp_cron"
        echo -e "${GREEN}✓ 计划任务已添加${NC}"
        echo -e "${GREEN}  任务: $cron_job${NC}"
        echo ""
        echo -e "${GREEN}查看计划任务:${NC}"
        echo "  sudo crontab -l | grep update_geoip"
        echo ""
        echo -e "${GREEN}查看更新日志:${NC}"
        echo "  tail -f ${SCRIPT_DIR}/../logs/geoip_update.log"
        echo ""
        echo -e "${GREEN}移除计划任务:${NC}"
        echo "  sudo crontab -e"
        echo "  # 删除包含 update_geoip.sh 的行"
    else
        rm -f "$temp_cron"
        echo -e "${RED}✗ 添加计划任务失败${NC}"
        echo -e "${YELLOW}  请手动配置 crontab${NC}"
    fi
}

# 验证安装
verify_installation() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}安装验证${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    local target_file="$GEOIP_DIR/GeoLite2-City.mmdb"
    local install_success=false
    local error_messages=()
    
    # 1. 检查文件是否存在
    if [ ! -f "$target_file" ]; then
        error_messages+=("数据库文件不存在: $target_file")
        echo -e "${RED}✗ 安装失败: 数据库文件不存在${NC}"
        echo "  预期路径: $target_file"
        return 1
    fi
    
    # 2. 检查文件大小
    local file_size=$(stat -f%z "$target_file" 2>/dev/null || stat -c%s "$target_file" 2>/dev/null || echo "0")
    local file_size_mb=$((file_size / 1048576))
    local file_size_human=$(du -h "$target_file" | cut -f1)
    
    if [ "$file_size" -lt 1048576 ]; then
        error_messages+=("文件大小异常小: ${file_size_human} (${file_size} 字节)，可能下载不完整")
        echo -e "${RED}✗ 安装失败: 文件大小异常小${NC}"
        echo "  文件大小: ${file_size_human} (${file_size} 字节)"
        echo "  预期大小: 应大于 1MB"
        return 1
    fi
    
    # 3. 检查文件是否可读
    if [ ! -r "$target_file" ]; then
        error_messages+=("文件不可读，权限可能有问题")
        echo -e "${RED}✗ 安装失败: 文件不可读${NC}"
        return 1
    fi
    
    # 4. 检查文件类型（简单检查：.mmdb 文件应该不是文本文件）
    local file_type=$(file "$target_file" 2>/dev/null || echo "")
    if echo "$file_type" | grep -qi "text\|empty\|ascii"; then
        error_messages+=("文件类型异常，可能是错误响应而非数据库文件")
        echo -e "${RED}✗ 安装失败: 文件类型异常${NC}"
        echo "  文件类型: $file_type"
        return 1
    fi
    
    # 5. 获取绝对路径
    local abs_path=$(cd "$(dirname "$target_file")" && pwd)/$(basename "$target_file")
    
    # 所有检查通过
    install_success=true
    
    echo -e "${GREEN}✓ 安装成功！${NC}"
    echo ""
    echo -e "${GREEN}安装结果:${NC}"
    echo "  状态: 成功"
    echo "  数据库文件路径: $abs_path"
    echo "  文件大小: ${file_size_human} (${file_size_mb} MB)"
    echo "  文件权限: $(ls -l "$target_file" | awk '{print $1}')"
    
    if [ -n "$file_type" ]; then
        echo "  文件类型: $file_type"
    fi
    
    echo ""
    echo -e "${GREEN}下一步:${NC}"
    echo "1. 在 lua/config.lua 中启用地域封控:"
    echo "   _M.geo = {"
    echo "       enable = true,"
    echo "       -- geoip_db_path 会在运行时自动设置，无需手动配置"
    echo "   }"
    echo ""
    echo "2. 运行部署脚本（如果还未运行）:"
    echo "   sudo ./scripts/deploy.sh"
    echo ""
    echo "3. 重启 OpenResty 服务"
    echo "4. 添加地域封控规则（参考 docs/地域封控使用示例.md）"
    echo ""
    echo -e "${GREEN}数据库文件位置:${NC}"
    echo "  $abs_path"
    
    return 0
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
    save_config  # 保存配置用于后续自动更新
    cleanup
    
    # 验证安装并获取结果
    if verify_installation; then
        local target_file="$GEOIP_DIR/GeoLite2-City.mmdb"
        local abs_path=$(cd "$(dirname "$target_file")" && pwd)/$(basename "$target_file")
        
        setup_crontab  # 设置计划任务
        
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}安装完成！${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo -e "${GREEN}安装结果: 成功${NC}"
        echo -e "${GREEN}数据库文件路径: $abs_path${NC}"
        
        # 返回成功状态码
        exit 0
    else
        echo ""
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}安装失败！${NC}"
        echo -e "${RED}========================================${NC}"
        echo ""
        echo -e "${RED}安装结果: 失败${NC}"
        echo -e "${YELLOW}请检查错误信息并重试${NC}"
        
        # 返回失败状态码
        exit 1
    fi
}

# 执行主函数
main "$@"

