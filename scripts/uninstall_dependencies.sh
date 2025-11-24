#!/bin/bash

# 依赖卸载脚本
# 功能：卸载已安装的第三方 Lua 模块依赖

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量（统一使用 OPENRESTY_PREFIX，兼容 OPENRESTY_DIR）
OPENRESTY_PREFIX="${OPENRESTY_PREFIX:-${OPENRESTY_DIR:-/usr/local/openresty}}"
LUALIB_DIR="${OPENRESTY_PREFIX}/site/lualib"

# 依赖定义（与 check_dependencies.sh 保持一致）
declare -A DEPENDENCIES
DEPENDENCIES["resty.mysql"]="openresty/lua-resty-mysql|必需|MySQL 客户端，用于数据库连接"
DEPENDENCIES["resty.redis"]="openresty/lua-resty-redis|可选|Redis 客户端，用于二级缓存"
DEPENDENCIES["resty.maxminddb"]="anjia0532/lua-resty-maxminddb|可选|GeoIP2 数据库查询，用于地域封控"
DEPENDENCIES["resty.http"]="ledgetech/lua-resty-http|可选|HTTP 客户端，用于告警 Webhook"
DEPENDENCIES["resty.file"]="openresty/lua-resty-file|可选|文件操作，用于日志队列"
DEPENDENCIES["resty.msgpack"]="chronolaw/lua-resty-msgpack|可选|MessagePack 序列化，用于高性能序列化"

# 统计
TOTAL=0
UNINSTALLED=0
SKIPPED=0
FAILED=0

# 打印标题
print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}依赖卸载工具${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

# 检查 OpenResty 是否安装
check_openresty() {
    if [ ! -f "${OPENRESTY_PREFIX}/bin/openresty" ]; then
        echo -e "${YELLOW}警告: OpenResty 未安装，无法卸载依赖模块${NC}"
        exit 0
    fi
    
    echo -e "${GREEN}✓ OpenResty 已安装${NC}"
    echo ""
}

# 检查模块是否已安装
check_module_installed() {
    local module_name=$1
    local module_file="${LUALIB_DIR}/${module_name//\./\/}.lua"
    local module_dir="${LUALIB_DIR}/${module_name//\./\/}"
    
    if [ -f "$module_file" ] || [ -d "$module_dir" ]; then
        return 0
    fi
    
    return 1
}

# 卸载模块
uninstall_module() {
    local module_name=$1
    local is_required=$2
    local description=$3
    
    TOTAL=$((TOTAL + 1))
    
    echo -n "检查 ${module_name}... "
    
    # 检查是否已安装
    if ! check_module_installed "$module_name"; then
        echo -e "${YELLOW}未安装${NC}"
        SKIPPED=$((SKIPPED + 1))
        return 0
    fi
    
    echo -e "${GREEN}已安装${NC}"
    
    # 如果是必需模块，警告用户
    if [ "$is_required" = "必需" ]; then
        echo -e "  ${RED}警告: 这是必需模块，卸载后系统将无法正常工作！${NC}"
        echo -e "  ${BLUE}说明: ${description}${NC}"
        read -p "  确认要卸载？[y/N]: " CONFIRM
        CONFIRM="${CONFIRM:-N}"
        
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            echo -e "  ${YELLOW}⏭ 跳过卸载${NC}"
            SKIPPED=$((SKIPPED + 1))
            return 0
        fi
    else
        echo -e "  ${BLUE}说明: ${description}${NC}"
        read -p "  是否卸载？[Y/n]: " UNINSTALL_IT
        UNINSTALL_IT="${UNINSTALL_IT:-Y}"
        
        if [[ ! "$UNINSTALL_IT" =~ ^[Yy]$ ]]; then
            echo -e "  ${YELLOW}⏭ 跳过卸载${NC}"
            SKIPPED=$((SKIPPED + 1))
            return 0
        fi
    fi
    
    # 卸载模块
    echo -n "  卸载中... "
    local module_path="${LUALIB_DIR}/${module_name//\./\/}"
    
    if rm -rf "$module_path" 2>/dev/null; then
        echo -e "${GREEN}✓ 卸载成功${NC}"
        UNINSTALLED=$((UNINSTALLED + 1))
        return 0
    else
        echo -e "${RED}✗ 卸载失败${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

# 卸载所有依赖
uninstall_dependencies() {
    echo -e "${BLUE}[1/2] 检查已安装的依赖模块...${NC}"
    echo ""
    
    local has_installed=false
    
    for module_name in "${!DEPENDENCIES[@]}"; do
        if check_module_installed "$module_name"; then
            has_installed=true
            break
        fi
    done
    
    if [ "$has_installed" = false ]; then
        echo -e "${YELLOW}未发现已安装的依赖模块${NC}"
        echo ""
        return 0
    fi
    
    echo -e "${BLUE}已安装的模块:${NC}"
    for module_name in "${!DEPENDENCIES[@]}"; do
        IFS='|' read -r opm_package is_required description <<< "${DEPENDENCIES[$module_name]}"
        uninstall_module "$module_name" "$is_required" "$description"
    done
    
    echo ""
}

# 验证卸载结果
verify_uninstallation() {
    echo -e "${BLUE}[2/2] 验证卸载结果...${NC}"
    echo ""
    
    local all_uninstalled=true
    
    for module_name in "${!DEPENDENCIES[@]}"; do
        IFS='|' read -r opm_package is_required description <<< "${DEPENDENCIES[$module_name]}"
        
        if check_module_installed "$module_name"; then
            echo -e "${YELLOW}⚠ ${module_name} - 仍存在${NC}"
            all_uninstalled=false
        else
            echo -e "${GREEN}✓ ${module_name} - 已卸载${NC}"
        fi
    done
    
    echo ""
    
    if [ "$all_uninstalled" = true ]; then
        echo -e "${GREEN}✓ 所有模块已卸载${NC}"
    else
        echo -e "${YELLOW}⚠ 部分模块仍存在，可能需要手动删除${NC}"
    fi
}

# 显示统计信息
show_summary() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}卸载完成${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "${BLUE}统计信息:${NC}"
    echo "  总计: $TOTAL"
    echo -e "  ${GREEN}已卸载: $UNINSTALLED${NC}"
    if [ $SKIPPED -gt 0 ]; then
        echo -e "  ${YELLOW}跳过: $SKIPPED${NC}"
    fi
    if [ $FAILED -gt 0 ]; then
        echo -e "  ${RED}失败: $FAILED${NC}"
    fi
    echo ""
    
    # 显示建议
    if [ $FAILED -gt 0 ]; then
        echo -e "${YELLOW}建议:${NC}"
        echo "  1. 检查文件权限"
        echo "  2. 手动删除失败的模块文件"
        echo ""
    fi
    
    # 显示下一步
    echo -e "${BLUE}下一步:${NC}"
    echo "  1. 如果卸载了必需模块，需要重新安装: sudo ./scripts/install_dependencies.sh"
    echo "  2. 重启 OpenResty 服务使更改生效"
    echo ""
}

# 主函数
main() {
    print_header
    
    # 检查是否为 root
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}警告: 建议使用 root 权限运行此脚本${NC}"
        echo -e "${YELLOW}某些操作可能需要 root 权限${NC}"
        echo ""
        read -p "是否继续？[Y/n]: " CONTINUE
        CONTINUE="${CONTINUE:-Y}"
        if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
            exit 0
        fi
        echo ""
    fi
    
    check_openresty
    uninstall_dependencies
    verify_uninstallation
    show_summary
}

# 运行主函数
main

