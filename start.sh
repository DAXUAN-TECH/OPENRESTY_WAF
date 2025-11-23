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
    echo ""
    echo "可用模块:"
    echo "  openresty    - 安装 OpenResty"
    echo "  mysql        - 安装 MySQL"
    echo "  redis        - 安装 Redis"
    echo "  geoip        - 安装 GeoIP 数据库"
    echo "  deploy       - 部署配置文件"
    echo "  optimize     - 系统优化"
    echo "  check        - 项目全面检查"
    echo "  update-config - 更新数据库连接配置"
    echo "  update-geoip - 更新 GeoIP 数据库"
    echo "  all          - 完整安装（默认）"
    echo ""
    echo "示例:"
    echo "  sudo $0              # 完整安装"
    echo "  sudo $0 mysql        # 只安装 MySQL"
    echo "  sudo $0 geoip        # 只安装 GeoIP"
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
    
    if [ -f "${OPENRESTY_PREFIX}/bin/openresty" ]; then
        echo -e "${YELLOW}检测到 OpenResty 已安装${NC}"
        read -p "是否重新安装？[y/N]: " REINSTALL
        if [[ ! "$REINSTALL" =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}跳过 OpenResty 安装${NC}"
            return 0
        fi
    fi
    
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
    
    read -p "MaxMind Account ID: " GEOIP_ACCOUNT_ID
    read -sp "MaxMind License Key: " GEOIP_LICENSE_KEY
    echo ""
    
    if [ -z "$GEOIP_ACCOUNT_ID" ] || [ -z "$GEOIP_LICENSE_KEY" ]; then
        echo -e "${YELLOW}警告: Account ID 或 License Key 为空，跳过 GeoIP 安装${NC}"
        return 0
    fi
    
    if ! bash "${SCRIPTS_DIR}/install_geoip.sh" "$GEOIP_ACCOUNT_ID" "$GEOIP_LICENSE_KEY"; then
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
    
    echo "请选择要更新的配置:"
    echo "1. MySQL 配置"
    echo "2. Redis 配置"
    echo "3. 验证配置文件语法"
    read -p "请选择 [1-3]: " CONFIG_CHOICE
    
    case "$CONFIG_CHOICE" in
        1)
            read -p "MySQL Host [127.0.0.1]: " MYSQL_HOST
            MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
            read -p "MySQL Port [3306]: " MYSQL_PORT
            MYSQL_PORT="${MYSQL_PORT:-3306}"
            read -p "MySQL Database [waf_db]: " MYSQL_DB
            MYSQL_DB="${MYSQL_DB:-waf_db}"
            read -p "MySQL User [waf_user]: " MYSQL_USER
            MYSQL_USER="${MYSQL_USER:-waf_user}"
            read -sp "MySQL Password: " MYSQL_PASS
            echo ""
            
            if ! bash "${SCRIPTS_DIR}/set_lua_database_connect.sh" mysql "$MYSQL_HOST" "$MYSQL_PORT" "$MYSQL_DB" "$MYSQL_USER" "$MYSQL_PASS"; then
                echo -e "${RED}✗ MySQL 配置更新失败${NC}"
                return 1
            fi
            ;;
        2)
            read -p "Redis Host [127.0.0.1]: " REDIS_HOST
            REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
            read -p "Redis Port [6379]: " REDIS_PORT
            REDIS_PORT="${REDIS_PORT:-6379}"
            read -p "Redis DB [0]: " REDIS_DB
            REDIS_DB="${REDIS_DB:-0}"
            read -sp "Redis Password (留空表示无密码): " REDIS_PASS
            echo ""
            
            if ! bash "${SCRIPTS_DIR}/set_lua_database_connect.sh" redis "$REDIS_HOST" "$REDIS_PORT" "$REDIS_DB" "$REDIS_PASS"; then
                echo -e "${RED}✗ Redis 配置更新失败${NC}"
                return 1
            fi
            ;;
        3)
            if ! bash "${SCRIPTS_DIR}/set_lua_database_connect.sh" verify; then
                echo -e "${RED}✗ 配置文件验证失败${NC}"
                return 1
            fi
            ;;
        *)
            echo -e "${RED}错误: 无效的选择${NC}"
            return 1
            ;;
    esac
    
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
    
    # MySQL 配置
    read -p "是否安装 MySQL？[Y/n]: " INSTALL_MYSQL
    INSTALL_MYSQL="${INSTALL_MYSQL:-Y}"
    
    # Redis 配置
    read -p "是否安装 Redis？[y/N]: " INSTALL_REDIS
    INSTALL_REDIS="${INSTALL_REDIS:-N}"
    
    # GeoIP 配置
    read -p "是否安装 GeoIP 数据库？[y/N]: " INSTALL_GEOIP
    INSTALL_GEOIP="${INSTALL_GEOIP:-N}"
    
    # 系统优化
    read -p "是否执行系统优化？[Y/n]: " OPTIMIZE_SYSTEM
    OPTIMIZE_SYSTEM="${OPTIMIZE_SYSTEM:-Y}"
    
    echo ""
    echo -e "${GREEN}✓ 配置信息收集完成${NC}"
    echo ""
    
    # 计算步骤
    CURRENT_STEP=2
    TOTAL_STEPS=3  # OpenResty + Deploy + 其他可选步骤
    [[ "$INSTALL_MYSQL" =~ ^[Yy]$ ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [[ "$INSTALL_REDIS" =~ ^[Yy]$ ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [[ "$INSTALL_GEOIP" =~ ^[Yy]$ ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    [[ "$OPTIMIZE_SYSTEM" =~ ^[Yy]$ ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    
    # 步骤 1: 安装 OpenResty
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}步骤 ${CURRENT_STEP}/${TOTAL_STEPS}: 安装 OpenResty${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    install_openresty
    CURRENT_STEP=$((CURRENT_STEP + 1))
    
    # 步骤 2: 部署配置文件
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}步骤 ${CURRENT_STEP}/${TOTAL_STEPS}: 部署配置文件${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    deploy_config
    CURRENT_STEP=$((CURRENT_STEP + 1))
    
    # 步骤 3: 安装 MySQL
    if [[ "$INSTALL_MYSQL" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}步骤 ${CURRENT_STEP}/${TOTAL_STEPS}: 安装 MySQL${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        install_mysql
        CURRENT_STEP=$((CURRENT_STEP + 1))
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
    local module="${1:-all}"
    
    case "$module" in
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
            echo -e "${RED}错误: 未知模块 '$module'${NC}"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
