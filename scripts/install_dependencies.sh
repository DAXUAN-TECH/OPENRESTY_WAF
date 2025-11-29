#!/bin/bash

# 依赖自动安装脚本
# 功能：自动安装所有缺失的依赖（不询问，直接安装）

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

# 引用依赖检查脚本（统一使用 check_dependencies.sh 的检查函数）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/check_dependencies.sh" ]; then
    source "${SCRIPT_DIR}/check_dependencies.sh"
else
    echo "错误: 无法找到 check_dependencies.sh"
    exit 1
fi

# 配置变量（统一使用 OPENRESTY_PREFIX，兼容 OPENRESTY_DIR）
OPENRESTY_PREFIX="${OPENRESTY_PREFIX:-${OPENRESTY_DIR:-/usr/local/openresty}}"
OPM_BIN="${OPENRESTY_PREFIX}/bin/opm"
LUALIB_DIR="${OPENRESTY_PREFIX}/site/lualib"

# 依赖定义（必需和可选）
declare -A REQUIRED_DEPENDENCIES
REQUIRED_DEPENDENCIES["resty.mysql"]="openresty/lua-resty-mysql|MySQL 客户端，用于数据库连接"

declare -A OPTIONAL_DEPENDENCIES
OPTIONAL_DEPENDENCIES["resty.redis"]="openresty/lua-resty-redis|Redis 客户端，用于二级缓存"
OPTIONAL_DEPENDENCIES["resty.maxminddb"]="anjia0532/lua-resty-maxminddb|GeoIP2 数据库查询，用于地域封控"
OPTIONAL_DEPENDENCIES["resty.http"]="ledgetech/lua-resty-http|HTTP 客户端，用于告警 Webhook"
# 注意：resty.file 模块在 OPM 中不存在，代码使用标准 Lua io 库，已从依赖列表中移除
OPTIONAL_DEPENDENCIES["resty.msgpack"]="chronolaw/lua-resty-msgpack|MessagePack 序列化，用于高性能序列化"

# 统计
TOTAL=0
INSTALLED=0
SKIPPED=0
FAILED=0

# 打印标题
print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}依赖自动安装工具${NC}"
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
    
    # 检查 opm 是否可用
    if [ ! -f "${OPM_BIN}" ]; then
        echo -e "${RED}✗ opm 未找到${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ opm 可用${NC}"
    echo ""
}

# check_module_installed() 函数已从 check_dependencies.sh 引用，无需重复定义

# 安装模块
install_module() {
    local module_name=$1
    local opm_package=$2
    local description=$3
    local is_required=$4
    
    TOTAL=$((TOTAL + 1))
    
    echo -n "检查 ${module_name}... "
    
    # 检查是否已安装（包括 Lua 加载测试）
    if check_module_installed "$module_name"; then
        echo -e "${GREEN}✓ 已安装（已验证可加载）${NC}"
        INSTALLED=$((INSTALLED + 1))
        return 0
    fi
    
    echo -e "${YELLOW}未安装，正在安装...${NC}"
    echo -e "  ${BLUE}说明: ${description}${NC}"
    
    # 安装模块（显示详细错误信息）
    local install_output
    local install_status
    
    # 尝试安装并捕获输出
    install_output=$(${OPM_BIN} get "$opm_package" 2>&1)
    install_status=$?
    
    if [ $install_status -eq 0 ]; then
        # 检查是否真的安装成功（验证文件是否存在）
        if check_module_installed "$module_name"; then
        echo -e "  ${GREEN}✓ 安装成功${NC}"
        INSTALLED=$((INSTALLED + 1))
        return 0
        else
            # 安装命令成功但文件不存在，可能是包结构问题
            echo -e "  ${YELLOW}⚠ 安装命令成功，但模块文件未找到${NC}"
            echo -e "  ${BLUE}OPM 输出:${NC}"
            echo "$install_output" | sed 's/^/    /'
            FAILED=$((FAILED + 1))
        fi
    else
        echo -e "  ${RED}✗ 安装失败${NC}"
        echo -e "  ${BLUE}错误信息:${NC}"
        echo "$install_output" | sed 's/^/    /'
        FAILED=$((FAILED + 1))
    fi
        
        if [ "$is_required" = "required" ]; then
            echo -e "${RED}错误: 必需模块安装失败${NC}"
            echo -e "${YELLOW}手动安装命令: ${OPM_BIN} get ${opm_package}${NC}"
        echo -e "${YELLOW}调试信息:${NC}"
        echo "  - OPM 路径: ${OPM_BIN}"
        if [ -f "${OPM_BIN}" ] && [ -x "${OPM_BIN}" ]; then
            echo "  - OPM 状态: 已安装且可执行"
            if ${OPM_BIN} -h &>/dev/null; then
                echo "  - OPM 验证: 正常工作"
            else
                echo "  - OPM 验证: 无法执行（可能有问题）"
            fi
        else
            echo "  - OPM 状态: 未找到或不可执行"
        fi
        echo "  - 目标目录: ${LUALIB_DIR}"
        echo "  - 模块路径: ${LUALIB_DIR}/${module_name//\./\/}.lua"
            return 1
        else
            echo -e "${YELLOW}警告: 可选模块安装失败，功能可能受限${NC}"
        echo -e "${BLUE}提示: 可以稍后手动安装: ${OPM_BIN} get ${opm_package}${NC}"
        echo -e "${YELLOW}调试信息:${NC}"
        echo "  - OPM 路径: ${OPM_BIN}"
        if [ -f "${OPM_BIN}" ] && [ -x "${OPM_BIN}" ]; then
            echo "  - OPM 状态: 已安装且可执行"
            if ${OPM_BIN} -h &>/dev/null; then
                echo "  - OPM 验证: 正常工作"
            else
                echo "  - OPM 验证: 无法执行（可能有问题）"
            fi
        else
            echo "  - OPM 状态: 未找到或不可执行"
        fi
        echo "  - 目标目录: ${LUALIB_DIR}"
        echo "  - 模块路径: ${LUALIB_DIR}/${module_name//\./\/}.lua"
        echo ""
        return 0
    fi
}

# 安装必需依赖
install_required() {
    echo -e "${BLUE}[2/3] 安装必需依赖...${NC}"
    echo ""
    
    local has_error=false
    
    for module_name in "${!REQUIRED_DEPENDENCIES[@]}"; do
        IFS='|' read -r opm_package description <<< "${REQUIRED_DEPENDENCIES[$module_name]}"
        if ! install_module "$module_name" "$opm_package" "$description" "required"; then
            has_error=true
        fi
    done
    
    echo ""
    
    if [ "$has_error" = true ]; then
        echo -e "${RED}✗ 部分必需模块安装失败${NC}"
        return 1
    else
        echo -e "${GREEN}✓ 所有必需模块安装完成${NC}"
        return 0
    fi
}

# 安装可选依赖
install_optional() {
    echo -e "${BLUE}[3/3] 安装可选依赖...${NC}"
    echo ""
    
    for module_name in "${!OPTIONAL_DEPENDENCIES[@]}"; do
        IFS='|' read -r opm_package description <<< "${OPTIONAL_DEPENDENCIES[$module_name]}"
        install_module "$module_name" "$opm_package" "$description" "optional"
    done
    
    echo ""
    echo -e "${GREEN}✓ 可选模块安装完成${NC}"
}

# 显示统计信息
show_summary() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}安装完成${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "${BLUE}统计信息:${NC}"
    echo "  总计: $TOTAL"
    echo -e "  ${GREEN}已安装: $INSTALLED${NC}"
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
        echo "  1. 检查网络连接"
        echo "  2. 检查 opm 是否正常工作: ${OPM_BIN} -h"
        echo "  3. 手动安装失败的模块"
        echo ""
    fi
    
    # 显示下一步
    echo -e "${BLUE}下一步:${NC}"
    echo "  1. 重启 OpenResty 服务使新安装的模块生效"
    echo "  2. 运行检查脚本验证: sudo ./scripts/check_dependencies.sh"
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
    
    # 安装必需依赖
    if ! install_required; then
        echo -e "${RED}必需模块安装失败，退出${NC}"
        exit 1
    fi
    
    # 安装可选依赖
    install_optional
    
    show_summary
}

# 运行主函数
main

