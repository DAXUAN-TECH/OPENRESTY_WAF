#!/bin/bash

# 紧急修复 PATH 环境变量脚本
# 用于修复因 /etc/environment 被破坏导致的系统命令无法使用的问题

set +e  # 不立即退出，允许错误

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

echo -e "${RED}========================================${NC}"
echo -e "${RED}紧急修复 PATH 环境变量${NC}"
echo -e "${RED}========================================${NC}"
echo ""

# 临时设置 PATH（使用绝对路径）
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

echo -e "${BLUE}步骤 1: 检查当前 PATH 设置...${NC}"
echo "当前 PATH: $PATH"
echo ""

# 检查 /etc/environment 文件
echo -e "${BLUE}步骤 2: 检查 /etc/environment 文件...${NC}"
if [ -f /etc/environment ]; then
    echo "文件内容："
    cat /etc/environment
    echo ""
    
    # 检查是否有问题
    if ! grep -q "^PATH=" /etc/environment || grep -q "^PATH=\"\"" /etc/environment; then
        echo -e "${RED}⚠ 检测到 /etc/environment 中的 PATH 可能有问题${NC}"
        echo ""
        echo -e "${YELLOW}建议修复方法：${NC}"
        echo "1. 备份当前文件："
        echo "   cp /etc/environment /etc/environment.bak.$(date +%Y%m%d_%H%M%S)"
        echo ""
        echo "2. 恢复标准 PATH 设置："
        echo "   编辑 /etc/environment，确保包含："
        echo "   PATH=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\""
        echo ""
        echo "3. 或者删除 /etc/environment 中的 PATH 行，使用默认值"
    fi
else
    echo -e "${YELLOW}⚠ /etc/environment 文件不存在${NC}"
fi
echo ""

# 检查 /etc/profile.d/openresty.sh
echo -e "${BLUE}步骤 3: 检查 /etc/profile.d/openresty.sh...${NC}"
if [ -f /etc/profile.d/openresty.sh ]; then
    echo "文件内容："
    cat /etc/profile.d/openresty.sh
    echo ""
    echo -e "${GREEN}✓ /etc/profile.d/openresty.sh 存在（这是正确的配置方式）${NC}"
else
    echo -e "${YELLOW}⚠ /etc/profile.d/openresty.sh 不存在${NC}"
fi
echo ""

# 提供修复建议
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}修复建议${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}方法 1: 临时修复（立即生效）${NC}"
echo "执行以下命令临时恢复 PATH："
echo "  export PATH=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\""
echo ""
echo -e "${YELLOW}方法 2: 修复 /etc/environment（永久修复）${NC}"
echo "1. 备份文件："
echo "   cp /etc/environment /etc/environment.bak"
echo ""
echo "2. 编辑文件，确保 PATH 行正确："
echo "   vi /etc/environment"
echo "   或"
echo "   nano /etc/environment"
echo ""
echo "3. 标准格式应该是："
echo "   PATH=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\""
echo ""
echo "4. 如果文件损坏严重，可以删除 PATH 行，使用系统默认值"
echo ""
echo -e "${YELLOW}方法 3: 使用 /etc/profile.d/（推荐）${NC}"
echo "如果 /etc/environment 有问题，可以："
echo "1. 从 /etc/environment 中删除 PATH 行"
echo "2. 确保 /etc/profile.d/openresty.sh 存在并包含正确的 PATH 设置"
echo ""
echo -e "${YELLOW}方法 4: 重新登录${NC}"
echo "修复后，重新登录系统使更改生效"
echo ""

# 生成修复脚本
echo -e "${BLUE}生成自动修复脚本...${NC}"
cat > /tmp/fix_path.sh << 'FIXSCRIPT'
#!/bin/bash
# 自动修复 PATH 脚本

# 临时设置 PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# 备份 /etc/environment
if [ -f /etc/environment ]; then
    cp /etc/environment /etc/environment.bak.$(date +%Y%m%d_%H%M%S)
    
    # 检查并修复 PATH
    if grep -q "^PATH=" /etc/environment; then
        # 如果 PATH 行有问题，修复它
        if grep -q "^PATH=\"\"" /etc/environment || ! grep -q "^PATH=\"/usr" /etc/environment; then
            # 删除有问题的 PATH 行
            sed -i '/^PATH=/d' /etc/environment
            # 添加正确的 PATH
            echo 'PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' >> /etc/environment
            echo "已修复 /etc/environment 中的 PATH"
        fi
    else
        # 如果没有 PATH 行，添加它
        echo 'PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' >> /etc/environment
        echo "已添加 PATH 到 /etc/environment"
    fi
fi

echo "修复完成，请重新登录系统"
FIXSCRIPT

chmod +x /tmp/fix_path.sh
echo -e "${GREEN}✓ 修复脚本已生成: /tmp/fix_path.sh${NC}"
echo ""
echo -e "${YELLOW}执行修复脚本：${NC}"
echo "  bash /tmp/fix_path.sh"
echo ""

