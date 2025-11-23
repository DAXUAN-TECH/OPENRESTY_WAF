#!/bin/bash

# 公共函数库
# 用途：供其他脚本引用的公共函数

# 获取项目根目录（返回相对路径）
get_project_root() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    echo "$script_dir/.."
}

# 检查依赖（通用）
check_dependencies_common() {
    local missing_deps=()
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if ! command -v tar &> /dev/null; then
        missing_deps+=("tar")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "错误: 缺少以下依赖: ${missing_deps[*]}"
        echo "请先安装这些依赖"
        return 1
    fi
    
    return 0
}

# 检查是否为 root 用户
check_root_common() {
    if [ "$EUID" -ne 0 ]; then
        echo "错误: 需要 root 权限"
        echo "请使用: sudo $0"
        return 1
    fi
    return 0
}

