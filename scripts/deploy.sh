#!/bin/bash

# OpenResty WAF 部署脚本
# 用途：自动部署配置文件，使用相对路径和 $project_root 变量

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

# 获取脚本目录（使用相对路径）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."

# OpenResty 安装目录
OPENRESTY_PREFIX="${OPENRESTY_PREFIX:-/usr/local/openresty}"
NGINX_CONF_DIR="${OPENRESTY_PREFIX}/nginx/conf"

# 获取项目根目录的绝对路径（仅用于写入配置文件，因为 error_log 和 pid 不支持变量）
PROJECT_ROOT_ABS="$(cd "$PROJECT_ROOT" && pwd)"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}OpenResty WAF 部署脚本${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "项目根目录: $PROJECT_ROOT_ABS"
echo "OpenResty 前缀: $OPENRESTY_PREFIX"
echo "Nginx 配置目录: $NGINX_CONF_DIR"
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}警告: 需要 root 权限来部署文件${NC}"
    echo "请使用: sudo $0"
    exit 1
fi

# 创建必要的目录（如果不存在）
echo -e "${GREEN}[1/3] 检查并创建目录...${NC}"
if [ ! -d "${PROJECT_ROOT}/logs" ]; then
    mkdir -p "${PROJECT_ROOT}/logs"
    echo -e "${GREEN}✓ 已创建: logs/${NC}"
else
    echo -e "${BLUE}✓ 已存在: logs/${NC}"
fi

if [ ! -d "${PROJECT_ROOT}/lua/geoip" ]; then
    mkdir -p "${PROJECT_ROOT}/lua/geoip"
    echo -e "${GREEN}✓ 已创建: lua/geoip/${NC}"
else
    echo -e "${BLUE}✓ 已存在: lua/geoip/${NC}"
fi

if [ ! -d "${PROJECT_ROOT}/conf.d/cert" ]; then
    mkdir -p "${PROJECT_ROOT}/conf.d/cert"
    echo -e "${GREEN}✓ 已创建: conf.d/cert/${NC}"
else
    echo -e "${BLUE}✓ 已存在: conf.d/cert/${NC}"
fi

if [ ! -d "${PROJECT_ROOT}/conf.d/upstream" ]; then
    mkdir -p "${PROJECT_ROOT}/conf.d/upstream"
    echo -e "${GREEN}✓ 已创建: conf.d/upstream/${NC}"
else
    echo -e "${BLUE}✓ 已存在: conf.d/upstream/${NC}"
fi

if [ ! -d "${PROJECT_ROOT}/conf.d/upstream/HTTP_HTTPS" ]; then
    mkdir -p "${PROJECT_ROOT}/conf.d/upstream/HTTP_HTTPS"
    echo -e "${GREEN}✓ 已创建: conf.d/upstream/HTTP_HTTPS/${NC}"
else
    echo -e "${BLUE}✓ 已存在: conf.d/upstream/HTTP_HTTPS/${NC}"
fi

if [ ! -d "${PROJECT_ROOT}/conf.d/upstream/TCP_UDP" ]; then
    mkdir -p "${PROJECT_ROOT}/conf.d/upstream/TCP_UDP"
    echo -e "${GREEN}✓ 已创建: conf.d/upstream/TCP_UDP/${NC}"
else
    echo -e "${BLUE}✓ 已存在: conf.d/upstream/TCP_UDP/${NC}"
fi
echo -e "${GREEN}✓ 目录检查完成${NC}"

# 复制 nginx.conf（只复制主配置文件）
echo -e "${GREEN}[2/3] 复制并配置主配置文件...${NC}"

# 步骤1: 先删除旧文件，确保干净开始
if [ -f "$NGINX_CONF_DIR/nginx.conf" ]; then
    echo -e "${YELLOW}  删除旧配置文件: $NGINX_CONF_DIR/nginx.conf${NC}"
    rm -f "$NGINX_CONF_DIR/nginx.conf"
fi

# 步骤2: 复制模板文件到目标位置（不进行任何替换）
echo -e "${YELLOW}  复制模板文件: ${PROJECT_ROOT}/init_file/nginx.conf -> $NGINX_CONF_DIR/nginx.conf${NC}"
cp "${PROJECT_ROOT}/init_file/nginx.conf" "$NGINX_CONF_DIR/nginx.conf"

# 步骤3: 获取项目目录并修改配置（替换路径占位符）
echo -e "${YELLOW}  替换路径占位符...${NC}"
# 替换 error.log 路径
sed -i "s|/path/to/project/logs/error.log|$PROJECT_ROOT_ABS/logs/error.log|g" "$NGINX_CONF_DIR/nginx.conf"
# 替换 conf.d/set_conf 路径
sed -i "s|/path/to/project/conf.d/set_conf|$PROJECT_ROOT_ABS/conf.d/set_conf|g" "$NGINX_CONF_DIR/nginx.conf"
# 替换 conf.d/vhost_conf 路径
sed -i "s|/path/to/project/conf.d/vhost_conf|$PROJECT_ROOT_ABS/conf.d/vhost_conf|g" "$NGINX_CONF_DIR/nginx.conf"
# 替换 conf.d/upstream 路径（包括子目录）
sed -i "s|/path/to/project/conf.d/upstream|$PROJECT_ROOT_ABS/conf.d/upstream|g" "$NGINX_CONF_DIR/nginx.conf"

# 删除 set $project_root 指令（某些 OpenResty 版本不支持在 http 块中使用 set）
# 我们会在子配置文件中直接替换 $project_root 为实际路径
sed -i '/set \$project_root/d' "$NGINX_CONF_DIR/nginx.conf"
# 删除相关的注释行（如果存在）
sed -i '/项目根目录变量/d' "$NGINX_CONF_DIR/nginx.conf"
sed -i '/此变量必须在 http 块的最开始设置/d' "$NGINX_CONF_DIR/nginx.conf"

# 替换子配置文件中的 $project_root 变量为实际路径
# 注意：由于某些 OpenResty 版本不支持在 http 块中使用 set 指令
# 我们直接在子配置文件中替换 $project_root 为实际路径
# 注意：只替换 conf.d/set_conf 和 conf.d/vhost_conf 目录下的配置文件
echo -e "${YELLOW}  替换子配置文件中的 \$project_root 变量...${NC}"

# 需要替换的文件列表（明确指定，避免误替换）
REPLACE_FILES=(
    "$PROJECT_ROOT_ABS/conf.d/set_conf/lua.conf"
    "$PROJECT_ROOT_ABS/conf.d/set_conf/log.conf"
)

# 替换指定文件
for file in "${REPLACE_FILES[@]}"; do
    if [ -f "$file" ]; then
        # 检查文件是否包含 $project_root 变量
        if grep -q "\$project_root" "$file"; then
            # 只替换 $project_root 变量，不替换其他内容
            sed -i "s|\$project_root|$PROJECT_ROOT_ABS|g" "$file"
            echo -e "${GREEN}  ✓ 已替换: $(basename $file)${NC}"
        else
            echo -e "${BLUE}  - 跳过: $(basename $file) (不包含 \$project_root)${NC}"
        fi
    else
        echo -e "${YELLOW}  ⚠ 文件不存在: $(basename $file)${NC}"
    fi
done

# 替换 conf.d/vhost_conf 目录下可能使用 $project_root 的配置文件（如果有）
if [ -d "$PROJECT_ROOT_ABS/conf.d/vhost_conf" ]; then
    find "$PROJECT_ROOT_ABS/conf.d/vhost_conf" -name "*.conf" -type f | while read -r file; do
        if grep -q "\$project_root" "$file"; then
            sed -i "s|\$project_root|$PROJECT_ROOT_ABS|g" "$file"
            echo -e "${GREEN}  ✓ 已替换: vhost_conf/$(basename $file)${NC}"
        fi
    done
fi

echo -e "${GREEN}✓ 已替换子配置文件中的变量${NC}"

# 步骤3.5: 立即验证并清理重复内容（在替换后立即执行）
# 找到 http 块结束位置并强制截取
http_start_line=$(grep -n "^http {" "$NGINX_CONF_DIR/nginx.conf" | cut -d: -f1 | head -1)
if [ -n "$http_start_line" ]; then
    http_end_line=$(awk -v start="$http_start_line" '
        BEGIN { brace_count = 0; found_start = 0 }
        NR >= start {
            if (!found_start) found_start = 1
            for (i = 1; i <= length($0); i++) {
                char = substr($0, i, 1)
                if (char == "{") brace_count++
                if (char == "}") {
                    brace_count--
                    if (brace_count == 0 && found_start) {
                        print NR
                        exit
                    }
                }
            }
        }
    ' "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null)
    
    if [ -n "$http_end_line" ]; then
        # 强制截取到 http 块结束位置（确保没有多余内容）
        head -n "$http_end_line" "$NGINX_CONF_DIR/nginx.conf" > "$NGINX_CONF_DIR/nginx.conf.tmp"
        if [ $? -eq 0 ]; then
            mv "$NGINX_CONF_DIR/nginx.conf.tmp" "$NGINX_CONF_DIR/nginx.conf"
            echo -e "${GREEN}✓ 已清理到 http 块结束位置（第 $http_end_line 行）${NC}"
        else
            echo -e "${YELLOW}⚠ 清理失败，但继续执行...${NC}"
            rm -f "$NGINX_CONF_DIR/nginx.conf.tmp"
        fi
    else
        echo -e "${YELLOW}⚠ 无法确定 http 块结束位置${NC}"
    fi
fi

# 步骤4: 清理 http 块后的重复内容（防止之前部署遗留的问题）
# 使用更简单可靠的方法：找到 http 块结束的 } 行
http_start_line=$(grep -n "^http {" "$NGINX_CONF_DIR/nginx.conf" | cut -d: -f1 | head -1)
if [ -n "$http_start_line" ]; then
    # 使用 awk 找到 http 块的结束位置（括号匹配）
    http_end_line=$(awk -v start="$http_start_line" '
        BEGIN { 
            brace_count = 0
            found_start = 0
        }
        NR >= start {
            if (!found_start) {
                found_start = 1
            }
            line = $0
            for (i = 1; i <= length(line); i++) {
                char = substr(line, i, 1)
                if (char == "{") {
                    brace_count++
                } else if (char == "}") {
                    brace_count--
                    if (brace_count == 0 && found_start) {
                        print NR
                        exit
                    }
                }
            }
        }
    ' "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null)
    
    if [ -n "$http_end_line" ]; then
        total_lines=$(wc -l < "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null | tr -d ' ')
        # 如果 http 块后还有内容，强制删除
        if [ -n "$total_lines" ] && [ "$http_end_line" -lt "$total_lines" ]; then
            echo -e "${YELLOW}  检测到 http 块后有多余内容（第 $((http_end_line + 1))-$total_lines 行），正在清理...${NC}"
            # 使用 head 截取到 http 块结束位置
            head -n "$http_end_line" "$NGINX_CONF_DIR/nginx.conf" > "$NGINX_CONF_DIR/nginx.conf.tmp"
            if [ $? -eq 0 ]; then
                mv "$NGINX_CONF_DIR/nginx.conf.tmp" "$NGINX_CONF_DIR/nginx.conf"
                echo -e "${GREEN}✓ 已清理多余内容${NC}"
            else
                echo -e "${YELLOW}⚠ 清理失败，但继续执行...${NC}"
                rm -f "$NGINX_CONF_DIR/nginx.conf.tmp"
            fi
        else
            echo -e "${GREEN}✓ http 块后无多余内容${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ 无法确定 http 块结束位置，跳过清理${NC}"
    fi
fi

# 步骤5: 验证文件行数并强制清理（双重保护）
template_lines=$(wc -l < "${PROJECT_ROOT}/init_file/nginx.conf" 2>/dev/null | tr -d ' ')
deployed_lines=$(wc -l < "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null | tr -d ' ')

# 如果行数不一致，强制截取
if [ -n "$template_lines" ] && [ -n "$deployed_lines" ]; then
    if [ "$deployed_lines" -gt "$template_lines" ]; then
        echo -e "${YELLOW}⚠ 警告: 部署后的文件行数 ($deployed_lines) 大于模板文件 ($template_lines)，强制截取到正确行数...${NC}"
        head -n "$template_lines" "$NGINX_CONF_DIR/nginx.conf" > "$NGINX_CONF_DIR/nginx.conf.tmp" && \
            mv "$NGINX_CONF_DIR/nginx.conf.tmp" "$NGINX_CONF_DIR/nginx.conf"
        echo -e "${GREEN}✓ 已截取到正确行数${NC}"
    fi
    
    # 额外检查：确保 http 块结束后没有内容（即使行数一致，也可能有重复内容）
    if [ -n "$http_end_line" ]; then
        # 检查 http 块结束后的内容是否包含 set 或 include 指令
        after_http_content=$(sed -n "$((http_end_line + 1)),\$p" "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null | grep -E "^\s*(set|include)" | head -1)
        if [ -n "$after_http_content" ]; then
            echo -e "${YELLOW}⚠ 检测到 http 块后有重复的配置指令，强制清理...${NC}"
            head -n "$http_end_line" "$NGINX_CONF_DIR/nginx.conf" > "$NGINX_CONF_DIR/nginx.conf.tmp" && \
                mv "$NGINX_CONF_DIR/nginx.conf.tmp" "$NGINX_CONF_DIR/nginx.conf"
            echo -e "${GREEN}✓ 已清理重复配置${NC}"
        fi
    fi
fi

# 步骤6: 确保文件以换行符结尾
if [ -f "$NGINX_CONF_DIR/nginx.conf" ]; then
    if ! tail -c 1 "$NGINX_CONF_DIR/nginx.conf" | grep -q '^$'; then
        echo "" >> "$NGINX_CONF_DIR/nginx.conf"
    fi
fi

echo -e "${GREEN}✓ 主配置文件已复制并配置${NC}"
echo -e "${YELLOW}  注意: conf.d、lua、logs、cert 目录保持在项目目录，使用相对路径引用${NC}"

# 验证配置文件
echo -e "${GREEN}[3/4] 验证配置...${NC}"

# 最终清理：在验证前再次确保文件正确（最后一道防线）
echo -e "${YELLOW}  执行最终清理检查...${NC}"
template_lines=$(wc -l < "${PROJECT_ROOT}/init_file/nginx.conf" 2>/dev/null | tr -d ' ')
if [ -n "$template_lines" ]; then
    # 找到 http 块结束位置
    http_start_line=$(grep -n "^http {" "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null | cut -d: -f1 | head -1)
    if [ -n "$http_start_line" ]; then
        http_end_line=$(awk -v start="$http_start_line" '
            BEGIN { brace_count = 0; found_start = 0 }
            NR >= start {
                if (!found_start) found_start = 1
                for (i = 1; i <= length($0); i++) {
                    char = substr($0, i, 1)
                    if (char == "{") brace_count++
                    if (char == "}") {
                        brace_count--
                        if (brace_count == 0 && found_start) {
                            print NR
                            exit
                        }
                    }
                }
            }
        ' "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null)
        
        if [ -n "$http_end_line" ]; then
            # 强制截取到 http 块结束位置
            head -n "$http_end_line" "$NGINX_CONF_DIR/nginx.conf" > "$NGINX_CONF_DIR/nginx.conf.final"
            if [ $? -eq 0 ]; then
                mv "$NGINX_CONF_DIR/nginx.conf.final" "$NGINX_CONF_DIR/nginx.conf"
                echo -e "${GREEN}✓ 最终清理完成（截取到第 $http_end_line 行）${NC}"
            else
                echo -e "${YELLOW}⚠ 最终清理失败，但继续验证...${NC}"
                rm -f "$NGINX_CONF_DIR/nginx.conf.final"
            fi
        else
            echo -e "${YELLOW}⚠ 无法确定 http 块结束位置${NC}"
        fi
    fi
    
    # 额外验证：检查文件行数
    final_lines=$(wc -l < "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null | tr -d ' ')
    if [ -n "$final_lines" ] && [ "$final_lines" -gt "$template_lines" ]; then
        echo -e "${YELLOW}⚠ 文件行数 ($final_lines) 仍大于模板 ($template_lines)，强制截取...${NC}"
        head -n "$template_lines" "$NGINX_CONF_DIR/nginx.conf" > "$NGINX_CONF_DIR/nginx.conf.final" && \
            mv "$NGINX_CONF_DIR/nginx.conf.final" "$NGINX_CONF_DIR/nginx.conf"
        echo -e "${GREEN}✓ 已强制截取到模板行数${NC}"
    fi
fi

# 验证 nginx.conf 语法
if [ -f "${OPENRESTY_PREFIX}/bin/openresty" ]; then
    echo "验证 nginx.conf 语法..."
    
    if ${OPENRESTY_PREFIX}/bin/openresty -t > /dev/null 2>&1; then
        echo -e "${GREEN}✓ nginx.conf 语法正确${NC}"
    else
        echo -e "${RED}✗ nginx.conf 语法错误${NC}"
        echo "错误信息："
        ${OPENRESTY_PREFIX}/bin/openresty -t 2>&1 | head -20
        echo ""
        echo -e "${YELLOW}显示配置文件相关部分：${NC}"
        if [ -f "$NGINX_CONF_DIR/nginx.conf" ]; then
            # 显示 http 块和 set 指令周围的内容
            http_start=$(grep -n "^http {" "$NGINX_CONF_DIR/nginx.conf" | cut -d: -f1 | head -1)
            if [ -n "$http_start" ]; then
                # 找到 http 块结束位置
                http_end=$(awk -v start="$http_start" '
                    BEGIN { brace_count = 0; found_start = 0 }
                    NR >= start {
                        if (!found_start) found_start = 1
                        for (i = 1; i <= length($0); i++) {
                            char = substr($0, i, 1)
                            if (char == "{") brace_count++
                            if (char == "}") {
                                brace_count--
                                if (brace_count == 0 && found_start) {
                                    print NR
                                    exit
                                }
                            }
                        }
                    }
                ' "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null)
                
                if [ -n "$http_end" ]; then
                    # 只显示 http 块内的内容
                    sed -n "${http_start},${http_end}p" "$NGINX_CONF_DIR/nginx.conf" || true
                else
                    # 如果无法找到结束位置，显示前15行
                    sed -n "${http_start},$((http_start + 15))p" "$NGINX_CONF_DIR/nginx.conf" || true
                fi
                
                # 检查是否有重复的 set 指令
                set_count=$(grep -c "set \$project_root" "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null || echo "0")
                # 清理 set_count 中的换行符和空格
                set_count=$(echo "$set_count" | tr -d '\n\r ' | head -1)
                if [ -n "$set_count" ] && [ "$set_count" -gt 1 ] 2>/dev/null; then
                    echo ""
                    echo -e "${RED}⚠ 检测到重复的 set \$project_root 指令（共 $set_count 个）${NC}"
                    echo "所有 set \$project_root 指令位置："
                    grep -n "set \$project_root" "$NGINX_CONF_DIR/nginx.conf" || true
                fi
            fi
            echo ""
            echo -e "${BLUE}配置文件总行数：$(wc -l < "$NGINX_CONF_DIR/nginx.conf")${NC}"
            echo -e "${BLUE}http 块开始行：${http_start}${NC}"
            if [ -n "$http_end" ]; then
                echo -e "${BLUE}http 块结束行：${http_end}${NC}"
            fi
        fi
        echo ""
        echo -e "${YELLOW}⚠ 请修复配置文件后重新部署${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ OpenResty 未安装，跳过语法验证${NC}"
fi

# 检查部署路径完整性
echo -e "${GREEN}[4/5] 检查部署路径完整性...${NC}"

# 检查所有必需的路径是否存在
REQUIRED_PATHS=(
    "${PROJECT_ROOT}/conf.d"
    "${PROJECT_ROOT}/lua"
    "${PROJECT_ROOT}/logs"
    "${PROJECT_ROOT}/conf.d/set_conf"
    "${PROJECT_ROOT}/conf.d/vhost_conf"
    "${PROJECT_ROOT}/conf.d/upstream"
    "${PROJECT_ROOT}/conf.d/upstream/HTTP_HTTPS"
    "${PROJECT_ROOT}/conf.d/upstream/TCP_UDP"
    "${PROJECT_ROOT}/lua/waf"
)

ALL_PATHS_OK=1
for path in "${REQUIRED_PATHS[@]}"; do
    if [ ! -d "$path" ]; then
        echo -e "${YELLOW}⚠ 路径不存在: $path${NC}"
        ALL_PATHS_OK=0
        # 尝试创建缺失的目录
        read -p "是否创建缺失的目录？[Y/n]: " CREATE_MISSING
        CREATE_MISSING="${CREATE_MISSING:-Y}"
        if [[ "$CREATE_MISSING" =~ ^[Yy]$ ]]; then
            mkdir -p "$path"
            echo -e "${GREEN}✓ 已创建: $path${NC}"
            ALL_PATHS_OK=1
        fi
    fi
done

if [ $ALL_PATHS_OK -eq 1 ]; then
    echo -e "${GREEN}✓ 所有必需路径存在${NC}"
else
    echo -e "${YELLOW}⚠ 部分路径不存在，可能影响功能${NC}"
fi

# 检查配置文件中的路径引用是否正确
if [ -f "$NGINX_CONF_DIR/nginx.conf" ]; then
    # 检查是否包含 project_root 变量
    if grep -q "\$project_root" "$NGINX_CONF_DIR/nginx.conf"; then
        echo -e "${GREEN}✓ nginx.conf 包含 project_root 变量${NC}"
        # 验证 project_root 路径是否存在
        project_root_in_conf=$(grep "set \$project_root" "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null | sed 's/.*"\(.*\)".*/\1/' | head -1)
        if [ -n "$project_root_in_conf" ]; then
            if [ -d "$project_root_in_conf" ]; then
                echo -e "${GREEN}✓ project_root 路径存在: $project_root_in_conf${NC}"
            else
                echo -e "${RED}✗ project_root 路径不存在: $project_root_in_conf${NC}"
                echo -e "${YELLOW}  建议修复为: $PROJECT_ROOT_ABS${NC}"
            fi
        fi
    else
        echo -e "${RED}✗ nginx.conf 未找到 project_root 变量${NC}"
    fi
    
    # 检查 include 路径是否正确
    if grep -q "include.*conf.d" "$NGINX_CONF_DIR/nginx.conf"; then
        echo -e "${GREEN}✓ nginx.conf 包含 conf.d 配置引用${NC}"
        # 检查引用的配置文件是否存在
        include_paths=$(grep "include.*conf.d" "$NGINX_CONF_DIR/nginx.conf" 2>/dev/null | sed "s|.*include.*\$project_root/\(.*\);|\1|" | head -1)
        if [ -n "$include_paths" ]; then
            full_include_path="${PROJECT_ROOT_ABS}/${include_paths}"
            if [ -f "$full_include_path" ] || [ -d "$full_include_path" ]; then
                echo -e "${GREEN}✓ 引用的配置文件存在: $full_include_path${NC}"
            else
                echo -e "${YELLOW}⚠ 引用的配置文件不存在: $full_include_path${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}⚠ nginx.conf 未找到 conf.d 配置引用${NC}"
    fi
    
    # 检查是否还有未替换的路径占位符
    if grep -q "/path/to/project" "$NGINX_CONF_DIR/nginx.conf"; then
        echo -e "${RED}✗ nginx.conf 仍包含路径占位符 /path/to/project${NC}"
        echo -e "${YELLOW}  请检查路径替换是否完整${NC}"
    else
        echo -e "${GREEN}✓ 所有路径占位符已替换${NC}"
    fi
fi

# 5. 检查配置文件语法和完整性
echo -e "${GREEN}[5/5] 检查配置文件语法和完整性...${NC}"

# 验证 nginx.conf 语法
if [ -f "${OPENRESTY_PREFIX}/bin/openresty" ]; then
    if ${OPENRESTY_PREFIX}/bin/openresty -t > /dev/null 2>&1; then
        echo -e "${GREEN}✓ nginx.conf 语法正确${NC}"
    else
        echo -e "${RED}✗ nginx.conf 语法错误${NC}"
        echo -e "${YELLOW}错误信息：${NC}"
        ${OPENRESTY_PREFIX}/bin/openresty -t 2>&1 | head -10
    fi
fi

# 检查关键配置文件是否存在
CRITICAL_CONFIGS=(
    "${PROJECT_ROOT}/conf.d/set_conf/waf.conf"
    "${PROJECT_ROOT}/conf.d/set_conf/lua.conf"
    "${PROJECT_ROOT}/lua/config.lua"
    "${PROJECT_ROOT}/lua/waf/init.lua"
)

for config in "${CRITICAL_CONFIGS[@]}"; do
    if [ -f "$config" ]; then
        echo -e "${GREEN}✓ 配置文件存在: $(basename $config)${NC}"
    else
        echo -e "${RED}✗ 关键配置文件不存在: $config${NC}"
    fi
done

# 设置权限
echo -e "${GREEN}设置文件权限...${NC}"
chown -R nobody:nobody "${PROJECT_ROOT}/logs" 2>/dev/null || true
chmod 755 "${PROJECT_ROOT}/logs"
chmod 644 "$NGINX_CONF_DIR/nginx.conf"
# conf.d 保持在项目目录，设置项目目录权限
chmod -R 755 "${PROJECT_ROOT}/conf.d" 2>/dev/null || true
find "${PROJECT_ROOT}/conf.d" -type f -name "*.conf" -exec chmod 644 {} \; 2>/dev/null || true

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}部署完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "系统配置文件（已复制）:"
echo "  - nginx.conf: $NGINX_CONF_DIR/nginx.conf"
echo ""
echo "项目文件位置（保持在项目目录，使用相对路径）:"
echo "  - 配置文件: ${PROJECT_ROOT}/conf.d/"
echo "    - set_conf/: 参数配置文件"
echo "    - vhost_conf/: 虚拟主机配置"
echo "    - upstream/: 自动生成的upstream配置"
echo "      - HTTP_HTTPS/: HTTP/HTTPS代理的upstream配置"
echo "      - TCP_UDP/: TCP/UDP代理的upstream配置"
echo "    - cert/: SSL 证书目录"
echo "  - Lua 脚本: ${PROJECT_ROOT}/lua/"
echo "  - GeoIP 数据库: ${PROJECT_ROOT}/lua/geoip/"
echo "  - 日志文件: ${PROJECT_ROOT}/logs/"
echo ""
echo "路径说明:"
echo "  - 所有路径使用 \$project_root 变量引用项目根目录"
echo "  - 配置文件中的路径示例:"
echo "    - 日志: \$project_root/logs/access.log"
echo "    - Lua: \$project_root/lua/?.lua"
echo "    - SSL: \$project_root/conf.d/cert/your_domain.crt"
echo "    - GeoIP: \$project_root/lua/geoip/GeoLite2-Country.mmdb"
echo ""
echo "配置说明:"
echo "  - nginx.conf 中的 include 路径使用 \$project_root 变量"
echo "  - 修改 conf.d 中的配置文件后，无需重新部署，直接 reload 即可"
echo ""
echo "下一步:"
echo "  1. 测试配置: $OPENRESTY_PREFIX/bin/openresty -t"
echo "  2. 启动服务: $OPENRESTY_PREFIX/bin/openresty"
echo "  3. 查看日志: tail -f ${PROJECT_ROOT}/logs/error.log"
echo ""
echo -e "${YELLOW}提示: 修改 conf.d 中的配置后，运行以下命令重新加载:${NC}"
echo "  $OPENRESTY_PREFIX/bin/openresty -s reload"

