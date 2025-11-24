#!/bin/bash

# 依赖检查和自动安装脚本
# 功能：检查项目所需的所有第三方依赖，并自动安装缺失的依赖

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量（统一使用 OPENRESTY_PREFIX，兼容 OPENRESTY_DIR）
OPENRESTY_PREFIX="${OPENRESTY_PREFIX:-${OPENRESTY_DIR:-/usr/local/openresty}}"
OPM_BIN="${OPENRESTY_PREFIX}/bin/opm"
LUALIB_DIR="${OPENRESTY_PREFIX}/site/lualib"

# 依赖定义
declare -A DEPENDENCIES
# 必需依赖
DEPENDENCIES["resty.mysql"]="openresty/lua-resty-mysql|必需|MySQL 客户端，用于数据库连接"
DEPENDENCIES["resty.redis"]="openresty/lua-resty-redis|可选|Redis 客户端，用于二级缓存"
DEPENDENCIES["resty.maxminddb"]="anjia0532/lua-resty-maxminddb|可选|GeoIP2 数据库查询，用于地域封控"
DEPENDENCIES["resty.http"]="ledgetech/lua-resty-http|可选|HTTP 客户端，用于告警 Webhook"
DEPENDENCIES["resty.file"]="openresty/lua-resty-file|可选|文件操作，用于日志队列"
DEPENDENCIES["resty.msgpack"]="openresty/lua-resty-msgpack|可选|MessagePack 序列化，用于高性能序列化"

# 内置模块（不需要安装）
BUILTIN_MODULES=("cjson" "bit")

# 统计
TOTAL=0
INSTALLED=0
MISSING=0
FAILED=0

# 打印标题
print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}依赖检查和自动安装工具${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

# 检查 OpenResty 是否安装
check_openresty() {
    echo -e "${BLUE}[1/3] 检查 OpenResty 安装...${NC}"
    
    if [ ! -f "${OPENRESTY_PREFIX}/bin/openresty" ]; then
        echo -e "${RED}✗ OpenResty 未安装${NC}"
        echo -e "${YELLOW}请先运行: sudo ./scripts/install_openresty.sh${NC}"
        exit 1
    fi
    
    local version=$(${OPENRESTY_PREFIX}/bin/openresty -v 2>&1 | head -n 1)
    echo -e "${GREEN}✓ OpenResty 已安装${NC}"
    echo "  版本: $version"
    echo "  安装路径: ${OPENRESTY_PREFIX}"
    
    # 检查 opm 是否可用
    if [ ! -f "${OPM_BIN}" ]; then
        echo -e "${RED}✗ opm 未找到${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ opm 可用${NC}"
    echo ""
}

# 检查模块是否已安装
check_module_installed() {
    local module_name=$1
    local module_file="${LUALIB_DIR}/${module_name//\./\/}.lua"
    
    # 检查文件是否存在
    if [ -f "$module_file" ]; then
        return 0
    fi
    
    # 检查目录是否存在（某些模块可能是目录结构）
    local module_dir="${LUALIB_DIR}/${module_name//\./\/}"
    if [ -d "$module_dir" ]; then
        return 0
    fi
    
    return 1
}

# 安装模块
install_module() {
    local module_name=$1
    local opm_package=$2
    local is_required=$3
    local description=$4
    
    TOTAL=$((TOTAL + 1))
    
    echo -n "检查 ${module_name}... "
    
    # 检查是否已安装
    if check_module_installed "$module_name"; then
        echo -e "${GREEN}✓ 已安装${NC}"
        INSTALLED=$((INSTALLED + 1))
        return 0
    fi
    
    echo -e "${YELLOW}未安装${NC}"
    MISSING=$((MISSING + 1))
    
    # 如果是可选模块，询问是否安装
    if [ "$is_required" != "必需" ]; then
        echo -e "  ${BLUE}说明: ${description}${NC}"
        read -p "  是否安装？[Y/n]: " INSTALL_IT
        INSTALL_IT="${INSTALL_IT:-Y}"
        
        if [[ ! "$INSTALL_IT" =~ ^[Yy]$ ]]; then
            echo -e "  ${YELLOW}⏭ 跳过安装${NC}"
            return 0
        fi
    else
        echo -e "  ${BLUE}说明: ${description}${NC}"
        echo -e "  ${YELLOW}正在安装...${NC}"
    fi
    
    # 安装模块
    echo -n "  安装中... "
    if ${OPM_BIN} get "$opm_package" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ 安装成功${NC}"
        INSTALLED=$((INSTALLED + 1))
        MISSING=$((MISSING - 1))
        return 0
    else
        echo -e "${RED}✗ 安装失败${NC}"
        FAILED=$((FAILED + 1))
        
        if [ "$is_required" = "必需" ]; then
            echo -e "${RED}错误: 必需模块安装失败，请手动安装${NC}"
            echo -e "${YELLOW}手动安装命令: ${OPM_BIN} get ${opm_package}${NC}"
            return 1
        else
            echo -e "${YELLOW}警告: 可选模块安装失败，功能可能受限${NC}"
            return 0
        fi
    fi
}

# 检查所有依赖
check_dependencies() {
    echo -e "${BLUE}[2/3] 检查依赖模块...${NC}"
    echo ""
    
    # 检查内置模块
    echo -e "${BLUE}内置模块（OpenResty 自带）:${NC}"
    for module in "${BUILTIN_MODULES[@]}"; do
        echo -e "  ${GREEN}✓ ${module}${NC}"
    done
    echo ""
    
    # 检查第三方模块
    echo -e "${BLUE}第三方模块:${NC}"
    for module_name in "${!DEPENDENCIES[@]}"; do
        IFS='|' read -r opm_package is_required description <<< "${DEPENDENCIES[$module_name]}"
        install_module "$module_name" "$opm_package" "$is_required" "$description"
    done
    
    echo ""
}

# 验证安装
verify_installation() {
    echo -e "${BLUE}[3/3] 验证安装结果...${NC}"
    echo ""
    
    local all_required_ok=true
    
    for module_name in "${!DEPENDENCIES[@]}"; do
        IFS='|' read -r opm_package is_required description <<< "${DEPENDENCIES[$module_name]}"
        
        if [ "$is_required" = "必需" ]; then
            if check_module_installed "$module_name"; then
                echo -e "${GREEN}✓ ${module_name} (必需) - 已安装${NC}"
            else
                echo -e "${RED}✗ ${module_name} (必需) - 未安装${NC}"
                all_required_ok=false
            fi
        fi
    done
    
    echo ""
    
    if [ "$all_required_ok" = true ]; then
        echo -e "${GREEN}✓ 所有必需模块已安装${NC}"
    else
        echo -e "${RED}✗ 部分必需模块未安装${NC}"
        echo -e "${YELLOW}请手动安装缺失的模块${NC}"
        return 1
    fi
}

# 显示统计信息
show_summary() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}检查完成${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "${BLUE}统计信息:${NC}"
    echo "  总计: $TOTAL"
    echo -e "  ${GREEN}已安装: $INSTALLED${NC}"
    if [ $MISSING -gt 0 ]; then
        echo -e "  ${YELLOW}未安装: $MISSING${NC}"
    fi
    if [ $FAILED -gt 0 ]; then
        echo -e "  ${RED}安装失败: $FAILED${NC}"
    fi
    echo ""
    
    # 显示建议
    if [ $FAILED -gt 0 ]; then
        echo -e "${YELLOW}建议:${NC}"
        echo "  1. 检查网络连接"
        echo "  2. 检查 opm 是否正常工作: ${OPM_BIN} -h"
        echo "  3. 手动安装失败的模块"
        echo ""
    fi
    
    # 显示下一步
    echo -e "${BLUE}下一步:${NC}"
    echo "  1. 重启 OpenResty 服务使新安装的模块生效"
    echo "  2. 检查配置文件是否正确"
    echo "  3. 运行测试验证功能"
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
    check_dependencies
    verify_installation
    show_summary
}

# 运行主函数
main

