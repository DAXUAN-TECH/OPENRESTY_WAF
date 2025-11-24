#!/bin/bash

# 部署配置一键卸载脚本
# 用途：删除部署的 OpenResty 配置文件

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

# OpenResty 安装目录
OPENRESTY_PREFIX="${OPENRESTY_PREFIX:-/usr/local/openresty}"
NGINX_CONF_DIR="${OPENRESTY_PREFIX}/nginx/conf"
NGINX_CONF_FILE="${NGINX_CONF_DIR}/nginx.conf"

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误: 需要 root 权限来卸载${NC}"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 停止服务
stop_service() {
    echo -e "${BLUE}[1/3] 停止 OpenResty 服务...${NC}"
    
    if systemctl is-active --quiet openresty 2>/dev/null; then
        systemctl stop openresty
        echo -e "${GREEN}✓ 服务已停止${NC}"
    elif [ -f "${OPENRESTY_PREFIX}/nginx/logs/nginx.pid" ]; then
        if [ -f "${OPENRESTY_PREFIX}/bin/openresty" ]; then
            ${OPENRESTY_PREFIX}/bin/openresty -s quit 2>/dev/null || true
        fi
        echo -e "${GREEN}✓ 服务已停止${NC}"
    else
        echo -e "${YELLOW}服务未运行${NC}"
    fi
}

# 删除配置文件
remove_config() {
    echo -e "${BLUE}[2/3] 删除部署的配置文件...${NC}"
    
    if [ -f "$NGINX_CONF_FILE" ]; then
        # 如果从命令行传入参数，使用参数值，否则询问用户
        if [ -n "$1" ]; then
            DELETE_CONF="$1"
        else
            echo -e "${YELLOW}警告: 将删除配置文件: $NGINX_CONF_FILE${NC}"
            read -p "是否删除？[y/N]: " DELETE_CONF
            DELETE_CONF="${DELETE_CONF:-N}"
        fi
        
        if [[ "$DELETE_CONF" =~ ^[Yy]$ ]]; then
            # 备份配置文件
            local backup_file="${NGINX_CONF_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
            cp "$NGINX_CONF_FILE" "$backup_file"
            echo -e "${GREEN}✓ 已备份到: $backup_file${NC}"
            
            rm -f "$NGINX_CONF_FILE"
            echo -e "${GREEN}✓ 配置文件已删除${NC}"
        else
            echo -e "${YELLOW}保留配置文件${NC}"
        fi
    else
        echo -e "${YELLOW}配置文件不存在: $NGINX_CONF_FILE${NC}"
    fi
}

# 清理项目目录（可选）
cleanup_project() {
    echo -e "${BLUE}[3/4] 清理项目目录（可选）...${NC}"
    
    # 获取脚本目录
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="${SCRIPT_DIR}/.."
    
    echo ""
    echo -e "${YELLOW}请选择清理选项：${NC}"
    echo "  1. 仅删除部署的配置文件，保留项目目录（推荐）"
    echo "  2. 删除部署的配置文件和日志文件，保留项目代码"
    echo "  3. 完全清理（删除所有部署相关文件，但保留项目代码）"
    echo "  4. 保留所有文件（不清理项目目录）"
    read -p "请选择 [1-4]: " CLEANUP_CHOICE
    
    case "$CLEANUP_CHOICE" in
        1)
            echo -e "${GREEN}✓ 仅删除部署的配置文件${NC}"
            echo -e "${BLUE}项目目录保持不变: $PROJECT_ROOT${NC}"
            ;;
        2)
            echo -e "${YELLOW}删除日志文件...${NC}"
            if [ -d "${PROJECT_ROOT}/logs" ]; then
                rm -rf "${PROJECT_ROOT}/logs"/*
                echo -e "${GREEN}✓ 已清理日志目录${NC}"
            fi
            echo -e "${GREEN}✓ 日志文件已删除，项目代码已保留${NC}"
            ;;
        3)
            echo -e "${YELLOW}完全清理部署相关文件...${NC}"
            
            # 删除日志文件
            if [ -d "${PROJECT_ROOT}/logs" ]; then
                rm -rf "${PROJECT_ROOT}/logs"/*
                echo -e "${GREEN}✓ 已清理日志目录${NC}"
            fi
            
            # 删除临时文件
            if [ -d "${PROJECT_ROOT}/tmp" ]; then
                rm -rf "${PROJECT_ROOT}/tmp"/*
                echo -e "${GREEN}✓ 已清理临时文件目录${NC}"
            fi
            
            # 删除备份文件（如果存在）
            if [ -d "${PROJECT_ROOT}/backup" ]; then
                read -p "是否删除备份文件？[y/N]: " DELETE_BACKUP
                DELETE_BACKUP="${DELETE_BACKUP:-N}"
                if [[ "$DELETE_BACKUP" =~ ^[Yy]$ ]]; then
                    rm -rf "${PROJECT_ROOT}/backup"/*
                    echo -e "${GREEN}✓ 已清理备份目录${NC}"
                fi
            fi
            
            echo -e "${GREEN}✓ 部署相关文件已清理，项目代码已保留${NC}"
            ;;
        4|*)
            echo -e "${GREEN}✓ 保留所有项目文件${NC}"
            ;;
    esac
}

# 检查部署残留
check_deploy_residue() {
    echo -e "${BLUE}[4/4] 检查部署残留...${NC}"
    
    OPENRESTY_PREFIX="${OPENRESTY_PREFIX:-/usr/local/openresty}"
    NGINX_CONF_FILE="${OPENRESTY_PREFIX}/nginx/conf/nginx.conf"
    
    local residue_found=0
    
    # 检查 nginx.conf 是否仍存在
    if [ -f "$NGINX_CONF_FILE" ]; then
        if grep -q "project_root" "$NGINX_CONF_FILE" 2>/dev/null; then
            echo -e "${YELLOW}⚠ 部署的 nginx.conf 仍存在: $NGINX_CONF_FILE${NC}"
            residue_found=1
        fi
    fi
    
    # 检查是否有其他配置文件残留
    if [ -d "${OPENRESTY_PREFIX}/nginx/conf/conf.d" ]; then
        echo -e "${YELLOW}⚠ 配置文件目录仍存在: ${OPENRESTY_PREFIX}/nginx/conf/conf.d${NC}"
        residue_found=1
    fi
    
    if [ $residue_found -eq 0 ]; then
        echo -e "${GREEN}✓ 未发现部署残留${NC}"
    else
        echo -e "${YELLOW}⚠ 发现部署残留，建议手动清理${NC}"
    fi
}

# 主函数
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}部署配置一键卸载脚本${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    check_root
    
    stop_service
    remove_config "$1"  # 传递命令行参数
    cleanup_project
    check_deploy_residue
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}卸载完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    echo -e "${GREEN}清理情况：${NC}"
    echo "  ✓ 部署的配置文件已删除: $NGINX_CONF_FILE"
    echo "  ✓ 项目目录已保留（conf.d、lua 等）"
    echo ""
    
    echo -e "${YELLOW}后续操作建议：${NC}"
    echo "  1. 如需重新部署，运行: sudo ./scripts/deploy.sh"
    echo "  2. 如需完全清理项目，手动删除项目目录"
    echo "  3. 检查是否有其他配置文件需要清理"
    echo ""
}

# 执行主函数
main "$@"

