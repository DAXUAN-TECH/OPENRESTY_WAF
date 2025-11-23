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
    echo "  sudo $0                    # 完整安装（交互式）"
    echo "  sudo $0 <module>           # 单独安装某个模块"
    echo "  sudo $0 uninstall <module> # 卸载某个模块"
    echo ""
    echo "可用模块（安装）:"
    echo "  openresty    - 安装 OpenResty"
    echo "  mysql        - 安装 MySQL"
    echo "  redis        - 安装 Redis"
    echo "  geoip        - 安装 GeoIP 数据库"
    echo "  deploy       - 部署配置文件"
    echo "  optimize     - 系统优化"
    echo "  check        - 项目全面检查"
    echo "  dependencies - 安装/检查 Lua 模块依赖"
    echo "  update-config - 更新数据库连接配置"
    echo "  update-geoip - 更新 GeoIP 数据库"
    echo "  all          - 完整安装（默认）"
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
    echo "  sudo $0                    # 完整安装"
    echo "  sudo $0 mysql              # 只安装 MySQL"
    echo "  sudo $0 uninstall mysql    # 卸载 MySQL"
    echo "  sudo $0 uninstall all      # 完整卸载"
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
    
    # 收集配置信息
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}步骤 1: 收集配置信息${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # OpenResty 配置
    read -p "是否安装 OpenResty？[Y/n]: " INSTALL_OPENRESTY
    INSTALL_OPENRESTY="${INSTALL_OPENRESTY:-Y}"
    
    # MySQL 配置
    read -p "是否安装 MySQL？[Y/n]: " INSTALL_MYSQL
    INSTALL_MYSQL="${INSTALL_MYSQL:-Y}"
    
    # Redis 配置
    read -p "是否安装 Redis？[Y/n]: " INSTALL_REDIS
    INSTALL_REDIS="${INSTALL_REDIS:-Y}"
    
    # GeoIP 配置
    read -p "是否安装 GeoIP 数据库？[Y/n]: " INSTALL_GEOIP
    INSTALL_GEOIP="${INSTALL_GEOIP:-Y}"
    
    # 系统优化
    read -p "是否执行系统优化？[Y/n]: " OPTIMIZE_SYSTEM
    OPTIMIZE_SYSTEM="${OPTIMIZE_SYSTEM:-Y}"
    
    echo ""
    echo -e "${GREEN}✓ 配置信息收集完成${NC}"
    echo ""
    
    # 计算步骤
    CURRENT_STEP=2
    TOTAL_STEPS=0
    [[ "$INSTALL_OPENRESTY" =~ ^[Yy]$ ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))  # OpenResty
    [[ "$INSTALL_OPENRESTY" =~ ^[Yy]$ ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))  # Deploy（需要 OpenResty）
    [[ "$INSTALL_MYSQL" =~ ^[Yy]$ ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [[ "$INSTALL_REDIS" =~ ^[Yy]$ ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [[ "$INSTALL_GEOIP" =~ ^[Yy]$ ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [[ "$OPTIMIZE_SYSTEM" =~ ^[Yy]$ ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    
    # 步骤 1: 安装 OpenResty
    if [[ "$INSTALL_OPENRESTY" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}步骤 ${CURRENT_STEP}/${TOTAL_STEPS}: 安装 OpenResty${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        install_openresty
        CURRENT_STEP=$((CURRENT_STEP + 1))
        
        # 步骤 2: 部署配置文件（需要 OpenResty）
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}步骤 ${CURRENT_STEP}/${TOTAL_STEPS}: 部署配置文件${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        deploy_config
        CURRENT_STEP=$((CURRENT_STEP + 1))
    else
        echo -e "${YELLOW}跳过 OpenResty 安装，配置文件部署也将跳过${NC}"
        echo ""
    fi
    
    # 步骤 3: 安装 MySQL
    if [[ "$INSTALL_MYSQL" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}步骤 ${CURRENT_STEP}/${TOTAL_STEPS}: 安装 MySQL${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        install_mysql
        CURRENT_STEP=$((CURRENT_STEP + 1))
        
        # 注意：install_mysql.sh 内部已经包含了：
        # 1. 数据库初始化（执行 SQL 脚本）
        # 2. WAF 配置文件更新（更新 lua/config.lua）
        # 如果安装成功，这些步骤会自动完成
    fi
    
    # 步骤 4: 安装 Redis
    if [[ "$INSTALL_REDIS" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}步骤 ${CURRENT_STEP}/${TOTAL_STEPS}: 安装 Redis${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        install_redis
        CURRENT_STEP=$((CURRENT_STEP + 1))
    fi
    
    # 步骤 5: 安装 GeoIP
    if [[ "$INSTALL_GEOIP" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}步骤 ${CURRENT_STEP}/${TOTAL_STEPS}: 安装 GeoIP 数据库${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        install_geoip
        CURRENT_STEP=$((CURRENT_STEP + 1))
    fi
    
    # 步骤 6: 系统优化
    if [[ "$OPTIMIZE_SYSTEM" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}步骤 ${CURRENT_STEP}/${TOTAL_STEPS}: 系统优化${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        optimize_system
    fi
    
    # 安装完成
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}安装完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
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
    # 检查 root 权限
    check_root
    
    # 处理参数
    local action="${1:-all}"
    local module="${2:-}"
    
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
    
    # 处理安装和维护命令
    case "$action" in
        -h|--help|help)
            show_usage
            ;;
        openresty)
            install_openresty
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
            echo -e "${RED}错误: 未知模块 '$action'${NC}"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
