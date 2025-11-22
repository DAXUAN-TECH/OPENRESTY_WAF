#!/bin/bash

# OpenResty WAF 一键安装脚本
# 用途：统一安装和配置 OpenResty WAF 系统
# 功能：按顺序执行各安装脚本，配置 MySQL 和 Redis 连接信息

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 获取项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# 脚本目录
SCRIPTS_DIR="${PROJECT_ROOT}/scripts"

# 配置文件路径
CONFIG_FILE="${PROJECT_ROOT}/lua/config.lua"

# 日志目录
LOGS_DIR="${PROJECT_ROOT}/logs"

# OpenResty 安装目录
OPENRESTY_PREFIX="${OPENRESTY_PREFIX:-/usr/local/openresty}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}OpenResty WAF 一键安装脚本${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "项目根目录: $PROJECT_ROOT"
echo ""

# 创建必要的目录
mkdir -p "$LOGS_DIR"
echo -e "${GREEN}✓ 已创建日志目录: $LOGS_DIR${NC}"
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 需要 root 权限来安装系统${NC}"
    echo "请使用: sudo $0"
    exit 1
fi

# ============================================
# 配置信息收集
# ============================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}步骤 1/7: 收集配置信息${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# MySQL 配置
echo -e "${CYAN}MySQL 数据库配置${NC}"
read -p "是否使用本地 MySQL？[Y/n]: " MYSQL_USE_LOCAL
MYSQL_USE_LOCAL="${MYSQL_USE_LOCAL:-Y}"

if [[ ! "$MYSQL_USE_LOCAL" =~ ^[Yy]$ ]]; then
    # 外部 MySQL
    MYSQL_INSTALL_LOCAL="N"
    echo -e "${GREEN}使用外部 MySQL 数据库${NC}"
    echo ""
    
    read -p "MySQL 主机地址 [127.0.0.1]: " MYSQL_HOST
    MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
    
    read -p "MySQL 端口 [3306]: " MYSQL_PORT
    MYSQL_PORT="${MYSQL_PORT:-3306}"
    
    read -p "数据库名称 [waf_db]: " MYSQL_DATABASE
    MYSQL_DATABASE="${MYSQL_DATABASE:-waf_db}"
    
    read -p "数据库用户名 [waf_user]: " MYSQL_USER
    MYSQL_USER="${MYSQL_USER:-waf_user}"
    
    read -sp "数据库密码: " MYSQL_PASSWORD
    echo ""
    if [ -z "$MYSQL_PASSWORD" ]; then
        echo -e "${RED}错误: 数据库密码不能为空${NC}"
        exit 1
    fi
else
    # 本地 MySQL
    MYSQL_INSTALL_LOCAL="Y"
    echo -e "${GREEN}使用本地 MySQL 数据库，将自动安装${NC}"
    echo ""
    
    # 先安装 MySQL
    echo -e "${BLUE}开始安装 MySQL...${NC}"
    
    # 创建临时文件用于传递变量
    TEMP_VARS_FILE=$(mktemp)
    export TEMP_VARS_FILE
    
    # 执行安装脚本
    if ! bash "${SCRIPTS_DIR}/install_mysql.sh"; then
        echo -e "${RED}✗ MySQL 安装失败${NC}"
        echo "请检查错误信息并重试"
        rm -f "$TEMP_VARS_FILE"
        exit 1
    fi
    
    # 读取导出的变量（install_mysql.sh 会在结束时写入）
    if [ -f "$TEMP_VARS_FILE" ]; then
        source "$TEMP_VARS_FILE"
        rm -f "$TEMP_VARS_FILE"
    fi
    
    # 如果 install_mysql.sh 已经创建了数据库和用户，使用这些信息
    if [ -n "$CREATED_DB_NAME" ] && [ -n "$MYSQL_USER_FOR_WAF" ] && [ -n "$MYSQL_PASSWORD_FOR_WAF" ]; then
        echo -e "${GREEN}✓ 使用 install_mysql.sh 创建的数据库和用户${NC}"
        MYSQL_DATABASE="$CREATED_DB_NAME"
        MYSQL_USER="$MYSQL_USER_FOR_WAF"
        MYSQL_PASSWORD="$MYSQL_PASSWORD_FOR_WAF"
    else
        # 如果没有创建，则提示用户输入
        echo ""
        echo -e "${CYAN}配置 MySQL 连接信息${NC}"
        
        read -p "数据库名称 [waf_db]: " MYSQL_DATABASE
        MYSQL_DATABASE="${MYSQL_DATABASE:-waf_db}"
        
        read -p "数据库用户名 [waf_user]: " MYSQL_USER
        MYSQL_USER="${MYSQL_USER:-waf_user}"
        
        read -sp "数据库密码（用于 WAF 连接）: " MYSQL_PASSWORD
        echo ""
        if [ -z "$MYSQL_PASSWORD" ]; then
            echo -e "${RED}错误: 数据库密码不能为空${NC}"
            exit 1
        fi
    fi
    
    # 本地 MySQL 默认配置
    MYSQL_HOST="127.0.0.1"
    MYSQL_PORT="3306"
    
    echo ""
fi

# Redis 配置（可选）
echo ""
echo -e "${CYAN}Redis 配置（可选，直接回车跳过）${NC}"
read -p "是否使用 Redis 缓存？[y/N]: " USE_REDIS
USE_REDIS="${USE_REDIS:-N}"

if [[ "$USE_REDIS" =~ ^[Yy]$ ]]; then
    read -p "是否使用本地 Redis？[Y/n]: " REDIS_USE_LOCAL
    REDIS_USE_LOCAL="${REDIS_USE_LOCAL:-Y}"
    
    if [[ ! "$REDIS_USE_LOCAL" =~ ^[Yy]$ ]]; then
        # 外部 Redis
        REDIS_INSTALL_LOCAL="N"
        echo -e "${GREEN}使用外部 Redis${NC}"
        echo ""
        
        read -p "Redis 主机地址 [127.0.0.1]: " REDIS_HOST
        REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
        
        read -p "Redis 端口 [6379]: " REDIS_PORT
        REDIS_PORT="${REDIS_PORT:-6379}"
        
        read -sp "Redis 密码（可选，直接回车跳过）: " REDIS_PASSWORD
        echo ""
        
        read -p "Redis 数据库编号 [0]: " REDIS_DB
        REDIS_DB="${REDIS_DB:-0}"
    else
        # 本地 Redis
        REDIS_INSTALL_LOCAL="Y"
        echo -e "${GREEN}使用本地 Redis，将自动安装${NC}"
        echo ""
        
        # 先安装 Redis
        echo -e "${BLUE}开始安装 Redis...${NC}"
        
        # 创建临时文件用于传递变量（在 install_redis.sh 执行前）
        TEMP_REDIS_VARS=$(mktemp)
        export TEMP_VARS_FILE="$TEMP_REDIS_VARS"
        
        if ! bash "${SCRIPTS_DIR}/install_redis.sh"; then
            echo -e "${YELLOW}⚠ Redis 安装失败，但这是可选步骤，将继续安装${NC}"
            echo "您可以稍后手动运行: sudo ${SCRIPTS_DIR}/install_redis.sh"
            USE_REDIS="N"
            REDIS_HOST=""
            REDIS_PORT=""
            REDIS_PASSWORD=""
            REDIS_DB=""
            rm -f "$TEMP_REDIS_VARS"
        else
            # 本地 Redis 默认配置
            REDIS_HOST="127.0.0.1"
            REDIS_PORT="6379"
            REDIS_DB="0"
            
            # 从 install_redis.sh 获取密码（如果已设置）
            # install_redis.sh 会在结束时写入密码到临时文件
            if [ -f "$TEMP_REDIS_VARS" ]; then
                source "$TEMP_REDIS_VARS" 2>/dev/null || true
            fi
            
            # 如果 install_redis.sh 未设置密码，询问用户
            if [ -z "$REDIS_PASSWORD" ]; then
                read -sp "Redis 密码（可选，直接回车跳过）: " REDIS_PASSWORD
                echo ""
            fi
            
            # 清理临时文件
            rm -f "$TEMP_REDIS_VARS"
            
            # 如果设置了密码，更新 Redis 配置（使用 Python，与 MySQL 一致）
            if [ -n "$REDIS_PASSWORD" ]; then
                REDIS_CONF=""
                if [ -f /etc/redis/redis.conf ]; then
                    REDIS_CONF="/etc/redis/redis.conf"
                elif [ -f /etc/redis.conf ]; then
                    REDIS_CONF="/etc/redis.conf"
                fi
                
                if [ -n "$REDIS_CONF" ] && command -v python3 &> /dev/null; then
                    # 使用 Python 更新 Redis 配置（支持特殊字符）
                    python3 << PYTHON_EOF
import re
import sys

redis_conf = "$REDIS_CONF"
redis_password = "$REDIS_PASSWORD"

try:
    with open(redis_conf, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 转义密码中的特殊字符
    escaped_password = redis_password.replace('\\', '\\\\').replace('$', '\\$').replace('`', '\\`')
    
    # 更新或添加 requirepass
    if re.search(r'^requirepass ', content, re.MULTILINE):
        content = re.sub(r'^requirepass .*', f'requirepass {escaped_password}', content, flags=re.MULTILINE)
    else:
        content += f'\nrequirepass {escaped_password}\n'
    
    with open(redis_conf, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print("✓ Redis 密码已设置")
except Exception as e:
    print(f"错误: {e}")
    sys.exit(1)
PYTHON_EOF
                    if [ $? -eq 0 ]; then
                        # 重启 Redis 服务
                        if command -v systemctl &> /dev/null; then
                            systemctl restart redis 2>/dev/null || systemctl restart redis-server 2>/dev/null || true
                        fi
                    fi
                elif [ -n "$REDIS_CONF" ]; then
                    # 备用方案：使用 sed（简单情况）
                    if grep -q "^requirepass " "$REDIS_CONF"; then
                        sed -i "s/^requirepass .*/requirepass ${REDIS_PASSWORD}/" "$REDIS_CONF"
                    else
                        echo "requirepass ${REDIS_PASSWORD}" >> "$REDIS_CONF"
                    fi
                    
                    # 重启 Redis 服务
                    if command -v systemctl &> /dev/null; then
                        systemctl restart redis 2>/dev/null || systemctl restart redis-server 2>/dev/null || true
                    fi
                fi
            fi
        fi
    fi
else
    REDIS_INSTALL_LOCAL="N"
    REDIS_HOST=""
    REDIS_PORT=""
    REDIS_PASSWORD=""
    REDIS_DB=""
fi

# GeoIP 配置（可选）
echo ""
echo -e "${CYAN}GeoIP 地域封控配置（可选）${NC}"
read -p "是否安装 GeoIP 数据库（用于地域封控）？[y/N]: " INSTALL_GEOIP
INSTALL_GEOIP="${INSTALL_GEOIP:-N}"

if [[ "$INSTALL_GEOIP" =~ ^[Yy]$ ]]; then
    read -p "MaxMind Account ID: " GEOIP_ACCOUNT_ID
    read -sp "MaxMind License Key: " GEOIP_LICENSE_KEY
    echo ""
    
    if [ -z "$GEOIP_ACCOUNT_ID" ] || [ -z "$GEOIP_LICENSE_KEY" ]; then
        echo -e "${YELLOW}警告: Account ID 或 License Key 为空，将跳过 GeoIP 安装${NC}"
        INSTALL_GEOIP="N"
    fi
fi

# 系统优化（可选）
echo ""
echo -e "${CYAN}系统优化配置${NC}"
read -p "是否执行系统优化（根据硬件自动优化）？[Y/n]: " OPTIMIZE_SYSTEM
OPTIMIZE_SYSTEM="${OPTIMIZE_SYSTEM:-Y}"

echo ""
echo -e "${GREEN}✓ 配置信息收集完成${NC}"
echo ""

# ============================================
# 步骤 2: 安装 OpenResty
# ============================================
echo -e "${BLUE}========================================${NC}"
if [[ "$MYSQL_INSTALL_LOCAL" == "Y" ]]; then
    echo -e "${BLUE}步骤 2/6: 安装 OpenResty${NC}"
else
    echo -e "${BLUE}步骤 2/7: 安装 OpenResty${NC}"
fi
echo -e "${BLUE}========================================${NC}"
echo ""

# 检查 OpenResty 是否已安装
if [ -f "${OPENRESTY_PREFIX}/bin/openresty" ]; then
    echo -e "${YELLOW}检测到 OpenResty 已安装${NC}"
    read -p "是否重新安装？[y/N]: " REINSTALL_OPENRESTY
    if [[ ! "$REINSTALL_OPENRESTY" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}跳过 OpenResty 安装${NC}"
    else
        echo -e "${GREEN}开始安装 OpenResty...${NC}"
        if ! bash "${SCRIPTS_DIR}/install_openresty.sh"; then
            echo -e "${RED}✗ OpenResty 安装失败${NC}"
            echo "请检查错误信息并重试"
            exit 1
        fi
    fi
else
    echo -e "${GREEN}开始安装 OpenResty...${NC}"
    if ! bash "${SCRIPTS_DIR}/install_openresty.sh"; then
        echo -e "${RED}✗ OpenResty 安装失败${NC}"
        echo "请检查错误信息并重试"
        exit 1
    fi
fi

echo ""

# ============================================
# 步骤 3: 部署配置文件
# ============================================
echo -e "${BLUE}========================================${NC}"
if [[ "$MYSQL_INSTALL_LOCAL" == "Y" ]]; then
    echo -e "${BLUE}步骤 3/6: 部署配置文件${NC}"
else
    echo -e "${BLUE}步骤 3/7: 部署配置文件${NC}"
fi
echo -e "${BLUE}========================================${NC}"
echo ""

echo -e "${GREEN}开始部署配置文件...${NC}"
if ! bash "${SCRIPTS_DIR}/deploy.sh"; then
    echo -e "${RED}✗ 配置文件部署失败${NC}"
    echo "请检查错误信息并重试"
    exit 1
fi

echo ""

# ============================================
# 步骤 4: 配置 MySQL 和 Redis
# ============================================
echo -e "${BLUE}========================================${NC}"
if [[ "$MYSQL_INSTALL_LOCAL" == "Y" ]]; then
    echo -e "${BLUE}步骤 4/6: 配置 MySQL 和 Redis${NC}"
else
    echo -e "${BLUE}步骤 4/7: 配置 MySQL 和 Redis${NC}"
fi
echo -e "${BLUE}========================================${NC}"
echo ""

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}错误: 配置文件不存在: $CONFIG_FILE${NC}"
    exit 1
fi

# 备份原配置文件
if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
    echo -e "${GREEN}✓ 已备份原配置文件${NC}"
fi

# 更新 MySQL 配置
echo -e "${GREEN}更新 MySQL 配置...${NC}"

# 更新 MySQL 配置
# 使用更安全的方式更新配置文件
update_mysql_config() {
    local config_file="$1"
    local mysql_host="$2"
    local mysql_port="$3"
    local mysql_database="$4"
    local mysql_user="$5"
    local mysql_password="$6"
    
    # 检查是否有 Python3
    if command -v python3 &> /dev/null; then
        python3 << PYTHON_EOF
import re
import sys

config_file = "$config_file"
mysql_host = "$mysql_host"
mysql_port = "$mysql_port"
mysql_database = "$mysql_database"
mysql_user = "$mysql_user"
mysql_password = "$mysql_password"

try:
    with open(config_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 更新 MySQL 配置（只更新 MySQL 部分，不更新 Redis 部分）
    # 使用更精确的匹配，确保只更新 MySQL 配置块
    mysql_block_pattern = r'(_M\.mysql = \{[\s\S]*?)(host = "127\.0\.0\.1")'
    replacement = r'\1host = "' + mysql_host + '"'
    content = re.sub(mysql_block_pattern, replacement, content)
    
    content = re.sub(r'(port = )3306', r'\1' + mysql_port, content)
    content = re.sub(r'(database = ")(waf_db)(")', r'\1' + mysql_database + r'\3', content)
    content = re.sub(r'(user = ")(waf_user)(")', r'\1' + mysql_user + r'\3', content)
    
    # 更新密码（需要转义引号和反斜杠）
    # 在 heredoc 中，反斜杠需要特殊处理
    # 先转义反斜杠（4个反斜杠 = 2个实际反斜杠），再转义双引号
    escaped_password = mysql_password.replace('\\', '\\\\').replace('"', '\\"')
    content = re.sub(r'(password = ")(waf_password)(")', r'\1' + escaped_password + r'\3', content)
    
    with open(config_file, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print("✓ MySQL 配置已更新")
except Exception as e:
    print(f"错误: {e}")
    sys.exit(1)
PYTHON_EOF
        return $?
    else
        # 备用方案：使用 sed（简单情况，不支持特殊字符）
        sed -i.bak "s|host = \"127.0.0.1\"|host = \"${mysql_host}\"|" "$config_file"
        sed -i.bak "s|port = 3306|port = ${mysql_port}|" "$config_file"
        sed -i.bak "s|database = \"waf_db\"|database = \"${mysql_database}\"|" "$config_file"
        sed -i.bak "s|user = \"waf_user\"|user = \"${mysql_user}\"|" "$config_file"
        # 密码需要手动处理
        echo -e "${YELLOW}警告: 请手动更新 MySQL 密码（密码可能包含特殊字符）${NC}"
        return 0
    fi
}

update_mysql_config "$CONFIG_FILE" "$MYSQL_HOST" "$MYSQL_PORT" "$MYSQL_DATABASE" "$MYSQL_USER" "$MYSQL_PASSWORD"

echo -e "${GREEN}✓ MySQL 配置已更新${NC}"

# 验证 Lua 配置文件语法
echo -e "${GREEN}验证配置文件语法...${NC}"
if command -v luajit &> /dev/null; then
    if luajit -bl "$CONFIG_FILE" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ 配置文件语法正确${NC}"
    else
        echo -e "${YELLOW}⚠ 警告: 配置文件语法检查失败，请手动检查${NC}"
    fi
elif command -v luac &> /dev/null; then
    if luac -p "$CONFIG_FILE" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ 配置文件语法正确${NC}"
    else
        echo -e "${YELLOW}⚠ 警告: 配置文件语法检查失败，请手动检查${NC}"
    fi
else
    echo -e "${YELLOW}⚠ 警告: 未找到 Lua 编译器，跳过语法检查${NC}"
fi

# 更新 Redis 配置（如果使用）
update_redis_config() {
    local config_file="$1"
    local redis_host="$2"
    local redis_port="$3"
    local redis_db="$4"
    local redis_password="$5"
    
    # 检查是否有 Python3
    if command -v python3 &> /dev/null; then
        python3 << PYTHON_EOF
import re
import sys

config_file = "$config_file"
redis_host = "$redis_host"
redis_port = "$redis_port"
redis_db = "$redis_db"
redis_password = "$redis_password"

try:
    with open(config_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 更新 Redis 配置（只更新 Redis 部分）
    redis_block_pattern = r'(_M\.redis = \{[\s\S]*?)(host = "127\.0\.0\.1")'
    replacement = r'\1host = "' + redis_host + '"'
    content = re.sub(redis_block_pattern, replacement, content)
    
    content = re.sub(r'(port = )6379', r'\1' + redis_port, content)
    content = re.sub(r'(db = )0', r'\1' + redis_db, content)
    
    # 更新密码
    if redis_password:
        # 在 heredoc 中，反斜杠需要特殊处理
        # 先转义反斜杠，再转义双引号
        escaped_password = redis_password.replace('\\', '\\\\').replace('"', '\\"')
        content = re.sub(r'password = nil', f'password = "{escaped_password}"', content)
    
    with open(config_file, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print("✓ Redis 配置已更新")
except Exception as e:
    print(f"错误: {e}")
    sys.exit(1)
PYTHON_EOF
        return $?
    else
        # 备用方案：使用 sed
        sed -i.bak "s|host = \"127.0.0.1\"|host = \"${redis_host}\"|" "$config_file"
        sed -i.bak "s|port = 6379|port = ${redis_port}|" "$config_file"
        sed -i.bak "s|db = 0|db = ${redis_db}|" "$config_file"
        if [ -n "$redis_password" ]; then
            echo -e "${YELLOW}警告: 请手动更新 Redis 密码${NC}"
        fi
        return 0
    fi
}

if [[ "$USE_REDIS" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}更新 Redis 配置...${NC}"
    update_redis_config "$CONFIG_FILE" "$REDIS_HOST" "$REDIS_PORT" "$REDIS_DB" "$REDIS_PASSWORD"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Redis 配置已更新${NC}"
        
        # 验证 Lua 配置文件语法（Redis 配置更新后）
        if command -v luajit &> /dev/null; then
            if luajit -bl "$CONFIG_FILE" > /dev/null 2>&1; then
                echo -e "${GREEN}✓ 配置文件语法正确${NC}"
            else
                echo -e "${YELLOW}⚠ 警告: 配置文件语法检查失败，请手动检查${NC}"
            fi
        elif command -v luac &> /dev/null; then
            if luac -p "$CONFIG_FILE" > /dev/null 2>&1; then
                echo -e "${GREEN}✓ 配置文件语法正确${NC}"
            else
                echo -e "${YELLOW}⚠ 警告: 配置文件语法检查失败，请手动检查${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}警告: 更新 Redis 配置失败，请手动更新${NC}"
    fi
else
    echo -e "${YELLOW}跳过 Redis 配置${NC}"
fi

echo ""

# ============================================
# 步骤 5: 初始化数据库
# ============================================
echo -e "${BLUE}========================================${NC}"
if [[ "$MYSQL_INSTALL_LOCAL" == "Y" ]]; then
    echo -e "${BLUE}步骤 5/6: 初始化数据库${NC}"
else
    echo -e "${BLUE}步骤 5/7: 初始化数据库${NC}"
fi
echo -e "${BLUE}========================================${NC}"
echo ""

SQL_FILE="${PROJECT_ROOT}/init_file/数据库设计.sql"

if [ ! -f "$SQL_FILE" ]; then
    echo -e "${RED}错误: SQL 文件不存在: $SQL_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}开始初始化数据库...${NC}"
echo "数据库: $MYSQL_DATABASE"
echo "用户: $MYSQL_USER"
echo ""

# 测试 MySQL 连接
echo "测试 MySQL 连接..."
if mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SELECT 1;" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ MySQL 连接成功${NC}"
else
    echo -e "${RED}✗ MySQL 连接失败${NC}"
    echo "请检查："
    echo "  1. MySQL 服务是否启动"
    echo "  2. 用户名和密码是否正确"
    echo "  3. 用户是否有创建数据库的权限"
    read -p "是否继续？[y/N]: " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 执行 SQL 脚本
echo "执行 SQL 脚本..."
SQL_OUTPUT=$(mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < "$SQL_FILE" 2>&1)
SQL_EXIT_CODE=$?

if [ $SQL_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ 数据库初始化成功${NC}"
else
    # 检查是否是"表已存在"的错误（这是正常的）
    if echo "$SQL_OUTPUT" | grep -qi "already exists\|Duplicate\|exists"; then
        echo -e "${YELLOW}⚠ 部分表可能已存在，这是正常的${NC}"
        echo -e "${GREEN}✓ 数据库初始化完成${NC}"
    else
        echo -e "${YELLOW}⚠ 数据库初始化可能有问题，请检查错误信息${NC}"
        echo "错误信息："
        echo "$SQL_OUTPUT" | head -20
    fi
fi

echo ""

# ============================================
# 步骤 6: 安装 GeoIP（可选）
# ============================================
if [[ "$INSTALL_GEOIP" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}========================================${NC}"
    if [[ "$MYSQL_INSTALL_LOCAL" == "Y" ]]; then
        echo -e "${BLUE}步骤 6/6: 安装 GeoIP 数据库${NC}"
    else
        echo -e "${BLUE}步骤 6/7: 安装 GeoIP 数据库${NC}"
    fi
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    echo -e "${GREEN}开始安装 GeoIP 数据库...${NC}"
    if ! bash "${SCRIPTS_DIR}/install_geoip.sh" "$GEOIP_ACCOUNT_ID" "$GEOIP_LICENSE_KEY"; then
        echo -e "${YELLOW}⚠ GeoIP 安装失败，但这是可选步骤，将继续安装${NC}"
        echo "您可以稍后手动运行: sudo ${SCRIPTS_DIR}/install_geoip.sh"
    else
        echo -e "${GREEN}✓ GeoIP 安装成功${NC}"
    fi
    
    echo ""
fi

# ============================================
# 步骤 7: 系统优化（可选）
# ============================================
if [[ "$OPTIMIZE_SYSTEM" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}========================================${NC}"
    if [[ "$MYSQL_INSTALL_LOCAL" == "Y" ]]; then
        echo -e "${BLUE}步骤 7/7: 系统优化${NC}"
    else
        echo -e "${BLUE}步骤 7/7: 系统优化${NC}"
    fi
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    echo -e "${GREEN}开始系统优化...${NC}"
    if ! bash "${SCRIPTS_DIR}/optimize_system.sh"; then
        echo -e "${YELLOW}⚠ 系统优化失败，但这是可选步骤，将继续安装${NC}"
        echo "您可以稍后手动运行: sudo ${SCRIPTS_DIR}/optimize_system.sh"
    else
        echo -e "${GREEN}✓ 系统优化成功${NC}"
    fi
    
    echo ""
fi

# ============================================
# 安装完成
# ============================================
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}安装完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${BLUE}配置信息总结：${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "MySQL:"
echo "  主机: $MYSQL_HOST"
echo "  端口: $MYSQL_PORT"
echo "  数据库: $MYSQL_DATABASE"
echo "  用户: $MYSQL_USER"
echo ""

if [[ "$USE_REDIS" =~ ^[Yy]$ ]]; then
    echo "Redis:"
    echo "  主机: $REDIS_HOST"
    echo "  端口: $REDIS_PORT"
    echo "  数据库: $REDIS_DB"
    echo ""
fi

if [[ "$INSTALL_GEOIP" =~ ^[Yy]$ ]]; then
    echo "GeoIP: 已安装"
    echo ""
fi

if [[ "$OPTIMIZE_SYSTEM" =~ ^[Yy]$ ]]; then
    echo "系统优化: 已执行"
    echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
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
echo "   tail -f ${PROJECT_ROOT}/logs/error.log"
echo "   tail -f ${PROJECT_ROOT}/logs/access.log"
echo ""
echo "5. 添加封控规则（参考文档）:"
echo "   docs/地域封控使用示例.md"
echo ""
echo -e "${YELLOW}提示:${NC}"
echo "  - 配置文件位置: ${PROJECT_ROOT}/lua/config.lua"
echo "  - 配置文件已备份: ${CONFIG_FILE}.bak.*"
echo "  - 修改配置后无需重新部署，直接 reload 即可"
echo ""

