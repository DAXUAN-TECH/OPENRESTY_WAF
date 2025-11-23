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
echo -e "${BLUE}[2/6] 检查重复逻辑...${NC}"

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
echo -e "${BLUE}[3/6] 检查路径引用...${NC}"

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
echo -e "${BLUE}[4/6] 检查脚本逻辑完整性和关键修复项...${NC}"

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

# install.sh 关键修复项检查
if grep -q "TEMP_VARS_FILE\|CREATED_DB_NAME\|MYSQL_USER_FOR_WAF" install.sh; then
    check_ok "install.sh 变量传递机制存在"
else
    check_error "install.sh 变量传递机制缺失"
fi

if grep -q "CURRENT_STEP\|TOTAL_STEPS" install.sh; then
    check_ok "install.sh 动态步骤编号存在"
else
    check_error "install.sh 动态步骤编号缺失"
fi

if grep -q "python3.*redis_password\|Redis 密码已设置" install.sh; then
    check_ok "install.sh Redis 密码 Python 更新存在"
else
    check_error "install.sh Redis 密码 Python 更新缺失"
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
echo -e "${BLUE}[5/6] 检查错误处理机制...${NC}"

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
for script in install.sh scripts/install_mysql.sh scripts/install_redis.sh scripts/deploy.sh; do
    if [ -f "$script" ]; then
        check_error_handling "$script"
    fi
done

echo ""

# 6. 检查文件存在性
echo -e "${BLUE}[6/6] 检查必要文件...${NC}"

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
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}检查完成${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "错误: $ERRORS"
echo "警告: $WARNINGS"

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

