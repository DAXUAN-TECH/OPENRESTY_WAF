# GeoIP2 数据库目录

## 说明

此目录用于存放 GeoIP2 地理位置数据库文件。

**重要**：地域封控功能支持国内（省市级别）和国外（国家级别），需要使用 **GeoLite2-City.mmdb**（而不是 Country 版本），以获取省市信息。

## 数据库文件

将 GeoIP2 数据库文件（.mmdb）放在此目录下：

```
lua/geoip/
└── GeoLite2-City.mmdb  # 注意：使用 City 版本以支持省市查询
```

## 获取数据库文件

### 方式一：MaxMind GeoLite2（免费）

1. 访问 [MaxMind GeoLite2](https://dev.maxmind.com/geoip/geoip2/geolite2/)
2. 注册账号（免费）
3. 下载 **GeoLite2-City.mmdb**（注意是 City 版本，不是 Country 版本）
4. 将文件放到此目录

### 方式二：使用 wget 下载（需要 License Key）

```bash
# 需要先注册 MaxMind 账号获取 License Key
# 替换 YOUR_LICENSE_KEY 为实际的 License Key
wget "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=YOUR_LICENSE_KEY&suffix=tar.gz" -O GeoLite2-City.tar.gz
      https://download.maxmind.com/geoip/databases/GeoLite2-City/download?suffix=tar.gz

# 解压
tar -xzf GeoLite2-City.tar.gz

# 复制数据库文件
cp GeoLite2-City_*/GeoLite2-City.mmdb /usr/local/openresty/nginx/lua/geoip/
```

### 方式三：使用第三方 IP 库

也可以使用其他 IP 地理位置数据库，但需要修改 `lua/waf/geo_block.lua` 中的查询逻辑。

## 安装依赖模块

```bash
# 安装 lua-resty-maxminddb
opm get anjia0532/lua-resty-maxminddb
```

## 配置

在 `lua/config.lua` 中配置：

```lua
_M.geo = {
    enable = true,  -- 启用地域封控
    geoip_db_path = "/usr/local/openresty/nginx/lua/geoip/GeoLite2-City.mmdb",
}
```

## 使用示例

### 地域封控规则格式

地域封控支持三种级别的封控：

1. **国家级别**（国外）：使用 ISO 3166-1 alpha-2 国家代码
2. **省份级别**（国内）：国家代码:省份名称
3. **城市级别**（国内）：国家代码:省份名称:城市名称

### 添加地域封控规则

#### 1. 封控整个国家（国外）

```sql
-- 封控美国
INSERT INTO waf_block_rules (rule_type, rule_value, rule_name, description, status, priority)
VALUES ('geo', 'US', '封控美国', '封控所有来自美国的访问', 1, 80);

-- 封控日本
INSERT INTO waf_block_rules (rule_type, rule_value, rule_name, description, status, priority)
VALUES ('geo', 'JP', '封控日本', '封控所有来自日本的访问', 1, 80);
```

#### 2. 封控国内省份

```sql
-- 封控北京
INSERT INTO waf_block_rules (rule_type, rule_value, rule_name, description, status, priority)
VALUES ('geo', 'CN:Beijing', '封控北京', '封控所有来自北京的访问', 1, 90);

-- 封控上海
INSERT INTO waf_block_rules (rule_type, rule_value, rule_name, description, status, priority)
VALUES ('geo', 'CN:Shanghai', '封控上海', '封控所有来自上海的访问', 1, 90);

-- 封控广东
INSERT INTO waf_block_rules (rule_type, rule_value, rule_name, description, status, priority)
VALUES ('geo', 'CN:Guangdong', '封控广东', '封控所有来自广东的访问', 1, 90);
```

#### 3. 封控国内城市（精确到城市）

```sql
-- 封控北京市（精确到城市）
INSERT INTO waf_block_rules (rule_type, rule_value, rule_name, description, status, priority)
VALUES ('geo', 'CN:Beijing:Beijing', '封控北京市', '封控所有来自北京市的访问', 1, 100);

-- 封控上海市（精确到城市）
INSERT INTO waf_block_rules (rule_type, rule_value, rule_name, description, status, priority)
VALUES ('geo', 'CN:Shanghai:Shanghai', '封控上海市', '封控所有来自上海市的访问', 1, 100);
```

### 匹配优先级

系统会按以下优先级进行匹配（从精确到模糊）：

1. **城市级别**：CN:Beijing:Beijing（最精确）
2. **省份级别**：CN:Beijing
3. **国家级别**：CN

如果匹配到更精确的规则，就不会继续匹配更模糊的规则。

### 国家代码

使用 ISO 3166-1 alpha-2 国家代码，例如：
- CN - 中国
- US - 美国
- JP - 日本
- KR - 韩国
- GB - 英国
- DE - 德国
- FR - 法国
- RU - 俄罗斯

完整列表请参考：[ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2)

### 国内省份名称

国内省份名称使用 GeoIP2 数据库中的标准名称（通常是英文或拼音），常见省份：
- Beijing - 北京
- Shanghai - 上海
- Guangdong - 广东
- Zhejiang - 浙江
- Jiangsu - 江苏
- Sichuan - 四川
- 等等...

**注意**：省份名称需要与 GeoIP2 数据库中的名称完全一致。可以通过查询 IP 获取实际的地理位置信息。

### 查询 IP 的地理位置

可以通过 Lua 代码查询 IP 的地理位置信息：

```lua
local geo_block = require "waf.geo_block"
local geo_info = geo_block.get_geo_info("8.8.8.8")
-- 返回：{country_code = "US", country_name = "United States", ...}
```

## 注意事项

1. **必须使用 GeoLite2-City.mmdb**：Country 版本不包含省市信息，无法支持国内省市封控
2. 数据库需要定期更新（建议每月更新一次）
3. 数据库文件较大（约 30-50MB），确保有足够空间
4. 首次加载数据库会有一定延迟，建议在 init_by_lua 阶段预加载
5. 如果数据库文件不存在，地域封控功能会自动禁用
6. 省份名称需要与数据库中的名称完全一致，建议先查询 IP 获取实际名称
7. 匹配规则时，系统会从精确到模糊进行匹配，优先匹配更精确的规则

