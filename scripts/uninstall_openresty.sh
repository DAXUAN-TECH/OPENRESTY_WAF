#!/bin/bash

# OpenResty 一键卸载脚本
# 用途：卸载 OpenResty 及其相关配置

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
INSTALL_DIR="${OPENRESTY_PREFIX:-/usr/local/openresty}"

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误: 需要 root 权限来卸载${NC}"
        echo "请使用: sudo $0"
        exit 1
    fi
}

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

# 停止服务
stop_service() {
    echo -e "${BLUE}[1/5] 停止 OpenResty 服务...${NC}"
    
    if systemctl is-active --quiet openresty 2>/dev/null; then
        systemctl stop openresty
        echo -e "${GREEN}✓ 服务已停止${NC}"
    elif [ -f "${INSTALL_DIR}/nginx/logs/nginx.pid" ]; then
        if [ -f "${INSTALL_DIR}/bin/openresty" ]; then
            ${INSTALL_DIR}/bin/openresty -s quit 2>/dev/null || true
        fi
        echo -e "${GREEN}✓ 服务已停止${NC}"
    else
        echo -e "${YELLOW}服务未运行${NC}"
    fi
}

# 禁用服务
disable_service() {
    echo -e "${BLUE}[2/5] 禁用开机自启...${NC}"
    
    if systemctl is-enabled --quiet openresty 2>/dev/null; then
        systemctl disable openresty
        echo -e "${GREEN}✓ 已禁用开机自启${NC}"
    else
        echo -e "${YELLOW}服务未设置开机自启${NC}"
    fi
}

# 删除 systemd 服务文件
remove_service_file() {
    echo -e "${BLUE}[3/5] 删除 systemd 服务文件...${NC}"
    
    if [ -f /etc/systemd/system/openresty.service ]; then
        rm -f /etc/systemd/system/openresty.service
        systemctl daemon-reload
        echo -e "${GREEN}✓ 服务文件已删除${NC}"
    else
        echo -e "${YELLOW}服务文件不存在${NC}"
    fi
}

# 删除符号链接
remove_symlinks() {
    echo -e "${BLUE}[4/5] 删除符号链接...${NC}"
    
    if [ -L /usr/local/bin/openresty ]; then
        rm -f /usr/local/bin/openresty
        echo -e "${GREEN}✓ 符号链接已删除${NC}"
    fi
    
    if [ -L /usr/local/bin/opm ]; then
        rm -f /usr/local/bin/opm
    fi
    
    if [ -L /usr/local/bin/resty ]; then
        rm -f /usr/local/bin/resty
    fi
}

# 检查依赖 OpenResty 的服务
check_dependent_services() {
    echo -e "${BLUE}检查依赖 OpenResty 的服务...${NC}"
    
    local dependent_services=()
    local affected_apps=()
    
    # 检查是否有其他 Nginx/OpenResty 实例
    if pgrep -x nginx > /dev/null 2>&1; then
        affected_apps+=("Nginx 服务")
    fi
    
    # 检查是否有应用使用 OpenResty 端口
    if command -v lsof &> /dev/null; then
        if lsof -i :80 2>/dev/null | grep -qv "openresty\|nginx"; then
            affected_apps+=("使用 80 端口的应用")
        fi
        if lsof -i :443 2>/dev/null | grep -qv "openresty\|nginx"; then
            affected_apps+=("使用 443 端口的应用")
        fi
    fi
    
    # 检查是否有项目使用 OpenResty
    if [ -f "${INSTALL_DIR}/nginx/conf/nginx.conf" ]; then
        if grep -q "project_root\|upstream\|server_name" "${INSTALL_DIR}/nginx/conf/nginx.conf" 2>/dev/null; then
            affected_apps+=("使用 OpenResty 配置的项目")
        fi
    fi
    
    if [ ${#affected_apps[@]} -gt 0 ]; then
        echo -e "${YELLOW}⚠ 检测到可能依赖 OpenResty 的服务或应用：${NC}"
        for app in "${affected_apps[@]}"; do
            echo -e "${YELLOW}  - $app${NC}"
        done
        echo ""
        return 1
    else
        echo -e "${GREEN}✓ 未检测到依赖 OpenResty 的服务${NC}"
        return 0
    fi
}

# 卸载 OpenResty
uninstall_openresty() {
    echo -e "${BLUE}[5/5] 卸载 OpenResty...${NC}"
    
    # 检查依赖服务
    if ! check_dependent_services; then
        echo -e "${YELLOW}⚠ 卸载 OpenResty 可能影响上述服务${NC}"
    fi
    
    # 检查安装目录是否存在
    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${YELLOW}OpenResty 未安装在 $INSTALL_DIR${NC}"
        return 0
    fi
    
    # 如果从命令行传入参数，使用参数值，否则询问用户
    if [ -n "$1" ]; then
        DELETE_DIR="$1"
    else
        echo ""
        echo -e "${YELLOW}请选择清理选项：${NC}"
        echo "  1. 仅卸载软件，保留安装目录和配置（推荐，可重新安装）"
        echo "  2. 卸载软件并删除配置文件，但保留安装目录"
        echo "  3. 完全删除（卸载软件、删除安装目录和所有配置）"
        read -p "请选择 [1-3]: " CLEANUP_CHOICE
        
        case "$CLEANUP_CHOICE" in
            1)
                DELETE_DIR="keep_all"
                ;;
            2)
                DELETE_DIR="keep_dir"
                ;;
            3)
                DELETE_DIR="delete_all"
                ;;
            *)
                DELETE_DIR="keep_all"
                echo -e "${YELLOW}无效选择，默认保留安装目录${NC}"
                ;;
        esac
    fi
    
    case "$DELETE_DIR" in
        keep_all)
            echo -e "${GREEN}✓ 保留安装目录和配置${NC}"
            echo -e "${BLUE}安装目录位置: $INSTALL_DIR${NC}"
            echo -e "${BLUE}配置文件位置: ${INSTALL_DIR}/nginx/conf/nginx.conf${NC}"
            ;;
        keep_dir)
            echo -e "${YELLOW}删除配置文件，但保留安装目录...${NC}"
            
            # 删除配置文件
            if [ -f "${INSTALL_DIR}/nginx/conf/nginx.conf" ]; then
                rm -f "${INSTALL_DIR}/nginx/conf/nginx.conf"
                echo -e "${GREEN}✓ 已删除配置文件${NC}"
            fi
            
            # 删除日志文件
            if [ -d "${INSTALL_DIR}/nginx/logs" ]; then
                rm -rf "${INSTALL_DIR}/nginx/logs"/*
                echo -e "${GREEN}✓ 已清理日志目录${NC}"
            fi
            
            echo -e "${GREEN}✓ 配置文件已删除，安装目录已保留${NC}"
            ;;
        delete_all|y|Y)
            echo -e "${RED}警告: 将删除 OpenResty 安装目录和所有配置！${NC}"
            
            # 再次确认
            if [ "$DELETE_DIR" != "delete_all" ]; then
                read -p "确认删除安装目录？[y/N]: " CONFIRM_DELETE
                CONFIRM_DELETE="${CONFIRM_DELETE:-N}"
                if [[ ! "$CONFIRM_DELETE" =~ ^[Yy]$ ]]; then
                    echo -e "${GREEN}取消删除，保留安装目录${NC}"
                    DELETE_DIR="keep_all"
                    return 0
                fi
            fi
            
            rm -rf "$INSTALL_DIR"
            echo -e "${GREEN}✓ 安装目录已删除${NC}"
            ;;
        *)
            echo -e "${YELLOW}保留安装目录: $INSTALL_DIR${NC}"
            ;;
    esac
    
    # 尝试使用包管理器卸载（如果是从包管理器安装的）
    detect_os
    
    case $OS in
        centos|rhel|fedora|rocky|almalinux|oraclelinux|amazonlinux)
            if command -v dnf &> /dev/null; then
                dnf remove -y openresty 2>/dev/null || true
            elif command -v yum &> /dev/null; then
                yum remove -y openresty 2>/dev/null || true
            fi
            ;;
        ubuntu|debian|linuxmint|raspbian|kali)
            if command -v apt-get &> /dev/null; then
                apt-get remove -y openresty 2>/dev/null || true
                apt-get purge -y openresty 2>/dev/null || true
            fi
            ;;
        opensuse*|sles)
            if command -v zypper &> /dev/null; then
                zypper remove -y openresty 2>/dev/null || true
            fi
            ;;
        arch|manjaro)
            if command -v pacman &> /dev/null; then
                pacman -R --noconfirm openresty 2>/dev/null || true
            fi
            ;;
    esac
}

# 主函数
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}OpenResty 一键卸载脚本${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    check_root
    
    stop_service
    disable_service
    remove_service_file
    remove_symlinks
    uninstall_openresty "$1"  # 传递命令行参数
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}卸载完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # 根据清理选项显示不同的提示
    if [ "$DELETE_DIR" = "keep_all" ]; then
        echo -e "${GREEN}数据保留情况：${NC}"
        echo "  ✓ 安装目录已保留"
        echo "  ✓ 配置文件已保留"
        echo ""
        echo -e "${BLUE}重新安装 OpenResty 后，配置将自动恢复${NC}"
    elif [ "$DELETE_DIR" = "keep_dir" ]; then
        echo -e "${GREEN}数据保留情况：${NC}"
        echo "  ✓ 安装目录已保留"
        echo "  ✗ 配置文件已删除"
        echo ""
        echo -e "${BLUE}重新安装 OpenResty 后，需要重新部署配置${NC}"
    else
        echo -e "${YELLOW}数据清理情况：${NC}"
        echo "  ✗ 安装目录已删除"
        echo "  ✗ 所有配置已删除"
        echo ""
        echo -e "${BLUE}如需重新安装 OpenResty，请运行安装脚本${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}后续操作建议：${NC}"
    echo "  1. 如果保留了安装目录，重新安装 OpenResty 后配置会自动恢复"
    echo "  2. 如果删除了安装目录，需要重新安装和部署配置"
    echo "  3. 检查依赖 OpenResty 的应用是否需要重新配置"
    echo ""
}

# 执行主函数
main "$@"

