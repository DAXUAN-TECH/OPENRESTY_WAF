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

# 获取项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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
echo -e "${BLUE}[1/5] 检查脚本文件...${NC}"
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
echo -e "${BLUE}[2/5] 检查重复逻辑...${NC}"

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
echo -e "${BLUE}[3/5] 检查路径引用...${NC}"

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

# 4. 检查脚本逻辑完整性
echo -e "${BLUE}[4/5] 检查脚本逻辑完整性...${NC}"

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

# 检查关键脚本的特定函数
if grep -q "check_root\|get_credentials\|download_database\|extract_database\|install_database\|save_config\|setup_crontab" scripts/install_geoip.sh; then
    check_ok "install_geoip.sh 关键函数存在"
else
    check_error "install_geoip.sh 关键函数缺失"
fi

if grep -q "load_config\|check_dependencies\|download_database\|extract_database\|install_database" scripts/update_geoip.sh; then
    check_ok "update_geoip.sh 关键函数存在"
else
    check_error "update_geoip.sh 关键函数缺失"
fi

if grep -q "PROJECT_ROOT\|NGINX_CONF_DIR\|sed.*project_root" scripts/deploy.sh; then
    check_ok "deploy.sh 关键逻辑存在"
else
    check_error "deploy.sh 关键逻辑缺失"
fi

if grep -q "CPU_CORES\|WORKER_PROCESSES\|ULIMIT_NOFILE\|BACKUP_DIR" scripts/optimize_system.sh; then
    check_ok "optimize_system.sh 关键变量存在"
else
    check_error "optimize_system.sh 关键变量缺失"
fi

echo ""

# 5. 检查文件存在性
echo -e "${BLUE}[5/5] 检查必要文件...${NC}"

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
    if [ -f "$PROJECT_ROOT/$file" ]; then
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

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ 所有检查通过！${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ 有警告，但无错误${NC}"
    exit 0
else
    echo -e "${RED}✗ 发现错误，请修复${NC}"
    exit 1
fi

