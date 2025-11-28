# 测试目录说明

本目录包含所有测试文件，包括单元测试和集成测试。

## 目录结构

```
lua/tests/
├── unit/                    # 单元测试
│   ├── ip_utils_test.lua   # IP工具函数测试
│   ├── config_test.lua      # 配置模块测试
│   └── ...
├── integration/             # 集成测试
│   ├── rule_management_test.lua  # 规则管理集成测试
│   └── ...
├── run_tests.lua           # 测试运行器
└── README.md               # 本文件
```

## 测试框架

使用 `waf.test_framework` 模块提供的测试框架，支持：
- 测试套件（describe）
- 测试用例（it）
- 钩子函数（before_each, after_each, before_all, after_all）
- 断言函数（assert.equal, assert.true等）
- 测试跳过（skip）

## 运行测试

### 方式1：通过API端点运行（推荐）

在nginx配置中添加测试端点：

```nginx
location /test {
    content_by_lua_block {
        local tests = require "tests.run_tests"
        tests.run()
    }
}
```

然后访问：`http://your-domain/test`

### 方式2：通过命令行运行

```bash
# 使用resty运行
resty -e 'require("tests.run_tests").run()'
```

### 方式3：在OpenResty中运行

```lua
local tests = require "tests.run_tests"
tests.run()
```

## 编写测试

### 单元测试示例

```lua
local test_framework = require "waf.test_framework"
local your_module = require "waf.your_module"

local assert = test_framework.assert

test_framework.describe("模块名称", function()
    
    test_framework.it("测试用例名称", function()
        -- 测试代码
        assert.equal(actual, expected, "错误消息")
    end)
    
end)
```

### 集成测试示例

```lua
test_framework.describe("集成测试", function()
    
    test_framework.before_all(function()
        -- 测试前准备
    end)
    
    test_framework.after_all(function()
        -- 测试后清理
    end)
    
    test_framework.it("集成测试用例", function()
        -- 测试代码
    end)
    
end)
```

## 断言函数

- `assert.equal(actual, expected, message)` - 相等断言
- `assert.not_equal(actual, expected, message)` - 不等断言
- `assert.true(value, message)` - 真值断言
- `assert.false(value, message)` - 假值断言
- `assert.nil(value, message)` - nil断言
- `assert.not_nil(value, message)` - 非nil断言
- `assert.type(value, expected_type, message)` - 类型断言
- `assert.contains(table, value, message)` - 包含断言

## 注意事项

1. **单元测试**：不依赖外部资源（数据库、网络等），可以快速运行
2. **集成测试**：需要数据库连接等外部资源，运行较慢
3. **测试隔离**：每个测试应该独立，不依赖其他测试的执行顺序
4. **清理数据**：集成测试后应该清理测试数据

## 测试覆盖率

当前测试覆盖：
- ✅ IP工具函数（ip_utils.lua）
- ✅ 配置模块（config.lua）
- ✅ 配置验证模块（config_validator.lua）
- ✅ 规则管理（部分覆盖）
- ⚠️ 认证模块（待补充）
- ⚠️ 密码工具模块（待补充）
- ⚠️ 其他模块（待补充）

**测试框架**：
- 使用 `waf.test_framework` 模块
- 支持单元测试和集成测试
- 支持测试套件和钩子函数

## 持续集成

可以将测试集成到CI/CD流程中：

```yaml
# GitHub Actions示例
- name: Run Tests
  run: |
    resty -e 'require("tests.run_tests").run()'
```

