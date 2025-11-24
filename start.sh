#!/bin/bash

# OpenResty WAF 一键启动脚本
# 用途：统一安装和配置 OpenResty WAF 系统
# 功能：按顺序执行各安装脚本，支持单独模块化安装和维护操作

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 获取脚本目录（使用相对路径）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
CONFIG_FILE="${SCRIPT_DIR}/lua/config.lua"
LOGS_DIR="${SCRIPT_DIR}/logs"
OPENRESTY_PREFIX="${OPENRESTY_PREFIX:-/usr/local/openresty}"

# 显示使用说明
show_usage() {
    echo "使用方法:"
    echo "  sudo $0                          # 显示帮助信息"
    echo "  sudo $0 install all              # 完整安装（交互式）"
    echo "  sudo $0 install <module>         # 单独安装某个模块"
    echo "  sudo $0 uninstall <module>      # 卸载某个模块"
    echo ""
    echo "可用模块（安装）:"
    echo "  openresty    - 安装 OpenResty（基础组件）"
    echo "  opm          - 安装 opm（OpenResty 包管理器）"
    echo "  dependencies - 安装 Lua 模块依赖（需要 opm）"
    echo "  mysql        - 安装 MySQL（数据库）"
    echo "  redis        - 安装 Redis（可选，缓存）"
    echo "  geoip        - 安装 GeoIP 数据库（可选，地域封控）"
    echo "  deploy       - 部署配置文件（需要 OpenResty）"
    echo "  optimize     - 系统优化"
    echo "  check        - 项目全面检查"
    echo "  check-deps   - 检查 Lua 模块依赖"
    echo "  update-config - 更新数据库连接配置（需要 MySQL）"
    echo "  update-geoip - 更新 GeoIP 数据库"
    echo "  all          - 完整安装（交互式，按依赖顺序）"
    echo ""
    echo "可用模块（卸载）:"
    echo "  uninstall openresty    - 卸载 OpenResty"
    echo "  uninstall mysql        - 卸载 MySQL"
    echo "  uninstall redis        - 卸载 Redis"
    echo "  uninstall geoip        - 卸载 GeoIP 数据库"
    echo "  uninstall deploy       - 卸载部署的配置文件"
    echo "  uninstall dependencies - 卸载 Lua 模块依赖"
    echo "  uninstall all          - 完整卸载（交互式）"
    echo ""
    echo "示例:"
    echo "  sudo $0                          # 显示帮助信息"
    echo "  sudo $0 install all              # 完整安装"
    echo "  sudo $0 install mysql            # 只安装 MySQL"
    echo "  sudo $0 install openresty        # 只安装 OpenResty"
    echo "  sudo $0 uninstall mysql          # 卸载 MySQL"
    echo "  sudo $0 uninstall all            # 完整卸载"
    exit 0
}

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误: 需要 root 权限来安装系统${NC}"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 安装 OpenResty
install_openresty() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}安装 OpenResty${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # 直接调用安装脚本，所有检测逻辑在脚本内部
    if ! bash "${SCRIPTS_DIR}/install_openresty.sh"; then
        echo -e "${RED}✗ OpenResty 安装失败${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ OpenResty 安装成功${NC}"
    echo ""
}

# 安装 MySQL
install_mysql() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}安装 MySQL${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # 直接调用 MySQL 安装脚本，脚本内部会处理所有配置
    if ! bash "${SCRIPTS_DIR}/install_mysql.sh"; then
        echo -e "${RED}✗ MySQL 安装失败${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ MySQL 安装完成${NC}"
    echo ""
}

# 安装 Redis
install_redis() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}安装 Redis${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # 直接调用 Redis 安装脚本，脚本内部会处理所有配置
    if ! bash "${SCRIPTS_DIR}/install_redis.sh"; then
        echo -e "${YELLOW}⚠ Redis 安装失败，但这是可选步骤${NC}"
        return 0
    fi
    
    echo -e "${GREEN}✓ Redis 安装完成${NC}"
    echo ""
}

# 安装 GeoIP
install_geoip() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}安装 GeoIP 数据库${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # 直接调用安装脚本，所有输入逻辑在脚本内部
    if ! bash "${SCRIPTS_DIR}/install_geoip.sh"; then
        echo -e "${YELLOW}⚠ GeoIP 安装失败，但这是可选步骤${NC}"
        return 0
    fi
    
    echo -e "${GREEN}✓ GeoIP 安装完成${NC}"
    echo ""
}

# 部署配置文件
deploy_config() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}部署配置文件${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    if ! bash "${SCRIPTS_DIR}/deploy.sh"; then
        echo -e "${RED}✗ 配置文件部署失败${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ 配置文件部署完成${NC}"
    echo ""
}

# 系统优化
optimize_system() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}系统优化${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    if ! bash "${SCRIPTS_DIR}/optimize_system.sh"; then
        echo -e "${YELLOW}⚠ 系统优化失败，但这是可选步骤${NC}"
        return 0
    fi
    
    echo -e "${GREEN}✓ 系统优化完成${NC}"
    echo ""
}

# 项目全面检查
check_all() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}项目全面检查${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    if ! bash "${SCRIPTS_DIR}/check_all.sh"; then
        echo -e "${YELLOW}⚠ 项目检查完成（可能有警告）${NC}"
        return 0
    fi
    
    echo -e "${GREEN}✓ 项目检查完成${NC}"
    echo ""
}

# 更新数据库连接配置
update_config() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}更新数据库连接配置${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # 直接调用配置更新脚本，所有输入逻辑在脚本内部（交互式模式）
    if ! bash "${SCRIPTS_DIR}/set_lua_database_connect.sh"; then
        echo -e "${RED}✗ 配置更新失败${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ 配置更新完成${NC}"
    echo ""
}

# 更新 GeoIP 数据库
update_geoip() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}更新 GeoIP 数据库${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    if ! bash "${SCRIPTS_DIR}/update_geoip.sh"; then
        echo -e "${RED}✗ GeoIP 数据库更新失败${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ GeoIP 数据库更新完成${NC}"
    echo ""
}

# 安装 opm
install_opm() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}安装 opm (OpenResty Package Manager)${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # 检测系统类型
    local OS=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
    fi
    
    local install_success=0
    
    # RedHat 系列
    if [[ "$OS" =~ ^(centos|rhel|fedora|rocky|almalinux|oraclelinux|amazonlinux)$ ]]; then
        if command -v dnf &> /dev/null; then
            echo "使用 dnf 安装 openresty-opm..."
            dnf install -y openresty-opm && install_success=1
        elif command -v yum &> /dev/null; then
            echo "使用 yum 安装 openresty-opm..."
            yum install -y openresty-opm && install_success=1
        fi
    # Debian 系列
    elif [[ "$OS" =~ ^(ubuntu|debian|linuxmint|raspbian|kali)$ ]]; then
        if command -v apt-get &> /dev/null; then
            echo "更新软件包列表..."
            apt-get update -qq
            echo "使用 apt-get 安装 openresty-opm..."
            apt-get install -y openresty-opm && install_success=1
        fi
    fi
    
    if [ $install_success -eq 1 ]; then
        echo -e "${GREEN}✓ opm 安装成功${NC}"
        echo ""
        return 0
    else
        echo -e "${YELLOW}⚠ opm 安装失败，但这是可选步骤${NC}"
        echo ""
        return 0
    fi
}

# 管理依赖
manage_dependencies() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}安装/检查 Lua 模块依赖${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    if ! bash "${SCRIPTS_DIR}/install_dependencies.sh"; then
        echo -e "${YELLOW}⚠ 依赖安装完成（可能有警告）${NC}"
        return 0
    fi
    
    echo -e "${GREEN}✓ 依赖管理完成${NC}"
    echo ""
}

# 检查依赖
check_dependencies() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}检查 Lua 模块依赖${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    if ! bash "${SCRIPTS_DIR}/check_dependencies.sh"; then
        echo -e "${YELLOW}⚠ 依赖检查完成（可能有警告）${NC}"
        return 0
    fi
    
    echo -e "${GREEN}✓ 依赖检查完成${NC}"
    echo ""
}

# 卸载 OpenResty
uninstall_openresty() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}卸载 OpenResty${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # 直接调用卸载脚本，所有输入逻辑在脚本内部
    if ! bash "${SCRIPTS_DIR}/uninstall_openresty.sh"; then
        echo -e "${RED}✗ OpenResty 卸载失败${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ OpenResty 卸载完成${NC}"
    echo ""
}

# 卸载 MySQL
uninstall_mysql() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}卸载 MySQL${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # 直接调用卸载脚本，所有输入逻辑在脚本内部
    if ! bash "${SCRIPTS_DIR}/uninstall_mysql.sh"; then
        echo -e "${RED}✗ MySQL 卸载失败${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ MySQL 卸载完成${NC}"
    echo ""
}

# 卸载 Redis
uninstall_redis() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}卸载 Redis${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # 直接调用卸载脚本，所有输入逻辑在脚本内部
    if ! bash "${SCRIPTS_DIR}/uninstall_redis.sh"; then
        echo -e "${RED}✗ Redis 卸载失败${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Redis 卸载完成${NC}"
    echo ""
}

# 卸载 GeoIP
uninstall_geoip() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}卸载 GeoIP 数据库${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # 直接调用卸载脚本，所有输入逻辑在脚本内部
    if ! bash "${SCRIPTS_DIR}/uninstall_geoip.sh"; then
        echo -e "${RED}✗ GeoIP 数据库卸载失败${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ GeoIP 数据库卸载完成${NC}"
    echo ""
}

# 卸载部署的配置文件
uninstall_deploy() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}卸载部署的配置文件${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # 直接调用卸载脚本，所有输入逻辑在脚本内部
    if ! bash "${SCRIPTS_DIR}/uninstall_deploy.sh"; then
        echo -e "${RED}✗ 配置文件卸载失败${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ 配置文件卸载完成${NC}"
    echo ""
}

# 卸载依赖
uninstall_dependencies() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}卸载 Lua 模块依赖${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # 直接调用卸载脚本，所有输入逻辑在脚本内部
    if ! bash "${SCRIPTS_DIR}/uninstall_dependencies.sh"; then
        echo -e "${YELLOW}⚠ 依赖卸载完成（可能有警告）${NC}"
        return 0
    fi
    
    echo -e "${GREEN}✓ 依赖卸载完成${NC}"
    echo ""
}

# 完整卸载
uninstall_all() {
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}OpenResty WAF 一键卸载脚本${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo -e "${YELLOW}警告: 此操作将卸载已安装的组件，请确认！${NC}"
    echo ""
    
    # 收集卸载信息
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}步骤 1: 选择要卸载的组件${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # OpenResty 配置
    read -p "是否卸载 OpenResty？[Y/n]: " UNINSTALL_OPENRESTY
    UNINSTALL_OPENRESTY="${UNINSTALL_OPENRESTY:-Y}"
    
    # 部署配置
    read -p "是否卸载部署的配置文件？[Y/n]: " UNINSTALL_DEPLOY
    UNINSTALL_DEPLOY="${UNINSTALL_DEPLOY:-Y}"
    
    # MySQL 配置
    read -p "是否卸载 MySQL？[Y/n]: " UNINSTALL_MYSQL
    UNINSTALL_MYSQL="${UNINSTALL_MYSQL:-Y}"
    
    # Redis 配置
    read -p "是否卸载 Redis？[Y/n]: " UNINSTALL_REDIS
    UNINSTALL_REDIS="${UNINSTALL_REDIS:-Y}"
    
    # GeoIP 配置
    read -p "是否卸载 GeoIP 数据库？[Y/n]: " UNINSTALL_GEOIP
    UNINSTALL_GEOIP="${UNINSTALL_GEOIP:-Y}"
    
    # 依赖配置
    read -p "是否卸载 Lua 模块依赖？[y/N]: " UNINSTALL_DEPENDENCIES
    UNINSTALL_DEPENDENCIES="${UNINSTALL_DEPENDENCIES:-N}"
    
    echo ""
    echo -e "${GREEN}✓ 卸载选项收集完成${NC}"
    echo ""
    
    # 计算步骤
    CURRENT_STEP=2
    TOTAL_STEPS=0
    [[ "$UNINSTALL_OPENRESTY" =~ ^[Yy]$ ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [[ "$UNINSTALL_DEPLOY" =~ ^[Yy]$ ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [[ "$UNINSTALL_MYSQL" =~ ^[Yy]$ ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [[ "$UNINSTALL_REDIS" =~ ^[Yy]$ ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [[ "$UNINSTALL_GEOIP" =~ ^[Yy]$ ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [[ "$UNINSTALL_DEPENDENCIES" =~ ^[Yy]$ ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [[ "$UNINSTALL_DEPENDENCIES" =~ ^[Yy]$ ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    
    # 步骤 1: 卸载 OpenResty
    if [[ "$UNINSTALL_OPENRESTY" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}步骤 ${CURRENT_STEP}/${TOTAL_STEPS}: 卸载 OpenResty${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        uninstall_openresty
        CURRENT_STEP=$((CURRENT_STEP + 1))
    fi
    
    # 步骤 2: 卸载部署的配置文件
    if [[ "$UNINSTALL_DEPLOY" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}步骤 ${CURRENT_STEP}/${TOTAL_STEPS}: 卸载部署的配置文件${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        uninstall_deploy
        CURRENT_STEP=$((CURRENT_STEP + 1))
    fi
    
    # 步骤 3: 卸载 MySQL
    if [[ "$UNINSTALL_MYSQL" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}步骤 ${CURRENT_STEP}/${TOTAL_STEPS}: 卸载 MySQL${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        uninstall_mysql
        CURRENT_STEP=$((CURRENT_STEP + 1))
    fi
    
    # 步骤 4: 卸载 Redis
    if [[ "$UNINSTALL_REDIS" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}步骤 ${CURRENT_STEP}/${TOTAL_STEPS}: 卸载 Redis${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        uninstall_redis
        CURRENT_STEP=$((CURRENT_STEP + 1))
    fi
    
    # 步骤 5: 卸载 GeoIP
    if [[ "$UNINSTALL_GEOIP" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}步骤 ${CURRENT_STEP}/${TOTAL_STEPS}: 卸载 GeoIP 数据库${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        uninstall_geoip
        CURRENT_STEP=$((CURRENT_STEP + 1))
    fi
    
    # 步骤 6: 卸载依赖
    if [[ "$UNINSTALL_DEPENDENCIES" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}步骤 ${CURRENT_STEP}/${TOTAL_STEPS}: 卸载 Lua 模块依赖${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        uninstall_dependencies
    fi
    
    # 卸载完成
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}卸载完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
}

# 显示所有已安装软件的配置信息
show_installed_configs() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}已安装软件配置信息汇总${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # OpenResty 配置信息
    if command -v openresty &> /dev/null || [ -f "${OPENRESTY_PREFIX}/bin/openresty" ]; then
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BLUE}OpenResty 配置信息:${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        local openresty_version=""
        if command -v openresty &> /dev/null; then
            openresty_version=$(openresty -v 2>&1 | head -n 1)
        elif [ -f "${OPENRESTY_PREFIX}/bin/openresty" ]; then
            openresty_version=$("${OPENRESTY_PREFIX}/bin/openresty" -v 2>&1 | head -n 1)
        fi
        
        if [ -n "$openresty_version" ]; then
            echo "  版本: ${openresty_version}"
        fi
        echo "  安装路径: ${OPENRESTY_PREFIX}"
        
        # 检查服务状态
        if command -v systemctl &> /dev/null; then
            if systemctl is-active --quiet openresty 2>/dev/null; then
                echo -e "  服务状态: ${GREEN}运行中${NC}"
            else
                echo -e "  服务状态: ${YELLOW}未运行${NC}"
            fi
            if systemctl is-enabled --quiet openresty 2>/dev/null; then
                echo -e "  开机自启: ${GREEN}已启用${NC}"
            else
                echo -e "  开机自启: ${YELLOW}未启用${NC}"
            fi
        fi
        
        echo "  配置文件: ${CONFIG_FILE}"
        echo ""
    fi
    
    # MySQL 配置信息
    if command -v mysql &> /dev/null || command -v mysqld &> /dev/null; then
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BLUE}MySQL 配置信息:${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        local mysql_version=""
        if command -v mysql &> /dev/null; then
            mysql_version=$(mysql --version 2>/dev/null | head -n 1)
        elif command -v mysqld &> /dev/null; then
            mysql_version=$(mysqld --version 2>/dev/null | head -n 1)
        fi
        
        if [ -n "$mysql_version" ]; then
            echo "  版本: ${mysql_version}"
        fi
        
        # 从 lua/config.lua 读取 MySQL 配置
        if [ -f "$CONFIG_FILE" ]; then
            # 提取 MySQL 配置块中的值（使用 sed 提取配置块，然后提取值）
            local mysql_block_start=$(grep -n "^_M\.mysql = {" "$CONFIG_FILE" | cut -d: -f1)
            local mysql_block_end=$(grep -n "^}" "$CONFIG_FILE" | awk -v start="$mysql_block_start" '$1 > start {print $1; exit}')
            
            if [ -n "$mysql_block_start" ] && [ -n "$mysql_block_end" ]; then
                local mysql_host=$(sed -n "${mysql_block_start},${mysql_block_end}p" "$CONFIG_FILE" | grep -E "^\s*host\s*=" | sed -E "s/.*host\s*=\s*[\"']([^\"']+)[\"'].*/\1/" | head -n 1 | tr -d ' ')
                local mysql_port=$(sed -n "${mysql_block_start},${mysql_block_end}p" "$CONFIG_FILE" | grep -E "^\s*port\s*=" | sed -E "s/.*port\s*=\s*([0-9]+).*/\1/" | head -n 1 | tr -d ' ')
                local mysql_database=$(sed -n "${mysql_block_start},${mysql_block_end}p" "$CONFIG_FILE" | grep -E "^\s*database\s*=" | sed -E "s/.*database\s*=\s*[\"']([^\"']+)[\"'].*/\1/" | head -n 1 | tr -d ' ')
                local mysql_user=$(sed -n "${mysql_block_start},${mysql_block_end}p" "$CONFIG_FILE" | grep -E "^\s*user\s*=" | sed -E "s/.*user\s*=\s*[\"']([^\"']+)[\"'].*/\1/" | head -n 1 | tr -d ' ')
                local mysql_password=$(sed -n "${mysql_block_start},${mysql_block_end}p" "$CONFIG_FILE" | grep -E "^\s*password\s*=" | sed -E "s/.*password\s*=\s*[\"']([^\"']+)[\"'].*/\1/" | head -n 1 | tr -d ' ')
                
                mysql_host="${mysql_host:-127.0.0.1}"
                mysql_port="${mysql_port:-3306}"
                mysql_database="${mysql_database:-waf_db}"
                mysql_user="${mysql_user:-waf_user}"
                
                echo "  主机: ${mysql_host}"
                echo "  端口: ${mysql_port}"
                echo "  数据库: ${mysql_database}"
                echo "  用户名: ${mysql_user}"
                if [ -n "$mysql_password" ] && [ "$mysql_password" != "waf_password" ]; then
                    echo "  密码: ${mysql_password}"
                else
                    echo -e "  密码: ${YELLOW}请查看配置文件${NC}"
                fi
                
                echo ""
                echo "  连接 URL: mysql://${mysql_user}:****@${mysql_host}:${mysql_port}/${mysql_database}"
            else
                echo -e "  ${YELLOW}配置信息: 无法读取配置文件${NC}"
            fi
        fi
        
        # 检查服务状态
        if command -v systemctl &> /dev/null; then
            if systemctl is-active --quiet mysqld 2>/dev/null || systemctl is-active --quiet mysql 2>/dev/null; then
                echo -e "  服务状态: ${GREEN}运行中${NC}"
            else
                echo -e "  服务状态: ${YELLOW}未运行${NC}"
            fi
            if systemctl is-enabled --quiet mysqld 2>/dev/null || systemctl is-enabled --quiet mysql 2>/dev/null; then
                echo -e "  开机自启: ${GREEN}已启用${NC}"
            else
                echo -e "  开机自启: ${YELLOW}未启用${NC}"
            fi
        fi
        echo ""
    fi
    
    # Redis 配置信息
    if command -v redis-cli &> /dev/null || command -v redis-server &> /dev/null; then
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BLUE}Redis 配置信息:${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        local redis_version=""
        if command -v redis-server &> /dev/null; then
            redis_version=$(redis-server --version 2>&1 | head -n 1)
        elif command -v redis-cli &> /dev/null; then
            redis_version=$(redis-cli --version 2>&1 | head -n 1)
        fi
        
        if [ -n "$redis_version" ]; then
            echo "  版本: ${redis_version}"
        fi
        
        # 从 lua/config.lua 读取 Redis 配置
        if [ -f "$CONFIG_FILE" ]; then
            # 提取 Redis 配置块中的值
            local redis_block_start=$(grep -n "^_M\.redis = {" "$CONFIG_FILE" | cut -d: -f1)
            local redis_block_end=$(grep -n "^}" "$CONFIG_FILE" | awk -v start="$redis_block_start" '$1 > start {print $1; exit}')
            
            if [ -n "$redis_block_start" ] && [ -n "$redis_block_end" ]; then
                local redis_host=$(sed -n "${redis_block_start},${redis_block_end}p" "$CONFIG_FILE" | grep -E "^\s*host\s*=" | sed -E "s/.*host\s*=\s*[\"']([^\"']+)[\"'].*/\1/" | head -n 1 | tr -d ' ')
                local redis_port=$(sed -n "${redis_block_start},${redis_block_end}p" "$CONFIG_FILE" | grep -E "^\s*port\s*=" | sed -E "s/.*port\s*=\s*([0-9]+).*/\1/" | head -n 1 | tr -d ' ')
                local redis_password=$(sed -n "${redis_block_start},${redis_block_end}p" "$CONFIG_FILE" | grep -E "^\s*password\s*=" | sed -E "s/.*password\s*=\s*[\"']([^\"']+)[\"'].*/\1/" | head -n 1 | tr -d ' ')
                local redis_db=$(sed -n "${redis_block_start},${redis_block_end}p" "$CONFIG_FILE" | grep -E "^\s*db\s*=" | sed -E "s/.*db\s*=\s*([0-9]+).*/\1/" | head -n 1 | tr -d ' ')
                
                # 检查 password 是否为 nil
                if [ -z "$redis_password" ]; then
                    redis_password=$(sed -n "${redis_block_start},${redis_block_end}p" "$CONFIG_FILE" | grep -E "^\s*password\s*=" | grep -q "nil" && echo "nil" || echo "")
                fi
                
                redis_host="${redis_host:-127.0.0.1}"
                redis_port="${redis_port:-6379}"
                redis_db="${redis_db:-0}"
                
                echo "  主机: ${redis_host}"
                echo "  端口: ${redis_port}"
                echo "  数据库索引: ${redis_db}"
                if [ -n "$redis_password" ] && [ "$redis_password" != "nil" ]; then
                    echo "  密码: ${redis_password}"
                    echo ""
                    echo "  连接 URL: redis://:****@${redis_host}:${redis_port}/${redis_db}"
                else
                    echo "  密码: 未设置"
                    echo ""
                    echo "  连接 URL: redis://${redis_host}:${redis_port}/${redis_db}"
                fi
            else
                echo -e "  ${YELLOW}配置信息: 无法读取配置文件${NC}"
            fi
        fi
        
        # 检查服务状态
        if command -v systemctl &> /dev/null; then
            if systemctl is-active --quiet redis 2>/dev/null || systemctl is-active --quiet redis-server 2>/dev/null; then
                echo -e "  服务状态: ${GREEN}运行中${NC}"
            else
                echo -e "  服务状态: ${YELLOW}未运行${NC}"
            fi
            if systemctl is-enabled --quiet redis 2>/dev/null || systemctl is-enabled --quiet redis-server 2>/dev/null; then
                echo -e "  开机自启: ${GREEN}已启用${NC}"
            else
                echo -e "  开机自启: ${YELLOW}未启用${NC}"
            fi
        fi
        echo ""
    fi
    
    # GeoIP 配置信息
    local geoip_db_path="${SCRIPT_DIR}/lua/geoip/GeoLite2-City.mmdb"
    if [ -f "$geoip_db_path" ]; then
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BLUE}GeoIP 配置信息:${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        local file_size=$(stat -f%z "$geoip_db_path" 2>/dev/null || stat -c%s "$geoip_db_path" 2>/dev/null || echo "0")
        local file_size_mb=$((file_size / 1048576))
        local file_size_human=$(du -h "$geoip_db_path" 2>/dev/null | cut -f1)
        
        echo "  数据库文件: ${geoip_db_path}"
        echo "  文件大小: ${file_size_human} (${file_size_mb} MB)"
        
        # 检查配置文件
        local geoip_config_file="${SCRIPTS_DIR}/.geoip_config"
        if [ -f "$geoip_config_file" ]; then
            echo "  配置文件: ${geoip_config_file}"
            echo -e "  自动更新: ${GREEN}已配置${NC}"
        else
            echo -e "  自动更新: ${YELLOW}未配置${NC}"
        fi
        echo ""
    fi
    
    echo -e "${GREEN}========================================${NC}"
    echo ""
}

# 完整安装
install_all() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}OpenResty WAF 一键安装脚本${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "项目根目录: $SCRIPT_DIR"
    echo ""
    
    # 创建必要的目录
    mkdir -p "$LOGS_DIR"
    echo -e "${GREEN}✓ 已创建日志目录: $LOGS_DIR${NC}"
    echo ""
    
    # 直接调用各个安装脚本，每个脚本内部会询问是否安装
    # 步骤 1: 安装 OpenResty（基础组件，必须先安装）
    install_openresty
    
    # 步骤 2: 部署配置文件（需要 OpenResty）
    deploy_config
    
    # 步骤 3: 安装 MySQL
    install_mysql
    
    # 注意：install_mysql.sh 内部已经包含了：
    # 1. 数据库初始化（执行 SQL 脚本）
    # 2. WAF 配置文件更新（更新 lua/config.lua）
    # 如果安装成功，这些步骤会自动完成
    
    # 步骤 4: 安装 Redis
    install_redis
    
    # 步骤 5: 安装 GeoIP
    install_geoip
    
    # 步骤 6: 系统优化
    optimize_system
    
    # 安装完成
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}安装完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # 显示所有已安装软件的配置信息
    show_installed_configs
    
    echo -e "${BLUE}下一步操作：${NC}"
    echo ""
    echo "1. 测试配置文件:"
    echo "   ${OPENRESTY_PREFIX}/bin/openresty -t"
    echo ""
    echo "2. 启动 OpenResty 服务:"
    echo "   systemctl start openresty"
    echo "   或"
    echo "   ${OPENRESTY_PREFIX}/bin/openresty"
    echo ""
    echo "3. 设置开机自启:"
    echo "   systemctl enable openresty"
    echo ""
    echo "4. 查看日志:"
    echo "   tail -f ${SCRIPT_DIR}/logs/error.log"
    echo "   tail -f ${SCRIPT_DIR}/logs/access.log"
    echo ""
    echo -e "${YELLOW}提示:${NC}"
    echo "  - 配置文件位置: ${CONFIG_FILE}"
    echo "  - 修改配置后无需重新部署，直接 reload 即可"
    echo ""
}

# 主函数
main() {
    # 处理参数
    local action="${1:-}"
    local module="${2:-}"
    
    # 如果没有参数，显示帮助信息
    if [ -z "$action" ]; then
        show_usage
        exit 0
    fi
    
    # 检查 root 权限（除了 help 命令）
    if [ "$action" != "-h" ] && [ "$action" != "--help" ] && [ "$action" != "help" ]; then
        check_root
    fi
    
    # 处理卸载命令
    if [ "$action" = "uninstall" ]; then
        # 直接调用卸载脚本，所有输入逻辑在脚本内部
        case "$module" in
            openresty)
                uninstall_openresty
                ;;
            mysql)
                uninstall_mysql
                ;;
            redis)
                uninstall_redis
                ;;
            geoip)
                uninstall_geoip
                ;;
            deploy)
                uninstall_deploy
                ;;
            dependencies)
                uninstall_dependencies
                ;;
            all|"")
                uninstall_all
                ;;
            *)
                echo -e "${RED}错误: 未知卸载模块 '$module'${NC}"
                echo ""
                show_usage
                exit 1
                ;;
        esac
        return 0
    fi
    
    # 处理安装命令
    if [ "$action" = "install" ]; then
        # 处理 install <module> 格式（按依赖顺序）
        case "$module" in
            openresty)
                install_openresty
                ;;
            opm)
                install_opm
                ;;
            dependencies)
                manage_dependencies
                ;;
            mysql)
                install_mysql
                ;;
            redis)
                install_redis
                ;;
            geoip)
                install_geoip
                ;;
            deploy)
                deploy_config
                ;;
            optimize)
                optimize_system
                ;;
            check)
                check_all
                ;;
            check-deps)
                check_dependencies
                ;;
            update-config)
                update_config
                ;;
            update-geoip)
                update_geoip
                ;;
            all|"")
                install_all
                ;;
            *)
                echo -e "${RED}错误: 未知安装模块 '$module'${NC}"
                echo ""
                show_usage
                exit 1
                ;;
        esac
        return 0
    fi
    
    # 处理其他命令（向后兼容：如果没有 install/uninstall，当作模块名处理）
    case "$action" in
        -h|--help|help)
            show_usage
            ;;
        openresty|opm|mysql|redis|geoip|deploy|optimize|check|dependencies|check-deps|update-config|update-geoip)
            # 向后兼容：直接使用模块名作为安装命令
            echo -e "${YELLOW}提示: 建议使用 'sudo $0 install $action' 格式${NC}"
            echo ""
            case "$action" in
                openresty)
                    install_openresty
                    ;;
                opm)
                    install_opm
                    ;;
                mysql)
                    install_mysql
                    ;;
                redis)
                    install_redis
                    ;;
                geoip)
                    install_geoip
                    ;;
                deploy)
                    deploy_config
                    ;;
                optimize)
                    optimize_system
                    ;;
                check)
                    check_all
                    ;;
                dependencies)
                    manage_dependencies
                    ;;
                check-deps)
                    check_dependencies
                    ;;
                update-config)
                    update_config
                    ;;
                update-geoip)
                    update_geoip
                    ;;
            esac
            ;;
        all)
            # 向后兼容：支持直接使用 all
            echo -e "${YELLOW}提示: 建议使用 'sudo $0 install all' 格式${NC}"
            echo ""
            install_all
            ;;
        *)
            echo -e "${RED}错误: 未知命令 '$action'${NC}"
            echo ""
            echo -e "${YELLOW}提示: 请使用以下格式之一：${NC}"
            echo "  sudo $0                      # 显示帮助信息"
            echo "  sudo $0 install <module>    # 安装模块"
            echo "  sudo $0 install all          # 完整安装（按依赖顺序）"
            echo "  sudo $0 uninstall <module>  # 卸载模块"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
