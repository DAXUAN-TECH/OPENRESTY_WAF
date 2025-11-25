#!/bin/bash

# 设置 Lua 数据库连接配置脚本
# 用途：更新 config.lua 中的 MySQL 和 Redis 连接配置

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

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../lua/config.lua"

# 更新 MySQL 配置
update_mysql_config() {
    local mysql_host="$1"
    local mysql_port="$2"
    local mysql_database="$3"
    local mysql_user="$4"
    local mysql_password="$5"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}错误: 配置文件不存在: $CONFIG_FILE${NC}"
        return 1
    fi
    
    # 备份原配置文件
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        echo -e "${GREEN}✓ 已备份原配置文件${NC}"
    fi
    
    # 检查是否有 Python3
    if command -v python3 &> /dev/null; then
        python3 << PYTHON_EOF
import re
import sys

config_file = "$CONFIG_FILE"
mysql_host = "$mysql_host"
mysql_port = "$mysql_port"
mysql_database = "$mysql_database"
mysql_user = "$mysql_user"
mysql_password = "$mysql_password"

try:
    with open(config_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 更新 MySQL 配置（只更新 MySQL 部分，不更新 Redis 部分）
    # 使用更灵活的正则表达式，匹配任何当前值（不仅仅是默认值）
    
    # 更新 host（匹配任何引号内的值）
    content = re.sub(r'(_M\.mysql = \{[\s\S]*?)(host\s*=\s*")[^"]+(")', r'\1' + mysql_host + r'\2', content)
    
    # 更新 port（匹配任何数字，包括逗号）
    content = re.sub(r'(_M\.mysql = \{[\s\S]*?)(port\s*=\s*)\d+', r'\1' + mysql_port, content)
    
    # 更新 database（匹配任何引号内的值）
    content = re.sub(r'(_M\.mysql = \{[\s\S]*?)(database\s*=\s*")[^"]+(")', r'\1' + mysql_database + r'\2', content)
    
    # 更新 user（匹配任何引号内的值）
    content = re.sub(r'(_M\.mysql = \{[\s\S]*?)(user\s*=\s*")[^"]+(")', r'\1' + mysql_user + r'\2', content)
    
    # 更新密码（需要转义引号和反斜杠，匹配任何引号内的值）
    escaped_password = mysql_password.replace('\\\\', '\\\\\\\\').replace('"', '\\\\"')
    content = re.sub(r'(_M\.mysql = \{[\s\S]*?)(password\s*=\s*")[^"]+(")', r'\1' + escaped_password + r'\2', content)
    
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
        # 使用更灵活的正则表达式，匹配任何当前值
        sed -i.bak "s|host = \"[^\"]*\"|host = \"${mysql_host}\"|" "$CONFIG_FILE"
        sed -i.bak "s|port = [0-9]*|port = ${mysql_port}|" "$CONFIG_FILE"
        sed -i.bak "s|database = \"[^\"]*\"|database = \"${mysql_database}\"|" "$CONFIG_FILE"
        sed -i.bak "s|user = \"[^\"]*\"|user = \"${mysql_user}\"|" "$CONFIG_FILE"
        if [ -n "$mysql_password" ]; then
            # 转义特殊字符用于 sed（转义 |、\、& 等）
            escaped_password=$(echo "$mysql_password" | sed 's/[[\.*^$()+?{|]/\\&/g' | sed 's/|/\\|/g' | sed 's/\\/\\\\/g')
            sed -i.bak "s|password = \"[^\"]*\"|password = \"${escaped_password}\"|" "$CONFIG_FILE"
        else
            # 即使密码为空，也更新配置文件（设置为空字符串）
            sed -i.bak "s|password = \"[^\"]*\"|password = \"\"|" "$CONFIG_FILE"
        fi
        return 0
    fi
}

# 更新 Redis 配置
update_redis_config() {
    local redis_host="$1"
    local redis_port="$2"
    local redis_db="$3"
    local redis_password="$4"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}错误: 配置文件不存在: $CONFIG_FILE${NC}"
        return 1
    fi
    
    # 检查是否有 Python3
    if command -v python3 &> /dev/null; then
        python3 << PYTHON_EOF
import re
import sys

config_file = "$CONFIG_FILE"
redis_host = "$redis_host"
redis_port = "$redis_port"
redis_db = "$redis_db"
redis_password = "$redis_password"

try:
    with open(config_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 更新 Redis 配置（只更新 Redis 部分）
    # 使用更灵活的正则表达式，匹配任何当前值（不仅仅是默认值）
    
    # 更新 host（匹配任何引号内的值）
    content = re.sub(r'(_M\.redis = \{[\s\S]*?)(host\s*=\s*")[^"]+(")', r'\1' + redis_host + r'\2', content)
    
    # 更新 port（匹配任何数字，包括逗号）
    content = re.sub(r'(_M\.redis = \{[\s\S]*?)(port\s*=\s*)\d+', r'\1' + redis_port, content)
    
    # 更新 db（匹配任何数字，包括逗号）
    content = re.sub(r'(_M\.redis = \{[\s\S]*?)(db\s*=\s*)\d+', r'\1' + redis_db, content)
    
    # 更新密码
    if redis_password:
        escaped_password = redis_password.replace('\\\\', '\\\\\\\\').replace('"', '\\\\"')
        # 匹配 password = nil 或 password = "xxx" 两种情况
        content = re.sub(r'(_M\.redis = \{[\s\S]*?)(password\s*=\s*)(nil|"[^"]*")', r'\1password = "' + escaped_password + '"', content)
    else:
        # 如果没有密码，设置为 nil
        content = re.sub(r'(_M\.redis = \{[\s\S]*?)(password\s*=\s*)(nil|"[^"]*")', r'\1password = nil', content)
    
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
        # 使用更灵活的正则表达式，匹配任何当前值
        sed -i.bak "s|host = \"[^\"]*\"|host = \"${redis_host}\"|" "$CONFIG_FILE"
        sed -i.bak "s|port = [0-9]*|port = ${redis_port}|" "$CONFIG_FILE"
        sed -i.bak "s|db = [0-9]*|db = ${redis_db}|" "$CONFIG_FILE"
        if [ -n "$redis_password" ]; then
            # 转义特殊字符用于 sed（转义 |、\、& 等）
            escaped_password=$(echo "$redis_password" | sed 's/[[\.*^$()+?{|]/\\&/g' | sed 's/|/\\|/g' | sed 's/\\/\\\\/g')
            # 匹配 password = nil 或 password = "xxx"
            sed -i.bak "s|password = nil|password = \"${escaped_password}\"|" "$CONFIG_FILE"
            sed -i.bak "s|password = \"[^\"]*\"|password = \"${escaped_password}\"|" "$CONFIG_FILE"
        else
            # 如果没有密码，设置为 nil
            sed -i.bak "s|password = nil|password = nil|" "$CONFIG_FILE"  # 已经是 nil，不需要修改
            sed -i.bak "s|password = \"[^\"]*\"|password = nil|" "$CONFIG_FILE"
        fi
        return 0
    fi
}

# 验证配置文件语法
verify_config_syntax() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}错误: 配置文件不存在: $CONFIG_FILE${NC}"
        return 1
    fi
    
    echo -e "${GREEN}验证配置文件语法...${NC}"
    if command -v luajit &> /dev/null; then
        if luajit -bl "$CONFIG_FILE" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ 配置文件语法正确${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠ 警告: 配置文件语法检查失败，请手动检查${NC}"
            return 1
        fi
    elif command -v luac &> /dev/null; then
        if luac -p "$CONFIG_FILE" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ 配置文件语法正确${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠ 警告: 配置文件语法检查失败，请手动检查${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}⚠ 警告: 未找到 Lua 编译器，跳过语法检查${NC}"
        return 0
    fi
}

# 交互式更新 MySQL 配置
interactive_mysql() {
    echo -e "${BLUE}交互式更新 MySQL 配置${NC}"
    echo ""
    
    read -p "MySQL Host [127.0.0.1]: " MYSQL_HOST
    MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
    
    read -p "MySQL Port [3306]: " MYSQL_PORT
    MYSQL_PORT="${MYSQL_PORT:-3306}"
    
    read -p "MySQL Database [waf_db]: " MYSQL_DB
    MYSQL_DB="${MYSQL_DB:-waf_db}"
    
    read -p "MySQL User [waf_user]: " MYSQL_USER
    MYSQL_USER="${MYSQL_USER:-waf_user}"
    
    read -p "MySQL Password: " MYSQL_PASS
    
    if [ -z "$MYSQL_PASS" ]; then
        echo -e "${YELLOW}警告: 密码为空${NC}"
        read -p "确认使用空密码？[y/N]: " CONFIRM_EMPTY
        CONFIRM_EMPTY="${CONFIRM_EMPTY:-N}"
        if [[ ! "$CONFIRM_EMPTY" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}取消配置更新${NC}"
            return 1
        fi
    fi
    
    update_mysql_config "$MYSQL_HOST" "$MYSQL_PORT" "$MYSQL_DB" "$MYSQL_USER" "$MYSQL_PASS"
    verify_config_syntax
}

# 交互式更新 Redis 配置
interactive_redis() {
    echo -e "${BLUE}交互式更新 Redis 配置${NC}"
    echo ""
    
    read -p "Redis Host [127.0.0.1]: " REDIS_HOST
    REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
    
    read -p "Redis Port [6379]: " REDIS_PORT
    REDIS_PORT="${REDIS_PORT:-6379}"
    
    read -p "Redis DB [0]: " REDIS_DB
    REDIS_DB="${REDIS_DB:-0}"
    
    read -p "Redis Password (留空表示无密码): " REDIS_PASS
    
    update_redis_config "$REDIS_HOST" "$REDIS_PORT" "$REDIS_DB" "$REDIS_PASS"
    verify_config_syntax
}

# 交互式菜单
interactive_menu() {
    echo -e "${BLUE}请选择要更新的配置:${NC}"
    echo "1. MySQL 配置"
    echo "2. Redis 配置"
    echo "3. 验证配置文件语法"
    read -p "请选择 [1-3]: " CONFIG_CHOICE
    
    case "$CONFIG_CHOICE" in
        1)
            interactive_mysql
            ;;
        2)
            interactive_redis
            ;;
        3)
            verify_config_syntax
            ;;
        *)
            echo -e "${RED}错误: 无效的选择${NC}"
            return 1
            ;;
    esac
}

# 主函数
main() {
    local action="${1:-interactive}"
    
    case "$action" in
        mysql)
            if [ $# -eq 1 ]; then
                # 没有参数，使用交互式模式
                interactive_mysql
            elif [ $# -ne 6 ]; then
                echo "用法: $0 mysql [<host> <port> <database> <user> <password>]"
                echo "  或: $0 mysql  # 交互式模式"
                exit 1
            else
                update_mysql_config "$2" "$3" "$4" "$5" "$6"
                verify_config_syntax
            fi
            ;;
        redis)
            if [ $# -eq 1 ]; then
                # 没有参数，使用交互式模式
                interactive_redis
            elif [ $# -ne 5 ]; then
                echo "用法: $0 redis [<host> <port> <db> <password>]"
                echo "  或: $0 redis  # 交互式模式"
                exit 1
            else
                update_redis_config "$2" "$3" "$4" "$5"
                verify_config_syntax
            fi
            ;;
        verify)
            verify_config_syntax
            ;;
        interactive|"")
            interactive_menu
            ;;
        *)
            echo "用法: $0 {mysql|redis|verify|interactive} [参数...]"
            echo ""
            echo "模式:"
            echo "  interactive  - 交互式模式（默认）"
            echo "  mysql        - 更新 MySQL 配置（可带参数或交互式）"
            echo "  redis        - 更新 Redis 配置（可带参数或交互式）"
            echo "  verify       - 验证配置文件语法"
            echo ""
            echo "示例:"
            echo "  $0                          # 交互式菜单"
            echo "  $0 mysql                    # 交互式更新 MySQL"
            echo "  $0 mysql 127.0.0.1 3306 waf_db waf_user password"
            echo "  $0 redis                    # 交互式更新 Redis"
            echo "  $0 redis 127.0.0.1 6379 0 password"
            echo "  $0 verify"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"

