# opm (OpenResty Package Manager) 安装指南

## 什么是 opm？

`opm` (OpenResty Package Manager) 是 OpenResty 的包管理器，用于安装和管理 Lua 模块（如 lua-resty-mysql、lua-resty-redis 等）。

## 快速安装

### 方法一：使用自动安装脚本（推荐）

```bash
sudo ./scripts/install_opm.sh
```

脚本会自动：
1. 检查 OpenResty 是否已安装
2. 检查 opm 是否已安装
3. 如果未安装，自动安装 `openresty-resty` 包
4. 验证安装是否成功

### 方法二：手动安装

#### RedHat 系列 (CentOS/RHEL/Fedora/Rocky/AlmaLinux)

```bash
# 使用 yum
sudo yum install -y openresty-resty

# 或使用 dnf
sudo dnf install -y openresty-resty
```

#### Debian 系列 (Ubuntu/Debian)

```bash
sudo apt-get update
sudo apt-get install -y openresty-resty
```

## 验证安装

### 1. 检查 opm 是否已安装

```bash
# 方法一：使用 which 命令
which opm

# 方法二：直接运行
opm --version

# 方法三：查找文件
find /usr /opt /usr/local -name opm -type f 2>/dev/null
```

### 2. 检查 opm 是否可用

```bash
# 查看版本
opm --version

# 查看帮助
opm --help

# 列出已安装的包
opm list
```

### 3. 测试安装 Lua 模块

```bash
# 安装 lua-resty-mysql（关键模块）
opm get openresty/lua-resty-mysql

# 安装 lua-resty-redis（可选）
opm get openresty/lua-resty-redis

# 验证安装
opm list
```

## 常见问题

### 问题 1：找不到 opm 命令

**原因**：
- `openresty-resty` 包未安装
- opm 不在 PATH 环境变量中

**解决方法**：

1. **检查包是否已安装**：

```bash
# RedHat 系列
rpm -q openresty-resty

# Debian 系列
dpkg -l | grep openresty-resty
```

2. **如果包已安装，查找 opm 位置**：

```bash
# RedHat 系列：查看包文件列表
rpm -ql openresty-resty | grep opm

# Debian 系列：查看包文件列表
dpkg -L openresty-resty | grep opm
```

3. **使用完整路径运行 opm**：

```bash
# 如果找到 opm 在 /usr/bin/opm
/usr/bin/opm --version

# 如果找到 opm 在 /usr/local/openresty/bin/opm
/usr/local/openresty/bin/opm --version
```

4. **添加到 PATH**（可选）：

```bash
# 临时添加到 PATH
export PATH=$PATH:/usr/local/openresty/bin

# 永久添加到 PATH（添加到 ~/.bashrc 或 /etc/profile）
echo 'export PATH=$PATH:/usr/local/openresty/bin' >> ~/.bashrc
source ~/.bashrc
```

### 问题 2：openresty-resty 包安装失败

**原因**：
- OpenResty 仓库未配置
- 网络问题
- 包名错误

**解决方法**：

1. **检查 OpenResty 仓库是否已配置**：

```bash
# RedHat 系列
cat /etc/yum.repos.d/openresty.repo

# Debian 系列
cat /etc/apt/sources.list.d/openresty.list
```

2. **如果仓库未配置，先配置仓库**：

```bash
# 运行 OpenResty 安装脚本（会自动配置仓库）
sudo ./scripts/install_openresty.sh
```

3. **手动配置仓库**（RedHat 系列）：

```bash
# 导入 GPG 密钥
sudo rpm --import https://openresty.org/package/pubkey.gpg

# 创建仓库文件
cat > /etc/yum.repos.d/openresty.repo <<EOF
[openresty]
name=Official OpenResty Repository
baseurl=https://openresty.org/package/centos/\$releasever/\$basearch
gpgcheck=1
enabled=1
gpgkey=https://openresty.org/package/pubkey.gpg
EOF

# 更新缓存
sudo yum makecache
```

4. **手动配置仓库**（Debian 系列）：

```bash
# 导入 GPG 密钥
wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -

# 添加仓库
echo "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/openresty.list

# 更新缓存
sudo apt-get update
```

### 问题 3：opm 命令执行失败

**原因**：
- 权限问题
- 文件损坏
- 依赖缺失

**解决方法**：

1. **检查文件权限**：

```bash
ls -l $(which opm)
# 或
ls -l /usr/local/openresty/bin/opm
```

2. **检查文件完整性**：

```bash
file $(which opm)
```

3. **重新安装 openresty-resty**：

```bash
# RedHat 系列
sudo yum reinstall -y openresty-resty

# Debian 系列
sudo apt-get install --reinstall openresty-resty
```

## 使用 opm 安装 Lua 模块

### 常用模块

```bash
# 数据库连接（必需）
opm get openresty/lua-resty-mysql

# Redis 连接（可选）
opm get openresty/lua-resty-redis

# MaxMind GeoIP2（可选，用于地域封控）
opm get anjia0532/lua-resty-maxminddb

# HTTP 客户端（可选）
opm get openresty/lua-resty-http

# JSON 处理（可选）
opm get openresty/lua-resty-json
```

### 查看已安装的模块

```bash
opm list
```

### 卸载模块

```bash
opm remove <package-name>
```

## 验证安装成功的完整步骤

```bash
# 1. 检查 OpenResty 是否已安装
openresty -v

# 2. 检查 opm 是否已安装
opm --version

# 3. 安装测试模块
opm get openresty/lua-resty-mysql

# 4. 验证模块是否安装成功
opm list | grep lua-resty-mysql

# 5. 测试模块是否可用（在 Lua 代码中）
# 在 nginx.conf 或 Lua 文件中：
# local mysql = require "resty.mysql"
```

## 手动安装 Lua 模块（如果 opm 不可用）

如果 opm 无法使用，可以手动从源码安装：

```bash
# 1. 克隆模块仓库
cd /tmp
git clone https://github.com/openresty/lua-resty-mysql.git

# 2. 复制到 OpenResty 的 Lua 库目录
mkdir -p /usr/local/openresty/site/lualib/resty
cp -r lua-resty-mysql/lib/resty/* /usr/local/openresty/site/lualib/resty/

# 3. 验证
ls -la /usr/local/openresty/site/lualib/resty/mysql.lua
```

## 相关文件位置

- **opm 可执行文件**：
  - `/usr/local/openresty/bin/opm`（源码安装）
  - `/usr/bin/opm`（包管理器安装）

- **Lua 模块安装目录**：
  - `/usr/local/openresty/site/lualib/resty/`（默认）
  - `/usr/local/openresty/lualib/resty/`（系统模块）

## 总结

1. **安装 opm**：通过安装 `openresty-resty` 包
2. **验证安装**：使用 `opm --version` 和 `opm list`
3. **安装模块**：使用 `opm get <package-name>`
4. **如果遇到问题**：检查包是否安装、路径是否正确、权限是否足够

如果以上方法都无法解决问题，请检查 OpenResty 是否正确安装，或查看 OpenResty 官方文档。

