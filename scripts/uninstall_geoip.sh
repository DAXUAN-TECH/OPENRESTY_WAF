#!/bin/bash

# GeoIP 数据库一键卸载脚本
# 用途：卸载 GeoIP 数据库及相关配置

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

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEOIP_DIR="${SCRIPT_DIR}/../lua/geoip"
CONFIG_FILE="${SCRIPT_DIR}/.geoip_config"

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}警告: 建议使用 root 权限来删除文件${NC}"
        echo "请使用: sudo $0"
    fi
}

# 删除数据库文件
remove_database() {
    echo -e "${BLUE}[1/3] 删除 GeoIP 数据库文件...${NC}"
    
    local db_file="${GEOIP_DIR}/GeoLite2-City.mmdb"
    
    if [ -f "$db_file" ]; then
        rm -f "$db_file"
        echo -e "${GREEN}✓ 已删除数据库文件: $db_file${NC}"
        
        # 删除备份文件
        if ls "${db_file}.backup."* 2>/dev/null; then
            rm -f "${db_file}.backup."*
            echo -e "${GREEN}✓ 已删除备份文件${NC}"
        fi
    else
        echo -e "${YELLOW}数据库文件不存在: $db_file${NC}"
    fi
    
    # 如果目录为空，询问是否删除目录
    if [ -d "$GEOIP_DIR" ] && [ -z "$(ls -A "$GEOIP_DIR" 2>/dev/null)" ]; then
        # 如果从命令行传入参数，使用参数值，否则询问用户
        if [ -n "$1" ]; then
            DELETE_DIR="$1"
        else
            read -p "是否删除空目录 $GEOIP_DIR？[y/N]: " DELETE_DIR
            DELETE_DIR="${DELETE_DIR:-N}"
        fi
        if [[ "$DELETE_DIR" =~ ^[Yy]$ ]]; then
            rmdir "$GEOIP_DIR" 2>/dev/null || true
            echo -e "${GREEN}✓ 已删除目录${NC}"
        fi
    fi
}

# 删除配置文件
remove_config() {
    echo -e "${BLUE}[2/3] 删除配置文件...${NC}"
    
    if [ -f "$CONFIG_FILE" ]; then
        rm -f "$CONFIG_FILE"
        echo -e "${GREEN}✓ 已删除配置文件: $CONFIG_FILE${NC}"
    else
        echo -e "${YELLOW}配置文件不存在: $CONFIG_FILE${NC}"
    fi
}

# 删除 crontab 任务
remove_crontab() {
    echo -e "${BLUE}[3/3] 删除计划任务...${NC}"
    
    local crontab_cmd="update_geoip.sh"
    local crontab_file="/tmp/crontab_backup_$$"
    
    # 备份当前 crontab
    if crontab -l > "$crontab_file" 2>/dev/null; then
        # 检查是否有 GeoIP 更新任务
        if grep -q "$crontab_cmd" "$crontab_file"; then
            # 删除包含 update_geoip.sh 的行
            grep -v "$crontab_cmd" "$crontab_file" | crontab -
            echo -e "${GREEN}✓ 已删除计划任务${NC}"
        else
            echo -e "${YELLOW}未找到计划任务${NC}"
        fi
        rm -f "$crontab_file"
    else
        echo -e "${YELLOW}当前用户没有 crontab 任务${NC}"
    fi
}

# 主函数
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}GeoIP 数据库一键卸载脚本${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    check_root
    
    remove_database "$1"  # 传递命令行参数
    remove_config
    remove_crontab
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}卸载完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}注意:${NC}"
    echo "  - 数据库文件已删除: ${GEOIP_DIR}/GeoLite2-City.mmdb"
    echo "  - 配置文件已删除: ${CONFIG_FILE}"
    echo "  - 计划任务已删除"
    echo ""
}

# 执行主函数
main "$@"

