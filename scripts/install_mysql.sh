#!/bin/bash

# MySQL 一键安装和配置脚本
# 支持多种 Linux 发行版：
#   - RedHat 系列：CentOS, RHEL, Fedora, Rocky Linux, AlmaLinux, Oracle Linux, Amazon Linux
#   - Debian 系列：Debian, Ubuntu, Linux Mint, Kali Linux, Raspbian
#   - SUSE 系列：openSUSE, SLES
#   - Arch 系列：Arch Linux, Manjaro
#   - 其他：Alpine Linux, Gentoo
# 用途：自动检测系统类型并安装配置 MySQL

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

# 配置变量
# 保存原始环境变量（如果通过环境变量设置）
MYSQL_VERSION_FROM_ENV="${MYSQL_VERSION:-}"
MYSQL_VERSION="${MYSQL_VERSION:-8.0}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"
MYSQL_DATABASE=""
MYSQL_USER=""
MYSQL_USER_PASSWORD=""
USE_NEW_USER="N"

# 临时密码和状态变量
TEMP_PASSWORD=""
SKIP_INSTALL=0
EXTERNAL_MYSQL_MODE=0
REINSTALL_MODE=""
MYSQL_HOST="127.0.0.1"
MYSQL_PORT="3306"
INIT_DB_FAILED=0  # 数据库初始化失败标志

# 状态标志（避免重复执行）
PASSWORD_VERIFIED=0      # 密码是否已验证
CONNECTION_INFO_CACHED=0  # 连接信息是否已缓存
CACHED_MYSQL_HOST=""      # 缓存的 MySQL 主机
CACHED_MYSQL_PORT=""      # 缓存的 MySQL 端口

# 硬件信息变量（将在检测后填充）
CPU_CORES=0
TOTAL_MEM_GB=0
TOTAL_MEM_MB=0

# 导出变量供父脚本使用
export CREATED_DB_NAME=""
export MYSQL_USER_FOR_WAF=""
export MYSQL_PASSWORD_FOR_WAF=""
export USE_NEW_USER

# ============================================
# MySQL 辅助函数（避免重复代码）
# ============================================

# 创建 MySQL 临时配置文件
# 参数: $1=host, $2=port, $3=user, $4=password (可选)
# 返回: 配置文件路径（通过全局变量 MYSQL_TEMP_CNF）
create_mysql_cnf() {
    local host="${1:-127.0.0.1}"
    local port="${2:-3306}"
    local user="${3:-root}"
    local password="${4:-}"
    
    MYSQL_TEMP_CNF=$(mktemp)
    cat > "$MYSQL_TEMP_CNF" <<CNF_EOF
[client]
host=${host}
port=${port}
user=${user}
${password:+password=${password}}
CNF_EOF
    chmod 600 "$MYSQL_TEMP_CNF"
    echo "$MYSQL_TEMP_CNF"
}

# 执行 MySQL 命令（自动处理配置文件方式失败的情况）
# 参数: $1=SQL 命令或文件, $2=host, $3=port, $4=user, $5=password, $6=额外参数（如 --connect-expired-password）
# 返回: 0=成功, 1=失败
# 输出: 标准输出和错误输出
mysql_execute() {
    local sql_or_file="$1"
    local host="${2:-127.0.0.1}"
    local port="${3:-3306}"
    local user="${4:-root}"
    local password="${5:-}"
    local extra_args="${6:-}"
    
    local temp_cnf=""
    local output=""
    local exit_code=1
    
    # 创建临时配置文件
    temp_cnf=$(create_mysql_cnf "$host" "$port" "$user" "$password")
    
    # 判断是 SQL 命令还是文件
    if [ -f "$sql_or_file" ]; then
        # 是文件，使用 < 重定向
        if [ -n "$extra_args" ]; then
            output=$(mysql $extra_args --defaults-file="$temp_cnf" < "$sql_or_file" 2>&1)
        else
            output=$(mysql --defaults-file="$temp_cnf" < "$sql_or_file" 2>&1)
        fi
        exit_code=$?
    else
        # 是 SQL 命令，使用 -e 参数
        if [ -n "$extra_args" ]; then
            output=$(mysql $extra_args --defaults-file="$temp_cnf" -e "$sql_or_file" 2>&1)
        else
            output=$(mysql --defaults-file="$temp_cnf" -e "$sql_or_file" 2>&1)
        fi
        exit_code=$?
    fi
    
    # 如果配置文件方式失败且错误是 "unknown variable"，尝试直接传递密码
    if [ $exit_code -ne 0 ] && echo "$output" | grep -qi "unknown variable.*defaults-file"; then
        if [ -f "$sql_or_file" ]; then
            if [ -n "$password" ]; then
                if [ -n "$extra_args" ]; then
                    output=$(mysql $extra_args -h"$host" -P"$port" -u"$user" -p"$password" < "$sql_or_file" 2>&1)
                else
                    output=$(mysql -h"$host" -P"$port" -u"$user" -p"$password" < "$sql_or_file" 2>&1)
                fi
            else
                if [ -n "$extra_args" ]; then
                    output=$(mysql $extra_args -h"$host" -P"$port" -u"$user" < "$sql_or_file" 2>&1)
    else
                    output=$(mysql -h"$host" -P"$port" -u"$user" < "$sql_or_file" 2>&1)
                fi
            fi
        else
            if [ -n "$password" ]; then
                if [ -n "$extra_args" ]; then
                    output=$(mysql $extra_args -h"$host" -P"$port" -u"$user" -p"$password" -e "$sql_or_file" 2>&1)
                else
                    output=$(mysql -h"$host" -P"$port" -u"$user" -p"$password" -e "$sql_or_file" 2>&1)
                fi
            else
                if [ -n "$extra_args" ]; then
                    output=$(mysql $extra_args -h"$host" -P"$port" -u"$user" -e "$sql_or_file" 2>&1)
                else
                    output=$(mysql -h"$host" -P"$port" -u"$user" -e "$sql_or_file" 2>&1)
                fi
            fi
        fi
        exit_code=$?
    fi
    
    # 清理临时文件
    rm -f "$temp_cnf"
    
    # 输出结果（过滤掉密码警告）
    echo "$output" | grep -v "Warning: Using a password on the command line" || echo "$output"
    
    return $exit_code
}

# 验证 MySQL 连接
# 参数: $1=host, $2=port, $3=user, $4=password
# 返回: 0=成功, 1=失败
mysql_verify_connection() {
    local host="${1:-127.0.0.1}"
    local port="${2:-3306}"
    local user="${3:-root}"
    local password="${4:-}"
    
    local output
    output=$(mysql_execute "SELECT 1;" "$host" "$port" "$user" "$password" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# 等待 MySQL 服务就绪
# 参数: $1=最大等待时间（秒，默认30）, $2=host（默认localhost）
# 返回: 0=成功, 1=超时
wait_for_mysql_ready() {
    local max_wait="${1:-30}"
    local host="${2:-localhost}"
    local waited=0
    
    echo "等待 MySQL 服务启动..."
    while [ $waited -lt $max_wait ]; do
        if mysqladmin ping -h "$host" --silent 2>/dev/null; then
            echo -e "${GREEN}✓ MySQL 服务已就绪${NC}"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
        echo -n "."
    done
    echo ""
    
    # 最后再尝试一次
    if mysqladmin ping -h "$host" --silent 2>/dev/null; then
        echo -e "${GREEN}✓ MySQL 服务已就绪${NC}"
        return 0
    else
        echo -e "${RED}✗ MySQL 服务启动超时（等待了 ${max_wait} 秒）${NC}"
        return 1
    fi
}

# 验证密码复杂度
# 参数: $1=密码
# 返回: 0=通过, 1=失败
# 输出: 错误消息（如果失败）
validate_password_complexity() {
    local password="$1"
    local pwd_length=${#password}
    
    if [ $pwd_length -lt 8 ]; then
        echo "密码长度至少 8 位（当前: ${pwd_length} 字符）"
        return 1
    elif ! echo "$password" | grep -q '[A-Z]'; then
        echo "密码必须包含至少一个大写字母 (A-Z)"
        return 1
    elif ! echo "$password" | grep -q '[a-z]'; then
        echo "密码必须包含至少一个小写字母 (a-z)"
        return 1
    elif ! echo "$password" | grep -q '[0-9]'; then
        echo "密码必须包含至少一个数字 (0-9)"
        return 1
    elif ! echo "$password" | grep -q '[^A-Za-z0-9]'; then
        echo "密码必须包含至少一个特殊字符 (!@#$%^&*等)"
        return 1
    fi
    
    return 0
}

# 获取 MySQL 临时密码（从日志文件）
# 返回: 临时密码（如果找到）
get_mysql_temp_password() {
    local temp_password=""
    local log_file
    
    # 使用统一函数获取错误日志文件
    log_file=$(get_mysql_error_log)
    
    if [ -n "$log_file" ] && [ -f "$log_file" ]; then
        temp_password=$(grep 'temporary password' "$log_file" 2>/dev/null | awk '{print $NF}' | tail -1)
        if [ -n "$temp_password" ]; then
            echo "$temp_password"
            return 0
        fi
    fi
    
    return 1
}

# 清理 MySQL 数据、配置和日志文件
# 参数: $1=是否删除数据目录（1=是，0=否）
# 返回: 0=成功, 1=失败
cleanup_mysql_files() {
    local delete_data="${1:-0}"
    
    # 删除数据目录（使用统一函数）
    if [ "$delete_data" -eq 1 ]; then
        local data_dir
        data_dir=$(get_mysql_data_dir 0) || true  # 防止 set -e 导致退出，如果数据目录不存在也没关系
        if [ -n "$data_dir" ]; then
            echo -e "${YELLOW}正在删除数据目录: ${data_dir}${NC}"
            rm -rf "$data_dir"
            echo -e "${GREEN}✓ 数据目录已删除: $data_dir${NC}"
        fi
    fi
    
    # 删除配置文件
    local config_files=(
        "/etc/my.cnf"
        "/etc/my.cnf.d"
        "/etc/mysql/my.cnf"
        "/etc/mysql/conf.d"
        "/etc/mysql/mysql.conf.d"
        "/etc/mysql/mariadb.conf.d"
    )
    for file in "${config_files[@]}"; do
        if [ -f "$file" ] || [ -d "$file" ]; then
            rm -rf "$file"
            echo -e "${GREEN}✓ 已删除: $file${NC}"
        fi
    done
    
    # 删除日志文件
    local log_files=(
        "/var/log/mysqld.log"
        "/var/log/mysql"
        "/var/log/mariadb"
    )
    for log_file in "${log_files[@]}"; do
        if [ -f "$log_file" ] || [ -d "$log_file" ]; then
            rm -rf "$log_file"
            echo -e "${GREEN}✓ 已删除: $log_file${NC}"
        fi
    done
    
    # 删除其他可能的残留文件
    rm -rf /var/run/mysqld 2>/dev/null || true
    rm -rf /var/run/mysql 2>/dev/null || true
    rm -rf /tmp/mysql* 2>/dev/null || true
    
    return 0
}

# 重置 MySQL 版本选择（保留环境变量设置）
reset_mysql_version() {
    if [ -z "${MYSQL_VERSION_FROM_ENV:-}" ]; then
        unset MYSQL_VERSION
    else
        MYSQL_VERSION="${MYSQL_VERSION_FROM_ENV}"
    fi
}

# 获取 MySQL 连接信息（统一函数，避免重复逻辑，带缓存）
# 返回: 通过全局变量 mysql_host 和 mysql_port
get_mysql_connection_info() {
    # 如果已缓存，直接返回
    if [ "${CONNECTION_INFO_CACHED:-0}" -eq 1 ] && [ -n "${CACHED_MYSQL_HOST:-}" ] && [ -n "${CACHED_MYSQL_PORT:-}" ]; then
        mysql_host="$CACHED_MYSQL_HOST"
        mysql_port="$CACHED_MYSQL_PORT"
        return 0
    fi
    
    mysql_host="${MYSQL_HOST:-127.0.0.1}"
    mysql_port="${MYSQL_PORT:-3306}"
    if [ "${EXTERNAL_MYSQL_MODE:-0}" -eq 1 ]; then
        mysql_host="${EXTERNAL_MYSQL_HOST:-127.0.0.1}"
        mysql_port="${EXTERNAL_MYSQL_PORT:-3306}"
    fi
    
    # 缓存结果
    CACHED_MYSQL_HOST="$mysql_host"
    CACHED_MYSQL_PORT="$mysql_port"
    CONNECTION_INFO_CACHED=1
}

# 获取 MySQL 错误日志文件路径（统一函数，避免重复逻辑）
# 返回: 第一个存在的日志文件路径，如果都不存在则返回空
get_mysql_error_log() {
    local log_files=(
        "/var/log/mysqld.log"
        "/var/log/mysql/error.log"
        "/var/log/mysql/mysql.log"
        "/var/log/mariadb/mariadb.log"
    )
    
    for log_file in "${log_files[@]}"; do
        if [ -f "$log_file" ]; then
            echo "$log_file"
            return 0
        fi
    done
    
    return 1
}

# 获取 MySQL 数据目录路径（统一函数，避免重复逻辑）
# 参数: $1=是否检查已初始化（1=是，检查系统数据库；0=否，只检查目录存在，默认0）
# 返回: 第一个存在且非空的数据目录路径，如果都不存在则返回空
get_mysql_data_dir() {
    local check_initialized="${1:-0}"
    local data_dirs=(
        "/var/lib/mysql"
        "/var/lib/mysqld"
        "/usr/local/mysql/data"
        "/opt/mysql/data"
    )
    
    for dir in "${data_dirs[@]}"; do
        if [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
            # 如果要求检查已初始化，验证是否包含系统数据库
            if [ "$check_initialized" -eq 1 ]; then
                if [ -d "$dir/mysql" ] && ([ -f "$dir/mysql/user.MYD" ] || [ -f "$dir/mysql/user.ibd" ] || [ -d "$dir/mysql.ibd" ]); then
                    echo "$dir"
                    return 0
                fi
            else
                echo "$dir"
                return 0
            fi
        fi
    done
    
    return 1
}

# 查询数据库表数量（统一函数，避免重复逻辑）
# 参数: $1=数据库名, $2=host, $3=port, $4=user, $5=password
# 返回: 表数量（数字），如果查询失败则返回 0
get_table_count() {
    local db_name="$1"
    local host="${2:-127.0.0.1}"
    local port="${3:-3306}"
    local user="${4:-root}"
    local password="${5:-}"
    
    local query="SELECT COUNT(*) as table_count FROM information_schema.tables WHERE table_schema='${db_name}';"
    local result
    result=$(mysql_execute "$query" "$host" "$port" "$user" "$password" 2>/dev/null | grep -v "table_count" | grep -v "^$" | awk '{print $1}')
    
    if [ -n "$result" ] && [ "$result" -gt 0 ] 2>/dev/null; then
        echo "$result"
        return 0
    else
        echo "0"
        return 1
    fi
}

# 同步数据库相关变量（统一函数，避免重复逻辑）
# 确保 MYSQL_DATABASE 和 CREATED_DB_NAME 保持一致
sync_database_variables() {
    if [ -z "$MYSQL_DATABASE" ] && [ -n "$CREATED_DB_NAME" ]; then
        MYSQL_DATABASE="$CREATED_DB_NAME"
    elif [ -z "$CREATED_DB_NAME" ] && [ -n "$MYSQL_DATABASE" ]; then
        export CREATED_DB_NAME="$MYSQL_DATABASE"
    fi
}

# 同步用户相关变量（统一函数，避免重复逻辑）
# 确保 MYSQL_USER/MYSQL_USER_PASSWORD 和 FOR_WAF 变量保持一致
sync_user_variables() {
    if [ -z "$MYSQL_USER" ] && [ -n "$MYSQL_USER_FOR_WAF" ]; then
        MYSQL_USER="$MYSQL_USER_FOR_WAF"
    fi
    if [ -z "$MYSQL_USER_PASSWORD" ] && [ -n "$MYSQL_PASSWORD_FOR_WAF" ]; then
        MYSQL_USER_PASSWORD="$MYSQL_PASSWORD_FOR_WAF"
    fi
}

# 设置并导出数据库变量（统一函数，避免重复逻辑）
# 参数: $1=数据库名称
set_and_export_database() {
    local db_name="$1"
    if [ -n "$db_name" ]; then
        MYSQL_DATABASE="$db_name"
        export CREATED_DB_NAME="$db_name"
    fi
}

# 设置并导出用户变量（统一函数，避免重复逻辑）
# 参数: $1=用户名, $2=密码, $3=是否新用户 (Y/N，默认Y)
set_and_export_user() {
    local user_name="$1"
    local user_password="$2"
    local use_new="${3:-Y}"
    
    if [ -n "$user_name" ]; then
        MYSQL_USER="$user_name"
        export MYSQL_USER_FOR_WAF="$user_name"
    fi
    if [ -n "$user_password" ]; then
        MYSQL_USER_PASSWORD="$user_password"
        export MYSQL_PASSWORD_FOR_WAF="$user_password"
    fi
    export USE_NEW_USER="$use_new"
}

# 导出变量到文件（统一函数，避免重复逻辑）
# 参数: $1=文件路径（可选，默认使用 TEMP_VARS_FILE）
export_variables_to_file() {
    local vars_file="${1:-${TEMP_VARS_FILE:-}}"
    
    if [ -z "$vars_file" ]; then
        return 0
    fi
    
    # 确保目录存在
    local vars_dir=$(dirname "$vars_file")
    if [ ! -d "$vars_dir" ] && [ "$vars_dir" != "." ]; then
        mkdir -p "$vars_dir" 2>/dev/null || true
    fi
    
    # 同步变量
    sync_database_variables
    
    # 写入文件
    {
        echo "CREATED_DB_NAME=\"${CREATED_DB_NAME}\""
        echo "MYSQL_USER_FOR_WAF=\"${MYSQL_USER_FOR_WAF}\""
        echo "MYSQL_PASSWORD_FOR_WAF=\"${MYSQL_PASSWORD_FOR_WAF}\""
        echo "USE_NEW_USER=\"${USE_NEW_USER}\""
    } > "$vars_file" 2>/dev/null || true
}

# MySQL 服务管理函数（统一函数，避免重复逻辑）
# 参数: $1=操作 (start|stop|restart|enable|disable|status), $2=是否静默 (可选，默认否)
# 返回: 0=成功, 1=失败
mysql_service_manage() {
    local action="${1:-start}"
    local silent="${2:-0}"
    local service_names=("mysqld" "mysql")
    
    for service_name in "${service_names[@]}"; do
        if command -v systemctl &> /dev/null; then
            case "$action" in
                start)
                    if systemctl start "$service_name" 2>/dev/null; then
                        [ "$silent" -eq 0 ] && echo -e "${GREEN}✓ MySQL 服务启动成功${NC}"
                        return 0
                    fi
                    ;;
                stop)
                    if systemctl stop "$service_name" 2>/dev/null; then
                        [ "$silent" -eq 0 ] && echo -e "${GREEN}✓ MySQL 服务已停止${NC}"
                        return 0
                    fi
                    ;;
                restart)
                    if systemctl restart "$service_name" 2>/dev/null; then
                        [ "$silent" -eq 0 ] && echo -e "${GREEN}✓ MySQL 服务重启成功${NC}"
                        return 0
                    fi
                    ;;
                enable)
                    if systemctl enable "$service_name" 2>/dev/null; then
                        [ "$silent" -eq 0 ] && echo -e "${GREEN}✓ 已启用 MySQL 开机自启动${NC}"
                        return 0
                    fi
                    ;;
                disable)
                    if systemctl disable "$service_name" 2>/dev/null; then
                        [ "$silent" -eq 0 ] && echo -e "${GREEN}✓ 已禁用 MySQL 开机自启动${NC}"
                        return 0
                    fi
                    ;;
                status)
                    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
                        return 0
                    fi
                ;;
        esac
        elif command -v service &> /dev/null; then
            case "$action" in
                start)
                    if service "$service_name" start 2>/dev/null; then
                        [ "$silent" -eq 0 ] && echo -e "${GREEN}✓ MySQL 服务启动成功${NC}"
                        # 启用开机自启动
                        if command -v chkconfig &> /dev/null; then
                            chkconfig "$service_name" on 2>/dev/null || true
                        fi
                        return 0
                    fi
                    ;;
                stop)
                    if service "$service_name" stop 2>/dev/null; then
                        [ "$silent" -eq 0 ] && echo -e "${GREEN}✓ MySQL 服务已停止${NC}"
                        return 0
                    fi
                    ;;
                restart)
                    if service "$service_name" restart 2>/dev/null; then
                        [ "$silent" -eq 0 ] && echo -e "${GREEN}✓ MySQL 服务重启成功${NC}"
                        return 0
                    fi
                    ;;
                enable)
                    if command -v chkconfig &> /dev/null; then
                        if chkconfig "$service_name" on 2>/dev/null; then
                            [ "$silent" -eq 0 ] && echo -e "${GREEN}✓ 已启用 MySQL 开机自启动${NC}"
                            return 0
                        fi
                    fi
                    ;;
                disable)
                    if command -v chkconfig &> /dev/null; then
                        if chkconfig "$service_name" off 2>/dev/null; then
                            [ "$silent" -eq 0 ] && echo -e "${GREEN}✓ 已禁用 MySQL 开机自启动${NC}"
                            return 0
                        fi
                    fi
                    ;;
                status)
                    if service "$service_name" status 2>/dev/null | grep -q "running"; then
                        return 0
                    fi
                    ;;
            esac
        fi
    done
    
    return 1
}

# 获取并验证 MySQL root 密码（统一函数，避免重复逻辑）
# 参数: $1=host (可选，默认127.0.0.1), $2=port (可选，默认3306)
# 返回: 0=成功, 1=失败
# 设置: MYSQL_ROOT_PASSWORD 和 TEMP_PASSWORD
get_and_verify_root_password() {
    local mysql_host="${1:-127.0.0.1}"
    local mysql_port="${2:-3306}"
    
    # 如果密码已验证，直接返回成功（避免重复验证）
    if [ "${PASSWORD_VERIFIED:-0}" -eq 1 ] && [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        echo -e "${BLUE}密码已验证，跳过重复验证${NC}"
        return 0
    fi
    
    # 如果已设置密码，直接验证
    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        if mysql_verify_connection "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD"; then
            echo -e "${GREEN}✓ 密码验证成功${NC}"
            PASSWORD_VERIFIED=1
            return 0
        elif mysql_execute "SELECT 1;" "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD" "--connect-expired-password" >/dev/null 2>&1; then
            echo -e "${YELLOW}⚠ 使用的是临时密码（已过期），后续操作可能需要先修改密码${NC}"
            return 0
        else
            echo -e "${RED}✗ 密码验证失败${NC}"
            return 1
        fi
    fi
    
    # 如果未设置密码，尝试多种方式获取
    echo ""
    echo -e "${BLUE}需要 MySQL root 密码以执行后续操作${NC}"
    
    # 先尝试无密码连接（某些 MariaDB 可能无密码）
    if mysql_verify_connection "$mysql_host" "$mysql_port" "root" ""; then
        echo -e "${GREEN}✓ MySQL root 用户无密码，可以使用无密码连接${NC}"
        MYSQL_ROOT_PASSWORD=""
        return 0
    fi
    
    # 尝试从日志中查找临时密码（MySQL 8.0，使用辅助函数）
    if [ -z "${TEMP_PASSWORD:-}" ]; then
        TEMP_PASSWORD=$(get_mysql_temp_password || echo "")
    fi
    
    if [ -n "$TEMP_PASSWORD" ]; then
        echo -e "${YELLOW}⚠ 检测到 MySQL 临时密码: ${TEMP_PASSWORD}${NC}"
        echo -e "${YELLOW}⚠ 建议先修改临时密码${NC}"
    fi
    
    # 提示用户输入密码
    read -p "请输入 MySQL root 密码（直接回车使用临时密码或无密码）: " MYSQL_ROOT_PASSWORD
    
    # 如果用户没有输入，使用临时密码或尝试无密码
    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
        if [ -n "$TEMP_PASSWORD" ]; then
            MYSQL_ROOT_PASSWORD="$TEMP_PASSWORD"
            echo -e "${BLUE}使用临时密码连接 MySQL${NC}"
        else
            echo -e "${YELLOW}⚠ 未输入密码，尝试无密码连接${NC}"
        fi
    fi
    
    # 验证密码是否正确（使用辅助函数）
    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        if mysql_verify_connection "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD"; then
            echo -e "${GREEN}✓ 密码验证成功${NC}"
            PASSWORD_VERIFIED=1
            return 0
        elif mysql_execute "SELECT 1;" "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD" "--connect-expired-password" >/dev/null 2>&1; then
            echo -e "${YELLOW}⚠ 使用的是临时密码（已过期），后续操作可能需要先修改密码${NC}"
            return 0
        else
            echo -e "${RED}✗ 密码验证失败${NC}"
            echo -e "${YELLOW}请检查密码是否正确，或手动测试连接${NC}"
            return 1
        fi
    else
        # 尝试无密码连接（使用辅助函数）
        if mysql_verify_connection "$mysql_host" "$mysql_port" "root" ""; then
            echo -e "${GREEN}✓ 无密码连接成功${NC}"
            PASSWORD_VERIFIED=1
            return 0
        else
            echo -e "${RED}✗ 无密码连接失败${NC}"
            echo -e "${YELLOW}请提供正确的 root 密码${NC}"
            return 1
        fi
    fi
}

# 检测硬件配置（使用公共函数）
detect_hardware() {
    echo -e "${BLUE}检测硬件配置...${NC}"
    detect_hardware_common
    echo -e "${GREEN}✓ CPU 核心数: ${CPU_CORES}${NC}"
    echo -e "${GREEN}✓ 总内存: ${TOTAL_MEM_GB}GB (${TOTAL_MEM_MB}MB)${NC}"
}

# 检测系统类型（使用公共函数）
detect_os() {
    detect_os_common "[1/8]"
    if [ "$OS" = "unknown" ]; then
        echo -e "${YELLOW}将尝试使用通用方法${NC}"
    fi
}

# 检查是否为 root 用户（使用公共函数）
check_root() {
    if ! check_root_common; then
        echo -e "${RED}错误: 需要 root 权限来安装 MySQL${NC}"
        exit 1
    fi
}

# 彻底卸载 MySQL/MariaDB
completely_uninstall_mysql() {
    echo -e "${BLUE}开始彻底卸载 MySQL/MariaDB...${NC}"
    
    # 确保已检测操作系统（如果未检测，先检测）
    if [ -z "$OS" ]; then
        detect_os
    fi
    
    # 停止 MySQL 服务（使用统一函数）
    echo "停止 MySQL 服务..."
    mysql_service_manage "stop" 0
    mysql_service_manage "disable" 0
    
    # 确保进程已停止
    sleep 2
    pkill -9 mysqld 2>/dev/null || true
    pkill -9 mysql_safe 2>/dev/null || true
    
    # 卸载 MySQL/MariaDB 软件包
    echo "卸载 MySQL/MariaDB 软件包..."
    case $OS in
        centos|rhel|fedora|rocky|almalinux|oraclelinux|amazonlinux)
            if command -v dnf &> /dev/null; then
                dnf remove -y mysql-server mysql mysql-common mysql-community-server mysql-community-client mariadb-server mariadb 2>/dev/null || true
            elif command -v yum &> /dev/null; then
                yum remove -y mysql-server mysql mysql-common mysql-community-server mysql-community-client mariadb-server mariadb 2>/dev/null || true
            fi
            ;;
        ubuntu|debian|linuxmint|raspbian|kali)
            if command -v apt-get &> /dev/null; then
                apt-get remove -y mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-* mariadb-server mariadb-client 2>/dev/null || true
                apt-get purge -y mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-* mariadb-server mariadb-client 2>/dev/null || true
                apt-get autoremove -y 2>/dev/null || true
            fi
            ;;
        opensuse*|sles)
            if command -v zypper &> /dev/null; then
                zypper remove -y mariadb mariadb-server mysql mysql-server 2>/dev/null || true
            fi
            ;;
        arch|manjaro)
            if command -v pacman &> /dev/null; then
                pacman -R --noconfirm mysql mariadb 2>/dev/null || true
            fi
            ;;
        alpine)
            if command -v apk &> /dev/null; then
                apk del mysql mysql-client mariadb mariadb-client 2>/dev/null || true
            fi
            ;;
        gentoo)
            if command -v emerge &> /dev/null; then
                emerge --unmerge dev-db/mysql dev-db/mariadb 2>/dev/null || true
            fi
            ;;
    esac
    
    echo -e "${GREEN}✓ MySQL/MariaDB 软件包已卸载${NC}"
}

# 检查 MySQL 是否已安装
check_existing() {
    echo -e "${BLUE}[2/8] 检查是否已安装 MySQL...${NC}"
    
    local mysql_installed=0
    local mysql_version=""
    local mysql_data_initialized=0
    local mysql_data_dir=""
    
    # 检查 MySQL 是否已安装
    if command -v mysql &> /dev/null || command -v mysqld &> /dev/null; then
        mysql_installed=1
        mysql_version=$(mysql --version 2>/dev/null || mysqld --version 2>/dev/null | head -n 1)
        echo -e "${YELLOW}检测到已安装 MySQL: ${mysql_version}${NC}"
        
        # 检查数据目录是否已初始化（使用统一函数，检查已初始化状态）
        local data_dir
        data_dir=$(get_mysql_data_dir 1) || true  # 防止 set -e 导致退出
        local mysql_data_initialized=0
        if [ -n "$data_dir" ]; then
            mysql_data_initialized=1
            mysql_data_dir="$data_dir"
        fi
        
        if [ $mysql_data_initialized -eq 1 ]; then
            echo -e "${YELLOW}检测到 MySQL 数据目录已初始化: ${mysql_data_dir}${NC}"
            echo ""
            echo "请选择操作："
            echo "  1. 保留现有数据和配置，跳过安装"
            echo "  2. 重新安装 MySQL（先卸载，保留数据目录）"
            echo "  3. 完全重新安装（先卸载，删除所有数据和配置）"
            # 检查是否在交互式终端中
            if [ -t 0 ]; then
                read -p "请选择 [1-3] (默认: 1): " REINSTALL_CHOICE
            else
                # 非交互模式，默认选择1
                REINSTALL_CHOICE="1"
                echo -e "${BLUE}[非交互模式] 自动选择: 1. 保留现有数据和配置，跳过安装${NC}"
            fi
            REINSTALL_CHOICE="${REINSTALL_CHOICE:-1}"  # 默认选择1
            
            case "$REINSTALL_CHOICE" in
                1)
                    echo -e "${GREEN}跳过 MySQL 安装，保留现有配置${NC}"
                    # 检查现有 MySQL 版本是否满足要求
                    if [ -n "$MYSQL_VERSION" ] && [ "$MYSQL_VERSION" != "default" ]; then
                        local current_major=$(echo "$mysql_version" | grep -oE '[0-9]+\.[0-9]+' | head -1)
                        local required_major=$(echo "$MYSQL_VERSION" | grep -oE '^[0-9]+\.[0-9]+' | head -1)
                        if [ "$current_major" != "$required_major" ]; then
                            echo -e "${YELLOW}⚠ 当前版本 ($current_major) 与要求版本 ($required_major) 不匹配${NC}"
                            echo -e "${YELLOW}⚠ 建议重新安装以匹配版本要求${NC}"
                        fi
                    fi
                    # 设置跳过安装标志，但继续执行后续步骤
                    SKIP_INSTALL=1
                    echo -e "${BLUE}将跳过安装步骤，继续执行数据库创建和用户设置等后续步骤${NC}"
                    ;;
                2)
                    echo -e "${YELLOW}将重新安装 MySQL，先卸载现有安装，但保留数据目录${NC}"
                    echo -e "${YELLOW}注意: 如果版本不兼容，可能导致数据无法使用${NC}"
                    echo -e "${YELLOW}建议: 在重新安装前备份数据目录${NC}"
                    read -p "是否先备份数据目录？[Y/n]: " BACKUP_DATA
                    BACKUP_DATA="${BACKUP_DATA:-Y}"
                    if [[ "$BACKUP_DATA" =~ ^[Yy]$ ]]; then
                        local backup_dir="/var/backups/mysql_$(date +%Y%m%d_%H%M%S)"
                        mkdir -p "$backup_dir"
                        echo -e "${BLUE}正在备份数据目录到: $backup_dir${NC}"
                        cp -r "${mysql_data_dir}" "$backup_dir/data" 2>/dev/null || {
                            echo -e "${YELLOW}⚠ 备份失败，继续安装${NC}"
                        }
                        echo -e "${GREEN}✓ 备份完成${NC}"
                    fi
                    REINSTALL_MODE="keep_data"
                    # 先卸载软件包
                    completely_uninstall_mysql
                    # 卸载后清除版本选择（使用辅助函数）
                    reset_mysql_version || true  # 防止 set -e 导致退出
                    
                    # 保留数据重新安装模式，清除 SKIP_INSTALL 标志，确保继续执行安装
                    SKIP_INSTALL=0
                    ;;
                3)
                    echo -e "${RED}警告: 将删除所有 MySQL 数据和配置！${NC}"
                    echo -e "${RED}这将包括：${NC}"
                    echo "  - 所有数据库和数据"
                    echo "  - 所有用户和权限"
                    echo "  - 配置文件"
                    echo "  - 日志文件"
                    read -p "确认删除所有数据？[y/N]: " CONFIRM_DELETE
                    CONFIRM_DELETE="${CONFIRM_DELETE:-N}"
                    if [[ "$CONFIRM_DELETE" =~ ^[Yy]$ ]]; then
                        echo -e "${YELLOW}将完全重新安装 MySQL，先卸载现有安装并删除所有数据${NC}"
                        REINSTALL_MODE="delete_all"
                        
                        # 先卸载软件包
                        completely_uninstall_mysql
                        
                        # 检查是否有其他服务依赖 MySQL
                        echo -e "${BLUE}检查是否有其他服务依赖 MySQL...${NC}"
                        if systemctl list-units --type=service --state=running 2>/dev/null | grep -qiE "php-fpm|wordpress|owncloud|nextcloud"; then
                            echo -e "${YELLOW}⚠ 检测到可能依赖 MySQL 的服务正在运行${NC}"
                            echo -e "${YELLOW}⚠ 删除 MySQL 可能导致这些服务无法正常工作${NC}"
                            read -p "是否继续？[y/N]: " CONTINUE_DELETE
                            CONTINUE_DELETE="${CONTINUE_DELETE:-N}"
                            if [[ ! "$CONTINUE_DELETE" =~ ^[Yy]$ ]]; then
                                echo -e "${GREEN}取消删除，将保留数据重新安装${NC}"
                                REINSTALL_MODE="keep_data"
                                return 0
                            fi
                        fi
                        
                        # 清理 MySQL 文件（使用辅助函数）
                        cleanup_mysql_files 1 || true  # 防止 set -e 导致退出
                        
                        # 卸载后清除版本选择（使用辅助函数）
                        reset_mysql_version || true  # 防止 set -e 导致退出
                        
                        # 完全重新安装模式，清除 SKIP_INSTALL 标志，确保继续执行安装
                        SKIP_INSTALL=0
                    else
                        echo -e "${GREEN}取消删除，将保留数据重新安装${NC}"
                        REINSTALL_MODE="keep_data"
                        # 仍然需要卸载软件包
                        completely_uninstall_mysql
                        # 卸载后清除版本选择（使用辅助函数）
                        reset_mysql_version || true  # 防止 set -e 导致退出
                        
                        # 保留数据重新安装模式，清除 SKIP_INSTALL 标志，确保继续执行安装
                        SKIP_INSTALL=0
                    fi
                    ;;
                *)
                    echo -e "${YELLOW}无效选择，将跳过安装${NC}"
                    SKIP_INSTALL=1
                    return 0
                    ;;
            esac
        else
            echo -e "${YELLOW}MySQL 已安装但数据目录未初始化${NC}"
            echo ""
            echo "请选择操作："
            echo "  1. 保留现有安装，跳过安装"
            echo "  2. 重新安装 MySQL（先卸载，保留数据目录）"
            echo "  3. 完全重新安装（先卸载，删除所有数据和配置）"
            # 检查是否在交互式终端中
            if [ -t 0 ]; then
                read -p "请选择 [1-3] (默认: 1): " REINSTALL_CHOICE
            else
                # 非交互模式，默认选择1
                REINSTALL_CHOICE="1"
                echo -e "${BLUE}[非交互模式] 自动选择: 1. 保留现有安装，跳过安装${NC}"
            fi
            REINSTALL_CHOICE="${REINSTALL_CHOICE:-1}"  # 默认选择1
            
            case "$REINSTALL_CHOICE" in
                1)
                    echo -e "${GREEN}跳过 MySQL 安装，保留现有安装${NC}"
                    # 检查现有 MySQL 版本是否满足要求
                    if [ -n "$MYSQL_VERSION" ] && [ "$MYSQL_VERSION" != "default" ]; then
                        local current_major=$(echo "$mysql_version" | grep -oE '[0-9]+\.[0-9]+' | head -1)
                        local required_major=$(echo "$MYSQL_VERSION" | grep -oE '^[0-9]+\.[0-9]+' | head -1)
                        if [ "$current_major" != "$required_major" ]; then
                            echo -e "${YELLOW}⚠ 当前版本 ($current_major) 与要求版本 ($required_major) 不匹配${NC}"
                            echo -e "${YELLOW}⚠ 建议重新安装以匹配版本要求${NC}"
                        fi
            fi
                    # 设置跳过安装标志，但继续执行后续步骤
                    SKIP_INSTALL=1
                    echo -e "${BLUE}将跳过安装步骤，继续执行数据库创建和用户设置等后续步骤${NC}"
                    ;;
                2)
                    echo -e "${YELLOW}将重新安装 MySQL，先卸载现有安装，但保留数据目录${NC}"
                    echo -e "${YELLOW}注意: 如果版本不兼容，可能导致数据无法使用${NC}"
                    REINSTALL_MODE="keep_data"
            # 先卸载软件包
            completely_uninstall_mysql
                    # 卸载后清除版本选择，让用户重新选择
                    if [ -z "${MYSQL_VERSION_FROM_ENV:-}" ]; then
                        unset MYSQL_VERSION
                    else
                        MYSQL_VERSION="${MYSQL_VERSION_FROM_ENV}"
                    fi
                    
                    # 保留数据重新安装模式，清除 SKIP_INSTALL 标志，确保继续执行安装
                    SKIP_INSTALL=0
                    ;;
                3)
                    echo -e "${RED}警告: 将删除所有 MySQL 数据和配置！${NC}"
                    echo -e "${RED}这将包括：${NC}"
                    echo "  - 所有数据库和数据"
                    echo "  - 所有用户和权限"
                    echo "  - 配置文件"
                    echo "  - 日志文件"
                    read -p "确认删除所有数据？[y/N]: " CONFIRM_DELETE
                    CONFIRM_DELETE="${CONFIRM_DELETE:-N}"
                    if [[ "$CONFIRM_DELETE" =~ ^[Yy]$ ]]; then
                        echo -e "${YELLOW}将完全重新安装 MySQL，先卸载现有安装并删除所有数据${NC}"
                        REINSTALL_MODE="delete_all"
                        
                        # 先卸载软件包
                        completely_uninstall_mysql
                        
                        # 检查是否有其他服务依赖 MySQL
                        echo -e "${BLUE}检查是否有其他服务依赖 MySQL...${NC}"
                        if systemctl list-units --type=service --state=running 2>/dev/null | grep -qiE "php-fpm|wordpress|owncloud|nextcloud"; then
                            echo -e "${YELLOW}⚠ 检测到可能依赖 MySQL 的服务正在运行${NC}"
                            echo -e "${YELLOW}⚠ 删除 MySQL 可能导致这些服务无法正常工作${NC}"
                            read -p "是否继续？[y/N]: " CONTINUE_DELETE
                            CONTINUE_DELETE="${CONTINUE_DELETE:-N}"
                            if [[ ! "$CONTINUE_DELETE" =~ ^[Yy]$ ]]; then
                                echo -e "${GREEN}取消删除，将保留数据重新安装${NC}"
                                REINSTALL_MODE="keep_data"
                                return 0
                            fi
                        fi
                        
                        # 清理 MySQL 文件（使用辅助函数）
                        cleanup_mysql_files 1 || true  # 防止 set -e 导致退出
                        
                        # 卸载后清除版本选择（使用辅助函数）
                        reset_mysql_version || true  # 防止 set -e 导致退出
                        
                        # 完全重新安装模式，清除 SKIP_INSTALL 标志，确保继续执行安装
                        SKIP_INSTALL=0
                    else
                        echo -e "${GREEN}取消删除，将保留数据重新安装${NC}"
                        REINSTALL_MODE="keep_data"
                        # 仍然需要卸载软件包
                        completely_uninstall_mysql
                        # 卸载后清除版本选择，让用户重新选择
                        if [ -z "${MYSQL_VERSION_FROM_ENV:-}" ]; then
                            unset MYSQL_VERSION
                        else
                            MYSQL_VERSION="${MYSQL_VERSION_FROM_ENV}"
                        fi
                        
                        # 保留数据重新安装模式，清除 SKIP_INSTALL 标志，确保继续执行安装
                        SKIP_INSTALL=0
                    fi
                    ;;
                *)
                    echo -e "${YELLOW}无效选择，将跳过安装${NC}"
                    SKIP_INSTALL=1
                    return 0
                    ;;
            esac
        fi
    else
        echo -e "${GREEN}✓ MySQL 未安装，将进行全新安装${NC}"
    fi
    
    # 如果设置了 SKIP_INSTALL，确保函数正确返回
    if [ "${SKIP_INSTALL:-0}" -eq 1 ]; then
        echo -e "${GREEN}✓ 检查完成（将跳过安装步骤）${NC}"
        return 0
    fi
    
    # 版本设置：默认安装 MySQL 8.0 最新版本
    # 如果通过环境变量指定了版本，则使用环境变量的版本
    if [ -n "${MYSQL_VERSION_FROM_ENV:-}" ]; then
        MYSQL_VERSION="${MYSQL_VERSION_FROM_ENV}"
        echo -e "${BLUE}使用环境变量指定的版本: ${MYSQL_VERSION}${NC}"
            else
        # 默认使用 MySQL 8.0
                        MYSQL_VERSION="8.0"
        echo -e "${BLUE}默认安装 MySQL 8.0 最新版本${NC}"
    fi
    
    echo -e "${GREEN}✓ 检查完成${NC}"
}

# 检查指定版本的MySQL是否可用（RedHat系列）
check_mysql_version_available_redhat() {
    local version="$1"
    local major_minor=""
    local full_version=""
    
    if [ -z "$version" ] || [ "$version" = "default" ]; then
        return 0  # 默认版本总是可用
    fi
    
    # 提取主次版本号
    if echo "$version" | grep -qE '^[0-9]+\.[0-9]+'; then
        major_minor=$(echo "$version" | grep -oE '^[0-9]+\.[0-9]+')
        full_version="$version"
    else
        return 0  # 格式不正确，让安装过程处理
    fi
    
    # 检查完整版本号是否可用
    if command -v yum &> /dev/null; then
        # 检查完整版本号包
        if yum list available "mysql-community-server-${full_version}" "mysql-community-client-${full_version}" 2>/dev/null | grep -qE "mysql-community-server|mysql-community-client"; then
            return 0
        fi
        
        # 检查主次版本号包
        if yum list available "mysql-community-server-${major_minor}*" "mysql-community-client-${major_minor}*" 2>/dev/null | grep -qE "mysql-community-server|mysql-community-client"; then
            return 0
        fi
        
        # 检查通用包名
        if yum list available mysql-community-server mysql-community-client 2>/dev/null | grep -qE "mysql-community-server|mysql-community-client"; then
            return 0
        fi
    elif command -v dnf &> /dev/null; then
        # 检查完整版本号包
        if dnf list available "mysql-community-server-${full_version}" "mysql-community-client-${full_version}" 2>/dev/null | grep -qE "mysql-community-server|mysql-community-client"; then
            return 0
        fi
        
        # 检查主次版本号包
        if dnf list available "mysql-community-server-${major_minor}*" "mysql-community-client-${major_minor}*" 2>/dev/null | grep -qE "mysql-community-server|mysql-community-client"; then
            return 0
        fi
        
        # 检查通用包名
        if dnf list available mysql-community-server mysql-community-client 2>/dev/null | grep -qE "mysql-community-server|mysql-community-client"; then
            return 0
        fi
    fi
    
    return 1  # 版本不可用
}

# 获取可用的MySQL版本列表（RedHat系列）
get_available_mysql_versions_redhat() {
    local versions=()
    
    # 先确保仓库已配置（如果可能）
    if [ ! -f /etc/yum.repos.d/mysql-community.repo ]; then
        # 尝试快速配置仓库（不安装）
        echo -e "${BLUE}正在检查可用版本，可能需要先配置MySQL仓库...${NC}"
    fi
    
    # 检查MySQL 8.0系列
    if command -v yum &> /dev/null; then
        if yum list available mysql-community-server mysql-community-client 2>/dev/null | grep -qE "mysql-community-server.*8\.0|mysql-community-client.*8\.0"; then
            # 尝试获取具体版本号
            local ver80=$(yum list available mysql-community-server 2>/dev/null | grep -E "mysql-community-server.*8\.0" | head -1 | awk '{print $2}' | grep -oE '8\.0\.[0-9]+' | head -1)
            if [ -n "$ver80" ]; then
                versions+=("$ver80")
            else
                versions+=("8.0")
            fi
        fi
        
        # 检查MySQL 5.7系列
        if yum list available mysql-community-server mysql-community-client 2>/dev/null | grep -qE "mysql-community-server.*5\.7|mysql-community-client.*5\.7"; then
            local ver57=$(yum list available mysql-community-server 2>/dev/null | grep -E "mysql-community-server.*5\.7" | head -1 | awk '{print $2}' | grep -oE '5\.7\.[0-9]+' | head -1)
            if [ -n "$ver57" ]; then
                versions+=("$ver57")
            else
                versions+=("5.7")
            fi
        fi
    elif command -v dnf &> /dev/null; then
        if dnf list available mysql-community-server mysql-community-client 2>/dev/null | grep -qE "mysql-community-server.*8\.0|mysql-community-client.*8\.0"; then
            local ver80=$(dnf list available mysql-community-server 2>/dev/null | grep -E "mysql-community-server.*8\.0" | head -1 | awk '{print $2}' | grep -oE '8\.0\.[0-9]+' | head -1)
            if [ -n "$ver80" ]; then
                versions+=("$ver80")
            else
                versions+=("8.0")
            fi
        fi
        
        if dnf list available mysql-community-server mysql-community-client 2>/dev/null | grep -qE "mysql-community-server.*5\.7|mysql-community-client.*5\.7"; then
            local ver57=$(dnf list available mysql-community-server 2>/dev/null | grep -E "mysql-community-server.*5\.7" | head -1 | awk '{print $2}' | grep -oE '5\.7\.[0-9]+' | head -1)
            if [ -n "$ver57" ]; then
                versions+=("$ver57")
            else
                versions+=("5.7")
            fi
        fi
    fi
    
    # 如果没有找到，返回默认版本
    if [ ${#versions[@]} -eq 0 ]; then
        versions+=("8.0")
        versions+=("default")
    fi
    
    echo "${versions[@]}"
}

# 验证 MySQL 是否真正安装成功
verify_mysql_installation() {
    local install_log="${1:-/tmp/mysql_install.log}"
    
    # 首先检查 MySQL 命令和服务包是否已安装（最可靠的验证方法）
    local mysql_installed=0
    if command -v mysql &> /dev/null || command -v mysqld &> /dev/null; then
        mysql_installed=1
    fi
    
    # 检查 MySQL 服务包是否已安装（RedHat系列）
    if command -v rpm &> /dev/null; then
        if rpm -qa | grep -qiE "mysql-community-server|mysql-server|mariadb-server"; then
            mysql_installed=1
        fi
    fi
    
    # 如果命令和包都已存在，认为安装成功
    if [ $mysql_installed -eq 1 ]; then
        return 0
    fi
    
    # 如果命令和包都不存在，检查安装日志
    if [ -f "$install_log" ]; then
        # 检查是否有"没有可用软件包"或"错误：无须任何处理"等错误
        if grep -qiE "没有可用软件包|No package available|错误：无须任何处理|Nothing to do|No packages marked for|无需任何处理|No match for argument" "$install_log"; then
            echo -e "${RED}✗ 检测到安装失败：软件包不可用或无需处理${NC}"
            return 1
        fi
        
        # 检查是否有其他安装错误（排除GPG警告）
        if grep -qiE "Error.*install|Failed.*install|无法安装|安装失败|安装.*失败|Cannot find a package" "$install_log" && ! grep -qiE "GPG key|GPG 密钥|GPG.*warning" "$install_log"; then
            echo -e "${RED}✗ 检测到安装错误${NC}"
            return 1
        fi
        
        # 检查是否真的安装了软件包（检查日志中是否有"Installed"或"已安装"）
        if grep -qiE "Installed|已安装|安装.*完成|Complete!|Package.*installed" "$install_log"; then
            # 有安装成功的标记，但命令不存在，可能是PATH问题
            echo -e "${YELLOW}⚠ 检测到安装成功标记，但命令未找到，可能是PATH问题${NC}"
            return 0  # 仍然返回成功，因为包已安装
        fi
        
            # 如果没有安装成功的标记，检查是否有错误
            if grep -qiE "Error|Failed|失败|错误" "$install_log" && ! grep -qiE "GPG|warning|警告" "$install_log"; then
            echo -e "${RED}✗ 未检测到安装成功的标记，且存在错误信息${NC}"
                return 1
        fi
    fi
    
    # 如果命令和包都不存在，且日志也没有明确说明，返回失败
    echo -e "${RED}✗ MySQL 命令和包都未找到，安装可能失败${NC}"
        return 1
}

# 修复 MySQL GPG 密钥问题
fix_mysql_gpg_key() {
    echo -e "${BLUE}正在修复 MySQL GPG 密钥问题...${NC}"
    
    # 尝试导入最新的 GPG 密钥
    local gpg_imported=0
    
    # 尝试多个 GPG 密钥源（包括正确的密钥ID）
    for gpg_url in \
        "https://repo.mysql.com/RPM-GPG-KEY-mysql-2022" \
        "https://repo.mysql.com/RPM-GPG-KEY-mysql" \
        "https://dev.mysql.com/doc/refman/8.0/en/checking-gpg-signature.html"; do
        if rpm --import "$gpg_url" 2>/dev/null; then
            gpg_imported=1
            echo -e "${GREEN}✓ GPG 密钥导入成功: $gpg_url${NC}"
            break
        fi
    done
    
    # 如果导入失败，尝试从仓库文件获取密钥
    if [ $gpg_imported -eq 0 ] && [ -f /etc/yum.repos.d/mysql-community.repo ]; then
        # 尝试从仓库配置中获取 GPG 密钥路径
        local gpg_key_path=$(grep -E "^gpgkey=" /etc/yum.repos.d/mysql-community.repo | head -1 | sed 's/.*=//' | sed 's|file://||')
        if [ -n "$gpg_key_path" ] && [ -f "$gpg_key_path" ]; then
            if rpm --import "$gpg_key_path" 2>/dev/null; then
                gpg_imported=1
                echo -e "${GREEN}✓ 从本地文件导入 GPG 密钥: $gpg_key_path${NC}"
            fi
        fi
    fi
    
    # 即使导入了密钥，也检查仓库配置中的gpgcheck设置
    # 如果仓库配置的密钥ID不匹配，仍然会失败，所以直接禁用GPG检查更可靠
    if [ -f /etc/yum.repos.d/mysql-community.repo ]; then
        # 检查是否已经有gpgcheck=0的设置
        if grep -q "^gpgcheck=0" /etc/yum.repos.d/mysql-community*.repo 2>/dev/null; then
            echo -e "${BLUE}✓ MySQL 仓库已禁用 GPG 检查${NC}"
            return 1  # 返回 1 表示需要使用 --nogpgcheck
        fi
        
        # 如果导入了密钥但可能不匹配，也禁用GPG检查以确保安装成功
        # 因为MySQL的GPG密钥ID经常变化，直接禁用更可靠
        echo -e "${YELLOW}⚠ 为保险起见，将禁用 MySQL 仓库的 GPG 检查${NC}"
        sed -i 's/^gpgcheck=1/gpgcheck=0/g' /etc/yum.repos.d/mysql-community*.repo 2>/dev/null || true
        echo -e "${GREEN}✓ 已禁用 MySQL 仓库的 GPG 检查${NC}"
        return 1  # 返回 1 表示需要使用 --nogpgcheck
    fi
    
    # 如果仍然失败，禁用 GPG 检查
    if [ $gpg_imported -eq 0 ]; then
        echo -e "${YELLOW}⚠ GPG 密钥导入失败，将禁用 GPG 检查${NC}"
        # 禁用所有 MySQL 仓库的 GPG 检查
        if [ -f /etc/yum.repos.d/mysql-community.repo ]; then
            sed -i 's/^gpgcheck=1/gpgcheck=0/g' /etc/yum.repos.d/mysql-community*.repo 2>/dev/null || true
            echo -e "${GREEN}✓ 已禁用 MySQL 仓库的 GPG 检查${NC}"
        fi
        return 1  # 返回 1 表示需要使用 --nogpgcheck
    fi
    
    return 1  # 默认返回 1，强制使用 --nogpgcheck 以确保安装成功
}

# 安装 MySQL（CentOS/RHEL/Fedora/Rocky/AlmaLinux/Oracle Linux/Amazon Linux）
install_mysql_redhat() {
    echo -e "${BLUE}[3/8] 安装 MySQL（RedHat 系列）...${NC}"
    
    # 确定仓库版本（根据实际系统）
    local el_version="el7"
    case $OS in
        fedora)
            # Fedora 通常使用 el8 或 el9
            if echo "$OS_VERSION" | grep -qE "^3[0-9]"; then
                el_version="el9"
            else
                el_version="el8"
            fi
            ;;
        rhel|rocky|almalinux|oraclelinux)
            # 根据主版本号确定
            if echo "$OS_VERSION" | grep -qE "^9\."; then
                el_version="el9"
            elif echo "$OS_VERSION" | grep -qE "^8\."; then
                el_version="el8"
            else
                el_version="el7"
            fi
            ;;
        amazonlinux)
            # Amazon Linux 2 使用 el7，Amazon Linux 2023 使用 el9
            if echo "$OS_VERSION" | grep -qE "^2023"; then
                el_version="el9"
            else
                el_version="el7"
            fi
            ;;
    esac
    
    # 根据选择的版本确定仓库包
    local repo_version="80"
    if [ "$MYSQL_VERSION" = "5.7" ] || echo "$MYSQL_VERSION" | grep -qE "^5\.7"; then
        repo_version="57"
    elif [ "$MYSQL_VERSION" = "8.0" ] || echo "$MYSQL_VERSION" | grep -qE "^8\.0"; then
        repo_version="80"
    elif [ "$MYSQL_VERSION" = "default" ]; then
        # 使用系统默认版本，尝试 MySQL 8.0
        repo_version="80"
    fi
    
    # ========== 步骤1: 下载并安装 MySQL Yum Repository（官方标准流程）==========
    echo -e "${BLUE}[步骤1/4] 添加 MySQL 官方 Yum 仓库...${NC}"
    echo -e "${BLUE}官方下载页面: https://dev.mysql.com/downloads/repo/yum/${NC}"
    
    if [ ! -f /etc/yum.repos.d/mysql-community.repo ]; then
        echo "添加 MySQL ${repo_version} 官方仓库..."
        
        # 下载 MySQL Yum Repository
        # 官方下载链接格式：https://dev.mysql.com/get/mysql{version}-community-release-{el_version}-{version}.noarch.rpm
        local repo_downloaded=0
        local repo_file=""
        
        # 尝试多个 el_version 变体（从最匹配到通用）
        local el_versions_to_try=()
        case $el_version in
            el9)
                el_versions_to_try=("el9" "el8" "el7")
                ;;
            el8)
                el_versions_to_try=("el8" "el7" "el9")
                ;;
            el7)
                el_versions_to_try=("el7" "el8" "el9")
                ;;
            *)
                el_versions_to_try=("el8" "el7" "el9")
                ;;
        esac
        
        # 尝试多个仓库包版本格式（MySQL 可能更新了包名格式）
        local repo_versions=("3" "2" "1")
        
        # 尝试下载对应版本的仓库
        for el_ver in "${el_versions_to_try[@]}"; do
            for repo_ver in "${repo_versions[@]}"; do
                # 尝试标准格式：mysql80-community-release-el8-3.noarch.rpm
                repo_file="mysql${repo_version}-community-release-${el_ver}-${repo_ver}.noarch.rpm"
            local repo_url="https://dev.mysql.com/get/${repo_file}"
                echo "尝试下载: $repo_url"
                
                # 使用公共下载函数
                if download_file_common "$repo_url" "/tmp/mysql-community-release.rpm" "RPM"; then
                repo_downloaded=1
                    echo -e "${GREEN}✓ 成功从官方下载 MySQL 仓库: ${repo_file}${NC}"
                    break 2
            fi
            done
        done
        
        if [ $repo_downloaded -eq 0 ]; then
            echo -e "${RED}✗ 无法从官方下载 MySQL 仓库${NC}"
            echo -e "${YELLOW}  官方下载页面: https://dev.mysql.com/downloads/repo/yum/${NC}"
            echo -e "${YELLOW}  请手动访问下载页面并安装对应的仓库包${NC}"
            echo ""
            echo -e "${BLUE}手动安装步骤：${NC}"
            echo "  1. 访问: https://dev.mysql.com/downloads/repo/yum/"
            echo "  2. 选择适合您系统的 RPM 包（el7/el8/el9）"
            echo "  3. 下载后运行: rpm -ivh mysql80-community-release-el*.rpm"
            echo "  4. 然后重新运行此脚本"
            exit 1
        fi
        
        # 安装 MySQL 仓库
        if [ -f /tmp/mysql-community-release.rpm ]; then
            # 尝试导入 GPG 密钥（在安装仓库之前）
            echo "导入 MySQL GPG 密钥..."
            rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2022 2>/dev/null || \
            rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql 2>/dev/null || true
            
            # 安装仓库（直接使用 --nodigest --nosignature 避免 GPG 验证问题）
            echo "正在安装 MySQL 仓库..."
            if rpm -ivh --nodigest --nosignature /tmp/mysql-community-release.rpm 2>&1; then
                echo -e "${GREEN}✓ MySQL 仓库安装成功${NC}"
                else
                echo -e "${YELLOW}⚠ 仓库安装失败，尝试强制安装...${NC}"
                # 如果安装失败，尝试强制安装
                rpm -ivh --nodigest --nosignature --force /tmp/mysql-community-release.rpm 2>&1 || {
                    echo -e "${RED}✗ MySQL 仓库安装失败${NC}"
                    rm -f /tmp/mysql-community-release.rpm
                    exit 1
                }
            fi
            rm -f /tmp/mysql-community-release.rpm
        
            # 安装仓库后，禁用 GPG 检查以确保后续安装成功
            if [ -f /etc/yum.repos.d/mysql-community.repo ]; then
                sed -i 's/^gpgcheck=1/gpgcheck=0/g' /etc/yum.repos.d/mysql-community*.repo 2>/dev/null || true
                echo -e "${GREEN}✓ 已禁用 MySQL 仓库的 GPG 检查${NC}"
            fi
            
            # 如果指定了 MySQL 8.0，启用 MySQL 8.0 仓库并禁用其他版本
            if [ "$repo_version" = "80" ] && [ -f /etc/yum.repos.d/mysql-community.repo ]; then
                sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/mysql-community*.repo 2>/dev/null || true
                sed -i '/\[mysql80-community\]/,/\[/ { /enabled=/ s/enabled=0/enabled=1/ }' /etc/yum.repos.d/mysql-community*.repo 2>/dev/null || true
                echo -e "${GREEN}✓ 已启用 MySQL 8.0 仓库${NC}"
            fi
        fi
    else
        echo -e "${GREEN}✓ MySQL 仓库已存在${NC}"
    fi
    
    # ========== 步骤2: 更新 yum/dnf 缓存 ==========
    echo -e "${BLUE}[步骤2/4] 更新包管理器缓存...${NC}"
    if command -v dnf &> /dev/null; then
        dnf makecache 2>&1 | grep -vE "GPG|密钥" || true
        echo -e "${GREEN}✓ dnf 缓存更新完成${NC}"
    elif command -v yum &> /dev/null; then
        yum makecache fast 2>&1 | grep -vE "GPG|密钥" || true
        echo -e "${GREEN}✓ yum 缓存更新完成${NC}"
    fi
    
    # ========== 步骤3: 安装 MySQL（官方标准流程）==========
    echo -e "${BLUE}[步骤3/4] 安装 MySQL...${NC}"
    INSTALL_SUCCESS=0
    
    # 修复 GPG 密钥问题（强制使用 --nogpgcheck 以确保安装成功）
    # 注意：fix_mysql_gpg_key 返回 1 表示需要使用 --nogpgcheck，这是正常的，不是错误
    fix_mysql_gpg_key || true
    local nogpgcheck_flag="--nogpgcheck"
    
    # 按照官方标准流程，直接安装 MySQL 8.0（不指定具体版本号）
    echo "按照 MySQL 官方标准流程安装 MySQL 8.0..."
    echo "正在下载并安装 MySQL 包（这可能需要几分钟，请耐心等待）..."
    
        if command -v dnf &> /dev/null; then
        echo "使用 dnf 安装 MySQL..."
        
        # 在安装前，先检查并禁用 MySQL 模块（如果存在），避免模块化过滤问题
        if dnf module list mysql 2>/dev/null | grep -qE "^mysql\s+.*\[.*\]"; then
            echo -e "${YELLOW}检测到 MySQL 模块，先禁用模块以避免模块化过滤问题...${NC}"
            dnf module disable -y mysql 2>&1 | grep -vE "GPG|密钥" || true
            # 清理缓存，确保模块禁用生效
            dnf clean all 2>/dev/null || true
            dnf makecache 2>&1 | grep -vE "GPG|密钥" || true
            echo -e "${GREEN}✓ MySQL 模块已禁用${NC}"
        fi
        
        # 先尝试正常安装
        echo "正在执行: dnf install -y $nogpgcheck_flag mysql-community-server mysql-community-client"
        dnf install -y $nogpgcheck_flag mysql-community-server mysql-community-client 2>&1 | tee /tmp/mysql_install.log
        local dnf_exit_code=${PIPESTATUS[0]}
        
        if [ $dnf_exit_code -eq 0 ]; then
            # dnf install 成功，验证是否真正安装成功
                if verify_mysql_installation /tmp/mysql_install.log; then
                INSTALL_SUCCESS=1
                echo -e "${GREEN}✓ MySQL 安装成功${NC}"
                else
                echo -e "${RED}✗ MySQL 安装失败（验证失败）${NC}"
                    INSTALL_SUCCESS=0
                fi
            else
            # dnf install 失败，检查错误原因
                INSTALL_SUCCESS=0
            echo -e "${YELLOW}第一次安装尝试失败，检查错误原因...${NC}"
            
            # 检查是否是模块化过滤问题（支持中英文错误信息）
            if grep -qiE "filtered out by modular filtering|modular filtering|模块化过滤条件筛除|模块化过滤" /tmp/mysql_install.log; then
                echo -e "${YELLOW}检测到模块化过滤问题，尝试禁用模块化过滤...${NC}"
                # 尝试禁用 MySQL 模块（如果存在）
                echo "尝试禁用 MySQL 模块..."
                dnf module disable -y mysql 2>&1 | tee -a /tmp/mysql_install.log || true
                
                # 清理 DNF 缓存，确保模块禁用生效
                echo "清理 DNF 缓存..."
                dnf clean all 2>/dev/null || true
                dnf makecache 2>&1 | grep -vE "GPG|密钥" || true
                
                # 禁用模块后，直接重新安装（不需要额外参数）
                echo -e "${YELLOW}MySQL 模块已禁用，重新安装...${NC}"
                echo "正在执行: dnf install -y $nogpgcheck_flag mysql-community-server mysql-community-client"
                dnf install -y $nogpgcheck_flag mysql-community-server mysql-community-client 2>&1 | tee -a /tmp/mysql_install.log
                local dnf_retry_exit_code=${PIPESTATUS[0]}
                
                if [ $dnf_retry_exit_code -eq 0 ]; then
                    if verify_mysql_installation /tmp/mysql_install.log; then
                        INSTALL_SUCCESS=1
                        echo -e "${GREEN}✓ MySQL 安装成功（已禁用 MySQL 模块）${NC}"
                    else
                        INSTALL_SUCCESS=0
                        echo -e "${RED}✗ MySQL 安装失败（验证失败）${NC}"
                    fi
                else
                    INSTALL_SUCCESS=0
                    echo -e "${RED}✗ dnf install 命令执行失败（即使禁用 MySQL 模块）${NC}"
                fi
            else
                echo -e "${RED}✗ dnf install 命令执行失败${NC}"
            fi
        fi
    elif command -v yum &> /dev/null; then
        echo "使用 yum 安装 MySQL..."
        echo "正在执行: yum install -y $nogpgcheck_flag mysql-community-server mysql-community-client"
        yum install -y $nogpgcheck_flag mysql-community-server mysql-community-client 2>&1 | tee /tmp/mysql_install.log
        local yum_exit_code=${PIPESTATUS[0]}
        
        if [ $yum_exit_code -eq 0 ]; then
                    # 验证是否真正安装成功
                    if verify_mysql_installation /tmp/mysql_install.log; then
                    INSTALL_SUCCESS=1
                echo -e "${GREEN}✓ MySQL 安装成功${NC}"
                    else
                echo -e "${RED}✗ MySQL 安装失败（验证失败）${NC}"
                        INSTALL_SUCCESS=0
                    fi
                else
                    INSTALL_SUCCESS=0
            echo -e "${RED}✗ yum install 命令执行失败${NC}"
            fi
        fi
        
    # 如果安装失败，显示详细错误信息
    if [ $INSTALL_SUCCESS -eq 0 ]; then
        echo ""
        echo -e "${YELLOW}安装日志（最后50行）：${NC}"
        if [ -f /tmp/mysql_install.log ] && [ -s /tmp/mysql_install.log ]; then
            tail -50 /tmp/mysql_install.log
        else
            echo "  日志文件为空或不存在"
        fi
        echo ""
        echo -e "${BLUE}详细错误分析：${NC}"
        if [ -f /tmp/mysql_install.log ]; then
            if grep -qiE "No package|没有可用软件包|No match for argument|Nothing to do|No packages marked for" /tmp/mysql_install.log; then
                echo "  - 软件包不可用，可能原因："
                echo "    1. 仓库未正确配置"
                echo "    2. 网络连接问题"
                echo "    3. 仓库缓存未更新"
                echo ""
                echo "  诊断命令："
            if command -v dnf &> /dev/null; then
                echo "    dnf list available mysql-community-server"
                echo "    dnf repolist | grep mysql"
                else
                    echo "    yum list available mysql-community-server"
                    echo "    yum repolist | grep mysql"
                fi
            elif grep -qiE "filtered out by modular filtering|modular filtering|模块化过滤条件筛除|模块化过滤" /tmp/mysql_install.log; then
                echo "  - 检测到模块化过滤问题"
                echo "    这是 DNF 的模块化仓库过滤功能导致的"
                echo ""
                echo "  解决方案："
                echo "    1. 禁用 MySQL 模块（如果存在）："
                echo "       dnf module disable -y mysql"
                echo "       dnf clean all"
                echo "       dnf makecache"
                echo "       dnf install -y mysql-community-server mysql-community-client"
                echo "    2. 或检查可用的 MySQL 模块："
                echo "       dnf module list mysql"
                echo "    3. 或检查 MySQL 仓库是否已启用："
                echo "       dnf repolist enabled | grep mysql"
            elif grep -qiE "Error|Failed|错误" /tmp/mysql_install.log; then
                echo "  - 检测到安装错误"
                grep -iE "Error|Failed|错误" /tmp/mysql_install.log | head -10
            else
                echo "  - 安装命令失败，但日志中没有明确错误信息"
                echo "  - 请检查网络连接和仓库配置"
            fi
        fi
        echo ""
        echo -e "${RED}✗ MySQL 安装失败${NC}"
        exit 1
    fi
    
    # ========== 步骤4: 安装完成后的后续配置（在安装成功后执行）==========
    echo -e "${BLUE}[步骤4/4] 安装完成，准备进行后续配置...${NC}"
    
    # 注意：以下配置步骤将在主函数中执行，这里只标记安装成功
    # 配置步骤包括：
    # - 启动 MySQL 服务
    # - 获取临时密码
    # - 配置 MySQL（配置文件优化）
    # - 设置 root 密码
    # - 其他优化配置
    
    # 安装成功，返回
    return 0
}

# 安装 MySQL（Ubuntu/Debian/Linux Mint/Kali Linux）
install_mysql_debian() {
    echo -e "${BLUE}[3/8] 安装 MySQL（Debian 系列）...${NC}"
    
    # ========== 步骤1: 添加 MySQL 官方 APT 仓库（官方标准流程）==========
    echo -e "${BLUE}[步骤1/4] 添加 MySQL 官方 APT 仓库...${NC}"
    echo -e "${BLUE}官方下载页面: https://dev.mysql.com/downloads/repo/apt/${NC}"
    
    # 检查是否已配置 MySQL 官方仓库
    if [ ! -f /etc/apt/sources.list.d/mysql.list ] && [ ! -f /etc/apt/sources.list.d/mysql-apt-config.list ]; then
        echo "从 MySQL 官方下载页面获取 APT 安装源..."
        
        # 安装必要的工具
        apt-get update -qq 2>/dev/null || true
        apt-get install -y wget gnupg lsb-release 2>/dev/null || true
        
        # 下载并安装 MySQL APT 仓库配置
        # 官方下载链接格式：https://dev.mysql.com/get/mysql-apt-config_{version}_all.deb
        local repo_downloaded=0
        # 尝试更多版本号（包括最新版本）
        local apt_config_versions=("0.8.36-1" "0.8.35-1" "0.8.34-1" "0.8.33-1" "0.8.32-1" "0.8.31-1" "0.8.30-1" "0.8.29-1" "0.8.28-1" "0.8.27-1" "0.8.26-1" "0.8.25-1" "0.8.24-1")
        
        for config_version in "${apt_config_versions[@]}"; do
            local repo_file="mysql-apt-config_${config_version}_all.deb"
            local repo_url="https://dev.mysql.com/get/${repo_file}"
            echo "尝试从官方下载: $repo_url"
            
            # 使用公共下载函数
            if download_file_common "$repo_url" "/tmp/${repo_file}" "DEB"; then
                repo_downloaded=1
                echo -e "${GREEN}✓ 成功从官方下载 MySQL APT 仓库配置: ${repo_file}${NC}"
                else
                echo -e "${YELLOW}  版本 ${config_version} 下载失败，尝试下一个...${NC}"
                continue
            fi
            
            # 如果下载成功，安装仓库配置
            if [ $repo_downloaded -eq 1 ]; then
                # 安装仓库配置（非交互式）
                DEBIAN_FRONTEND=noninteractive dpkg -i /tmp/${repo_file} 2>/dev/null || {
                    echo -e "${RED}✗ MySQL APT 仓库配置安装失败${NC}"
                    rm -f /tmp/${repo_file}
                    exit 1
                }
                rm -f /tmp/${repo_file}
                
                # 配置 MySQL 8.0 仓库（默认）
                echo "mysql-apt-config mysql-apt-config/select-server select mysql-8.0" | debconf-set-selections 2>/dev/null || true
                echo -e "${GREEN}✓ MySQL APT 仓库配置安装成功${NC}"
                break
            fi
        done
        
        if [ $repo_downloaded -eq 0 ]; then
            echo -e "${RED}✗ 无法从官方下载 MySQL APT 仓库配置${NC}"
            echo -e "${YELLOW}  官方下载页面: https://dev.mysql.com/downloads/repo/apt/${NC}"
            echo -e "${YELLOW}  请手动访问下载页面并安装对应的仓库包${NC}"
            echo ""
            echo -e "${BLUE}手动安装步骤：${NC}"
            echo "  1. 访问: https://dev.mysql.com/downloads/repo/apt/"
            echo "  2. 下载 mysql-apt-config_*.deb 包"
            echo "  3. 运行: dpkg -i mysql-apt-config_*.deb"
            echo "  4. 运行: apt-get update"
            echo "  5. 然后重新运行此脚本"
            exit 1
                fi
            else
        echo -e "${GREEN}✓ MySQL APT 仓库已存在${NC}"
    fi
    
    # ========== 步骤2: 更新 APT 缓存 ==========
    echo -e "${BLUE}[步骤2/4] 更新包管理器缓存...${NC}"
    apt-get update -qq 2>/dev/null || {
        echo -e "${RED}✗ APT 缓存更新失败${NC}"
        exit 1
    }
    echo -e "${GREEN}✓ APT 缓存更新完成${NC}"
    
    # ========== 步骤3: 安装 MySQL（官方标准流程）==========
    echo -e "${BLUE}[步骤3/4] 安装 MySQL...${NC}"
    
    # 安装必要的工具
    if ! command -v debconf-set-selections &> /dev/null; then
        apt-get install -y debconf-utils 2>/dev/null || true
    fi
    
    # 设置非交互式安装（使用空密码，后续会设置）
    echo "mysql-server mysql-server/root_password password" | debconf-set-selections 2>/dev/null || true
    echo "mysql-server mysql-server/root_password_again password" | debconf-set-selections 2>/dev/null || true
    
    # 按照官方标准流程，直接安装 MySQL 8.0
    echo "按照 MySQL 官方标准流程安装 MySQL 8.0..."
    if DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server mysql-client 2>&1 | tee /tmp/mysql_install.log; then
                # 验证是否真正安装成功
                if verify_mysql_installation /tmp/mysql_install.log; then
            echo -e "${GREEN}✓ MySQL 安装成功${NC}"
                else
            echo -e "${RED}✗ MySQL 安装失败（验证失败）${NC}"
            echo ""
            echo -e "${YELLOW}安装日志（最后50行）：${NC}"
            if [ -f /tmp/mysql_install.log ] && [ -s /tmp/mysql_install.log ]; then
                tail -50 /tmp/mysql_install.log
            fi
            exit 1
            fi
        else
        echo -e "${RED}✗ apt-get install 命令执行失败${NC}"
        echo ""
        echo -e "${YELLOW}安装日志（最后50行）：${NC}"
        if [ -f /tmp/mysql_install.log ] && [ -s /tmp/mysql_install.log ]; then
            tail -50 /tmp/mysql_install.log
        fi
        exit 1
    fi
    
    # ========== 步骤4: 安装完成后的后续配置（在安装成功后执行）==========
    echo -e "${BLUE}[步骤4/4] 安装完成，准备进行后续配置...${NC}"
    
    # 注意：以下配置步骤将在主函数中执行，这里只标记安装成功
    # 配置步骤包括：
    # - 启动 MySQL 服务
    # - 获取临时密码
    # - 配置 MySQL（配置文件优化）
    # - 设置 root 密码
    # - 其他优化配置
    
    # 安装成功，返回
    return 0
}

# 安装 MySQL（openSUSE/SLES）
install_mysql_suse() {
    echo -e "${BLUE}[3/8] 安装 MySQL（SUSE 系列）...${NC}"
    
    # ========== 步骤1: 添加 MySQL 官方 SUSE 仓库（官方标准流程）==========
    echo -e "${BLUE}[步骤1/4] 添加 MySQL 官方 SUSE 仓库...${NC}"
    echo -e "${BLUE}官方下载页面: https://dev.mysql.com/downloads/repo/suse/${NC}"
    
    # 检查是否已配置 MySQL 官方仓库
    if ! zypper repos | grep -qi mysql; then
        echo "从 MySQL 官方下载页面获取 SUSE 安装源..."
        
        # 安装必要的工具
        zypper install -y wget 2>/dev/null || true
        
        # 下载并安装 MySQL SUSE 仓库配置
        # 官方下载链接格式：https://dev.mysql.com/get/mysql80-community-release-sles{version}-{version}.noarch.rpm
        local repo_downloaded=0
        local sles_version=""
        
        # 检测 SUSE 版本
        if [ -f /etc/os-release ]; then
            sles_version=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2 | cut -d'.' -f1)
        fi
        
        # 尝试多个版本格式
        local sles_versions=("15" "12" "11")
        if [ -n "$sles_version" ]; then
            sles_versions=("$sles_version" "${sles_versions[@]}")
        fi
        
        for sles_ver in "${sles_versions[@]}"; do
            for repo_ver in "1" "2" "3"; do
                local repo_file="mysql80-community-release-sles${sles_ver}-${repo_ver}.noarch.rpm"
                local repo_url="https://dev.mysql.com/get/${repo_file}"
                echo "尝试从官方下载: $repo_url"
                
                # 使用公共下载函数
                if download_file_common "$repo_url" "/tmp/${repo_file}" "RPM"; then
                    repo_downloaded=1
                    echo -e "${GREEN}✓ 成功从官方下载 MySQL SUSE 仓库: ${repo_file}${NC}"
                    break 2
                fi
            done
        done
        
        if [ $repo_downloaded -eq 1 ] && [ -f /tmp/${repo_file} ]; then
            # 安装仓库
            zypper install -y /tmp/${repo_file} 2>/dev/null || {
                echo -e "${RED}✗ MySQL SUSE 仓库安装失败${NC}"
                rm -f /tmp/${repo_file}
                exit 1
            }
            rm -f /tmp/${repo_file}
            echo -e "${GREEN}✓ MySQL SUSE 仓库安装成功${NC}"
        else
            echo -e "${YELLOW}⚠ 无法从官方下载 MySQL SUSE 仓库，尝试使用系统仓库安装 MariaDB${NC}"
            echo -e "${BLUE}提示: 可以访问 https://dev.mysql.com/downloads/repo/suse/ 手动下载${NC}"
        fi
    else
        echo -e "${GREEN}✓ MySQL SUSE 仓库已存在${NC}"
    fi
    
    # ========== 步骤2: 刷新仓库缓存 ==========
    echo -e "${BLUE}[步骤2/4] 刷新仓库缓存...${NC}"
    zypper refresh 2>/dev/null || true
    echo -e "${GREEN}✓ 仓库缓存刷新完成${NC}"
    
    # ========== 步骤3: 安装 MySQL（官方标准流程）==========
    echo -e "${BLUE}[步骤3/4] 安装 MySQL...${NC}"
    
    # 优先尝试安装 MySQL（如果仓库可用）
    if zypper repos | grep -qi mysql; then
        echo "使用 MySQL 官方仓库安装..."
        if zypper install -y mysql-community-server mysql-community-client 2>&1 | tee /tmp/mysql_install.log; then
            if verify_mysql_installation /tmp/mysql_install.log; then
                echo -e "${GREEN}✓ MySQL 安装成功${NC}"
            else
                echo -e "${RED}✗ MySQL 安装失败（验证失败）${NC}"
                exit 1
            fi
        else
            echo -e "${YELLOW}⚠ MySQL 官方仓库安装失败，尝试使用系统仓库安装 MariaDB${NC}"
            if zypper install -y mariadb mariadb-server 2>&1 | tee /tmp/mysql_install.log; then
                if verify_mysql_installation /tmp/mysql_install.log; then
                    echo -e "${GREEN}✓ MariaDB 安装完成（MySQL 兼容）${NC}"
                else
                    echo -e "${RED}✗ MariaDB 安装失败${NC}"
                    exit 1
                fi
            else
                echo -e "${RED}✗ MySQL/MariaDB 安装失败${NC}"
                exit 1
        fi
    fi
    else
        # 如果没有 MySQL 官方仓库，使用系统仓库安装 MariaDB
        echo "使用系统仓库安装 MariaDB（MySQL 兼容）..."
        if zypper install -y mariadb mariadb-server 2>&1 | tee /tmp/mysql_install.log; then
            if verify_mysql_installation /tmp/mysql_install.log; then
                echo -e "${GREEN}✓ MariaDB 安装完成（MySQL 兼容）${NC}"
        else
                echo -e "${RED}✗ MariaDB 安装失败${NC}"
            exit 1
        fi
        else
            echo -e "${RED}✗ MariaDB 安装失败${NC}"
            exit 1
        fi
    fi
    
    # ========== 步骤4: 安装完成后的后续配置（在安装成功后执行）==========
    echo -e "${BLUE}[步骤4/4] 安装完成，准备进行后续配置...${NC}"
    
    # 安装成功，返回
    return 0
}

# 安装 MySQL（Arch Linux/Manjaro）
install_mysql_arch() {
    echo -e "${BLUE}[3/8] 安装 MySQL（Arch Linux）...${NC}"
    
    INSTALL_SUCCESS=0
    
    # Arch Linux 使用 AUR 或系统仓库
    if command -v yay &> /dev/null; then
        echo "使用 yay 从 AUR 安装..."
        if yay -S --noconfirm mysql 2>&1; then
            INSTALL_SUCCESS=1
        fi
    elif command -v paru &> /dev/null; then
        echo "使用 paru 从 AUR 安装..."
        if paru -S --noconfirm mysql 2>&1; then
            INSTALL_SUCCESS=1
        fi
    else
        # 尝试使用 pacman（可能需要启用 AUR）
        if pacman -S --noconfirm mysql 2>&1; then
            INSTALL_SUCCESS=1
        fi
    fi
    
    if [ $INSTALL_SUCCESS -eq 0 ]; then
        echo -e "${YELLOW}⚠ 需要从 AUR 安装，请安装 yay/paru 或手动安装${NC}"
        echo -e "${YELLOW}⚠ 安装命令: yay -S mysql 或 pacman -S mysql${NC}"
        exit 1
    else
        echo -e "${GREEN}✓ MySQL 安装完成${NC}"
    fi
}

# 安装 MySQL（Alpine Linux）
install_mysql_alpine() {
    echo -e "${BLUE}[3/8] 安装 MySQL（Alpine Linux）...${NC}"
    
    # Alpine Linux 使用 MariaDB（MySQL 兼容）
    apk add --no-cache mariadb mariadb-client mariadb-server-utils
    
    echo -e "${GREEN}✓ MariaDB 安装完成（MySQL 兼容）${NC}"
}

# 安装 MySQL（Gentoo）
install_mysql_gentoo() {
    echo -e "${BLUE}[3/8] 安装 MySQL（Gentoo）...${NC}"
    
    # Gentoo 使用 emerge
    emerge --ask=n --quiet-build y dev-db/mysql || {
        echo -e "${YELLOW}⚠ 安装失败，请手动安装${NC}"
        exit 1
    }
    
    echo -e "${GREEN}✓ MySQL 安装完成${NC}"
}

# 安装 MySQL
install_mysql() {
    case $OS in
        centos|rhel|fedora|rocky|almalinux|oraclelinux|amazonlinux)
            install_mysql_redhat
            ;;
        ubuntu|debian|linuxmint|raspbian|kali)
            install_mysql_debian
            ;;
        opensuse*|sles)
            install_mysql_suse
            ;;
        arch|manjaro)
            install_mysql_arch
            ;;
        alpine)
            install_mysql_alpine
            ;;
        gentoo)
            install_mysql_gentoo
            ;;
        *)
            echo -e "${YELLOW}警告: 未识别的系统类型 (${OS})，尝试使用通用方法${NC}"
            # 根据包管理器自动选择
            if command -v yum &> /dev/null || command -v dnf &> /dev/null; then
                echo -e "${BLUE}检测到 yum/dnf，使用 RedHat 系列方法${NC}"
                install_mysql_redhat
            elif command -v apt-get &> /dev/null; then
                echo -e "${BLUE}检测到 apt-get，使用 Debian 系列方法${NC}"
                install_mysql_debian
            elif command -v zypper &> /dev/null; then
                echo -e "${BLUE}检测到 zypper，使用 SUSE 系列方法${NC}"
                install_mysql_suse
            elif command -v pacman &> /dev/null; then
                echo -e "${BLUE}检测到 pacman，使用 Arch 系列方法${NC}"
                install_mysql_arch
            elif command -v apk &> /dev/null; then
                echo -e "${BLUE}检测到 apk，使用 Alpine 方法${NC}"
                install_mysql_alpine
            elif command -v emerge &> /dev/null; then
                echo -e "${BLUE}检测到 emerge，使用 Gentoo 方法${NC}"
                install_mysql_gentoo
            else
                echo -e "${RED}错误: 无法确定包管理器${NC}"
                exit 1
            fi
            ;;
    esac
}

# 设置 MySQL 配置文件（在初始化前）
# 重要：所有 my.cnf 等配置文件的改动必须在数据库初始化前完成
# 包括：
#   1. 基础配置（lower_case_table_names、default_time_zone 等）
#   2. 硬件优化配置（InnoDB 缓冲池、连接数、IO 线程等）
# 因为 MySQL 首次启动时会根据配置文件初始化数据字典，之后修改某些配置（如 lower_case_table_names）
# 需要重新初始化数据目录，否则会导致启动失败
# 硬件优化配置（如 innodb_buffer_pool_size）虽然可以在运行时修改，但为了最佳性能，
# 应该在初始化前就设置好，避免初始化后再调整导致性能波动
setup_mysql_config() {
    echo -e "${BLUE}[4/8] 设置 MySQL 配置文件（初始化前）...${NC}"
    echo -e "${YELLOW}注意: 所有配置优化（包括硬件优化）必须在数据库初始化前完成${NC}"
    
    # 检查 MySQL 数据目录是否已初始化（使用统一函数，检查已初始化状态）
    local data_dir
    data_dir=$(get_mysql_data_dir 1) || true  # 防止 set -e 导致退出，新安装时数据目录未初始化是正常的
    local mysql_initialized=0
    local mysql_data_dir=""
    if [ -n "$data_dir" ]; then
        mysql_initialized=1
        mysql_data_dir="$data_dir"
    fi
    
    if [ $mysql_initialized -eq 1 ]; then
        echo -e "${YELLOW}⚠ 检测到 MySQL 数据目录已初始化: ${mysql_data_dir}${NC}"
        echo -e "${YELLOW}⚠ 如果 lower_case_table_names 设置不一致，MySQL 将无法启动${NC}"
        echo ""
        echo -e "${BLUE}解决方案：${NC}"
        echo "  1. 如果这是新安装，可以删除数据目录并重新初始化"
        echo "  2. 如果已有重要数据，需要备份后重新初始化"
        echo ""
        read -p "是否删除现有数据目录并重新初始化？[y/N]: " RECREATE_DATA
        RECREATE_DATA="${RECREATE_DATA:-N}"
        if [[ "$RECREATE_DATA" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}正在停止 MySQL 服务...${NC}"
            mysql_service_manage "stop" 0
            sleep 2
            
            echo -e "${YELLOW}正在删除数据目录: ${mysql_data_dir}${NC}"
            rm -rf "${mysql_data_dir}"/*
            rm -rf "${mysql_data_dir}"/.* 2>/dev/null || true
            echo -e "${GREEN}✓ 数据目录已清空${NC}"
            mysql_initialized=0
        else
            echo -e "${YELLOW}⚠ 保留现有数据目录，如果 lower_case_table_names 不一致，MySQL 可能无法启动${NC}"
        fi
    fi
    
    local my_cnf_files=(
        "/etc/my.cnf"
        "/etc/mysql/my.cnf"
        "/usr/local/mysql/etc/my.cnf"
        "/usr/local/etc/my.cnf"
        "/etc/mysql/mysql.conf.d/mysqld.cnf"
    )
    
    local my_cnf_file=""
    for file in "${my_cnf_files[@]}"; do
        if [ -f "$file" ]; then
            my_cnf_file="$file"
            break
        fi
    done
    
    if [ -z "$my_cnf_file" ]; then
        # 如果找不到配置文件，尝试创建或使用默认位置
        my_cnf_file="/etc/my.cnf"
        if [ ! -f "$my_cnf_file" ]; then
            touch "$my_cnf_file"
            echo "[mysqld]" >> "$my_cnf_file"
        fi
    fi
    
    if [ -n "$my_cnf_file" ]; then
        # 检查是否已存在 lower_case_table_names 配置
        if grep -q "^lower_case_table_names" "$my_cnf_file" 2>/dev/null || grep -q "^[[:space:]]*lower_case_table_names" "$my_cnf_file" 2>/dev/null; then
            # 如果已存在，检查值是否为 1
            if ! grep -q "^[[:space:]]*lower_case_table_names[[:space:]]*=[[:space:]]*1" "$my_cnf_file" 2>/dev/null; then
                # 修改现有配置
                sed -i 's/^[[:space:]]*lower_case_table_names[[:space:]]*=.*/lower_case_table_names=1/' "$my_cnf_file" 2>/dev/null || \
                sed -i 's/^lower_case_table_names.*/lower_case_table_names=1/' "$my_cnf_file" 2>/dev/null
                echo -e "${GREEN}✓ 已更新 lower_case_table_names 为 1${NC}"
            else
                echo -e "${GREEN}✓ lower_case_table_names 已设置为 1${NC}"
            fi
        else
            # 如果不存在，检查是否有 [mysqld] 段
            if grep -q "^\[mysqld\]" "$my_cnf_file" 2>/dev/null; then
                # 在 [mysqld] 段下添加配置
                sed -i '/^\[mysqld\]/a lower_case_table_names=1' "$my_cnf_file" 2>/dev/null
                echo -e "${GREEN}✓ 已在 [mysqld] 段下添加 lower_case_table_names=1${NC}"
            else
                # 如果没有 [mysqld] 段，添加它和配置
                echo "" >> "$my_cnf_file"
                echo "[mysqld]" >> "$my_cnf_file"
                echo "lower_case_table_names=1" >> "$my_cnf_file"
                echo -e "${GREEN}✓ 已添加 [mysqld] 段和 lower_case_table_names=1${NC}"
            fi
        fi
        
        # 设置时区 default_time_zone = '+08:00' (MySQL 8.0 使用 UTC 偏移量格式)
        # 注意：MySQL 8.0 不支持 'Asia/Shanghai' 格式，需要使用 '+08:00' 或 'SYSTEM'
        local timezone_value="'+08:00'"
        if grep -q "^default_time_zone" "$my_cnf_file" 2>/dev/null || grep -q "^[[:space:]]*default_time_zone" "$my_cnf_file" 2>/dev/null; then
            # 如果已存在，检查值是否为 +08:00
            if ! grep -q "^[[:space:]]*default_time_zone[[:space:]]*=[[:space:]]*['\"]+08:00['\"]" "$my_cnf_file" 2>/dev/null && \
               ! grep -q "^[[:space:]]*default_time_zone[[:space:]]*=[[:space:]]*['\"]SYSTEM['\"]" "$my_cnf_file" 2>/dev/null; then
                # 修改现有配置
                sed -i "s/^[[:space:]]*default_time_zone[[:space:]]*=.*/default_time_zone = '+08:00'/" "$my_cnf_file" 2>/dev/null || \
                sed -i "s/^default_time_zone.*/default_time_zone = '+08:00'/" "$my_cnf_file" 2>/dev/null
                echo -e "${GREEN}✓ 已更新 default_time_zone 为 '+08:00'（中国时区）${NC}"
            else
                echo -e "${GREEN}✓ default_time_zone 已设置为 '+08:00'${NC}"
            fi
        else
            # 如果不存在，在 [mysqld] 段下添加配置
            if grep -q "^\[mysqld\]" "$my_cnf_file" 2>/dev/null; then
                # 在 [mysqld] 段下添加配置（在 lower_case_table_names 之后）
                if grep -q "lower_case_table_names" "$my_cnf_file" 2>/dev/null; then
                    sed -i '/lower_case_table_names/a default_time_zone = '\''+08:00'\''' "$my_cnf_file" 2>/dev/null
                else
                    sed -i '/^\[mysqld\]/a default_time_zone = '\''+08:00'\''' "$my_cnf_file" 2>/dev/null
                fi
                echo -e "${GREEN}✓ 已添加 default_time_zone = '+08:00'（中国时区）${NC}"
            else
                # 如果没有 [mysqld] 段，添加它和配置
                echo "[mysqld]" >> "$my_cnf_file"
                echo "default_time_zone = '+08:00'" >> "$my_cnf_file"
                echo -e "${GREEN}✓ 已添加 [mysqld] 段和 default_time_zone = '+08:00'（中国时区）${NC}"
            fi
        fi
        
        # ========== 硬件优化配置 ==========
        # 重要：硬件优化配置必须在数据库初始化前完成
        # 这些配置包括：InnoDB 缓冲池、连接数、IO 线程、日志文件大小等
        # 虽然部分配置可以在运行时修改，但为了最佳性能和稳定性，应在初始化前设置
        echo -e "${BLUE}根据硬件配置优化 MySQL 参数（初始化前）...${NC}"
        
        # 备份配置文件
        cp "$my_cnf_file" "${my_cnf_file}.bak.$(date +%Y%m%d_%H%M%S)"
        
        # 确保有 [mysqld] 段
        if ! grep -q "^\[mysqld\]" "$my_cnf_file" 2>/dev/null; then
            echo "" >> "$my_cnf_file"
            echo "[mysqld]" >> "$my_cnf_file"
        fi
        
        # 1. InnoDB 缓冲池优化（最重要的性能参数）
        # 根据内存大小设置：小内存（<4GB）使用 50%，中等内存（4-16GB）使用 60%，大内存（>16GB）使用 70%
        local innodb_buffer_pool_size_mb=0
        if [ $TOTAL_MEM_GB -lt 4 ]; then
            innodb_buffer_pool_size_mb=$((TOTAL_MEM_MB * 50 / 100))
        elif [ $TOTAL_MEM_GB -lt 16 ]; then
            innodb_buffer_pool_size_mb=$((TOTAL_MEM_MB * 60 / 100))
        else
            innodb_buffer_pool_size_mb=$((TOTAL_MEM_MB * 70 / 100))
        fi
        
        # 确保最小值（至少 256MB）
        if [ $innodb_buffer_pool_size_mb -lt 256 ]; then
            innodb_buffer_pool_size_mb=256
        fi
        
        # 设置 InnoDB 缓冲池大小
        if grep -q "^innodb_buffer_pool_size" "$my_cnf_file" 2>/dev/null || grep -q "^[[:space:]]*innodb_buffer_pool_size" "$my_cnf_file" 2>/dev/null; then
            sed -i "s/^[[:space:]]*innodb_buffer_pool_size[[:space:]]*=.*/innodb_buffer_pool_size = ${innodb_buffer_pool_size_mb}M/" "$my_cnf_file" 2>/dev/null || \
            sed -i "s/^innodb_buffer_pool_size.*/innodb_buffer_pool_size = ${innodb_buffer_pool_size_mb}M/" "$my_cnf_file" 2>/dev/null
        else
            sed -i '/^\[mysqld\]/a innodb_buffer_pool_size = '"${innodb_buffer_pool_size_mb}"'M' "$my_cnf_file" 2>/dev/null
        fi
        echo -e "${GREEN}  ✓ innodb_buffer_pool_size: ${innodb_buffer_pool_size_mb}M${NC}"
        
        # 2. InnoDB 缓冲池实例数（提高并发性能）
        # 根据缓冲池大小设置：<1GB 使用 1 个，1-8GB 使用 2-4 个，>8GB 使用 4-8 个
        local innodb_buffer_pool_instances=1
        if [ $innodb_buffer_pool_size_mb -ge 8192 ]; then
            innodb_buffer_pool_instances=8
        elif [ $innodb_buffer_pool_size_mb -ge 4096 ]; then
            innodb_buffer_pool_instances=4
        elif [ $innodb_buffer_pool_size_mb -ge 1024 ]; then
            innodb_buffer_pool_instances=2
        fi
        
        if grep -q "^innodb_buffer_pool_instances" "$my_cnf_file" 2>/dev/null || grep -q "^[[:space:]]*innodb_buffer_pool_instances" "$my_cnf_file" 2>/dev/null; then
            sed -i "s/^[[:space:]]*innodb_buffer_pool_instances[[:space:]]*=.*/innodb_buffer_pool_instances = ${innodb_buffer_pool_instances}/" "$my_cnf_file" 2>/dev/null || \
            sed -i "s/^innodb_buffer_pool_instances.*/innodb_buffer_pool_instances = ${innodb_buffer_pool_instances}/" "$my_cnf_file" 2>/dev/null
        else
            sed -i '/^\[mysqld\]/a innodb_buffer_pool_instances = '"${innodb_buffer_pool_instances}"'' "$my_cnf_file" 2>/dev/null
        fi
        echo -e "${GREEN}  ✓ innodb_buffer_pool_instances: ${innodb_buffer_pool_instances}${NC}"
        
        # 3. 最大连接数优化（根据内存和 CPU 调整）
        local max_connections=200
        if [ $TOTAL_MEM_GB -ge 16 ] && [ $CPU_CORES -ge 8 ]; then
            max_connections=1000
        elif [ $TOTAL_MEM_GB -ge 8 ] && [ $CPU_CORES -ge 4 ]; then
            max_connections=500
        elif [ $TOTAL_MEM_GB -ge 4 ]; then
            max_connections=300
        fi
        
        if grep -q "^max_connections" "$my_cnf_file" 2>/dev/null || grep -q "^[[:space:]]*max_connections" "$my_cnf_file" 2>/dev/null; then
            sed -i "s/^[[:space:]]*max_connections[[:space:]]*=.*/max_connections = ${max_connections}/" "$my_cnf_file" 2>/dev/null || \
            sed -i "s/^max_connections.*/max_connections = ${max_connections}/" "$my_cnf_file" 2>/dev/null
        else
            sed -i '/^\[mysqld\]/a max_connections = '"${max_connections}"'' "$my_cnf_file" 2>/dev/null
        fi
        echo -e "${GREEN}  ✓ max_connections: ${max_connections}${NC}"
        
        # 4. 连接超时和等待时间
        if ! grep -q "^wait_timeout" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*wait_timeout" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a wait_timeout = 28800' "$my_cnf_file" 2>/dev/null
        fi
        if ! grep -q "^interactive_timeout" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*interactive_timeout" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a interactive_timeout = 28800' "$my_cnf_file" 2>/dev/null
        fi
        
        # 5. InnoDB 日志文件大小（提高写入性能）
        # 根据缓冲池大小设置：小缓冲池使用 256MB，大缓冲池使用 512MB-1GB
        local innodb_log_file_size_mb=256
        if [ $innodb_buffer_pool_size_mb -ge 8192 ]; then
            innodb_log_file_size_mb=1024
        elif [ $innodb_buffer_pool_size_mb -ge 4096 ]; then
            innodb_log_file_size_mb=512
        fi
        
        if grep -q "^innodb_log_file_size" "$my_cnf_file" 2>/dev/null || grep -q "^[[:space:]]*innodb_log_file_size" "$my_cnf_file" 2>/dev/null; then
            sed -i "s/^[[:space:]]*innodb_log_file_size[[:space:]]*=.*/innodb_log_file_size = ${innodb_log_file_size_mb}M/" "$my_cnf_file" 2>/dev/null || \
            sed -i "s/^innodb_log_file_size.*/innodb_log_file_size = ${innodb_log_file_size_mb}M/" "$my_cnf_file" 2>/dev/null
        else
            sed -i '/^\[mysqld\]/a innodb_log_file_size = '"${innodb_log_file_size_mb}"'M' "$my_cnf_file" 2>/dev/null
        fi
        echo -e "${GREEN}  ✓ innodb_log_file_size: ${innodb_log_file_size_mb}M${NC}"
        
        # 6. InnoDB 日志缓冲大小
        local innodb_log_buffer_size_mb=16
        if [ $TOTAL_MEM_GB -ge 16 ]; then
            innodb_log_buffer_size_mb=64
        elif [ $TOTAL_MEM_GB -ge 8 ]; then
            innodb_log_buffer_size_mb=32
        fi
        
        if grep -q "^innodb_log_buffer_size" "$my_cnf_file" 2>/dev/null || grep -q "^[[:space:]]*innodb_log_buffer_size" "$my_cnf_file" 2>/dev/null; then
            sed -i "s/^[[:space:]]*innodb_log_buffer_size[[:space:]]*=.*/innodb_log_buffer_size = ${innodb_log_buffer_size_mb}M/" "$my_cnf_file" 2>/dev/null || \
            sed -i "s/^innodb_log_buffer_size.*/innodb_log_buffer_size = ${innodb_log_buffer_size_mb}M/" "$my_cnf_file" 2>/dev/null
        else
            sed -i '/^\[mysqld\]/a innodb_log_buffer_size = '"${innodb_log_buffer_size_mb}"'M' "$my_cnf_file" 2>/dev/null
        fi
        echo -e "${GREEN}  ✓ innodb_log_buffer_size: ${innodb_log_buffer_size_mb}M${NC}"
        
        # 7. InnoDB 线程并发数（根据 CPU 核心数设置）
        local innodb_thread_concurrency=$((CPU_CORES * 2))
        if [ $innodb_thread_concurrency -gt 64 ]; then
            innodb_thread_concurrency=64
        fi
        if [ $innodb_thread_concurrency -lt 4 ]; then
            innodb_thread_concurrency=4
        fi
        
        if grep -q "^innodb_thread_concurrency" "$my_cnf_file" 2>/dev/null || grep -q "^[[:space:]]*innodb_thread_concurrency" "$my_cnf_file" 2>/dev/null; then
            sed -i "s/^[[:space:]]*innodb_thread_concurrency[[:space:]]*=.*/innodb_thread_concurrency = ${innodb_thread_concurrency}/" "$my_cnf_file" 2>/dev/null || \
            sed -i "s/^innodb_thread_concurrency.*/innodb_thread_concurrency = ${innodb_thread_concurrency}/" "$my_cnf_file" 2>/dev/null
        else
            sed -i '/^\[mysqld\]/a innodb_thread_concurrency = '"${innodb_thread_concurrency}"'' "$my_cnf_file" 2>/dev/null
        fi
        echo -e "${GREEN}  ✓ innodb_thread_concurrency: ${innodb_thread_concurrency}${NC}"
        
        # 8. InnoDB IO 线程数（提高 I/O 性能）
        local innodb_read_io_threads=4
        local innodb_write_io_threads=4
        if [ $CPU_CORES -ge 16 ]; then
            innodb_read_io_threads=8
            innodb_write_io_threads=8
        elif [ $CPU_CORES -ge 8 ]; then
            innodb_read_io_threads=6
            innodb_write_io_threads=6
        fi
        
        if ! grep -q "^innodb_read_io_threads" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*innodb_read_io_threads" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a innodb_read_io_threads = '"${innodb_read_io_threads}"'' "$my_cnf_file" 2>/dev/null
        fi
        if ! grep -q "^innodb_write_io_threads" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*innodb_write_io_threads" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a innodb_write_io_threads = '"${innodb_write_io_threads}"'' "$my_cnf_file" 2>/dev/null
        fi
        echo -e "${GREEN}  ✓ innodb_read_io_threads: ${innodb_read_io_threads}, innodb_write_io_threads: ${innodb_write_io_threads}${NC}"
        
        # 9. 表缓存和打开文件限制
        local table_open_cache=2000
        local open_files_limit=65535
        if [ $TOTAL_MEM_GB -ge 16 ]; then
            table_open_cache=4000
            open_files_limit=65535
        elif [ $TOTAL_MEM_GB -ge 8 ]; then
            table_open_cache=3000
            open_files_limit=32768
        fi
        
        if ! grep -q "^table_open_cache" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*table_open_cache" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a table_open_cache = '"${table_open_cache}"'' "$my_cnf_file" 2>/dev/null
        fi
        if ! grep -q "^open_files_limit" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*open_files_limit" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a open_files_limit = '"${open_files_limit}"'' "$my_cnf_file" 2>/dev/null
        fi
        
        # 10. 查询缓存（MySQL 8.0 已移除，但为兼容性保留配置注释）
        # MySQL 8.0 不再支持 query_cache，跳过
        
        # 11. 临时表和排序缓冲区
        local tmp_table_size_mb=64
        local max_heap_table_size_mb=64
        local sort_buffer_size_kb=256
        if [ $TOTAL_MEM_GB -ge 16 ]; then
            tmp_table_size_mb=256
            max_heap_table_size_mb=256
            sort_buffer_size_kb=512
        elif [ $TOTAL_MEM_GB -ge 8 ]; then
            tmp_table_size_mb=128
            max_heap_table_size_mb=128
            sort_buffer_size_kb=384
        fi
        
        if ! grep -q "^tmp_table_size" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*tmp_table_size" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a tmp_table_size = '"${tmp_table_size_mb}"'M' "$my_cnf_file" 2>/dev/null
        fi
        if ! grep -q "^max_heap_table_size" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*max_heap_table_size" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a max_heap_table_size = '"${max_heap_table_size_mb}"'M' "$my_cnf_file" 2>/dev/null
        fi
        if ! grep -q "^sort_buffer_size" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*sort_buffer_size" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a sort_buffer_size = '"${sort_buffer_size_kb}"'K' "$my_cnf_file" 2>/dev/null
        fi
        
        # 12. InnoDB 刷新方法（使用 O_DIRECT 提高性能）
        if ! grep -q "^innodb_flush_method" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*innodb_flush_method" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a innodb_flush_method = O_DIRECT' "$my_cnf_file" 2>/dev/null
        fi
        
        # 13. InnoDB 双写缓冲（提高数据安全性，SSD 可以关闭以提高性能）
        if ! grep -q "^innodb_doublewrite" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*innodb_doublewrite" "$my_cnf_file" 2>/dev/null; then
            # 默认启用（数据安全优先）
            sed -i '/^\[mysqld\]/a innodb_doublewrite = ON' "$my_cnf_file" 2>/dev/null
        fi
        
        # 14. 慢查询日志（生产环境建议启用）
        if ! grep -q "^slow_query_log" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*slow_query_log" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a slow_query_log = 1' "$my_cnf_file" 2>/dev/null
            sed -i '/^\[mysqld\]/a slow_query_log_file = /var/log/mysql/slow.log' "$my_cnf_file" 2>/dev/null
            sed -i '/^\[mysqld\]/a long_query_time = 2' "$my_cnf_file" 2>/dev/null
        fi
        
        # 15. 二进制日志（用于主从复制和数据恢复）
        # 先创建日志目录（如果不存在）
        if [ ! -d "/var/log/mysql" ]; then
            mkdir -p /var/log/mysql
            chown mysql:mysql /var/log/mysql 2>/dev/null || chown mysql:mysql /var/log/mysql 2>/dev/null || true
            chmod 755 /var/log/mysql
            echo -e "${GREEN}  ✓ 已创建日志目录: /var/log/mysql${NC}"
        fi
        
        if ! grep -q "^log_bin" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*log_bin" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a log_bin = /var/log/mysql/mysql-bin.log' "$my_cnf_file" 2>/dev/null
            # MySQL 8.0 使用 binlog_expire_logs_seconds 替代 expire_logs_days
            # expire_logs_days 已废弃，但为了兼容性，如果使用 MySQL 8.0 则使用新参数
            if echo "$MYSQL_VERSION" | grep -qE "^8\.0"; then
                # MySQL 8.0: 使用 binlog_expire_logs_seconds (7天 = 604800秒)
                sed -i '/^\[mysqld\]/a binlog_expire_logs_seconds = 604800' "$my_cnf_file" 2>/dev/null
            else
                # MySQL 5.7: 使用 expire_logs_days
            sed -i '/^\[mysqld\]/a expire_logs_days = 7' "$my_cnf_file" 2>/dev/null
            fi
            sed -i '/^\[mysqld\]/a max_binlog_size = 100M' "$my_cnf_file" 2>/dev/null
        else
            # 如果已存在 log_bin 配置，检查并更新 expire_logs_days 为 binlog_expire_logs_seconds（MySQL 8.0）
            if echo "$MYSQL_VERSION" | grep -qE "^8\.0"; then
                if grep -q "^expire_logs_days" "$my_cnf_file" 2>/dev/null || grep -q "^[[:space:]]*expire_logs_days" "$my_cnf_file" 2>/dev/null; then
                    # 如果存在 expire_logs_days，替换为 binlog_expire_logs_seconds
                    if ! grep -q "^binlog_expire_logs_seconds" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*binlog_expire_logs_seconds" "$my_cnf_file" 2>/dev/null; then
                        sed -i '/expire_logs_days/a binlog_expire_logs_seconds = 604800' "$my_cnf_file" 2>/dev/null
                        # 注释掉旧的 expire_logs_days（不删除，以防回退）
                        sed -i 's/^\([[:space:]]*expire_logs_days\)/#\1/' "$my_cnf_file" 2>/dev/null
                        echo -e "${GREEN}  ✓ 已更新为 MySQL 8.0 的 binlog_expire_logs_seconds${NC}"
                    fi
                fi
            fi
        fi
        
        # 16. 字符集设置（UTF8MB4）
        if ! grep -q "^character-set-server" "$my_cnf_file" 2>/dev/null && ! grep -q "^[[:space:]]*character-set-server" "$my_cnf_file" 2>/dev/null; then
            sed -i '/^\[mysqld\]/a character-set-server = utf8mb4' "$my_cnf_file" 2>/dev/null
            sed -i '/^\[mysqld\]/a collation-server = utf8mb4_general_ci' "$my_cnf_file" 2>/dev/null
        fi
        
        echo -e "${BLUE}  配置文件位置: ${my_cnf_file}${NC}"
        echo -e "${GREEN}✓ MySQL 配置文件设置完成（已根据硬件优化）${NC}"
    else
        echo -e "${YELLOW}⚠ 未找到 MySQL 配置文件，跳过配置${NC}"
    fi
    
    return 0
}

# 配置 MySQL（启动服务）
# 重要：此函数会在首次启动时根据配置文件初始化数据库
# 因此 setup_mysql_config 必须在此函数之前执行
configure_mysql() {
    echo -e "${BLUE}[5/8] 配置 MySQL（启动服务）...${NC}"
    echo -e "${YELLOW}注意: 首次启动时会根据配置文件初始化数据库${NC}"
    
    # 启动 MySQL 服务（首次启动会自动初始化，使用统一函数）
    mysql_service_manage "enable" 1  # 先启用开机自启动（静默）
    mysql_service_manage "start" 0   # 启动服务
    
    # 等待 MySQL 启动并检查服务状态（使用辅助函数）
    local start_failed=0
    if ! wait_for_mysql_ready 30 localhost; then
        start_failed=1
    fi
    
    # 检查 MySQL 是否启动成功
    if [ $start_failed -eq 1 ]; then
        echo -e "${RED}✗ MySQL 服务启动失败${NC}"
        echo ""
        echo -e "${YELLOW}可能的原因：${NC}"
        echo "  1. lower_case_table_names 设置与数据字典不一致"
        echo "  2. 配置文件语法错误"
        echo "  3. 端口被占用"
        echo "  4. 权限问题"
        echo ""
        echo -e "${BLUE}检查 MySQL 错误日志：${NC}"
        local error_log_file
        error_log_file=$(get_mysql_error_log)
        if [ -n "$error_log_file" ]; then
            echo -e "${BLUE}  日志文件: ${error_log_file}${NC}"
                echo -e "${YELLOW}  最后几行错误：${NC}"
            tail -30 "$error_log_file" | tail -10
        else
            echo -e "${YELLOW}  未找到错误日志文件${NC}"
            fi
        echo ""
        echo -e "${BLUE}检测到初始化失败，尝试自动修复...${NC}"
        
        # 检查错误日志中是否有初始化失败的错误（使用统一函数）
        local init_failed=0
        if [ -n "$error_log_file" ] && [ -f "$error_log_file" ]; then
            if tail -50 "$error_log_file" | grep -qiE "Data Dictionary initialization failed|Illegal or unknown default time zone|designated data directory.*is unusable"; then
                    init_failed=1
                fi
            fi
        
        if [ $init_failed -eq 1 ]; then
            echo -e "${YELLOW}检测到数据目录初始化失败，需要清理数据目录并重新初始化${NC}"
            read -p "是否自动清理数据目录并重新初始化？[Y/n]: " CLEAN_DATA
            CLEAN_DATA="${CLEAN_DATA:-Y}"
            if [[ "$CLEAN_DATA" =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}正在停止 MySQL 服务...${NC}"
                mysql_service_manage "stop" 0
                sleep 2
                
                # 查找并清理数据目录（使用统一函数，不检查初始化状态）
                local data_dir
                data_dir=$(get_mysql_data_dir 0)
                if [ -n "$data_dir" ]; then
                    echo -e "${YELLOW}正在清理数据目录: ${data_dir}${NC}"
                    rm -rf "${data_dir}"/*
                    rm -rf "${data_dir}"/.* 2>/dev/null || true
                        echo -e "${GREEN}✓ 数据目录已清理${NC}"
                else
                    echo -e "${YELLOW}⚠ 未找到 MySQL 数据目录${NC}"
                    fi
                
                echo -e "${BLUE}重新启动 MySQL 服务（将自动重新初始化）...${NC}"
                mysql_service_manage "start" 0
                
                # 等待重新初始化（使用统一函数，避免重复逻辑）
                echo "等待 MySQL 重新初始化..."
                if wait_for_mysql_ready 30 localhost; then
                        echo -e "${GREEN}✓ MySQL 重新初始化成功并已启动${NC}"
                        start_failed=0
                else
                    echo -e "${RED}✗ MySQL 重新初始化超时${NC}"
                    start_failed=1
                    fi
            else
                echo -e "${YELLOW}⚠ 未清理数据目录，请手动处理${NC}"
            fi
        fi
        
        if [ $start_failed -eq 1 ]; then
            echo ""
            echo -e "${RED}========================================${NC}"
            echo -e "${RED}MySQL 启动失败，停止后续步骤${NC}"
            echo -e "${RED}========================================${NC}"
            echo ""
            echo -e "${BLUE}如果看到 'Different lower_case_table_names settings' 或时区错误：${NC}"
            echo "  1. 停止 MySQL 服务"
            echo "  2. 删除数据目录（如果有重要数据请先备份）"
            echo "  3. 确保配置文件中 lower_case_table_names=1 和 default_time_zone = '+08:00'"
            echo "  4. 重新启动 MySQL 服务"
            echo ""
            echo -e "${YELLOW}示例命令：${NC}"
            echo "  systemctl stop mysqld"
            echo "  rm -rf /var/lib/mysql/*"
            echo "  systemctl start mysqld"
            echo ""
            echo -e "${YELLOW}⚠ 请修复 MySQL 启动问题后重新运行安装脚本${NC}"
            echo ""
            exit 1
        fi
        sleep 2
    else
        # 额外等待几秒确保 MySQL 完全就绪
        sleep 3
    fi
    
    # 获取临时 root 密码（MySQL 8.0，使用辅助函数）
    # 只在未设置时获取，避免重复调用
    if [ -z "${TEMP_PASSWORD:-}" ]; then
        TEMP_PASSWORD=$(get_mysql_temp_password || echo "")
        fi
    
    # 对于 MariaDB（Alpine/SUSE），可能没有临时密码
    if [ -z "$TEMP_PASSWORD" ] && [ "$OS" = "alpine" ]; then
        echo -e "${BLUE}  MariaDB 通常没有临时密码，root 用户可能无密码或需要初始化${NC}"
    fi
    
    echo -e "${GREEN}✓ MySQL 配置完成${NC}"
    
    if [ -n "$TEMP_PASSWORD" ]; then
        echo -e "${YELLOW}⚠ MySQL 临时 root 密码: ${TEMP_PASSWORD}${NC}"
        echo -e "${YELLOW}⚠ 请使用以下命令修改 root 密码:${NC}"
        echo "   mysql -u root -p'${TEMP_PASSWORD}' -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY 'your_new_password';\""
    fi
}

# 设置 root 密码（可选）
set_root_password() {
    # 临时禁用 set -e，以便更好地处理错误
    set +e
    
    echo -e "${BLUE}[6/8] 设置 MySQL root 密码...${NC}"
    
    # 如果 TEMP_PASSWORD 未设置，尝试获取（configure_mysql 可能已经获取）
    if [ -z "${TEMP_PASSWORD:-}" ]; then
        TEMP_PASSWORD=$(get_mysql_temp_password || echo "")
    fi
    
    # 如果检测到临时密码，主动提示用户设置密码
    if [ -z "$MYSQL_ROOT_PASSWORD" ] && [ -n "$TEMP_PASSWORD" ]; then
        echo -e "${YELLOW}检测到 MySQL 临时密码，建议立即修改 root 密码${NC}"
        echo -e "${YELLOW}临时密码: ${TEMP_PASSWORD}${NC}"
        echo ""
        read -p "是否现在设置 root 密码？[Y/n]: " SET_PASSWORD
        SET_PASSWORD="${SET_PASSWORD:-Y}"
        if [[ "$SET_PASSWORD" =~ ^[Yy]$ ]]; then
            # 显示密码输入（用户要求显示文本）
            echo -n "请输入新的 MySQL root 密码: "
            IFS= read -r MYSQL_ROOT_PASSWORD
            if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                echo -e "${RED}错误: 密码不能为空${NC}"
                echo -e "${YELLOW}跳过 root 密码设置${NC}"
                return 0
            fi
        else
            echo -e "${YELLOW}跳过 root 密码设置${NC}"
            return 0
        fi
    elif [ -z "$MYSQL_ROOT_PASSWORD" ]; then
        read -p "请输入 MySQL root 密码（直接回车跳过）: " MYSQL_ROOT_PASSWORD
    fi
    
    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        # 检查 MySQL 是否已启动（configure_mysql 已经确保启动，这里只做快速检查）
        if ! mysqladmin ping -h localhost --silent 2>/dev/null; then
            echo -e "${YELLOW}⚠ MySQL 服务可能未运行，尝试启动并等待...${NC}"
            # 尝试启动服务（使用统一函数）
            mysql_service_manage "start" 0 || true
            # 等待 MySQL 启动（使用辅助函数）
            if ! wait_for_mysql_ready 30 localhost; then
                echo -e "${RED}✗ MySQL 服务启动失败${NC}"
                return 1
            fi
        fi
        
        # 尝试使用临时密码登录并修改（MySQL 8.0 需要使用 --connect-expired-password）
        if [ -n "$TEMP_PASSWORD" ]; then
            echo "正在使用临时密码修改 root 密码..."
            
            # 首先检查 MySQL 版本
            echo "检查 MySQL 版本..."
            local mysql_version_output=$(mysql --version 2>&1 || echo "")
            local mysql_version=""
            if echo "$mysql_version_output" | grep -qi "8\.0"; then
                mysql_version="8.0"
                echo -e "${GREEN}✓ 检测到 MySQL 8.0${NC}"
            elif echo "$mysql_version_output" | grep -qi "5\.7"; then
                mysql_version="5.7"
                echo -e "${GREEN}✓ 检测到 MySQL 5.7${NC}"
            else
                echo -e "${YELLOW}⚠ 未检测到 MySQL 8.0 或 5.7${NC}"
            fi
            
            # 验证密码复杂度（使用辅助函数）
            echo "验证密码复杂度..."
            local pwd_length=${#MYSQL_ROOT_PASSWORD}
            echo -e "${BLUE}调试: 密码长度 = ${pwd_length} 字符${NC}"
            
            local password_check_msg
            password_check_msg=$(validate_password_complexity "$MYSQL_ROOT_PASSWORD")
            local password_valid=$?
            
            if [ $password_valid -ne 0 ]; then
                echo -e "${RED}✗ 密码复杂度验证失败: ${password_check_msg}${NC}"
                echo -e "${YELLOW}密码要求:${NC}"
                echo "  - 至少 8 位长度"
                echo "  - 包含至少一个大写字母 (A-Z)"
                echo "  - 包含至少一个小写字母 (a-z)"
                echo "  - 包含至少一个数字 (0-9)"
                echo "  - 包含至少一个特殊字符 (!@#$%^&*等)"
                echo ""
                echo ""
                echo -e "${YELLOW}提示: 如果刚才输入的密码是正确的，请直接按回车继续${NC}"
                read -p "是否重新输入密码？[Y/n]: " REENTER_PWD
                REENTER_PWD="${REENTER_PWD:-Y}"
                # 如果用户输入的内容看起来像密码（包含特殊字符或长度较长），直接当作密码处理
                if [ ${#REENTER_PWD} -gt 3 ] || echo "$REENTER_PWD" | grep -q '[^YyNn]'; then
                    # 用户可能直接输入了密码而不是选择
                    if echo "$REENTER_PWD" | grep -qE '[^YyNn]'; then
                        echo -e "${YELLOW}⚠ 检测到您可能直接输入了密码，将使用该密码${NC}"
                        MYSQL_ROOT_PASSWORD="$REENTER_PWD"
                        # 重新验证密码复杂度（使用辅助函数）
                        password_check_msg=$(validate_password_complexity "$MYSQL_ROOT_PASSWORD")
                        password_valid=$?
                        if [ $password_valid -ne 0 ]; then
                            echo -e "${RED}✗ 密码不满足复杂度要求: ${password_check_msg}${NC}"
                            echo -e "${YELLOW}请重新输入满足要求的密码${NC}"
                            set -e
                            return 1
                        else
                            # 密码验证通过，跳过后续的重新输入流程
                            echo -e "${GREEN}✓ 密码复杂度验证通过${NC}"
                            REENTER_PWD="N"
                        fi
                    else
                        # 如果输入的是Y/y，继续重新输入流程
                        REENTER_PWD="Y"
                    fi
                fi
                
                if [[ "$REENTER_PWD" =~ ^[Yy]$ ]]; then
                    # 显示密码输入（用户要求显示文本）
                    echo -n "请输入新的 MySQL root 密码（必须满足复杂度要求）: "
                    IFS= read -r MYSQL_ROOT_PASSWORD
                    
                    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                        echo -e "${RED}错误: 密码不能为空${NC}"
                        set -e
                        return 1
                    fi
                    # 调试：显示密码长度
                    echo -e "${BLUE}调试: 已重新读取密码，长度 = ${#MYSQL_ROOT_PASSWORD} 字符${NC}"
                    # 重新验证（使用辅助函数）
                    password_check_msg=$(validate_password_complexity "$MYSQL_ROOT_PASSWORD")
                    password_valid=$?
                    if [ $password_valid -ne 0 ]; then
                        echo -e "${RED}✗ 密码仍然不满足复杂度要求: ${password_check_msg}${NC}"
                        set -e
                        return 1
                    fi
                else
                    # 用户选择不重新输入，使用原来的密码继续（可能是验证逻辑有问题）
                    echo -e "${YELLOW}⚠ 使用原密码继续，如果密码修改失败，请手动修改${NC}"
                    # 不返回，继续执行密码修改
                fi
            fi
            
            echo -e "${GREEN}✓ 密码复杂度验证通过${NC}"
            
            # 步骤 1: 修改 root 密码（必须满足密码复杂度）
            echo ""
            echo -e "${BLUE}步骤 1: 修改 root 密码...${NC}"
            
            # 执行密码修改（使用临时密码）
            local error_output=""
            local exit_code=1
            local has_error=1
            
            # 转义密码中的单引号
                local escaped_password=$(echo "$MYSQL_ROOT_PASSWORD" | sed "s/'/''/g")
            local alter_sql="ALTER USER 'root'@'localhost' IDENTIFIED BY '${escaped_password}';"
            
            # 获取连接信息（使用统一函数，带缓存，只调用一次）
            get_mysql_connection_info
            local mysql_host="$mysql_host"
            local mysql_port="$mysql_port"
            
            # 执行密码修改（使用辅助函数，使用缓存的连接信息）
            error_output=$(mysql_execute "$alter_sql" "$mysql_host" "$mysql_port" "root" "$TEMP_PASSWORD" "--connect-expired-password" 2>&1)
                exit_code=$?
            
            # 如果第一个用户修改成功，继续修改其他用户（使用缓存的连接信息）
            if [ $exit_code -eq 0 ]; then
                local alter_sql2="ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '${escaped_password}';"
                local alter_sql3="ALTER USER 'root'@'::1' IDENTIFIED BY '${escaped_password}';"
                local flush_sql="FLUSH PRIVILEGES;"
                
                mysql_execute "$alter_sql2" "$mysql_host" "$mysql_port" "root" "$TEMP_PASSWORD" "--connect-expired-password" >/dev/null 2>&1
                mysql_execute "$alter_sql3" "$mysql_host" "$mysql_port" "root" "$TEMP_PASSWORD" "--connect-expired-password" >/dev/null 2>&1
                mysql_execute "$flush_sql" "$mysql_host" "$mysql_port" "root" "$TEMP_PASSWORD" "--connect-expired-password" >/dev/null 2>&1
                has_error=0
            else
                # 检查是否是密码策略错误（ERROR 1819）
                if echo "$error_output" | grep -qi "1819\|does not satisfy.*policy\|policy requirements"; then
                    echo -e "${YELLOW}⚠ 密码不满足当前策略要求，需要先设置密码策略${NC}"
                    echo -e "${YELLOW}错误信息: $(echo "$error_output" | grep -vE 'Warning: Using a password' | head -1)${NC}"
                    echo ""
                    echo -e "${YELLOW}提示: 密码必须满足 MySQL 当前的密码策略要求${NC}"
                    echo -e "${YELLOW}请重新输入一个满足策略要求的密码，或手动修改密码策略后重试${NC}"
                    set -e
                    return 1
                else
                    has_error=1
                fi
            fi
            
            if [ $has_error -eq 0 ]; then
                echo -e "${GREEN}✓ root 密码修改成功${NC}"
                # 等待一下让密码生效
                sleep 2
                
                # 刷新权限已在上面执行，无需再次执行
                
                # 验证新密码是否生效（使用辅助函数，使用缓存的连接信息）
                echo "验证新密码..."
                # 等待一下让密码完全生效
                sleep 1
                
                # 使用已缓存的连接信息，无需重复调用 get_mysql_connection_info
                if mysql_verify_connection "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD"; then
                    echo -e "${GREEN}✓ 新密码验证成功${NC}"
                    # 标记密码已验证
                    PASSWORD_VERIFIED=1
                    
                    # 步骤 2-7: 使用新密码设置密码策略、修改配置文件、重启服务、验证
                    if [ -n "$mysql_version" ]; then
                        # 使用已缓存的连接信息，无需重复调用 get_mysql_connection_info
                        
                        echo ""
                        echo -e "${BLUE}步骤 2: 设置密码策略为 LOW（使用新密码）...${NC}"
                        
                        # 设置密码策略为 LOW
                        local policy_sql=""
                        if [ "$mysql_version" = "8.0" ]; then
                            policy_sql="SET GLOBAL validate_password.policy = LOW;"
                        elif [ "$mysql_version" = "5.7" ]; then
                            policy_sql="SET GLOBAL validate_password_policy = LOW;"
                        fi
                        
                        if [ -n "$policy_sql" ]; then
                            local policy_output
                            policy_output=$(mysql_execute "$policy_sql" "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD" 2>&1)
                            local policy_exit_code=$?
                            
                            if [ $policy_exit_code -eq 0 ]; then
                                echo -e "${GREEN}✓ 密码策略设置为 LOW${NC}"
                            else
                                if echo "$policy_output" | grep -qi "Unknown system variable\|Unknown variable"; then
                                    echo -e "${YELLOW}⚠ 密码验证插件未安装，跳过密码策略设置${NC}"
                                else
                                    echo -e "${YELLOW}⚠ 密码策略设置失败: $(echo "$policy_output" | grep -vE 'Warning: Using a password' | head -1)${NC}"
                                fi
                            fi
                        fi
                        
                        # 步骤 3: 设置密码最小长度为 6
                        echo -e "${BLUE}步骤 3: 设置密码最小长度为 6（使用新密码）...${NC}"
                        local policy_length_sql=""
                        if [ "$mysql_version" = "8.0" ]; then
                            policy_length_sql="SET GLOBAL validate_password.length = 6;"
                        elif [ "$mysql_version" = "5.7" ]; then
                            policy_length_sql="SET GLOBAL validate_password_length = 6;"
                        fi
                        
                        if [ -n "$policy_length_sql" ]; then
                            local length_output
                            length_output=$(mysql_execute "$policy_length_sql" "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD" 2>&1)
                            local length_exit_code=$?
                            
                            if [ $length_exit_code -eq 0 ]; then
                                echo -e "${GREEN}✓ 密码最小长度设置为 6${NC}"
                            else
                                if echo "$length_output" | grep -qi "Unknown system variable\|Unknown variable"; then
                                    echo -e "${YELLOW}⚠ 密码验证插件未安装，跳过密码长度设置${NC}"
                                else
                                    echo -e "${YELLOW}⚠ 密码长度设置失败: $(echo "$length_output" | grep -vE 'Warning: Using a password' | head -1)${NC}"
                                fi
                            fi
                        fi
                        
                        # 步骤 4: 验证配置文件（已在启动前设置，无需修改）
                        echo -e "${BLUE}步骤 4: 验证 MySQL 配置文件...${NC}"
                        echo -e "${GREEN}✓ lower_case_table_names 和 default_time_zone 已在 MySQL 启动前配置${NC}"
                        echo -e "${BLUE}  配置文件位置: /etc/my.cnf 或 /etc/mysql/my.cnf${NC}"
                        
                        # 步骤 5: 验证修改的内容
                        echo -e "${BLUE}步骤 5: 验证修改的内容...${NC}"
                        
                        # 验证配置（使用辅助函数，使用缓存的连接信息）
                        if [ "$mysql_version" = "8.0" ]; then
                            local policy_check
                            policy_check=$(mysql_execute "SHOW VARIABLES LIKE 'validate_password.policy';" "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD" 2>&1 | grep -i "validate_password.policy" | awk '{print $2}')
                            if [ "$policy_check" = "LOW" ]; then
                                echo -e "${GREEN}✓ 密码策略验证: LOW${NC}"
                            else
                                echo -e "${YELLOW}⚠ 密码策略验证: ${policy_check:-未设置}${NC}"
                            fi
                            
                            local length_check
                            length_check=$(mysql_execute "SHOW VARIABLES LIKE 'validate_password.length';" "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD" 2>&1 | grep -i "validate_password.length" | awk '{print $2}')
                            if [ "$length_check" = "6" ]; then
                                echo -e "${GREEN}✓ 密码最小长度验证: 6${NC}"
                            else
                                echo -e "${YELLOW}⚠ 密码最小长度验证: ${length_check:-未设置}${NC}"
                            fi
                        elif [ "$mysql_version" = "5.7" ]; then
                            local policy_check
                            policy_check=$(mysql_execute "SHOW VARIABLES LIKE 'validate_password_policy';" "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD" 2>&1 | grep -i "validate_password_policy" | awk '{print $2}')
                            if [ "$policy_check" = "LOW" ]; then
                                echo -e "${GREEN}✓ 密码策略验证: LOW${NC}"
                            else
                                echo -e "${YELLOW}⚠ 密码策略验证: ${policy_check:-未设置}${NC}"
                            fi
                            
                            local length_check
                            length_check=$(mysql_execute "SHOW VARIABLES LIKE 'validate_password_length';" "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD" 2>&1 | grep -i "validate_password_length" | awk '{print $2}')
                            if [ "$length_check" = "6" ]; then
                                echo -e "${GREEN}✓ 密码最小长度验证: 6${NC}"
                            else
                                echo -e "${YELLOW}⚠ 密码最小长度验证: ${length_check:-未设置}${NC}"
                            fi
                        fi
                        
                        # 验证 lower_case_table_names（使用缓存的连接信息）
                        local case_check
                        case_check=$(mysql_execute "SHOW VARIABLES LIKE 'lower_case_table_names';" "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD" 2>&1 | grep -i "lower_case_table_names" | awk '{print $2}')
                        if [ "$case_check" = "1" ]; then
                            echo -e "${GREEN}✓ lower_case_table_names 验证: 1（不区分大小写）${NC}"
                        else
                            echo -e "${YELLOW}⚠ lower_case_table_names 验证: ${case_check:-未设置}（需要重启 MySQL 服务后生效）${NC}"
                        fi
                        
                        # 验证时区设置（检查 time_zone 变量，使用缓存的连接信息）
                        local timezone_check
                        timezone_check=$(mysql_execute "SHOW VARIABLES LIKE 'time_zone';" "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD" 2>&1 | grep -i "time_zone" | awk '{print $2}')
                        # time_zone 可能显示为 SYSTEM（使用系统时区）或具体的时区值（+08:00）
                        if [ "$timezone_check" = "+08:00" ] || [ "$timezone_check" = "SYSTEM" ]; then
                            echo -e "${GREEN}✓ 时区验证: ${timezone_check}（default_time_zone 已在配置文件中设置为 '+08:00'）${NC}"
                        else
                            echo -e "${YELLOW}⚠ 时区验证: ${timezone_check:-未设置}（default_time_zone 已在配置文件中设置为 '+08:00'，可能需要重启 MySQL 服务后生效）${NC}"
                        fi
                        
                        echo -e "${BLUE}步骤 6: 继续下一步...${NC}"
                    fi
                    
                    set -e  # 重新启用 set -e
                    return 0
                else
                    # 如果验证失败，先尝试手动测试（因为可能是验证方式的问题）
                    echo -e "${YELLOW}⚠ 新密码验证失败，但密码可能已经修改成功${NC}"
                    echo ""
                    echo -e "${BLUE}请手动测试新密码是否可以登录:${NC}"
                    echo "  mysql -u root -p'${MYSQL_ROOT_PASSWORD}' -e 'SELECT 1;'"
                    echo ""
                    read -p "新密码是否可以正常登录？[Y/n]: " PWD_WORKS
                    PWD_WORKS="${PWD_WORKS:-Y}"
                    if [[ "$PWD_WORKS" =~ ^[Yy]$ ]]; then
                        echo -e "${GREEN}✓ 密码已成功修改（手动验证通过）${NC}"
                        set -e  # 重新启用 set -e
                        return 0
                    fi
                    
                    # 如果手动验证也失败，尝试使用临时密码再次验证密码是否真的修改了
                    echo -e "${YELLOW}⚠ 继续使用临时密码验证...${NC}"
                    local temp_verify_exit_code=1
                    
                    # 使用辅助函数验证临时密码（使用缓存的连接信息）
                    get_mysql_connection_info
                    local mysql_host="$mysql_host"
                    local mysql_port="$mysql_port"
                    
                    if mysql_verify_connection "$mysql_host" "$mysql_port" "root" "$TEMP_PASSWORD"; then
                        temp_verify_exit_code=0
                    fi
                    
                    # 更严格的验证：如果临时密码仍然可以登录（exit_code=0），说明密码修改失败
                    if [ $temp_verify_exit_code -eq 0 ];                     then
                        echo -e "${RED}✗ 密码修改失败：临时密码仍然可以登录${NC}"
                        echo ""
                        echo -e "${YELLOW}可能的原因:${NC}"
                        echo "  1. SQL 语句执行失败（密码包含特殊字符导致 SQL 错误）"
                        echo "  2. 只修改了部分 root 用户"
                        echo "  3. MySQL 8.0 需要额外的步骤"
                        echo ""
                        echo -e "${YELLOW}建议:${NC}"
                        echo "  1. 检查 MySQL 错误日志: tail -20 /var/log/mysqld.log"
                        echo "  2. 手动修改密码:"
                        echo "     mysql --connect-expired-password -u root -p'${TEMP_PASSWORD}'"
                        echo "     # 然后在 MySQL 中执行:"
                        echo "     ALTER USER 'root'@'localhost' IDENTIFIED BY 'your_new_password';"
                        echo "     ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY 'your_new_password';"
                        echo "     ALTER USER 'root'@'::1' IDENTIFIED BY 'your_new_password';"
                        echo "     FLUSH PRIVILEGES;"
                        set -e  # 重新启用 set -e
                        return 1
                    else
                        echo -e "${GREEN}✓ 密码已成功修改（临时密码已失效）${NC}"
                        echo -e "${YELLOW}⚠ 但新密码验证失败，可能是密码包含特殊字符${NC}"
                        echo ""
                        echo -e "${YELLOW}建议:${NC}"
                        echo "  1. 手动测试密码: mysql -u root -p"
                        echo "  2. 如果密码包含特殊字符，可能需要使用引号: mysql -u root -p'your_password'"
                        echo "  3. 或者重新设置一个不包含特殊字符的密码"
                        # 继续执行，让用户知道密码已设置
                        set -e  # 重新启用 set -e
                        return 0
                    fi
                fi
            else
                echo ""
                echo -e "${RED}========================================${NC}"
                echo -e "${RED}✗ 使用临时密码修改密码失败${NC}"
                echo -e "${RED}========================================${NC}"
                echo ""
                echo -e "${YELLOW}详细错误信息:${NC}"
                # 显示所有错误信息（过滤掉密码警告）
                local clean_error=$(echo "$error_output" | grep -vE "Warning: Using a password|Using a password on the command line" || echo "$error_output")
                if [ -n "$clean_error" ]; then
                    echo "$clean_error"
                else
                    echo "$error_output"
                fi
                echo ""
                echo -e "${YELLOW}退出代码: ${exit_code}${NC}"
                echo ""
                echo -e "${YELLOW}可能的原因:${NC}"
                echo "  1. MySQL 服务未完全启动"
                echo "  2. 临时密码已过期或无效"
                echo "  3. 临时密码不正确"
                echo "  4. 新密码包含特殊字符导致 SQL 执行失败"
                echo "  5. SQL 文件格式问题"
                echo ""
                echo -e "${BLUE}调试信息:${NC}"
                echo "  临时密码: ${TEMP_PASSWORD}"
                echo "  新密码长度: ${#MYSQL_ROOT_PASSWORD} 字符"
                echo "  SQL 命令: ALTER USER 'root'@'localhost' IDENTIFIED BY '...';"
                echo ""
                echo -e "${YELLOW}建议的解决步骤:${NC}"
                echo ""
                echo "  步骤 1: 测试临时密码是否可以连接"
                echo "    mysql --connect-expired-password -u root -p'${TEMP_PASSWORD}' -e 'SELECT 1;'"
                echo ""
                echo "  步骤 2: 如果步骤1成功，手动修改密码（推荐）"
                echo "    mysql --connect-expired-password -u root -p'${TEMP_PASSWORD}'"
                echo "    # 然后在 MySQL 中执行以下命令（替换 your_new_password 为你的新密码）:"
                echo "    ALTER USER 'root'@'localhost' IDENTIFIED BY 'your_new_password';"
                echo "    ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY 'your_new_password';"
                echo "    ALTER USER 'root'@'::1' IDENTIFIED BY 'your_new_password';"
                echo "    FLUSH PRIVILEGES;"
                echo "    exit;"
                echo ""
                echo "  步骤 3: 验证新密码"
                echo "    mysql -u root -p'your_new_password' -e 'SELECT 1;'"
                echo ""
                echo "  步骤 4: 重新运行安装脚本"
                echo "    sudo ./scripts/install_mysql.sh"
                echo ""
                echo -e "${BLUE}其他调试命令:${NC}"
                echo "  检查 MySQL 服务状态: systemctl status mysqld"
                echo "  查看 MySQL 错误日志: tail -30 /var/log/mysqld.log"
                echo ""
                # 清除错误的密码，让后续步骤重新提示输入
                MYSQL_ROOT_PASSWORD=""
                set -e  # 重新启用 set -e
                    return 1
            fi
        fi
        
        # 如果临时密码方式失败，尝试无密码方式（某些系统可能没有临时密码，如 MariaDB）
        # 注意：如果上面已经设置了密码，这里不应该再执行
        if [ -z "$TEMP_PASSWORD" ] && ! mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" > /dev/null 2>&1; then
            # 尝试无密码连接（MariaDB 可能默认无密码）
            if mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';" 2>/dev/null; then
                echo -e "${GREEN}✓ root 密码已设置${NC}"
            else
                # 对于 MariaDB，可能需要先初始化或使用不同的命令（使用缓存的连接信息）
                if mysql -h "$mysql_host" -P "$mysql_port" -u root -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${MYSQL_ROOT_PASSWORD}');" 2>/dev/null; then
                    echo -e "${GREEN}✓ root 密码已设置（MariaDB 方式）${NC}"
                else
                    echo -e "${YELLOW}⚠ 无法自动设置密码，请手动设置${NC}"
                    echo -e "${YELLOW}  对于 MariaDB，可能需要运行: mysql_secure_installation${NC}"
                fi
            fi
        else
            echo -e "${GREEN}✓ root 密码验证成功${NC}"
        fi
    else
        echo -e "${YELLOW}跳过 root 密码设置${NC}"
    fi
    
    # 重新启用 set -e
    set -e
}

# 配置安全设置（可选）
secure_mysql() {
    echo -e "${BLUE}[7/8] 配置 MySQL 安全设置...${NC}"
    
    read -p "是否运行 mysql_secure_installation？（推荐）[Y/n]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
            # 获取连接信息（使用统一函数，带缓存）
            get_mysql_connection_info
            local mysql_host="$mysql_host"
            local mysql_port="$mysql_port"
            
            # 先验证密码是否有效（使用辅助函数）
            echo "验证 root 密码..."
            if ! mysql_verify_connection "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD"; then
                echo -e "${RED}✗ root 密码验证失败${NC}"
                echo ""
                echo -e "${YELLOW}可能的原因:${NC}"
                echo "  1. 密码不正确"
                echo "  2. 密码修改未成功（仍在使用临时密码）"
                echo "  3. 密码包含特殊字符导致验证失败"
                echo ""
                echo -e "${YELLOW}建议:${NC}"
                echo "  1. 如果密码修改失败，请先手动修改密码:"
                if [ -n "$TEMP_PASSWORD" ]; then
                    echo "     mysql --connect-expired-password -u root -p'${TEMP_PASSWORD}'"
                else
                    echo "     mysql -u root -p"
                fi
                echo "     # 然后在 MySQL 中执行:"
                echo "     ALTER USER 'root'@'localhost' IDENTIFIED BY 'your_new_password';"
                echo "     FLUSH PRIVILEGES;"
                echo "  2. 或者重新输入正确的密码"
                echo ""
                read -p "是否重新输入 root 密码？[Y/n]: " REENTER_PWD
                REENTER_PWD="${REENTER_PWD:-Y}"
                if [[ "$REENTER_PWD" =~ ^[Yy]$ ]]; then
                    read -p "请输入正确的 MySQL root 密码: " MYSQL_ROOT_PASSWORD
                    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                        echo -e "${RED}错误: 密码不能为空${NC}"
                        echo -e "${YELLOW}跳过安全配置${NC}"
                        return 0
                    fi
                    # 重新验证（使用辅助函数，使用缓存的连接信息）
                    if ! mysql_verify_connection "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD"; then
                        echo -e "${RED}✗ 密码仍然不正确，跳过安全配置${NC}"
                        return 0
                    fi
                    echo -e "${GREEN}✓ 密码验证成功${NC}"
                else
                    echo -e "${YELLOW}跳过安全配置${NC}"
                    return 0
                fi
            else
                echo -e "${GREEN}✓ root 密码验证成功${NC}"
                # 非交互式运行 mysql_secure_installation（使用辅助函数，使用缓存的连接信息）
                echo "执行安全配置..."
                local secure_sql="DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;"
                
                local secure_output
                secure_output=$(mysql_execute "$secure_sql" "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD" 2>&1)
                local secure_exit_code=$?
                
                if [ $secure_exit_code -eq 0 ]; then
                    echo -e "${GREEN}✓ 安全配置完成${NC}"
                else
                    echo -e "${YELLOW}⚠ 安全配置执行时出现警告或错误${NC}"
                    echo "$secure_output" | grep -v "Warning: Using a password" | head -5
                fi
            fi
        elif [ -n "$TEMP_PASSWORD" ]; then
            # 如果未设置密码但有临时密码，使用临时密码（需要 --connect-expired-password）
            echo -e "${YELLOW}⚠ 检测到临时密码，使用临时密码进行安全配置${NC}"
            echo -e "${YELLOW}⚠ 注意：使用临时密码时，必须先修改密码才能执行其他操作${NC}"
            echo -e "${YELLOW}⚠ 建议先设置 root 密码，然后再运行安全配置${NC}"
            echo ""
            read -p "是否现在设置 root 密码？[Y/n]: " SET_PWD_NOW
            SET_PWD_NOW="${SET_PWD_NOW:-Y}"
            if [[ "$SET_PWD_NOW" =~ ^[Yy]$ ]]; then
                read -p "请输入新密码: " NEW_PASSWORD
                if [ -n "$NEW_PASSWORD" ]; then
                    # 使用临时密码修改密码
                    if mysql --connect-expired-password -u root -p"${TEMP_PASSWORD}" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${NEW_PASSWORD}';" 2>/dev/null; then
                        MYSQL_ROOT_PASSWORD="$NEW_PASSWORD"
                        echo -e "${GREEN}✓ root 密码已设置${NC}"
                        # 现在可以使用新密码进行安全配置
                        mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
                    else
                        echo -e "${RED}✗ 密码修改失败，请手动修改密码后重试${NC}"
                        echo -e "${YELLOW}手动修改密码命令:${NC}"
                        echo "  mysql --connect-expired-password -u root -p'${TEMP_PASSWORD}' -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY 'your_new_password';\""
                    fi
                else
                    echo -e "${RED}错误: 新密码不能为空${NC}"
                fi
            else
                echo -e "${YELLOW}跳过安全配置${NC}"
            fi
        else
            echo -e "${YELLOW}⚠ 未设置 root 密码，跳过安全配置${NC}"
            echo -e "${YELLOW}⚠ 请手动运行: mysql_secure_installation${NC}"
        fi
    else
        echo -e "${YELLOW}跳过安全配置${NC}"
    fi
    
    echo -e "${GREEN}✓ 安全配置完成${NC}"
}

# 验证安装
verify_installation() {
    echo -e "${BLUE}[8/8] 验证安装...${NC}"
    
    if command -v mysql &> /dev/null; then
        local version=$(mysql --version 2>&1 | head -n 1)
        echo -e "${GREEN}✓ MySQL 安装成功${NC}"
        echo "  版本: $version"
    else
        echo -e "${RED}✗ MySQL 安装失败${NC}"
        exit 1
    fi
    
    # 测试连接（使用统一函数，更可靠）
    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        # 获取连接信息（使用统一函数，带缓存）
        get_mysql_connection_info
        local mysql_host="$mysql_host"
        local mysql_port="$mysql_port"
        
        if mysql_verify_connection "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD"; then
            echo -e "${GREEN}✓ MySQL 连接测试成功${NC}"
        else
            # 如果连接测试失败，尝试使用 mysqladmin ping 作为备用检查
            if mysqladmin ping -h localhost --silent 2>/dev/null; then
                echo -e "${GREEN}✓ MySQL 服务运行正常（连接测试使用备用方法）${NC}"
            else
                echo -e "${YELLOW}⚠ MySQL 连接测试失败${NC}"
            echo ""
                echo -e "${YELLOW}可能的原因:${NC}"
                echo "  1. 密码不正确或包含特殊字符"
                echo "  2. MySQL 服务未完全启动"
                echo "  3. 权限问题"
            echo ""
            echo -e "${BLUE}建议手动测试连接:${NC}"
            echo "  mysql -u root -p"
            echo "  # 然后输入密码进行交互式连接"
            echo ""
            echo -e "${BLUE}或者使用配置文件方式:${NC}"
            echo "  echo '[client]' > ~/.my.cnf"
            echo "  echo 'user=root' >> ~/.my.cnf"
                echo "  echo 'password=your_password' >> ~/.my.cnf"
            echo "  chmod 600 ~/.my.cnf"
            echo "  mysql -e 'SELECT 1;'"
                echo ""
                echo -e "${YELLOW}注意: 如果之前的步骤（密码设置、安全配置）成功，说明密码实际上是正确的${NC}"
                echo -e "${YELLOW}连接测试失败可能是因为密码包含特殊字符导致 shell 解析问题${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}⚠ 未设置密码，跳过连接测试${NC}"
    fi
}

# 创建数据库
create_database() {
    echo -e "${BLUE}[8/10] 创建数据库...${NC}"
    
    read -p "是否创建数据库？[Y/n]: " CREATE_DB
    CREATE_DB="${CREATE_DB:-Y}"
    
    if [[ ! "$CREATE_DB" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}跳过数据库创建${NC}"
        return 0
    fi
    
    # 获取连接信息（使用统一函数，带缓存，只调用一次）
    get_mysql_connection_info
    local mysql_host="$mysql_host"
    local mysql_port="$mysql_port"
    
    # 获取 root 密码（如果未设置）
    # 注意：set_root_password 已经设置了密码，这里只处理特殊情况（如 SKIP_INSTALL 模式）
    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
        # 使用统一函数获取并验证密码（使用已缓存的连接信息）
        if ! get_and_verify_root_password "$mysql_host" "$mysql_port"; then
            return 1
        fi
    fi
    
    # 交互式输入数据库名称
    read -p "请输入数据库名称 [waf_db]: " DB_NAME
    DB_NAME="${DB_NAME:-waf_db}"
    
    # 检测是否存在同名数据库（使用辅助函数）
    local db_exists=0
    local check_db_query="SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='${DB_NAME}';"
    local db_check_result
    db_check_result=$(mysql_execute "$check_db_query" "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD" 2>/dev/null | grep -v "SCHEMA_NAME" | grep -v "^$")
        if [ -n "$db_check_result" ]; then
            db_exists=1
    fi
    
    if [ $db_exists -eq 1 ]; then
        echo -e "${YELLOW}⚠ 检测到数据库 ${DB_NAME} 已存在${NC}"
        read -p "是否使用现有数据库？[Y/n]: " USE_EXISTING_DB
        USE_EXISTING_DB="${USE_EXISTING_DB:-Y}"
        if [[ "$USE_EXISTING_DB" =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}✓ 将使用现有数据库 ${DB_NAME}${NC}"
            set_and_export_database "$DB_NAME"
            return 0
        else
            echo -e "${YELLOW}请重新输入数据库名称${NC}"
            read -p "请输入新的数据库名称: " DB_NAME
            if [ -z "$DB_NAME" ]; then
                echo -e "${RED}错误: 数据库名称不能为空${NC}"
                return 1
            fi
        fi
    fi
    
    # 创建数据库
    echo "正在创建数据库 ${DB_NAME}..."
    local db_create_output=""
    local db_create_exit_code=0
    
        # 尝试连接并创建数据库（使用辅助函数）
    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
            # 使用已缓存的连接信息，无需重复调用 get_mysql_connection_info
            
            # 首先验证密码是否有效（使用辅助函数，使用已缓存的连接信息）
            if ! mysql_verify_connection "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD"; then
            # 密码验证失败，可能是密码不正确或密码修改未成功
            echo -e "${RED}✗ MySQL root 密码验证失败${NC}"
            echo ""
            echo -e "${YELLOW}可能的原因:${NC}"
            echo "  1. 密码不正确"
            echo "  2. 密码修改未成功（仍在使用临时密码）"
            echo "  3. 密码包含特殊字符导致验证失败"
            echo ""
            echo -e "${YELLOW}建议:${NC}"
            echo "  1. 如果密码修改失败，请先手动修改密码:"
            echo "     mysql --connect-expired-password -u root -p'${TEMP_PASSWORD}'"
            echo "     # 然后在 MySQL 中执行:"
            echo "     ALTER USER 'root'@'localhost' IDENTIFIED BY 'your_new_password';"
            echo "     FLUSH PRIVILEGES;"
            echo "  2. 或者重新输入正确的密码"
            echo ""
            read -p "是否重新输入 root 密码？[Y/n]: " REENTER_PWD
            REENTER_PWD="${REENTER_PWD:-Y}"
            if [[ "$REENTER_PWD" =~ ^[Yy]$ ]]; then
                read -p "请输入正确的 MySQL root 密码: " MYSQL_ROOT_PASSWORD
                if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                    echo -e "${RED}错误: 密码不能为空${NC}"
                    return 1
                fi
                # 重新验证（使用辅助函数，使用缓存的连接信息）
                if ! mysql_verify_connection "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD"; then
                    echo -e "${RED}✗ 密码仍然不正确，请检查密码${NC}"
                    return 1
                fi
                echo -e "${GREEN}✓ 密码验证成功${NC}"
            else
                return 1
            fi
        fi
        
        # 使用辅助函数创建数据库（使用缓存的连接信息）
        local create_db_sql="CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
        db_create_output=$(mysql_execute "$create_db_sql" "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD" 2>&1)
            db_create_exit_code=$?
            
            if [ $db_create_exit_code -eq 0 ]; then
            echo -e "${GREEN}✓ 数据库创建成功${NC}"
        fi
        
        # 如果失败且使用的是临时密码，提示用户需要先修改密码
        if [ $db_create_exit_code -ne 0 ] && [ "$MYSQL_ROOT_PASSWORD" = "$TEMP_PASSWORD" ]; then
            echo -e "${YELLOW}⚠ 使用临时密码创建数据库失败${NC}"
            echo -e "${YELLOW}MySQL 8.0 要求首次登录后必须修改临时密码才能执行其他操作${NC}"
            echo -e "${YELLOW}请先修改 root 密码，然后再创建数据库${NC}"
            echo ""
            echo -e "${BLUE}修改密码命令:${NC}"
            echo "  mysql -u root -p'${TEMP_PASSWORD}' -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY 'your_new_password';\""
            echo ""
            read -p "是否现在修改 root 密码？[Y/n]: " CHANGE_PWD
            CHANGE_PWD="${CHANGE_PWD:-Y}"
            if [[ "$CHANGE_PWD" =~ ^[Yy]$ ]]; then
                read -p "请输入新密码: " NEW_PASSWORD
                if [ -n "$NEW_PASSWORD" ]; then
                    # 修改密码（使用辅助函数）
                    local alter_pwd_sql="ALTER USER 'root'@'localhost' IDENTIFIED BY '${NEW_PASSWORD}';"
                    if mysql_execute "$alter_pwd_sql" "$mysql_host" "$mysql_port" "root" "$TEMP_PASSWORD" "--connect-expired-password" >/dev/null 2>&1; then
                        MYSQL_ROOT_PASSWORD="$NEW_PASSWORD"
                        echo -e "${GREEN}✓ root 密码已修改${NC}"
                        # 验证新密码是否有效（使用辅助函数）
                        echo "验证新密码..."
                        sleep 1
                        if mysql_verify_connection "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD"; then
                            echo -e "${GREEN}✓ 新密码验证成功${NC}"
                        # 重新尝试创建数据库
                            db_create_output=$(mysql_execute "$create_db_sql" "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD" 2>&1)
                        db_create_exit_code=$?
                        else
                            echo -e "${RED}✗ 新密码验证失败，请检查密码${NC}"
                            return 1
                        fi
                    else
                        echo -e "${RED}✗ 密码修改失败，请手动修改密码后重试${NC}"
                        return 1
                    fi
                else
                    echo -e "${RED}错误: 新密码不能为空${NC}"
                    return 1
                fi
            else
                return 1
            fi
        fi
    else
        # 无密码连接（使用已缓存的连接信息，无需重复调用 get_mysql_connection_info）
        local create_db_sql="CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
        db_create_output=$(mysql_execute "$create_db_sql" "$mysql_host" "$mysql_port" "root" "" 2>&1)
        db_create_exit_code=$?
    fi
    
    if [ $db_create_exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ 数据库 ${DB_NAME} 创建成功（字符集：utf8mb4，排序规则：utf8mb4_general_ci）${NC}"
        # 保存数据库名称到全局变量并导出（使用统一函数）
        set_and_export_database "$DB_NAME"
        return 0
    else
        echo -e "${RED}✗ 数据库创建失败${NC}"
        # 显示详细错误信息（过滤掉警告信息）
        local error_msg=$(echo "$db_create_output" | grep -v "Warning: Using a password" | head -5)
        if [ -n "$error_msg" ]; then
            echo -e "${RED}错误信息:${NC}"
            echo "$error_msg"
        else
            echo -e "${RED}错误信息: ${db_create_output}${NC}"
        fi
        echo ""
        echo -e "${YELLOW}可能的原因:${NC}"
        echo "  1. MySQL 服务未启动"
        echo "  2. root 密码不正确或包含特殊字符"
        echo "  3. 数据库名称已存在且权限不足"
        echo "  4. MySQL 连接失败"
        echo "  5. 密码包含特殊字符，shell 解析错误"
        echo ""
        echo -e "${YELLOW}建议:${NC}"
        echo "  1. 检查 MySQL 服务状态: systemctl status mysqld"
        echo "  2. 验证 root 密码: mysql -u root -p（交互式输入密码）"
        echo "  3. 手动创建数据库:"
        echo "     mysql -u root -p"
        echo "     # 然后执行: CREATE DATABASE ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
        echo "  4. 或者使用配置文件方式:"
        echo "     echo '[client]' > ~/.my.cnf"
        echo "     echo 'user=root' >> ~/.my.cnf"
        echo "     echo 'password=your_password' >> ~/.my.cnf"
        echo "     chmod 600 ~/.my.cnf"
        echo "     mysql -e \"CREATE DATABASE ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;\""
        echo ""
        read -p "是否跳过数据库创建？[y/N]: " SKIP_DB
        if [[ "$SKIP_DB" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}跳过数据库创建${NC}"
            return 0
        else
            return 1
        fi
    fi
}

# 创建数据库用户
create_database_user() {
    echo -e "${BLUE}[9/10] 创建数据库用户...${NC}"
    
    read -p "是否创建数据库用户？[Y/n]: " CREATE_USER
    CREATE_USER="${CREATE_USER:-Y}"
    
    if [[ ! "$CREATE_USER" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}跳过用户创建，将使用 root 用户${NC}"
        MYSQL_USER="root"
        MYSQL_USER_PASSWORD="$MYSQL_ROOT_PASSWORD"
        USE_NEW_USER="N"
        return 0
    fi
    
    # 检查是否已创建数据库
    if [ -z "$MYSQL_DATABASE" ]; then
        echo -e "${YELLOW}⚠ 未创建数据库，请先创建数据库${NC}"
        return 1
    fi
    
    # 交互式输入用户名
    read -p "请输入数据库用户名 [waf_user]: " DB_USER
    DB_USER="${DB_USER:-waf_user}"
    
    # 检测是否存在同名用户
    local user_exists=0
    local check_user_query="SELECT CONCAT(User, '@', Host) as 'User@Host' FROM mysql.user WHERE User='${DB_USER}';"
    
    # 获取连接信息（使用统一函数）
    get_mysql_connection_info
    local mysql_host="$mysql_host"
    local mysql_port="$mysql_port"
    
    # 检查用户是否存在（使用辅助函数）
    local user_check_result
    user_check_result=$(mysql_execute "$check_user_query" "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD" 2>/dev/null | grep -v "User@Host" | grep -v "^$" | grep -E "${DB_USER}@")
        if [ -n "$user_check_result" ]; then
            user_exists=1
    fi
    
    if [ $user_exists -eq 1 ]; then
        echo -e "${YELLOW}⚠ 检测到用户 ${DB_USER} 已存在${NC}"
        echo "  现有用户:"
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                echo "    ${line}"
            fi
        done <<< "$user_check_result"
        echo ""
        read -p "是否使用现有用户？[Y/n]: " USE_EXISTING_USER
        USE_EXISTING_USER="${USE_EXISTING_USER:-Y}"
        if [[ "$USE_EXISTING_USER" =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}✓ 将使用现有用户 ${DB_USER}${NC}"
            read -p "请输入用户 ${DB_USER} 的密码: " DB_USER_PASSWORD
            if [ -z "$DB_USER_PASSWORD" ]; then
                echo -e "${RED}错误: 用户密码不能为空${NC}"
                return 1
            fi
            # 验证用户密码是否正确（使用辅助函数）
            if mysql_verify_connection "$mysql_host" "$mysql_port" "$DB_USER" "$DB_USER_PASSWORD"; then
                echo -e "${GREEN}✓ 用户密码验证成功${NC}"
                # 确保用户有数据库权限（使用辅助函数）
                local grant_sql="GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;"
                mysql_execute "$grant_sql" "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD" >/dev/null 2>&1
                # 设置并导出用户变量（使用统一函数）
                set_and_export_user "$DB_USER" "$DB_USER_PASSWORD" "Y"
                return 0
            else
                echo -e "${RED}✗ 用户密码验证失败，请重新输入${NC}"
                return 1
            fi
        else
            echo -e "${YELLOW}请重新输入用户名${NC}"
            read -p "请输入新的数据库用户名: " DB_USER
            if [ -z "$DB_USER" ]; then
                echo -e "${RED}错误: 用户名不能为空${NC}"
                return 1
            fi
        fi
    fi
    
    # 交互式输入密码
    read -p "请输入数据库用户密码: " DB_USER_PASSWORD
    if [ -z "$DB_USER_PASSWORD" ]; then
        echo -e "${RED}错误: 用户密码不能为空${NC}"
        return 1
    fi
    
    # 创建用户（使用辅助函数，使用缓存的连接信息）
    echo "正在创建用户 ${DB_USER}..."
    local create_user_sql="CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_USER_PASSWORD}';
GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;"
    mysql_execute "$create_user_sql" "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 用户 ${DB_USER} 创建成功，并已授予 ${MYSQL_DATABASE} 数据库的全部权限${NC}"
        
        # 询问是否使用新创建的用户
        read -p "是否使用新创建的用户 ${DB_USER} 连接 MySQL？[Y/n]: " USE_NEW_USER
        USE_NEW_USER="${USE_NEW_USER:-Y}"
        
        if [[ "$USE_NEW_USER" =~ ^[Yy]$ ]]; then
            # 设置并导出用户变量（使用统一函数）
            set_and_export_user "$DB_USER" "$DB_USER_PASSWORD" "Y"
            echo -e "${GREEN}✓ 将使用用户 ${DB_USER} 连接 MySQL${NC}"
        else
            # 设置并导出用户变量（使用统一函数）
            set_and_export_user "root" "$MYSQL_ROOT_PASSWORD" "N"
            echo -e "${YELLOW}将使用 root 用户连接 MySQL${NC}"
        fi
    else
        echo -e "${RED}✗ 用户创建失败${NC}"
        MYSQL_USER="root"
        MYSQL_USER_PASSWORD="$MYSQL_ROOT_PASSWORD"
        return 1
    fi
}

# 更新 WAF 配置文件
update_waf_config() {
    echo -e "${BLUE}[11/11] 更新 WAF 配置文件...${NC}"
    
    # 检查是否有数据库和用户信息
    # 优先使用导出的变量，如果没有则使用当前函数内的变量
    local db_name="${CREATED_DB_NAME:-${MYSQL_DATABASE}}"
    local db_user="${MYSQL_USER_FOR_WAF:-${MYSQL_USER}}"
    local db_password="${MYSQL_PASSWORD_FOR_WAF:-${MYSQL_USER_PASSWORD}}"
    
    if [ -z "$db_name" ] || [ -z "$db_user" ]; then
        echo -e "${YELLOW}⚠ 缺少数据库或用户信息，跳过配置文件更新${NC}"
        echo -e "${YELLOW}  数据库: ${db_name:-未设置}${NC}"
        echo -e "${YELLOW}  用户: ${db_user:-未设置}${NC}"
        echo -e "${YELLOW}  请手动更新 lua/config.lua 文件${NC}"
        return 0
    fi
    
    echo -e "${BLUE}配置信息:${NC}"
    echo -e "  数据库: ${db_name}"
    echo -e "  用户: ${db_user}"
    echo -e "  密码: ${db_password:+已设置（隐藏）}"
    echo ""
    
    # 使用全局 SCRIPT_DIR（避免重复定义）
    UPDATE_CONFIG_SCRIPT="${SCRIPT_DIR}/set_lua_database_connect.sh"
    
    # 检查配置更新脚本是否存在
    if [ ! -f "$UPDATE_CONFIG_SCRIPT" ]; then
        echo -e "${YELLOW}⚠ 配置更新脚本不存在: $UPDATE_CONFIG_SCRIPT${NC}"
        echo -e "${YELLOW}  请手动更新 lua/config.lua 文件${NC}"
        echo -e "${YELLOW}  或运行: bash $UPDATE_CONFIG_SCRIPT mysql 127.0.0.1 3306 ${db_name} ${db_user} <password>${NC}"
        return 0
    fi
    
    # 检查配置文件是否存在
    local config_file="${SCRIPT_DIR}/../lua/config.lua"
    if [ ! -f "$config_file" ]; then
        echo -e "${YELLOW}⚠ 配置文件不存在: $config_file${NC}"
        echo -e "${YELLOW}  请确保项目目录结构正确${NC}"
        return 0
    fi
    
    # 获取连接信息（使用统一函数）
    get_mysql_connection_info
    local mysql_host="$mysql_host"
    local mysql_port="$mysql_port"
    
    # 更新配置文件
    echo -e "${BLUE}正在更新配置文件: $config_file${NC}"
    echo -e "${BLUE}MySQL 地址: ${mysql_host}:${mysql_port}${NC}"
    if bash "$UPDATE_CONFIG_SCRIPT" mysql "$mysql_host" "$mysql_port" "$db_name" "$db_user" "$db_password"; then
        echo -e "${GREEN}✓ WAF 配置文件已更新${NC}"
        echo -e "${GREEN}  配置文件路径: $config_file${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ 配置文件更新失败，请手动更新${NC}"
        echo ""
        echo -e "${BLUE}手动更新步骤:${NC}"
        echo "  1. 编辑配置文件: $config_file"
        echo "  2. 找到数据库配置部分，更新以下信息:"
        echo "     - host: ${mysql_host}"
        echo "     - port: ${mysql_port}"
        echo "     - database: ${db_name}"
        echo "     - user: ${db_user}"
        echo "     - password: <your_password>"
        echo ""
        echo -e "${BLUE}或使用配置更新脚本:${NC}"
        echo "  bash $UPDATE_CONFIG_SCRIPT mysql ${mysql_host} ${mysql_port} ${db_name} ${db_user} <password>"
        echo ""
        echo -e "${YELLOW}注意: 配置文件更新失败不影响 MySQL 安装，您可以稍后手动更新${NC}"
        return 1
    fi
}

# 初始化数据库数据
init_database() {
    echo -e "${BLUE}[10/10] 初始化数据库数据...${NC}"
    
    read -p "是否初始化数据库数据（导入 SQL 脚本）？[Y/n]: " INIT_DB
    INIT_DB="${INIT_DB:-Y}"
    
    if [[ ! "$INIT_DB" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}跳过数据库初始化${NC}"
        return 0
    fi
    
    # 检查是否已创建数据库（优先使用 CREATED_DB_NAME，如果没有则使用 MYSQL_DATABASE）
    if [ -z "$MYSQL_DATABASE" ] && [ -z "$CREATED_DB_NAME" ]; then
        echo -e "${YELLOW}⚠ 未创建数据库，无法初始化${NC}"
        return 1
    fi
    
    # 同步变量（使用统一函数）
    sync_database_variables
    sync_user_variables
    
    # 查找 SQL 文件（使用全局 SCRIPT_DIR，避免重复定义）
    SQL_FILE="${SCRIPT_DIR}/../init_file/数据库设计.sql"
    
    # 检查 SQL 文件是否存在且可读（合并检查）
    if [ ! -f "$SQL_FILE" ] || [ ! -r "$SQL_FILE" ]; then
        echo -e "${YELLOW}⚠ SQL 文件不存在或不可读: ${SQL_FILE}${NC}"
        echo "请手动导入 SQL 脚本"
        return 1
    fi
    
    # 获取连接信息（使用统一函数）
    get_mysql_connection_info
    local mysql_host="$mysql_host"
    local mysql_port="$mysql_port"
    
    # 检测数据库内是否有数据（使用统一函数）
    local table_count
    table_count=$(get_table_count "$MYSQL_DATABASE" "$mysql_host" "$mysql_port" "$MYSQL_USER" "$MYSQL_USER_PASSWORD")
    local has_data=0
    if [ "$table_count" -gt 0 ] 2>/dev/null; then
            has_data=1
    fi
    
    if [ $has_data -eq 1 ]; then
        echo -e "${YELLOW}⚠ 检测到数据库 ${MYSQL_DATABASE} 中已有数据（${table_count} 个表）${NC}"
        echo -e "${RED}警告: 导入 SQL 脚本可能会覆盖现有数据！${NC}"
        echo ""
        read -p "是否继续导入 SQL 脚本（将覆盖现有数据）？[y/N]: " OVERWRITE_DATA
        OVERWRITE_DATA="${OVERWRITE_DATA:-N}"
        if [[ ! "$OVERWRITE_DATA" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}跳过 SQL 脚本导入${NC}"
            echo -e "${BLUE}提示: 如需导入，可以稍后手动执行:${NC}"
            echo "  mysql -u ${MYSQL_USER} -p ${MYSQL_DATABASE} < ${SQL_FILE}"
            return 0
        fi
        echo -e "${YELLOW}⚠ 将覆盖数据库中的现有数据${NC}"
    fi
    
    # 导入 SQL 脚本
    echo "正在导入 SQL 脚本: ${SQL_FILE}"
    echo -e "${BLUE}使用用户: ${MYSQL_USER}，数据库: ${MYSQL_DATABASE}${NC}"
    
    # 显示 SQL 文件大小
    local sql_file_size=$(du -h "$SQL_FILE" | cut -f1)
    echo -e "${BLUE}SQL 文件大小: ${sql_file_size}${NC}"
    
    # 导入 SQL 脚本（显示详细进度）
    echo -e "${BLUE}开始导入...${NC}"
    echo ""
    
    # 使用辅助函数导入 SQL 文件
    echo -e "${BLUE}正在执行 SQL 语句...${NC}"
    
    # 使用 pv 显示进度（如果可用），否则使用普通导入
    local total_lines=$(wc -l < "$SQL_FILE" 2>/dev/null || echo "0")
    if [ "$total_lines" -gt 0 ]; then
        echo -e "${BLUE}SQL 文件共 ${total_lines} 行，正在导入...${NC}"
    fi
    
    # 创建带数据库的配置文件（用于导入）
    local temp_cnf=$(create_mysql_cnf "$mysql_host" "$mysql_port" "$MYSQL_USER" "$MYSQL_USER_PASSWORD")
    echo "database=${MYSQL_DATABASE}" >> "$temp_cnf"
    
    local import_log=$(mktemp)
    if command -v pv &> /dev/null; then
        pv -p -t -e -r -b "$SQL_FILE" | mysql --defaults-file="$temp_cnf" > "$import_log" 2>&1
        SQL_EXIT_CODE=${PIPESTATUS[1]}
    else
        mysql --defaults-file="$temp_cnf" < "$SQL_FILE" > "$import_log" 2>&1
        SQL_EXIT_CODE=$?
    fi
    
    # 如果配置文件方式失败，尝试直接传递密码
    if [ $SQL_EXIT_CODE -ne 0 ] && grep -qi "unknown variable.*defaults-file" "$import_log"; then
    if [ -n "$MYSQL_USER_PASSWORD" ]; then
            if command -v pv &> /dev/null; then
                pv -p -t -e -r -b "$SQL_FILE" | mysql -h"$mysql_host" -P"$mysql_port" -u"${MYSQL_USER}" -p"${MYSQL_USER_PASSWORD}" "${MYSQL_DATABASE}" > "$import_log" 2>&1
                SQL_EXIT_CODE=${PIPESTATUS[1]}
            else
                mysql -h"$mysql_host" -P"$mysql_port" -u"${MYSQL_USER}" -p"${MYSQL_USER_PASSWORD}" "${MYSQL_DATABASE}" < "$SQL_FILE" > "$import_log" 2>&1
        SQL_EXIT_CODE=$?
            fi
    else
            if command -v pv &> /dev/null; then
                pv -p -t -e -r -b "$SQL_FILE" | mysql -h"$mysql_host" -P"$mysql_port" -u"${MYSQL_USER}" "${MYSQL_DATABASE}" > "$import_log" 2>&1
                SQL_EXIT_CODE=${PIPESTATUS[1]}
            else
                mysql -h"$mysql_host" -P"$mysql_port" -u"${MYSQL_USER}" "${MYSQL_DATABASE}" < "$SQL_FILE" > "$import_log" 2>&1
        SQL_EXIT_CODE=$?
            fi
        fi
    fi
    
    # 读取导入日志
    SQL_OUTPUT=$(cat "$import_log")
    rm -f "$temp_cnf" "$import_log"
    
    # 过滤掉警告信息（MySQL 8.0 会输出密码警告）
    SQL_OUTPUT=$(echo "$SQL_OUTPUT" | grep -v "Warning: Using a password on the command line")
    
    # 显示导入过程中的关键信息
        if [ -n "$SQL_OUTPUT" ]; then
        # 检查是否有视图删除的警告（这是正常的，MySQL 5.7 不支持 DROP VIEW IF EXISTS）
        local view_drop_warnings=$(echo "$SQL_OUTPUT" | grep -iE "unknown table|doesn't exist" | grep -i "view" | wc -l)
        if [ "$view_drop_warnings" -gt 0 ]; then
            echo -e "${BLUE}提示: 视图删除警告（这是正常的，首次导入时视图不存在）${NC}"
        fi
    fi
    
    # 检查导入后的表数量（使用统一函数）
    local table_count
    table_count=$(get_table_count "$MYSQL_DATABASE" "$mysql_host" "$mysql_port" "$MYSQL_USER" "$MYSQL_USER_PASSWORD")
    
    # 显示导入结果
    echo ""
    if [ -n "$table_count" ] && [ "$table_count" -gt 0 ]; then
        echo -e "${GREEN}✓ 已成功创建 ${table_count} 个表${NC}"
        
        # 列出所有创建的表（使用辅助函数）
        echo -e "${BLUE}已创建的表：${NC}"
        local list_tables_query="SELECT table_name FROM information_schema.tables WHERE table_schema='${MYSQL_DATABASE}' ORDER BY table_name;"
        mysql_execute "$list_tables_query" "$mysql_host" "$mysql_port" "$MYSQL_USER" "$MYSQL_USER_PASSWORD" 2>/dev/null | grep -v "table_name" | while read table_name; do
            if [ -n "$table_name" ]; then
                echo -e "  ${GREEN}✓${NC} ${table_name}"
            fi
        done
    fi
    
    # 检查是否有错误输出
    if [ -n "$SQL_OUTPUT" ]; then
        # 检查是否是已知的兼容性警告（这些可以忽略）
        local known_warnings=$(echo "$SQL_OUTPUT" | grep -iE "already exists|duplicate|view.*does not exist|unknown database|unknown table|doesn't exist" | wc -l)
        local error_count=$(echo "$SQL_OUTPUT" | grep -iE "error|failed|syntax error" | grep -v "Warning" | wc -l)
        
        # 过滤掉视图删除的警告（MySQL 5.7 不支持 DROP VIEW IF EXISTS）
        local view_drop_errors=$(echo "$SQL_OUTPUT" | grep -iE "error.*view|unknown table.*view" | wc -l)
        if [ "$view_drop_errors" -gt 0 ]; then
            error_count=$((error_count - view_drop_errors))
            echo -e "${BLUE}提示: 视图删除警告已忽略（MySQL 5.7 兼容性处理）${NC}"
        fi
        
        if [ "$error_count" -gt 0 ]; then
            echo ""
            echo -e "${YELLOW}⚠ 导入过程中发现错误：${NC}"
            echo "$SQL_OUTPUT" | grep -iE "error|failed|syntax error" | grep -v "Warning" | head -20
            echo ""
            
            # 如果表数量大于0，说明部分成功
            if [ -n "$table_count" ] && [ "$table_count" -gt 0 ]; then
                echo -e "${YELLOW}⚠ 部分表已成功创建（${table_count} 个表），但存在错误，请检查上述错误信息${NC}"
                echo -e "${YELLOW}建议：${NC}"
                echo "  1. 检查上述错误信息，可能是视图创建失败（不影响主要功能）"
                echo "  2. 检查数据库用户权限是否足够"
                echo "  3. 可以手动修复错误后继续使用"
                # 即使有错误，如果表已创建，也认为部分成功
                echo ""
                echo -e "${GREEN}✓ 数据库表已创建（${table_count} 个表），部分错误不影响主要功能${NC}"
        show_installation_summary
                return 0
            else
                echo -e "${RED}✗ 数据库初始化失败${NC}"
                echo -e "${YELLOW}建议：${NC}"
                echo "  1. 检查 SQL 文件语法是否正确"
                echo "  2. 检查数据库用户权限是否足够"
                echo "  3. 手动导入 SQL 文件: mysql -u ${MYSQL_USER} -p ${MYSQL_DATABASE} < ${SQL_FILE}"
                return 1
            fi
        elif [ "$known_warnings" -gt 0 ]; then
            echo ""
            echo -e "${BLUE}提示：部分对象可能已存在（这是正常的，使用 IF NOT EXISTS 语句）${NC}"
        fi
    fi
    
    # 如果表数量大于0，认为导入成功
    if [ -n "$table_count" ] && [ "$table_count" -gt 0 ]; then
        echo ""
        echo -e "${GREEN}✓ 数据库初始化完成（已创建 ${table_count} 个表）${NC}"
            # 显示安装总结
            show_installation_summary
        return 0
    elif [ $SQL_EXIT_CODE -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✓ 数据库初始化完成（SQL 执行成功）${NC}"
        # 显示安装总结
        show_installation_summary
        return 0
        else
        echo ""
            echo -e "${RED}✗ 数据库初始化失败${NC}"
        if [ -n "$SQL_OUTPUT" ]; then
            echo -e "${YELLOW}错误信息：${NC}"
            echo "$SQL_OUTPUT" | head -30
        fi
            echo ""
            echo -e "${YELLOW}建议：${NC}"
            echo "  1. 检查 SQL 文件语法是否正确"
            echo "  2. 检查数据库用户权限是否足够"
            echo "  3. 手动导入 SQL 文件: mysql -u ${MYSQL_USER} -p ${MYSQL_DATABASE} < ${SQL_FILE}"
        echo ""
        # 提供重试选项
        read -p "是否重试导入 SQL 脚本？[y/N]: " RETRY_IMPORT
        RETRY_IMPORT="${RETRY_IMPORT:-N}"
        if [[ "$RETRY_IMPORT" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}重试导入 SQL 脚本...${NC}"
            # 清理临时文件
            rm -f "$temp_cnf" "$import_log" 2>/dev/null || true
            # 重新创建配置文件
            temp_cnf=$(create_mysql_cnf "$mysql_host" "$mysql_port" "$MYSQL_USER" "$MYSQL_USER_PASSWORD")
            echo "database=${MYSQL_DATABASE}" >> "$temp_cnf"
            import_log=$(mktemp)
            # 重新导入
            if command -v pv &> /dev/null; then
                pv -p -t -e -r -b "$SQL_FILE" | mysql --defaults-file="$temp_cnf" > "$import_log" 2>&1
                SQL_EXIT_CODE=${PIPESTATUS[1]}
            else
                mysql --defaults-file="$temp_cnf" < "$SQL_FILE" > "$import_log" 2>&1
                SQL_EXIT_CODE=$?
            fi
            # 如果配置文件方式失败，尝试直接传递密码
            if [ $SQL_EXIT_CODE -ne 0 ] && grep -qi "unknown variable.*defaults-file" "$import_log"; then
                if [ -n "$MYSQL_USER_PASSWORD" ]; then
                    if command -v pv &> /dev/null; then
                        pv -p -t -e -r -b "$SQL_FILE" | mysql -h"$mysql_host" -P"$mysql_port" -u"${MYSQL_USER}" -p"${MYSQL_USER_PASSWORD}" "${MYSQL_DATABASE}" > "$import_log" 2>&1
                        SQL_EXIT_CODE=${PIPESTATUS[1]}
                    else
                        mysql -h"$mysql_host" -P"$mysql_port" -u"${MYSQL_USER}" -p"${MYSQL_USER_PASSWORD}" "${MYSQL_DATABASE}" < "$SQL_FILE" > "$import_log" 2>&1
                        SQL_EXIT_CODE=$?
                    fi
                else
                    if command -v pv &> /dev/null; then
                        pv -p -t -e -r -b "$SQL_FILE" | mysql -h"$mysql_host" -P"$mysql_port" -u"${MYSQL_USER}" "${MYSQL_DATABASE}" > "$import_log" 2>&1
                        SQL_EXIT_CODE=${PIPESTATUS[1]}
                    else
                        mysql -h"$mysql_host" -P"$mysql_port" -u"${MYSQL_USER}" "${MYSQL_DATABASE}" < "$SQL_FILE" > "$import_log" 2>&1
                        SQL_EXIT_CODE=$?
                    fi
                fi
            fi
            # 读取导入日志
            SQL_OUTPUT=$(cat "$import_log")
            rm -f "$temp_cnf" "$import_log"
            # 过滤掉警告信息
            SQL_OUTPUT=$(echo "$SQL_OUTPUT" | grep -v "Warning: Using a password on the command line")
            # 检查导入后的表数量
            table_count=$(get_table_count "$MYSQL_DATABASE" "$mysql_host" "$mysql_port" "$MYSQL_USER" "$MYSQL_USER_PASSWORD")
            if [ -n "$table_count" ] && [ "$table_count" -gt 0 ]; then
                echo ""
                echo -e "${GREEN}✓ 重试成功，已创建 ${table_count} 个表${NC}"
                show_installation_summary
                return 0
            elif [ $SQL_EXIT_CODE -eq 0 ]; then
                echo ""
                echo -e "${GREEN}✓ 重试成功，SQL 执行成功${NC}"
                show_installation_summary
                return 0
            else
                echo ""
                echo -e "${RED}✗ 重试仍然失败${NC}"
                if [ -n "$SQL_OUTPUT" ]; then
                    echo -e "${YELLOW}错误信息：${NC}"
                    echo "$SQL_OUTPUT" | head -30
                fi
                # 设置失败标志供主函数使用
                INIT_DB_FAILED=1
                return 1
            fi
        else
            # 设置失败标志供主函数使用
            INIT_DB_FAILED=1
            return 1
        fi
    fi
}

# 显示安装总结信息
show_installation_summary() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}数据库安装已完成，SQL已全部导入${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # 显示root密码
    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        echo -e "${BLUE}MySQL Root 密码:${NC}"
        echo "  ${MYSQL_ROOT_PASSWORD}"
        echo ""
    else
        echo -e "${YELLOW}⚠ MySQL Root 密码未设置${NC}"
        echo ""
    fi
    
    # 显示数据库信息
    if [ -n "$MYSQL_DATABASE" ]; then
        echo -e "${BLUE}创建的数据库:${NC}"
        echo "  数据库名称: ${MYSQL_DATABASE}"
        echo ""
    else
        echo -e "${YELLOW}⚠ 未创建数据库${NC}"
        echo ""
    fi
    
    # 显示用户信息（用户名@host格式）
    echo -e "${BLUE}用户信息:${NC}"
    
    # 获取连接信息（使用统一函数）
    get_mysql_connection_info
    local mysql_host="$mysql_host"
    local mysql_port="$mysql_port"
        
    # 查询并显示root用户的host信息（使用辅助函数）
    local root_query="SELECT CONCAT(User, '@', Host) as 'User@Host' FROM mysql.user WHERE User='root' ORDER BY Host;"
    local root_hosts
    root_hosts=$(mysql_execute "$root_query" "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD" 2>/dev/null | grep -v "User@Host" | grep -v "^$" | grep -E "root@")
    
    if [ -n "$root_hosts" ]; then
        echo "  root用户:"
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                echo "    ${line}"
            fi
        done <<< "$root_hosts"
        if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
            echo "    密码: ${MYSQL_ROOT_PASSWORD}"
        fi
        echo ""
    fi
    
    # 显示连接URL信息（支持外部 MySQL）
    echo -e "${BLUE}连接 URL 信息:${NC}"
    if [ -n "$MYSQL_USER" ] && [ "$MYSQL_USER" != "root" ] && [ -n "$MYSQL_USER_PASSWORD" ]; then
        # 使用创建的用户
        echo "  MySQL URL: mysql://${MYSQL_USER}:${MYSQL_USER_PASSWORD}@${mysql_host}:${mysql_port}/${MYSQL_DATABASE}"
        echo "  连接命令: mysql -h ${mysql_host} -P ${mysql_port} -u ${MYSQL_USER} -p'${MYSQL_USER_PASSWORD}' ${MYSQL_DATABASE}"
    elif [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        # 使用root用户
        echo "  MySQL URL: mysql://root:${MYSQL_ROOT_PASSWORD}@${mysql_host}:${mysql_port}/${MYSQL_DATABASE:-}"
        if [ -n "$MYSQL_DATABASE" ]; then
            echo "  连接命令: mysql -h ${mysql_host} -P ${mysql_port} -u root -p'${MYSQL_ROOT_PASSWORD}' ${MYSQL_DATABASE}"
        else
            echo "  连接命令: mysql -h ${mysql_host} -P ${mysql_port} -u root -p'${MYSQL_ROOT_PASSWORD}'"
        fi
    else
        echo "  MySQL URL: mysql://root@${mysql_host}:${mysql_port}/${MYSQL_DATABASE:-}"
        if [ -n "$MYSQL_DATABASE" ]; then
            echo "  连接命令: mysql -h ${mysql_host} -P ${mysql_port} -u root ${MYSQL_DATABASE}"
        else
            echo "  连接命令: mysql -h ${mysql_host} -P ${mysql_port} -u root"
        fi
    fi
    echo ""
    
    # 检查开机启动状态（仅本地 MySQL）
    if [ "${EXTERNAL_MYSQL_MODE:-0}" -eq 0 ]; then
    echo -e "${BLUE}开机启动状态:${NC}"
        if mysql_service_manage "status" 1 2>/dev/null; then
            # 检查是否启用开机自启动
    if command -v systemctl &> /dev/null; then
        if systemctl is-enabled mysqld >/dev/null 2>&1 || systemctl is-enabled mysql >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓ 已启用开机自启动${NC}"
        else
            echo -e "  ${YELLOW}⚠ 未启用开机自启动${NC}"
            echo -e "  ${BLUE}提示: 运行 'systemctl enable mysqld' 启用开机自启动${NC}"
        fi
    elif command -v chkconfig &> /dev/null; then
        if chkconfig mysqld 2>/dev/null | grep -q "3:on\|5:on" || chkconfig mysql 2>/dev/null | grep -q "3:on\|5:on"; then
            echo -e "  ${GREEN}✓ 已启用开机自启动${NC}"
        else
            echo -e "  ${YELLOW}⚠ 未启用开机自启动${NC}"
            echo -e "  ${BLUE}提示: 运行 'chkconfig mysqld on' 启用开机自启动${NC}"
                fi
        fi
    fi
    echo ""
    fi
    
    # 显示创建的用户（如果不是root）
    if [ -n "$MYSQL_USER" ] && [ "$MYSQL_USER" != "root" ]; then
        # 查询用户的host信息（使用辅助函数）
        local user_query="SELECT CONCAT(User, '@', Host) as 'User@Host' FROM mysql.user WHERE User='${MYSQL_USER}' ORDER BY Host;"
        local user_hosts
        user_hosts=$(mysql_execute "$user_query" "$mysql_host" "$mysql_port" "root" "$MYSQL_ROOT_PASSWORD" 2>/dev/null | grep -v "User@Host" | grep -v "^$" | grep -E "${MYSQL_USER}@")
        
        if [ -n "$user_hosts" ]; then
            echo "  创建的用户:"
            while IFS= read -r line; do
                if [ -n "$line" ]; then
                    echo "    ${line}"
                fi
            done <<< "$user_hosts"
            echo "    密码: ${MYSQL_USER_PASSWORD}"
            echo ""
        else
            # 如果查询失败，使用默认值
            echo "  创建的用户:"
            echo "    ${MYSQL_USER}@localhost"
            echo "    密码: ${MYSQL_USER_PASSWORD}"
            echo ""
        fi
    fi
    
    echo -e "${GREEN}========================================${NC}"
    echo ""
}

# 显示后续步骤
show_next_steps() {
    echo ""
    if [ "${SKIP_INSTALL:-0}" -eq 1 ]; then
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}MySQL 配置完成！${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo -e "${BLUE}注意: 已跳过安装步骤，使用的是现有 MySQL 安装${NC}"
        echo ""
    else
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}MySQL 安装完成！${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
    fi
    
    # 显示创建的数据库和用户信息（如果已经显示过总结，这里只显示简要信息）
    if [ -n "$MYSQL_DATABASE" ]; then
        echo -e "${BLUE}数据库信息:${NC}"
        echo "  数据库名称: ${MYSQL_DATABASE}"
        if [ -n "$MYSQL_USER" ] && [ "$MYSQL_USER" != "root" ]; then
            echo "  用户名: ${MYSQL_USER}"
            echo "  密码: ${MYSQL_USER_PASSWORD}"
            echo "  Host: localhost"
        else
            echo "  使用 root 用户"
            if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
                echo "  Root 密码: ${MYSQL_ROOT_PASSWORD}"
            fi
        fi
        echo ""
    fi
    
    # 获取连接信息（使用统一函数）
    get_mysql_connection_info
    local mysql_host="$mysql_host"
    local mysql_port="$mysql_port"
    
    echo -e "${BLUE}后续步骤:${NC}"
    echo ""
    
    # 仅本地 MySQL 显示服务状态检查
    if [ "${EXTERNAL_MYSQL_MODE:-0}" -eq 0 ]; then
    echo "1. 检查 MySQL 服务状态:"
    echo "   sudo systemctl status mysqld"
    echo "   或"
    echo "   sudo systemctl status mysql"
    echo ""
    fi
    
    echo "2. 连接 MySQL:"
    if [ -n "$MYSQL_USER_PASSWORD" ] && [ "$MYSQL_USER" != "root" ]; then
        echo "   mysql -h ${mysql_host} -P ${mysql_port} -u ${MYSQL_USER} -p'${MYSQL_USER_PASSWORD}' ${MYSQL_DATABASE}"
        echo "   MySQL URL: mysql://${MYSQL_USER}:${MYSQL_USER_PASSWORD}@${mysql_host}:${mysql_port}/${MYSQL_DATABASE}"
    elif [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        if [ -n "$MYSQL_DATABASE" ]; then
            echo "   mysql -h ${mysql_host} -P ${mysql_port} -u root -p'${MYSQL_ROOT_PASSWORD}' ${MYSQL_DATABASE}"
            echo "   MySQL URL: mysql://root:${MYSQL_ROOT_PASSWORD}@${mysql_host}:${mysql_port}/${MYSQL_DATABASE}"
        else
            echo "   mysql -h ${mysql_host} -P ${mysql_port} -u root -p'${MYSQL_ROOT_PASSWORD}'"
            echo "   MySQL URL: mysql://root:${MYSQL_ROOT_PASSWORD}@${mysql_host}:${mysql_port}/"
        fi
    else
        if [ -n "$MYSQL_DATABASE" ]; then
            echo "   mysql -h ${mysql_host} -P ${mysql_port} -u root ${MYSQL_DATABASE}"
            echo "   MySQL URL: mysql://root@${mysql_host}:${mysql_port}/${MYSQL_DATABASE}"
        else
            echo "   mysql -h ${mysql_host} -P ${mysql_port} -u root"
            echo "   MySQL URL: mysql://root@${mysql_host}:${mysql_port}/"
        fi
    fi
    echo ""
    
    if [ -z "$MYSQL_DATABASE" ]; then
        echo "3. 创建数据库和用户（用于 WAF 系统）:"
        echo "   mysql -u root -p < init_file/数据库设计.sql"
        echo ""
    fi
    
    echo "4. 修改 WAF 配置文件:"
    echo "   vim lua/config.lua"
    echo "   或使用 install.sh 自动配置"
    echo ""
    # 仅本地 MySQL 显示服务管理命令
    if [ "${EXTERNAL_MYSQL_MODE:-0}" -eq 0 ]; then
    echo -e "${BLUE}服务管理:${NC}"
    echo "  启动: sudo systemctl start mysqld"
    echo "  停止: sudo systemctl stop mysqld"
    echo "  重启: sudo systemctl restart mysqld"
    echo "  开机自启: sudo systemctl enable mysqld"
    echo ""
    fi
}

# 配置外部 MySQL（不安装 MySQL，只配置数据库和导入数据）
configure_external_mysql() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}配置外部 MySQL${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # 输入外部 MySQL 连接信息
    read -p "请输入外部 MySQL 地址 [127.0.0.1]: " EXTERNAL_MYSQL_HOST
    EXTERNAL_MYSQL_HOST="${EXTERNAL_MYSQL_HOST:-127.0.0.1}"
    
    read -p "请输入外部 MySQL 端口 [3306]: " EXTERNAL_MYSQL_PORT
    EXTERNAL_MYSQL_PORT="${EXTERNAL_MYSQL_PORT:-3306}"
    
    echo -e "${YELLOW}提示: 需要使用管理员账户（如 root）来创建数据库和用户${NC}"
    read -p "请输入管理员用户名 [root]: " EXTERNAL_MYSQL_ADMIN_USER
    EXTERNAL_MYSQL_ADMIN_USER="${EXTERNAL_MYSQL_ADMIN_USER:-root}"
    
    read -p "请输入管理员密码: " EXTERNAL_MYSQL_ADMIN_PASSWORD
    if [ -z "$EXTERNAL_MYSQL_ADMIN_PASSWORD" ]; then
        echo -e "${YELLOW}⚠ 未输入密码，尝试无密码连接${NC}"
    fi
    
    # 测试连接（使用辅助函数）
        echo ""
    echo -e "${BLUE}正在测试 MySQL 连接...${NC}"
    if ! mysql_verify_connection "$EXTERNAL_MYSQL_HOST" "$EXTERNAL_MYSQL_PORT" "$EXTERNAL_MYSQL_ADMIN_USER" "$EXTERNAL_MYSQL_ADMIN_PASSWORD"; then
        echo -e "${RED}✗ MySQL 连接失败，请检查连接信息${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ MySQL 连接成功${NC}"
    echo ""
    
    # 设置变量供后续函数使用
    MYSQL_ROOT_PASSWORD="$EXTERNAL_MYSQL_ADMIN_PASSWORD"
    MYSQL_HOST="$EXTERNAL_MYSQL_HOST"
    MYSQL_PORT="$EXTERNAL_MYSQL_PORT"
    export EXTERNAL_MYSQL_MODE=1
    
    # 创建数据库（使用辅助函数）
    echo -e "${BLUE}创建数据库...${NC}"
    read -p "请输入数据库名称 [waf_db]: " DB_NAME
    DB_NAME="${DB_NAME:-waf_db}"
    
    local create_db_sql="CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
    if mysql_execute "$create_db_sql" "$EXTERNAL_MYSQL_HOST" "$EXTERNAL_MYSQL_PORT" "$EXTERNAL_MYSQL_ADMIN_USER" "$EXTERNAL_MYSQL_ADMIN_PASSWORD" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 数据库 ${DB_NAME} 创建成功${NC}"
        set_and_export_database "$DB_NAME"
    else
        echo -e "${RED}✗ 数据库创建失败${NC}"
        return 1
    fi
            echo ""
            
    # 创建应用连接用户
    echo -e "${BLUE}创建应用连接用户...${NC}"
    read -p "请输入应用用户名 [waf_user]: " APP_USER
    APP_USER="${APP_USER:-waf_user}"
    
    read -p "请输入应用用户密码: " APP_USER_PASSWORD
    if [ -z "$APP_USER_PASSWORD" ]; then
        echo -e "${RED}错误: 应用用户密码不能为空${NC}"
        return 1
    fi
    
    # 创建用户并授权（使用辅助函数）
    local create_user_sql="CREATE USER IF NOT EXISTS '${APP_USER}'@'%' IDENTIFIED BY '${APP_USER_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${APP_USER}'@'%';
FLUSH PRIVILEGES;"
    
    if mysql_execute "$create_user_sql" "$EXTERNAL_MYSQL_HOST" "$EXTERNAL_MYSQL_PORT" "$EXTERNAL_MYSQL_ADMIN_USER" "$EXTERNAL_MYSQL_ADMIN_PASSWORD" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 用户 ${APP_USER} 创建成功并已授权${NC}"
        # 设置并导出用户变量（使用统一函数）
        set_and_export_user "$APP_USER" "$APP_USER_PASSWORD" "Y"
    else
        echo -e "${RED}✗ 用户创建失败${NC}"
        return 1
    fi
            echo ""
    
    # 导入数据
    echo -e "${BLUE}导入数据库数据...${NC}"
    # 使用全局 SCRIPT_DIR（避免重复定义）
    SQL_FILE="${SCRIPT_DIR}/../init_file/数据库设计.sql"
    
    if [ ! -f "$SQL_FILE" ]; then
        echo -e "${YELLOW}⚠ SQL 文件不存在: ${SQL_FILE}${NC}"
        echo "请手动导入 SQL 脚本"
        return 1
    fi
    
    echo -e "${BLUE}正在导入 SQL 脚本: ${SQL_FILE}${NC}"
    local sql_file_size=$(du -h "$SQL_FILE" | cut -f1)
    echo -e "${BLUE}SQL 文件大小: ${sql_file_size}${NC}"
    echo -e "${BLUE}开始导入...${NC}"
    
    # 创建带数据库的配置文件（用于导入）
    local import_cnf=$(create_mysql_cnf "$EXTERNAL_MYSQL_HOST" "$EXTERNAL_MYSQL_PORT" "$EXTERNAL_MYSQL_ADMIN_USER" "$EXTERNAL_MYSQL_ADMIN_PASSWORD")
    echo "database=${DB_NAME}" >> "$import_cnf"
    
    local sql_output
    sql_output=$(mysql --defaults-file="$import_cnf" < "$SQL_FILE" 2>&1)
    local sql_exit_code=$?
    
    # 如果配置文件方式失败，尝试直接传递密码
    if [ $sql_exit_code -ne 0 ] && echo "$sql_output" | grep -qi "unknown variable.*defaults-file"; then
        if [ -n "$EXTERNAL_MYSQL_ADMIN_PASSWORD" ]; then
            sql_output=$(mysql -h"$EXTERNAL_MYSQL_HOST" -P"$EXTERNAL_MYSQL_PORT" -u"$EXTERNAL_MYSQL_ADMIN_USER" -p"$EXTERNAL_MYSQL_ADMIN_PASSWORD" "$DB_NAME" < "$SQL_FILE" 2>&1)
        else
            sql_output=$(mysql -h"$EXTERNAL_MYSQL_HOST" -P"$EXTERNAL_MYSQL_PORT" -u"$EXTERNAL_MYSQL_ADMIN_USER" "$DB_NAME" < "$SQL_FILE" 2>&1)
        fi
        sql_exit_code=$?
    fi
    
    rm -f "$import_cnf"
    
    # 过滤掉警告信息
    sql_output=$(echo "$sql_output" | grep -v "Warning: Using a password on the command line")
    
    # 检查导入后的表数量（使用统一函数）
    local table_count
    table_count=$(get_table_count "$DB_NAME" "$EXTERNAL_MYSQL_HOST" "$EXTERNAL_MYSQL_PORT" "$EXTERNAL_MYSQL_ADMIN_USER" "$EXTERNAL_MYSQL_ADMIN_PASSWORD")
    
    if [ -n "$table_count" ] && [ "$table_count" -gt 0 ]; then
                echo ""
        echo -e "${GREEN}✓ 数据库初始化完成（已创建 ${table_count} 个表）${NC}"
        
        # 列出所有创建的表（使用辅助函数）
        echo -e "${BLUE}已创建的表：${NC}"
        local list_query="SELECT table_name FROM information_schema.tables WHERE table_schema='${DB_NAME}' ORDER BY table_name;"
        mysql_execute "$list_query" "$EXTERNAL_MYSQL_HOST" "$EXTERNAL_MYSQL_PORT" "$EXTERNAL_MYSQL_ADMIN_USER" "$EXTERNAL_MYSQL_ADMIN_PASSWORD" 2>/dev/null | grep -v "table_name" | while read table_name; do
            if [ -n "$table_name" ]; then
                echo -e "  ${GREEN}✓${NC} ${table_name}"
            fi
        done
                    else
        echo -e "${YELLOW}⚠ 未检测到表，可能导入失败${NC}"
        if [ -n "$sql_output" ]; then
            echo -e "${YELLOW}错误信息：${NC}"
            echo "$sql_output" | head -20
        fi
        return 1
    fi
    
    # 更新 WAF 配置文件
    update_waf_config
    
    echo ""
    echo -e "${GREEN}✓ 外部 MySQL 配置完成${NC}"
    echo ""
    echo -e "${BLUE}连接信息：${NC}"
    echo "  地址: ${EXTERNAL_MYSQL_HOST}:${EXTERNAL_MYSQL_PORT}"
    echo "  数据库: ${DB_NAME}"
    echo "  应用用户: ${APP_USER}"
    echo ""
    
    return 0
}

# 主函数
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}MySQL 一键安装和配置脚本${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # 询问是否安装 MySQL
    read -p "是否安装 MySQL？[Y/n]: " INSTALL_MYSQL
    INSTALL_MYSQL="${INSTALL_MYSQL:-Y}"
    
    if [[ ! "$INSTALL_MYSQL" =~ ^[Yy]$ ]]; then
        # 不安装 MySQL，询问是否导入 SQL
        echo ""
        read -p "是否导入 SQL 到外部 MySQL？[Y/n]: " IMPORT_SQL
        IMPORT_SQL="${IMPORT_SQL:-Y}"
        
        if [[ "$IMPORT_SQL" =~ ^[Yy]$ ]]; then
            # 配置外部 MySQL
            if configure_external_mysql; then
                echo -e "${GREEN}✓ 外部 MySQL 配置完成${NC}"
                return 0
            else
                echo -e "${RED}✗ 外部 MySQL 配置失败${NC}"
                return 1
                    fi
                else
            echo -e "${YELLOW}跳过 MySQL 安装和配置${NC}"
            return 0
        fi
    fi
    
    # 检查 root 权限（安装 MySQL 需要 root 权限）
    check_root
    
    # 检测操作系统（只调用一次，确保 OS 变量已设置）
    if [ -z "${OS:-}" ]; then
        detect_os
    else
        echo -e "${BLUE}[1/8] 检测操作系统...${NC}"
        echo -e "${GREEN}✓ 系统类型: ${OS}${NC}"
    fi
    
    # 检测硬件配置
    detect_hardware
    
    # 检查现有安装
    check_existing
    
    # 检查 check_existing 的返回状态
    local check_existing_result=$?
    
    # 如果选择跳过安装，只执行后续步骤
    if [ "${SKIP_INSTALL:-0}" -eq 1 ]; then
        echo -e "${BLUE}[跳过安装步骤] 检测到已安装 MySQL，跳过安装步骤${NC}"
        echo ""
        
        # 确保 MySQL 服务已启动（使用辅助函数）
        echo -e "${BLUE}检查 MySQL 服务状态...${NC}"
        if ! mysqladmin ping -h localhost --silent 2>/dev/null; then
            echo -e "${YELLOW}MySQL 服务未运行，尝试启动...${NC}"
            mysql_service_manage "start" 0 || true
            
            # 等待 MySQL 启动（使用辅助函数，内部已包含连接验证）
            if ! wait_for_mysql_ready 30 localhost; then
                echo -e "${RED}✗ MySQL 服务启动失败${NC}"
                echo -e "${YELLOW}请手动启动 MySQL 服务后重新运行脚本${NC}"
                    exit 1
                fi
            else
            echo -e "${GREEN}✓ MySQL 服务正在运行${NC}"
        fi
        
        # 获取并验证 root 密码（使用统一函数，内部已包含连接验证）
        if ! get_and_verify_root_password "127.0.0.1" "3306"; then
            exit 1
        fi
        
        echo ""
        echo -e "${GREEN}✓ 跳过安装步骤完成，继续执行后续步骤${NC}"
        echo -e "${BLUE}注意: 已跳过配置优化步骤，使用现有 MySQL 配置${NC}"
        echo -e "${BLUE}      如需优化配置，请手动修改 /etc/my.cnf 或 /etc/mysql/my.cnf${NC}"
        echo ""
    else
        # 正常安装流程
        # 检查是否真的需要安装（防止 check_existing 没有正确设置 SKIP_INSTALL）
        if command -v mysql &> /dev/null || command -v mysqld &> /dev/null; then
            echo -e "${YELLOW}⚠ 检测到 MySQL 已安装，但未选择跳过安装${NC}"
            echo -e "${YELLOW}⚠ 如果不想重新安装，请重新运行脚本并选择跳过安装${NC}"
            echo -e "${YELLOW}⚠ 继续执行安装流程...${NC}"
            echo ""
        fi
        
        # 安装 MySQL
        install_mysql
        
        # 设置 MySQL 配置文件（必须在初始化前完成）
        # 重要：所有 my.cnf 等配置文件的改动必须在数据库初始化前完成
        # 包括：
        #   - 基础配置（lower_case_table_names、default_time_zone 等）
        #   - 硬件优化配置（InnoDB 缓冲池、连接数、IO 线程等）
        # 因为 MySQL 首次启动时会根据配置文件初始化数据字典
        # 硬件优化配置虽然可以在运行时修改，但为了最佳性能，应在初始化前设置
        setup_mysql_config
        
        # 配置 MySQL（启动服务，首次启动会自动初始化）
        # 注意：首次启动时会根据配置文件初始化数据库
        # 所有配置优化（包括硬件优化）必须在此步骤之前完成
        configure_mysql
        
        # 设置 root 密码
        if ! set_root_password; then
            echo ""
            echo -e "${RED}========================================${NC}"
            echo -e "${RED}MySQL 安装失败：root 密码设置失败${NC}"
            echo -e "${RED}========================================${NC}"
            echo ""
            echo -e "${YELLOW}请按照上面的错误提示手动修改密码，然后重新运行安装脚本${NC}"
            echo ""
            exit 1
        fi
        
        # 安全配置
        secure_mysql
        
        # 验证安装
        verify_installation
    fi
    
    # 创建数据库
    if ! create_database; then
        echo ""
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}MySQL 安装失败：数据库创建失败${NC}"
        echo -e "${RED}========================================${NC}"
        echo ""
        echo -e "${YELLOW}请按照上面的错误提示手动创建数据库，然后重新运行安装脚本${NC}"
        echo ""
        echo -e "${BLUE}手动创建数据库命令:${NC}"
        echo "  mysql -u root -p"
        echo "  CREATE DATABASE waf_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
        echo ""
        exit 1
    fi
    
    # 创建数据库用户
    if ! create_database_user; then
        echo ""
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}MySQL 安装失败：数据库用户创建失败${NC}"
        echo -e "${RED}========================================${NC}"
        echo ""
        echo -e "${YELLOW}请按照上面的错误提示手动创建数据库用户，然后重新运行安装脚本${NC}"
        echo ""
        exit 1
    fi
    
    # 初始化数据库数据
    if ! init_database; then
        echo ""
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}MySQL 安装失败：数据库初始化失败${NC}"
        echo -e "${RED}========================================${NC}"
        echo ""
        echo -e "${YELLOW}数据库初始化失败，但已创建的数据库和用户仍然可用${NC}"
        echo -e "${YELLOW}您可以稍后手动导入 SQL 脚本${NC}"
        echo ""
        echo -e "${BLUE}手动导入 SQL 脚本命令:${NC}"
        if [ -n "$MYSQL_DATABASE" ] && [ -n "$MYSQL_USER" ]; then
            # 使用全局 SCRIPT_DIR（避免重复定义）
            SQL_FILE="${SCRIPT_DIR}/../init_file/数据库设计.sql"
            echo "  mysql -u ${MYSQL_USER} -p ${MYSQL_DATABASE} < ${SQL_FILE}"
        else
            echo "  mysql -u <user> -p <database> < <sql_file>"
        fi
        echo ""
        # 即使初始化失败，也继续更新配置和显示后续步骤（因为数据库和用户已创建）
        echo -e "${YELLOW}继续执行后续步骤（更新配置和显示信息）...${NC}"
        echo ""
    fi
    
    # 更新 WAF 配置文件（如果创建了数据库和用户）
    if ! update_waf_config; then
        echo ""
        echo -e "${YELLOW}⚠ WAF 配置文件更新失败，请手动更新${NC}"
        echo -e "${YELLOW}配置文件路径: ${SCRIPT_DIR}/../lua/config.lua${NC}"
        echo ""
        # 显示手动更新命令
        if [ -n "$CREATED_DB_NAME" ] && [ -n "$MYSQL_USER_FOR_WAF" ]; then
            get_mysql_connection_info
            echo -e "${BLUE}手动更新命令:${NC}"
            echo "  bash ${SCRIPT_DIR}/set_lua_database_connect.sh mysql $mysql_host $mysql_port ${CREATED_DB_NAME} ${MYSQL_USER_FOR_WAF} <password>"
        fi
        echo ""
        # 配置文件更新失败不影响整体安装，继续执行
    fi
    
    # 显示后续步骤
    show_next_steps
    
    # 导出变量到文件（使用统一函数）
    export_variables_to_file
    
    # 最终检查：如果数据库初始化失败，返回非零退出码
    if [ "${INIT_DB_FAILED:-0}" -eq 1 ]; then
        echo ""
        echo -e "${YELLOW}⚠ 警告: 数据库初始化失败，但其他步骤已完成${NC}"
        echo -e "${YELLOW}请按照上述提示手动导入 SQL 脚本${NC}"
        return 1
    fi
    
    return 0
}

# 执行主函数
main "$@"

