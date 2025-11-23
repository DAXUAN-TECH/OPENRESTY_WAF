#!/bin/bash

# MySQL 密码修复脚本
# 用于修复密码修改失败的问题

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}MySQL 密码修复脚本${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 获取临时密码
TEMP_PASSWORD=""
for log_file in /var/log/mysqld.log /var/log/mysql/error.log /var/log/mysql/mysql.log /var/log/mariadb/mariadb.log; do
    if [ -f "$log_file" ]; then
        TEMP_PASSWORD=$(grep 'temporary password' "$log_file" 2>/dev/null | awk '{print $NF}' | tail -1)
        if [ -n "$TEMP_PASSWORD" ]; then
            break
        fi
    fi
done

if [ -z "$TEMP_PASSWORD" ]; then
    echo -e "${YELLOW}⚠ 未找到临时密码，请手动输入临时密码${NC}"
    read -sp "请输入 MySQL 临时密码（如果已修改过密码，请输入当前密码）: " TEMP_PASSWORD
    echo ""
fi

if [ -z "$TEMP_PASSWORD" ]; then
    echo -e "${RED}错误: 密码不能为空${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}步骤 1: 测试临时密码连接...${NC}"
# 创建临时配置文件
TEMP_CNF=$(mktemp)
cat > "$TEMP_CNF" <<CNF_EOF
[client]
user=root
password=${TEMP_PASSWORD}
CNF_EOF
chmod 600 "$TEMP_CNF"

# 测试连接
if mysql --connect-expired-password --defaults-file="$TEMP_CNF" -e "SELECT 1;" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ 临时密码连接成功${NC}"
    IS_TEMP_PASSWORD=1
elif mysql --defaults-file="$TEMP_CNF" -e "SELECT 1;" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ 密码连接成功（非临时密码）${NC}"
    IS_TEMP_PASSWORD=0
else
    echo -e "${RED}✗ 密码连接失败，请检查密码是否正确${NC}"
    rm -f "$TEMP_CNF"
    exit 1
fi

echo ""
echo -e "${BLUE}步骤 2: 设置新密码...${NC}"
read -sp "请输入新的 MySQL root 密码: " NEW_PASSWORD
echo ""
if [ -z "$NEW_PASSWORD" ]; then
    echo -e "${RED}错误: 密码不能为空${NC}"
    rm -f "$TEMP_CNF"
    exit 1
fi

# 使用 Python 安全地转义密码并生成 SQL
SQL_FILE=$(mktemp)
if command -v python3 &> /dev/null; then
    NEW_MYSQL_PASSWORD="$NEW_PASSWORD" python3 <<'PYTHON_EOF' > "$SQL_FILE"
import os
import sys
new_password = os.environ.get('NEW_MYSQL_PASSWORD', '')
# 转义 SQL 中的单引号（将 ' 替换为 ''）
escaped_password = new_password.replace("'", "''")
# 生成修改所有 root 用户密码的 SQL
sql = f"""ALTER USER 'root'@'localhost' IDENTIFIED BY '{escaped_password}';
ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '{escaped_password}';
ALTER USER 'root'@'::1' IDENTIFIED BY '{escaped_password}';
FLUSH PRIVILEGES;"""
print(sql)
PYTHON_EOF
else
    # 如果没有 Python，使用 sed 转义单引号
    ESCAPED_PASSWORD=$(echo "$NEW_PASSWORD" | sed "s/'/''/g")
    cat > "$SQL_FILE" <<SQL_EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${ESCAPED_PASSWORD}';
ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '${ESCAPED_PASSWORD}';
ALTER USER 'root'@'::1' IDENTIFIED BY '${ESCAPED_PASSWORD}';
FLUSH PRIVILEGES;
SQL_EOF
fi

# 执行密码修改
echo "正在修改密码..."
if [ $IS_TEMP_PASSWORD -eq 1 ]; then
    ERROR_OUTPUT=$(mysql --connect-expired-password --defaults-file="$TEMP_CNF" < "$SQL_FILE" 2>&1)
else
    ERROR_OUTPUT=$(mysql --defaults-file="$TEMP_CNF" < "$SQL_FILE" 2>&1)
fi
EXIT_CODE=$?
rm -f "$SQL_FILE"
rm -f "$TEMP_CNF"

if [ $EXIT_CODE -ne 0 ]; then
    echo -e "${RED}✗ 密码修改失败${NC}"
    echo -e "${YELLOW}错误信息:${NC}"
    echo "$ERROR_OUTPUT" | grep -v "Warning: Using a password" || echo "$ERROR_OUTPUT"
    exit 1
fi

echo -e "${GREEN}✓ 密码修改成功${NC}"

echo ""
echo -e "${BLUE}步骤 3: 验证新密码...${NC}"
# 创建新密码的配置文件
NEW_CNF=$(mktemp)
cat > "$NEW_CNF" <<CNF_EOF
[client]
user=root
password=${NEW_PASSWORD}
CNF_EOF
chmod 600 "$NEW_CNF"

# 验证新密码
if mysql --defaults-file="$NEW_CNF" -e "SELECT 1;" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ 新密码验证成功${NC}"
    rm -f "$NEW_CNF"
else
    echo -e "${RED}✗ 新密码验证失败${NC}"
    rm -f "$NEW_CNF"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}密码修复完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}新密码: ${NEW_PASSWORD}${NC}"
echo ""
echo -e "${BLUE}测试连接:${NC}"
echo "  mysql -u root -p'${NEW_PASSWORD}'"
echo ""
echo -e "${BLUE}或者使用配置文件方式（推荐，避免特殊字符问题）:${NC}"
echo "  echo '[client]' > ~/.my.cnf"
echo "  echo 'user=root' >> ~/.my.cnf"
echo "  echo 'password=${NEW_PASSWORD}' >> ~/.my.cnf"
echo "  chmod 600 ~/.my.cnf"
echo "  mysql -e 'SELECT 1;'"
echo ""

