# OpenResty 一键安装脚本说明

## 脚本功能

`install_openresty.sh` 是一个全自动的 OpenResty 安装和配置脚本，支持多种 Linux 发行版。

### 支持的系统

- ✅ **CentOS/RHEL** (6.x, 7.x, 8.x, 9.x)
- ✅ **Fedora** (所有版本)
- ✅ **Rocky Linux** / **AlmaLinux**
- ✅ **Ubuntu** (16.04+)
- ✅ **Debian** (9+)
- ✅ **openSUSE** (需要从源码编译)
- ✅ **Arch Linux** / **Manjaro** (需要 yay 或从源码编译)

### 功能特性

- 🔍 **自动检测系统类型**：自动识别 Linux 发行版
- 📦 **自动安装依赖**：根据系统类型安装所需依赖包
- 🚀 **多种安装方式**：优先使用包管理器，失败则从源码编译
- 🛡️ **容错机制**：GPG 密钥失败时自动禁用检查，包管理器失败时自动切换源码编译
- ⚙️ **自动配置**：创建目录结构、systemd 服务文件
- 📚 **安装 Lua 模块**：自动安装常用 Lua 模块
- ✅ **验证安装**：检查安装是否成功

## 使用方法

### 基本使用

```bash
# 下载脚本
wget https://raw.githubusercontent.com/your-repo/OPENRESTY_WAF/main/scripts/install_openresty.sh

# 或者使用项目中的脚本
chmod +x scripts/install_openresty.sh

# 运行安装脚本（需要 root 权限）
sudo ./scripts/install_openresty.sh
```

### 指定 OpenResty 版本

```bash
# 通过环境变量指定版本
sudo OPENRESTY_VERSION=1.21.4.1 ./scripts/install_openresty.sh
```

## 安装过程

脚本会执行以下步骤：

1. **[1/8] 检测操作系统** - 自动识别 Linux 发行版（CentOS/RHEL、Ubuntu/Debian、Fedora、openSUSE、Arch Linux）
2. **[2/8] 安装依赖包** - 根据系统类型安装编译工具和依赖库
3. **[3/8] 检查现有安装** - 如果已安装，询问是否继续
4. **[4/8] 安装 OpenResty** - 使用包管理器或从源码编译
   - RedHat 系列：使用 yum/dnf 安装
   - Debian 系列：使用 apt-get 安装
   - openSUSE：使用 zypper 安装或源码编译
   - Arch Linux：使用 yay 安装或源码编译
   - 其他系统：自动从源码编译
5. **[5/8] 创建目录结构** - 创建必要的配置和脚本目录
6. **[6/8] 配置 OpenResty** - 创建 systemd 服务文件和符号链接
7. **[7/8] 安装 Lua 模块** - 安装常用的 Lua 模块（lua-resty-mysql、lua-resty-redis、lua-resty-maxminddb）
8. **[8/8] 验证安装** - 检查安装是否成功，测试配置文件语法

## 安装位置

OpenResty 将安装到以下位置：

```
/usr/local/openresty/
├── bin/
│   ├── openresty          # 主程序
│   ├── opm                # 包管理器
│   └── resty              # RESTy CLI
├── nginx/
│   ├── conf/              # 配置文件目录
│   ├── lua/               # Lua 脚本目录
│   └── logs/              # 日志目录
└── lualib/                # Lua 库目录
```

## 服务管理

安装完成后，可以使用 systemd 管理 OpenResty：

```bash
# 启动服务
sudo systemctl start openresty

# 停止服务
sudo systemctl stop openresty

# 重启服务
sudo systemctl restart openresty

# 重新加载配置（不中断服务）
sudo systemctl reload openresty

# 查看状态
sudo systemctl status openresty

# 设置开机自启
sudo systemctl enable openresty

# 禁用开机自启
sudo systemctl disable openresty
```

## 配置文件

### 主配置文件

```
/usr/local/openresty/nginx/conf/nginx.conf
```

### 测试配置文件

```bash
/usr/local/openresty/bin/openresty -t
```

### 重新加载配置

```bash
sudo systemctl reload openresty
# 或
sudo /usr/local/openresty/bin/openresty -s reload
```

## 安装的 Lua 模块

脚本会自动安装以下 Lua 模块（如果可用）：

- `lua-resty-mysql` - MySQL 客户端
- `lua-resty-redis` - Redis 客户端（可选）
- `lua-resty-maxminddb` - GeoIP2 数据库查询（可选）

## 故障排查

### 问题 1：GPG 密钥错误

**错误信息**：
```
来自 file:///etc/pki/rpm-gpg/RPM-GPG-KEY-openresty 的无效 GPG 密钥：No key found in given key data
```

**可能原因**：
- GPG 密钥下载失败
- 网络连接问题
- GPG 工具未安装或版本不兼容

**解决方法**：
1. **自动处理**：脚本已自动处理此问题
   - 如果 GPG 密钥导入失败，脚本会自动禁用 GPG 检查（`gpgcheck=0`）
   - 如果包管理器安装失败，脚本会自动切换到源码编译安装
   - 安装过程会继续，不会中断

2. **手动修复**（如果需要启用 GPG 检查）：
   ```bash
   # 删除旧的密钥文件
   rm -f /etc/pki/rpm-gpg/RPM-GPG-KEY-openresty
   
   # 重新下载并导入密钥
   wget -qO - https://openresty.org/package/pubkey.gpg | gpg --dearmor -o /etc/pki/rpm-gpg/RPM-GPG-KEY-openresty
   
   # 验证密钥文件
   ls -lh /etc/pki/rpm-gpg/RPM-GPG-KEY-openresty
   
   # 更新仓库配置（如果需要）
   sed -i 's/gpgcheck=0/gpgcheck=1/' /etc/yum.repos.d/openresty.repo
   ```

3. **检查网络连接**：
   ```bash
   # 测试 OpenResty 官网连接
   curl -I https://openresty.org/package/pubkey.gpg
   
   # 检查 DNS 解析
   nslookup openresty.org
   ```

**注意**：即使 GPG 密钥导入失败，脚本也会继续安装。如果包管理器安装失败，会自动切换到源码编译安装。

### 问题 2：安装失败

**可能原因**：
- 网络连接问题
- 依赖包安装失败
- 权限不足
- 包管理器仓库问题

**解决方法**：
```bash
# 检查网络连接
ping -c 3 openresty.org

# 检查权限
whoami  # 应该是 root

# 手动安装依赖后重试
# CentOS/RHEL
yum install -y gcc gcc-c++ pcre-devel zlib-devel openssl-devel

# 如果包管理器安装失败，脚本会自动切换到源码编译
```

### 问题 3：服务启动失败

**可能原因**：
- 配置文件语法错误
- 端口被占用
- 权限问题

**解决方法**：
```bash
# 检查配置文件
/usr/local/openresty/bin/openresty -t

# 检查端口占用
netstat -tlnp | grep :80

# 查看错误日志
tail -f /usr/local/openresty/nginx/logs/error.log
```

### 问题 4：Lua 模块未安装

**可能原因**：
- opm 不可用
- 网络问题
- 模块名称错误

**解决方法**：
```bash
# 手动安装模块
/usr/local/openresty/bin/opm get openresty/lua-resty-mysql

# 检查 opm 是否可用
/usr/local/openresty/bin/opm --version
```

### 问题 5：不支持的系统

**解决方法**：
- 脚本会自动尝试从源码编译安装
- 或手动从源码编译安装

## 手动从源码编译

如果包管理器安装失败，可以手动从源码编译：

```bash
# 下载源码
wget https://openresty.org/download/openresty-1.21.4.1.tar.gz
tar -xzf openresty-1.21.4.1.tar.gz
cd openresty-1.21.4.1

# 配置
./configure --prefix=/usr/local/openresty \
    --with-http_realip_module \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_gzip_static_module \
    --with-pcre \
    --with-luajit

# 编译安装
make -j$(nproc)
sudo make install
```

## 卸载 OpenResty

```bash
# 停止服务
sudo systemctl stop openresty
sudo systemctl disable openresty

# 删除服务文件
sudo rm /etc/systemd/system/openresty.service
sudo systemctl daemon-reload

# 删除安装目录
sudo rm -rf /usr/local/openresty

# 删除符号链接
sudo rm -f /usr/local/bin/openresty

# 删除仓库配置（如果使用包管理器安装）
# CentOS/RHEL
sudo rm -f /etc/yum.repos.d/openresty.repo
# Ubuntu/Debian
sudo rm -f /etc/apt/sources.list.d/openresty.list
```

## 验证安装

安装完成后，验证安装：

```bash
# 检查版本
/usr/local/openresty/bin/openresty -v

# 检查模块
/usr/local/openresty/bin/openresty -V

# 测试配置
/usr/local/openresty/bin/openresty -t

# 检查服务状态
systemctl status openresty
```

## 后续配置

安装完成后，需要：

1. **部署项目文件**（推荐使用部署脚本）：
   ```bash
   # 使用部署脚本（自动处理路径）
   sudo ./scripts/deploy.sh
   ```
   
   或手动部署：
   ```bash
   # 只复制 nginx.conf（从 init_file 目录）
   sudo cp init_file/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
   # 注意：conf.d 和 lua 目录保持在项目目录，不复制
   ```

2. **配置数据库**：
   ```bash
   # 创建数据库
   mysql -u root -p < init_file/数据库设计.sql
   
   # 修改配置文件（项目目录）
   vim lua/config.lua
   ```

3. **安装 GeoIP2 数据库**（可选，用于地域封控）：
   ```bash
   sudo ./scripts/install_geoip.sh YOUR_ACCOUNT_ID YOUR_LICENSE_KEY
   ```

4. **系统优化**（推荐，提高性能）：
   ```bash
   sudo ./scripts/optimize_system.sh
   ```

5. **启动服务**：
   ```bash
   # 测试配置
   sudo /usr/local/openresty/bin/openresty -t
   
   # 启动服务
   sudo systemctl start openresty
   sudo systemctl enable openresty
   ```

## 注意事项

1. **需要 root 权限**：安装过程需要 root 权限
2. **网络连接**：需要网络连接下载包和源码
3. **磁盘空间**：确保有足够的磁盘空间（至少 500MB）
4. **编译时间**：从源码编译可能需要较长时间（10-30 分钟）
5. **防火墙**：确保防火墙允许 HTTP/HTTPS 端口（80/443）

## 参考文档

- [OpenResty 官网](https://openresty.org/)
- [OpenResty 安装文档](https://openresty.org/cn/installation.html)
- [Nginx 文档](http://nginx.org/en/docs/)

