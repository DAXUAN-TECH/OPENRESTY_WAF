# 公共函数库使用说明

## 概述

`common.sh` 是一个公共函数库，提供可复用的函数供其他脚本引用，减少代码重复，提高代码可维护性。

## 当前状态

**注意**：此文件目前**未被使用**，其他脚本都直接在自己的代码中实现相同功能，保持脚本独立性。

这是一个**可选工具**，如果未来需要统一代码或减少重复，可以使用此公共函数库。

## 包含的函数

### 1. get_project_root()

获取项目根目录路径。

**函数定义**：
```bash
get_project_root() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    echo "$(cd "$script_dir/.." && pwd)"
}
```

**使用示例**：
```bash
# 在脚本中引用
source "$(dirname "$0")/common.sh"
PROJECT_ROOT=$(get_project_root)
echo "项目根目录: $PROJECT_ROOT"
```

**当前实现方式**（各脚本直接实现）：
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
```

### 2. check_dependencies_common()

检查通用依赖（curl、tar）。

**函数定义**：
```bash
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
```

**使用示例**：
```bash
source "$(dirname "$0")/common.sh"

if ! check_dependencies_common; then
    exit 1
fi
```

**当前实现方式**：各脚本都有自己的 `check_dependencies()` 函数。

### 3. check_root_common()

检查是否为 root 用户。

**函数定义**：
```bash
check_root_common() {
    if [ "$EUID" -ne 0 ]; then
        echo "错误: 需要 root 权限"
        echo "请使用: sudo $0"
        return 1
    fi
    return 0
}
```

**使用示例**：
```bash
source "$(dirname "$0")/common.sh"

if ! check_root_common; then
    exit 1
fi
```

**当前实现方式**：各脚本都有自己的 root 检查逻辑。

## 如何使用

### 方法 1：在脚本开头引用

```bash
#!/bin/bash

# 引用公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# 使用公共函数
PROJECT_ROOT=$(get_project_root)

if ! check_root_common; then
    exit 1
fi

if ! check_dependencies_common; then
    exit 1
fi

# 脚本的其他代码...
```

### 方法 2：条件引用（推荐）

```bash
#!/bin/bash

# 如果 common.sh 存在，则引用
if [ -f "$(dirname "$0")/common.sh" ]; then
    source "$(dirname "$0")/common.sh"
    USE_COMMON=true
else
    USE_COMMON=false
fi

# 根据是否使用公共函数库选择实现方式
if [ "$USE_COMMON" = true ]; then
    PROJECT_ROOT=$(get_project_root)
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
```

## 为什么当前未使用？

### 优点（使用公共函数库）
- ✅ 减少代码重复
- ✅ 统一实现，便于维护
- ✅ 修改一处，所有脚本生效

### 缺点（当前策略：保持脚本独立性）
- ⚠️ 脚本依赖外部文件，不能独立运行
- ⚠️ 需要确保 `common.sh` 路径正确
- ⚠️ 增加脚本复杂度

### 当前策略

**保持脚本独立性**：
- 每个脚本可独立运行
- 不依赖其他文件
- 便于单独使用和维护
- 代码重复量不大，可接受

## 何时使用公共函数库？

### 适合使用的场景

1. **代码重复较多**：当多个脚本有大量重复代码时
2. **需要统一修改**：当需要统一修改所有脚本的某个逻辑时
3. **团队协作**：当多人维护，需要统一代码风格时

### 不适合使用的场景

1. **脚本需要独立运行**：脚本需要单独分发或使用
2. **代码重复较少**：重复代码量不大，不值得引入依赖
3. **简单脚本**：脚本逻辑简单，不需要抽象

## 扩展公共函数库

如果需要添加新的公共函数，可以在 `common.sh` 中添加：

```bash
# 示例：日志函数
log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_warn() {
    echo "[WARN] $*"
}
```

## 相关文档

- [代码审计报告](../docs/代码审计报告.md) - 包含代码重复分析
- [部署脚本说明](deploy_README.md) - 脚本使用示例

---

**总结**：`common.sh` 是一个可选工具，当前未使用是为了保持脚本独立性。如果未来需要统一代码或减少重复，可以使用此公共函数库。

