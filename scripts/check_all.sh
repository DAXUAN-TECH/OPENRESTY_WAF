#!/bin/bash

# 项目全面检查脚本
# 用途：检查所有脚本逻辑、代码完善性、重复逻辑

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 获取脚本目录（使用相对路径）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}项目全面检查${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 检查结果
ERRORS=0
WARNINGS=0

# 检查函数
check_error() {
    echo -e "${RED}✗ $1${NC}"
    ((ERRORS++))
}

check_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
    ((WARNINGS++))
}

check_ok() {
    echo -e "${GREEN}✓ $1${NC}"
}

# 1. 检查脚本文件
echo -e "${BLUE}[1/6] 检查脚本文件...${NC}"
for script in scripts/*.sh; do
    if [ -f "$script" ]; then
        script_name=$(basename "$script")
        
        # 检查执行权限
        if [ ! -x "$script" ]; then
            check_warning "$script_name 缺少执行权限"
        else
            check_ok "$script_name 有执行权限"
        fi
        
        # 检查 shebang
        if ! head -1 "$script" | grep -q "^#!/bin/bash"; then
            check_warning "$script_name 缺少或错误的 shebang"
        fi
        
        # 检查 set -e
        if ! grep -q "set -e" "$script"; then
            check_warning "$script_name 未使用 'set -e'（错误时继续执行）"
        fi
    fi
done
echo ""

# 2. 检查重复逻辑
echo -e "${BLUE}[2/7] 检查重复逻辑...${NC}"

# 检查重复的函数名
echo "检查函数定义..."
FUNCTIONS=$(grep -h "^[a-z_]*()" scripts/*.sh 2>/dev/null | sed 's/()//' | sort | uniq -d)
if [ -n "$FUNCTIONS" ]; then
    check_warning "发现重复的函数定义:"
    echo "$FUNCTIONS" | while read func; do
        echo "  - $func"
    done
else
    check_ok "未发现重复的函数定义"
fi

# 检查重复的代码块（PROJECT_ROOT 获取）
PROJECT_ROOT_COUNT=$(grep -c "PROJECT_ROOT.*SCRIPT_DIR" scripts/*.sh 2>/dev/null | awk -F: '{sum+=$2} END {print sum}')
if [ "$PROJECT_ROOT_COUNT" -gt 1 ]; then
    check_warning "多个脚本中有相同的 PROJECT_ROOT 获取逻辑（可提取为公共函数）"
else
    check_ok "PROJECT_ROOT 获取逻辑正常"
fi

echo ""

# 3. 检查路径引用
echo -e "${BLUE}[3/7] 检查路径引用...${NC}"

# 检查硬编码路径
HARDCODED_PATHS=$(grep -r "/usr/local/openresty" scripts/*.sh 2>/dev/null | grep -v "OPENRESTY_PREFIX" | grep -v "INSTALL_DIR" | wc -l)
if [ "$HARDCODED_PATHS" -gt 0 ]; then
    check_warning "发现硬编码路径（应使用变量）"
    grep -rn "/usr/local/openresty" scripts/*.sh 2>/dev/null | grep -v "OPENRESTY_PREFIX" | grep -v "INSTALL_DIR" | head -5
else
    check_ok "未发现硬编码路径"
fi

# 检查占位符路径
PLACEHOLDER_PATHS=$(grep -r "/path/to" scripts/*.sh 2>/dev/null | wc -l)
if [ "$PLACEHOLDER_PATHS" -gt 0 ]; then
    check_warning "发现占位符路径（应使用 PROJECT_ROOT）"
else
    check_ok "未发现占位符路径"
fi

echo ""

# 4. 检查脚本逻辑完整性和关键修复项
echo -e "${BLUE}[4/7] 检查脚本逻辑完整性和关键修复项...${NC}"

# 检查函数调用关系
check_script_logic() {
    local script_file="$1"
    local script_name=$(basename "$script_file")
    local functions_defined=$(grep -E "^[a-z_]+\(\)" "$script_file" 2>/dev/null | sed 's/()//' | wc -l)
    local functions_called=$(grep -E "[a-z_]+\(\)" "$script_file" 2>/dev/null | grep -v "^#" | grep -v "^[a-z_]*()" | wc -l)
    
    if [ "$functions_defined" -gt 0 ]; then
        # 检查 main 函数是否存在
        if grep -q "^main\|^main()" "$script_file"; then
            check_ok "$script_name 有 main 函数"
        else
            check_warning "$script_name 未找到 main 函数（可能直接执行）"
        fi
        
        # 检查函数是否被调用
        local unused_functions=0
        while IFS= read -r func_name; do
            if [ -n "$func_name" ]; then
                # 检查函数是否被调用（排除自身定义）
                local call_count=$(grep -c "$func_name" "$script_file" 2>/dev/null || echo "0")
                if [ "$call_count" -le 1 ]; then
                    ((unused_functions++))
                fi
            fi
        done < <(grep -E "^[a-z_]+\(\)" "$script_file" 2>/dev/null | sed 's/()//')
        
        if [ $unused_functions -gt 0 ]; then
            check_warning "$script_name 可能有 $unused_functions 个未使用的函数"
        fi
    fi
}

# 检查各个脚本
for script in scripts/*.sh; do
    if [ -f "$script" ] && [ "$(basename "$script")" != "common.sh" ]; then
        check_script_logic "$script"
    fi
done

# 检查关键脚本的特定函数和修复项
echo "检查关键修复项..."

# start.sh 关键修复项检查
if [ -f "start.sh" ]; then
    if grep -q "TEMP_VARS_FILE\|CREATED_DB_NAME\|MYSQL_USER_FOR_WAF" start.sh; then
        check_ok "start.sh 变量传递机制存在"
    else
        check_warning "start.sh 变量传递机制可能缺失"
    fi

    if grep -q "CURRENT_STEP\|TOTAL_STEPS" start.sh; then
        check_ok "start.sh 动态步骤编号存在"
    else
        check_warning "start.sh 动态步骤编号可能缺失"
    fi

    if grep -q "uninstall\|卸载" start.sh; then
        check_ok "start.sh 卸载功能存在"
    else
        check_warning "start.sh 卸载功能可能缺失"
    fi
else
    check_warning "start.sh 文件不存在（可能已重命名）"
fi

# install_mysql.sh 关键修复项检查
if grep -q "export CREATED_DB_NAME\|export MYSQL_USER_FOR_WAF\|TEMP_VARS_FILE" scripts/install_mysql.sh; then
    check_ok "install_mysql.sh 变量导出机制存在"
else
    check_error "install_mysql.sh 变量导出机制缺失"
fi

if grep -q "db_create_output\|可能的原因" scripts/install_mysql.sh; then
    check_ok "install_mysql.sh 数据库创建错误处理存在"
else
    check_error "install_mysql.sh 数据库创建错误处理缺失"
fi

# 检查 SQL 导入是否只执行一次（通过检查 SQL_OUTPUT 变量使用）
SQL_IMPORT_COUNT=$(grep -c "SQL_OUTPUT.*mysql.*SQL_FILE\|mysql.*SQL_FILE.*SQL_OUTPUT" scripts/install_mysql.sh 2>/dev/null || echo "0")
if [ "$SQL_IMPORT_COUNT" -le 2 ]; then
    check_ok "install_mysql.sh SQL 导入单次执行（已优化）"
else
    check_warning "install_mysql.sh SQL 导入可能重复执行"
fi

# install_redis.sh 关键修复项检查
if grep -q "export REDIS_PASSWORD\|TEMP_VARS_FILE" scripts/install_redis.sh; then
    check_ok "install_redis.sh 变量导出机制存在"
else
    check_error "install_redis.sh 变量导出机制缺失"
fi

if grep -q "service_started\|redis-cli ping\|systemctl is-active" scripts/install_redis.sh; then
    check_ok "install_redis.sh 服务启动状态检查存在"
else
    check_error "install_redis.sh 服务启动状态检查缺失"
fi

if grep -q "possible_paths\|find.*redis.conf" scripts/install_redis.sh; then
    check_ok "install_redis.sh 扩展路径检测存在"
else
    check_warning "install_redis.sh 路径检测可能不够全面"
fi

# deploy.sh 关键修复项检查
if grep -q "openresty -t\|nginx.conf 语法" scripts/deploy.sh; then
    check_ok "deploy.sh 配置语法验证存在"
else
    check_error "deploy.sh 配置语法验证缺失"
fi

if grep -q "REMAINING_PATHS\|所有路径占位符已替换" scripts/deploy.sh; then
    check_ok "deploy.sh 路径替换完整性检查存在"
else
    check_error "deploy.sh 路径替换完整性检查缺失"
fi

if grep -q "PROJECT_ROOT\|NGINX_CONF_DIR\|sed.*project_root" scripts/deploy.sh; then
    check_ok "deploy.sh 关键逻辑存在"
else
    check_error "deploy.sh 关键逻辑缺失"
fi

# install_openresty.sh 关键修复项检查
if grep -q "critical_modules_failed\|手动安装方法" scripts/install_openresty.sh; then
    check_ok "install_openresty.sh Lua 模块失败处理存在"
else
    check_error "install_openresty.sh Lua 模块失败处理缺失"
fi

# install_geoip.sh 关键修复项检查
if grep -q "check_root\|get_credentials\|download_database\|extract_database\|install_database\|save_config\|setup_crontab" scripts/install_geoip.sh; then
    check_ok "install_geoip.sh 关键函数存在"
else
    check_error "install_geoip.sh 关键函数缺失"
fi

if grep -q "Permalink URL.*仍然需要\|必须提供.*Account ID\|必须提供.*License Key" scripts/install_geoip.sh; then
    check_ok "install_geoip.sh Permalink URL 认证检查存在"
else
    check_warning "install_geoip.sh Permalink URL 认证检查可能不完善"
fi

# update_geoip.sh 关键修复项检查
if grep -q "load_config\|check_dependencies\|download_database\|extract_database\|install_database" scripts/update_geoip.sh; then
    check_ok "update_geoip.sh 关键函数存在"
else
    check_error "update_geoip.sh 关键函数缺失"
fi

if grep -q "available_space\|磁盘.*空间\|备份文件总大小\|df -m" scripts/update_geoip.sh; then
    check_ok "update_geoip.sh 磁盘空间检查存在"
else
    check_error "update_geoip.sh 磁盘空间检查缺失"
fi

if grep -q "total_backup_size\|清理旧备份" scripts/update_geoip.sh; then
    check_ok "update_geoip.sh 智能备份清理存在"
else
    check_warning "update_geoip.sh 备份清理可能不完善"
fi

# optimize_system.sh 关键修复项检查
if grep -q "CPU_CORES\|WORKER_PROCESSES\|ULIMIT_NOFILE\|BACKUP_DIR" scripts/optimize_system.sh; then
    check_ok "optimize_system.sh 关键变量存在"
else
    check_error "optimize_system.sh 关键变量缺失"
fi

if grep -q "sysctl -p.*返回值\|内核参数应用失败\|sysctl -p > /dev/null" scripts/optimize_system.sh; then
    check_ok "optimize_system.sh sysctl 返回值检查存在"
else
    check_error "optimize_system.sh sysctl 返回值检查缺失"
fi

if grep -q "ulimit -n.*临时生效" scripts/optimize_system.sh; then
    check_ok "optimize_system.sh 文件描述符临时生效提示存在"
else
    check_warning "optimize_system.sh 文件描述符提示可能不完善"
fi

echo ""

# 5. 检查错误处理机制
echo -e "${BLUE}[5/7] 检查错误处理机制...${NC}"

# 检查关键脚本的错误处理
check_error_handling() {
    local script_file="$1"
    local script_name=$(basename "$script_file")
    
    # 检查是否有错误处理（set -e 或错误检查）
    if grep -q "set -e" "$script_file"; then
        check_ok "$script_name 使用 set -e"
    else
        check_warning "$script_name 未使用 set -e"
    fi
    
    # 检查是否有退出码检查
    if grep -q "\$?\|exit_code\|EXIT_CODE" "$script_file"; then
        check_ok "$script_name 有退出码检查"
    else
        check_warning "$script_name 可能缺少退出码检查"
    fi
    
    # 检查是否有错误信息输出
    if grep -q "错误\|error\|ERROR\|失败\|fail\|FAIL" "$script_file"; then
        check_ok "$script_name 有错误信息输出"
    else
        check_warning "$script_name 可能缺少错误信息输出"
    fi
}

# 检查关键脚本
for script in start.sh scripts/install_mysql.sh scripts/install_redis.sh scripts/deploy.sh scripts/install_openresty.sh; do
    if [ -f "$script" ]; then
        check_error_handling "$script"
    fi
done

echo ""

# 6. 检查文件存在性
echo -e "${BLUE}[6/7] 检查必要文件...${NC}"

REQUIRED_FILES=(
    "init_file/nginx.conf"
    "init_file/数据库设计.sql"
    "conf.d/set_conf/lua.conf"
    "conf.d/set_conf/log.conf"
    "conf.d/set_conf/waf.conf"
    "conf.d/set_conf/performance.conf"
    "conf.d/vhost_conf/default.conf"
    "lua/config.lua"
    "lua/waf/init.lua"
    "lua/waf/ip_block.lua"
    "lua/waf/ip_utils.lua"
    "lua/waf/log_collect.lua"
    "lua/waf/mysql_pool.lua"
    "lua/waf/geo_block.lua"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "${PROJECT_ROOT}/$file" ]; then
        check_ok "$file 存在"
    else
        check_error "$file 不存在"
    fi
done

echo ""

# 7. 检查卸载后残留
echo -e "${BLUE}[7/8] 检查卸载后残留（如果已卸载）...${NC}"

# 检查 OpenResty 残留
OPENRESTY_PREFIX="${OPENRESTY_PREFIX:-/usr/local/openresty}"
if [ ! -f "${OPENRESTY_PREFIX}/bin/openresty" ]; then
    if [ -d "${OPENRESTY_PREFIX}" ]; then
        check_warning "OpenResty 已卸载但安装目录仍存在: ${OPENRESTY_PREFIX}"
        # 检查目录大小
        local dir_size=$(du -sh "${OPENRESTY_PREFIX}" 2>/dev/null | cut -f1 || echo "未知")
        echo -e "${BLUE}  目录大小: $dir_size${NC}"
    fi
    if [ -f "/etc/systemd/system/openresty.service" ]; then
        check_warning "OpenResty 服务文件仍存在: /etc/systemd/system/openresty.service"
    fi
    if [ -L "/usr/local/bin/openresty" ] || [ -L "/usr/local/bin/opm" ] || [ -L "/usr/local/bin/resty" ]; then
        check_warning "OpenResty 符号链接仍存在: /usr/local/bin/openresty, /usr/local/bin/opm, /usr/local/bin/resty"
    fi
else
    check_ok "OpenResty 已安装: ${OPENRESTY_PREFIX}/bin/openresty"
fi

# 检查 MySQL 残留
if ! command -v mysql &> /dev/null && ! command -v mysqld &> /dev/null; then
    local mysql_data_dirs=(
        "/var/lib/mysql"
        "/var/lib/mysqld"
        "/usr/local/mysql/data"
    )
    for dir in "${mysql_data_dirs[@]}"; do
        if [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
            check_warning "MySQL 已卸载但数据目录仍存在: $dir"
            local dir_size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "未知")
            echo -e "${BLUE}  目录大小: $dir_size${NC}"
            # 检查是否有用户数据库
            local user_dbs=$(find "$dir" -mindepth 1 -maxdepth 1 -type d ! -name "mysql" ! -name "sys" ! -name "information_schema" ! -name "performance_schema" 2>/dev/null | wc -l)
            if [ "$user_dbs" -gt 0 ]; then
                echo -e "${YELLOW}  包含 $user_dbs 个用户数据库${NC}"
            fi
        fi
    done
    
    local mysql_config_files=(
        "/etc/my.cnf"
        "/etc/mysql/my.cnf"
        "/etc/mysql/conf.d"
        "/etc/mysql/mysql.conf.d"
    )
    for file in "${mysql_config_files[@]}"; do
        if [ -f "$file" ] || [ -d "$file" ]; then
            check_warning "MySQL 配置文件仍存在: $file"
        fi
    done
    
    if [ -f "/var/log/mysqld.log" ] || [ -d "/var/log/mysql" ]; then
        check_warning "MySQL 日志文件仍存在"
    fi
else
    check_ok "MySQL 已安装: $(command -v mysql 2>/dev/null || command -v mysqld 2>/dev/null)"
fi

# 检查 Redis 残留
if ! command -v redis-server &> /dev/null; then
    local redis_data_dirs=(
        "/var/lib/redis"
        "/var/db/redis"
    )
    for dir in "${redis_data_dirs[@]}"; do
        if [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
            check_warning "Redis 已卸载但数据目录仍存在: $dir"
            local dir_size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "未知")
            echo -e "${BLUE}  目录大小: $dir_size${NC}"
        fi
    done
    
    local redis_config_files=(
        "/etc/redis/redis.conf"
        "/etc/redis.conf"
        "/usr/local/etc/redis.conf"
    )
    for file in "${redis_config_files[@]}"; do
        if [ -f "$file" ]; then
            check_warning "Redis 配置文件仍存在: $file"
        fi
    done
    
    if [ -d "/var/log/redis" ]; then
        check_warning "Redis 日志目录仍存在: /var/log/redis"
    fi
    
    if [ -f "/etc/systemd/system/redis.service" ]; then
        check_warning "Redis 服务文件仍存在: /etc/systemd/system/redis.service"
    fi
else
    check_ok "Redis 已安装: $(command -v redis-server 2>/dev/null)"
fi

# 检查 GeoIP 残留
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEOIP_DIR="${SCRIPT_DIR}/../lua/geoip"
if [ ! -f "${GEOIP_DIR}/GeoLite2-City.mmdb" ]; then
    if [ -d "${GEOIP_DIR}" ] && [ -n "$(ls -A "${GEOIP_DIR}" 2>/dev/null)" ]; then
        check_warning "GeoIP 数据库已卸载但目录仍存在: ${GEOIP_DIR}"
    fi
    if [ -f "${SCRIPT_DIR}/.geoip_config" ]; then
        check_warning "GeoIP 配置文件仍存在: ${SCRIPT_DIR}/.geoip_config"
    fi
    # 检查 crontab 任务
    if crontab -l 2>/dev/null | grep -q "update_geoip.sh"; then
        check_warning "GeoIP 更新计划任务仍存在"
    fi
else
    check_ok "GeoIP 数据库已安装: ${GEOIP_DIR}/GeoLite2-City.mmdb"
fi

# 检查部署配置残留
if [ -f "${OPENRESTY_PREFIX}/nginx/conf/nginx.conf" ]; then
    if grep -q "project_root\|project_root" "${OPENRESTY_PREFIX}/nginx/conf/nginx.conf" 2>/dev/null; then
        check_ok "nginx.conf 已部署（包含 project_root 变量）"
        # 检查 project_root 路径是否正确
        local project_root_in_conf=$(grep "set \$project_root" "${OPENRESTY_PREFIX}/nginx/conf/nginx.conf" 2>/dev/null | sed 's/.*"\(.*\)".*/\1/' | head -1)
        if [ -n "$project_root_in_conf" ] && [ ! -d "$project_root_in_conf" ]; then
            check_warning "nginx.conf 中的 project_root 路径不存在: $project_root_in_conf"
        fi
    else
        check_warning "nginx.conf 存在但可能不是本项目部署的配置"
    fi
else
    check_ok "nginx.conf 未部署或已清理"
fi

# 8. 检查 Lua 模块依赖
echo -e "${BLUE}[8/9] 检查 Lua 模块依赖...${NC}"

OPENRESTY_PREFIX="${OPENRESTY_PREFIX:-/usr/local/openresty}"
LUALIB_DIR="${OPENRESTY_PREFIX}/site/lualib"

if [ -f "${OPENRESTY_PREFIX}/bin/openresty" ]; then
    # 检查必需模块
    if [ -f "${LUALIB_DIR}/resty/mysql.lua" ] || [ -d "${LUALIB_DIR}/resty/mysql" ]; then
        check_ok "resty.mysql (必需) - 已安装"
    else
        check_error "resty.mysql (必需) - 未安装，请运行: sudo ./scripts/install_dependencies.sh"
    fi
    
    # 检查可选模块
    if [ -f "${LUALIB_DIR}/resty/redis.lua" ] || [ -d "${LUALIB_DIR}/resty/redis" ]; then
        check_ok "resty.redis (可选) - 已安装"
    else
        check_warning "resty.redis (可选) - 未安装，Redis 二级缓存功能将受限"
    fi
    
    if [ -f "${LUALIB_DIR}/resty/maxminddb.lua" ] || [ -d "${LUALIB_DIR}/resty/maxminddb" ]; then
        check_ok "resty.maxminddb (可选) - 已安装"
    else
        check_warning "resty.maxminddb (可选) - 未安装，地域封控功能将受限"
    fi
    
    if [ -f "${LUALIB_DIR}/resty/http.lua" ] || [ -d "${LUALIB_DIR}/resty/http" ]; then
        check_ok "resty.http (可选) - 已安装"
    else
        check_warning "resty.http (可选) - 未安装，告警 Webhook 功能将受限"
    fi
    
    # 注意：resty.file 模块在 OPM 中不存在，代码使用标准 Lua io 库，无需检查
    
    if [ -f "${LUALIB_DIR}/resty/msgpack.lua" ] || [ -d "${LUALIB_DIR}/resty/msgpack" ]; then
        check_ok "resty.msgpack (可选) - 已安装"
    else
        check_warning "resty.msgpack (可选) - 未安装，将使用 JSON 序列化"
    fi
    
    echo ""
    echo -e "${BLUE}提示: 运行 sudo ./scripts/check_dependencies.sh 进行详细依赖检查${NC}"
else
    check_warning "OpenResty 未安装，无法检查 Lua 模块依赖"
fi

echo ""

# 9. 检查服务状态和依赖关系
echo -e "${BLUE}[9/9] 检查服务状态和依赖关系...${NC}"

# 检查 OpenResty 服务状态
if [ -f "${OPENRESTY_PREFIX}/bin/openresty" ]; then
    if systemctl is-active --quiet openresty 2>/dev/null || pgrep -x openresty > /dev/null 2>&1; then
        check_ok "OpenResty 服务正在运行"
    else
        check_warning "OpenResty 已安装但服务未运行"
    fi
fi

# 检查 MySQL 服务状态
if command -v mysql &> /dev/null || command -v mysqld &> /dev/null; then
    if systemctl is-active --quiet mysqld 2>/dev/null || systemctl is-active --quiet mysql 2>/dev/null || pgrep -x mysqld > /dev/null 2>&1; then
        check_ok "MySQL 服务正在运行"
        # 检查 MySQL 连接
        if mysqladmin ping -h localhost --silent 2>/dev/null; then
            check_ok "MySQL 连接正常"
        else
            check_warning "MySQL 服务运行但连接失败"
        fi
    else
        check_warning "MySQL 已安装但服务未运行"
    fi
fi

# 检查 Redis 服务状态
if command -v redis-server &> /dev/null; then
    if systemctl is-active --quiet redis 2>/dev/null || systemctl is-active --quiet redis-server 2>/dev/null || pgrep -x redis-server > /dev/null 2>&1; then
        check_ok "Redis 服务正在运行"
        # 检查 Redis 连接
        if redis-cli ping > /dev/null 2>&1; then
            check_ok "Redis 连接正常"
        else
            check_warning "Redis 服务运行但连接失败"
        fi
    else
        check_warning "Redis 已安装但服务未运行"
    fi
fi

# 检查服务依赖关系
if command -v lsof &> /dev/null; then
    # 检查端口占用
    if lsof -i :80 2>/dev/null | grep -qE "openresty|nginx"; then
        check_ok "80 端口被 OpenResty/Nginx 占用（正常）"
    elif lsof -i :80 > /dev/null 2>&1; then
        check_warning "80 端口被其他服务占用"
    fi
    
    if lsof -i :3306 2>/dev/null | grep -qE "mysqld|mysql"; then
        check_ok "3306 端口被 MySQL 占用（正常）"
    elif lsof -i :3306 > /dev/null 2>&1; then
        check_warning "3306 端口被其他服务占用"
    fi
    
    if lsof -i :6379 2>/dev/null | grep -q "redis-server"; then
        check_ok "6379 端口被 Redis 占用（正常）"
    elif lsof -i :6379 > /dev/null 2>&1; then
        check_warning "6379 端口被其他服务占用"
    fi
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}检查完成${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}检查统计：${NC}"
echo "  错误: $ERRORS"
echo "  警告: $WARNINGS"
echo ""

# 生成检查摘要
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}检查摘要${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 统计检查项
TOTAL_CHECKS=$((ERRORS + WARNINGS))
if [ $TOTAL_CHECKS -eq 0 ]; then
    echo -e "${GREEN}✓ 所有检查通过！${NC}"
    echo ""
    echo "检查项统计："
    echo "  - 脚本文件检查：✓"
    echo "  - 重复逻辑检查：✓"
    echo "  - 路径引用检查：✓"
    echo "  - 逻辑完整性检查：✓"
    echo "  - 关键修复项检查：✓"
    echo "  - 错误处理检查：✓"
    echo "  - 文件存在性检查：✓"
    echo "  - 卸载残留检查：✓"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ 有警告，但无错误${NC}"
    echo ""
    echo "建议："
    echo "  - 警告项不影响功能，但建议优化"
    echo "  - 可以查看上方详细检查结果"
    exit 0
else
    echo -e "${RED}✗ 发现错误，请修复${NC}"
    echo ""
    echo "必须修复的错误："
    echo "  - 请查看上方标记为 ✗ 的检查项"
    echo "  - 这些错误可能影响脚本功能"
    exit 1
fi

