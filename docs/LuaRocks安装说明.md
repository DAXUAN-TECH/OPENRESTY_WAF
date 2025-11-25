# LuaRocks 安装说明

## 概述

LuaRocks 是 Lua 的包管理器，用于安装 Lua 模块。由于 OPM 官方库中没有 `lua-resty-bcrypt`，我们可以使用 LuaRocks 来安装它，以提高密码哈希的安全性。

## 安装 LuaRocks

### 方法 1：使用项目提供的安装脚本（推荐）

```bash
cd /data/OPENRESTY_WAF
sudo ./scripts/install_luarocks.sh
```

脚本会自动：
1. 检测系统类型（CentOS/RHEL/Fedora/Rocky/Ubuntu/Debian 等）
2. 安装必要的依赖包（wget, gcc, make, unzip）
3. 下载 LuaRocks 源码
4. 配置 LuaRocks 使用 OpenResty 的 LuaJIT
5. 编译并安装 LuaRocks
6. 验证安装

### 方法 2：手动安装

如果脚本安装失败，可以手动安装：

```bash
# 1. 安装依赖
# CentOS/RHEL/Rocky:
sudo yum install -y wget gcc make unzip

# Ubuntu/Debian:
sudo apt-get update
sudo apt-get install -y wget build-essential unzip

# 2. 下载 LuaRocks
cd /tmp
wget https://luarocks.org/releases/luarocks-3.11.1.tar.gz
tar -xzf luarocks-3.11.1.tar.gz
cd luarocks-3.11.1

# 3. 配置（使用 OpenResty 的 LuaJIT）
./configure \
    --prefix=/usr/local \
    --with-lua=/usr/local/openresty/luajit \
    --with-lua-include=/usr/local/openresty/luajit/include/luajit-2.1 \
    --lua-suffix=jit \
    --with-lua-interpreter=luajit

# 4. 编译和安装
make
sudo make install
```

## 验证安装

安装完成后，验证 LuaRocks 是否正常工作：

```bash
# 检查版本
luarocks --version

# 测试功能
luarocks list
```

## 安装 lua-resty-bcrypt

安装 LuaRocks 后，使用以下命令安装 BCrypt 库：

```bash
luarocks install lua-resty-bcrypt
```

**注意**：
- 安装的模块将位于：`/usr/local/openresty/site/lualib/`
- 如果安装失败，请检查网络连接和依赖包
- 某些系统可能需要安装额外的开发库（如 openssl-devel）

## 安装后验证

安装 `lua-resty-bcrypt` 后，重启 OpenResty 服务：

```bash
sudo systemctl restart openresty
```

然后测试登录功能，系统应该会自动使用 BCrypt 而不是 MD5+salt。

## 故障排查

### 问题 1：luarocks 命令未找到

**原因**：LuaRocks 可能未正确安装或 PATH 未配置

**解决**：
```bash
# 检查安装路径
which luarocks

# 如果未找到，检查 /usr/local/bin
ls -la /usr/local/bin/luarocks

# 如果存在但未在 PATH 中，添加到 PATH
export PATH=/usr/local/bin:$PATH
```

### 问题 2：编译失败

**原因**：缺少必要的开发库

**解决**：
```bash
# CentOS/RHEL/Rocky:
sudo yum install -y openssl-devel readline-devel

# Ubuntu/Debian:
sudo apt-get install -y libssl-dev libreadline-dev
```

### 问题 3：configure 失败

**原因**：OpenResty 路径不正确

**解决**：
```bash
# 检查 OpenResty 安装路径
ls -la /usr/local/openresty/luajit/bin/luajit

# 如果路径不同，修改 configure 命令中的路径
```

### 问题 4：luarocks install 失败

**原因**：网络问题或依赖缺失

**解决**：
```bash
# 检查网络连接
ping luarocks.org

# 安装必要的开发库
# CentOS/RHEL/Rocky:
sudo yum install -y openssl-devel

# Ubuntu/Debian:
sudo apt-get install -y libssl-dev
```

## 不使用 BCrypt 的情况

如果无法安装 LuaRocks 或 lua-resty-bcrypt，系统会使用备用方案：
- **MD5+salt**：使用随机盐值和 MD5 哈希（比明文密码安全，但不如 BCrypt）
- 格式：`md5:salt:hash`

虽然不如 BCrypt 安全，但足以满足大多数场景的需求。

## 相关文档

- [密码管理使用说明](密码管理使用说明.md)
- [部署文档](部署文档.md)

