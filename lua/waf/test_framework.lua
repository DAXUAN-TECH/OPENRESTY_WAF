-- 测试框架模块
-- 路径：项目目录下的 lua/waf/test_framework.lua（保持在项目目录，不复制到系统目录）
-- 功能：提供单元测试和集成测试框架

local _M = {}

-- 测试结果
local TestResult = {
    PASS = "PASS",
    FAIL = "FAIL",
    SKIP = "SKIP"
}

-- 测试套件
local test_suites = {}
local current_suite = nil
local current_test = nil

-- 测试统计
local test_stats = {
    total = 0,
    passed = 0,
    failed = 0,
    skipped = 0
}

-- 断言函数
local function assert_equal(actual, expected, message)
    message = message or "值不相等"
    if actual ~= expected then
        error(string.format("断言失败: %s (期望: %s, 实际: %s)", message, tostring(expected), tostring(actual)))
    end
end

local function assert_not_equal(actual, expected, message)
    message = message or "值相等"
    if actual == expected then
        error(string.format("断言失败: %s (值: %s)", message, tostring(actual)))
    end
end

local function assert_true(value, message)
    message = message or "值不为true"
    if not value then
        error(string.format("断言失败: %s", message))
    end
end

local function assert_false(value, message)
    message = message or "值不为false"
    if value then
        error(string.format("断言失败: %s", message))
    end
end

local function assert_nil(value, message)
    message = message or "值不为nil"
    if value ~= nil then
        error(string.format("断言失败: %s (值: %s)", message, tostring(value)))
    end
end

local function assert_not_nil(value, message)
    message = message or "值为nil"
    if value == nil then
        error(string.format("断言失败: %s", message))
    end
end

local function assert_type(value, expected_type, message)
    message = message or string.format("类型不匹配 (期望: %s)", expected_type)
    local actual_type = type(value)
    if actual_type ~= expected_type then
        error(string.format("断言失败: %s (实际类型: %s)", message, actual_type))
    end
end

local function assert_contains(table, value, message)
    message = message or "表中不包含指定值"
    local found = false
    for _, v in ipairs(table) do
        if v == value then
            found = true
            break
        end
    end
    if not found then
        error(string.format("断言失败: %s", message))
    end
end

-- 导出断言函数
_M.assert = {
    equal = assert_equal,
    not_equal = assert_not_equal,
    true = assert_true,
    false = assert_false,
    nil = assert_nil,
    not_nil = assert_not_nil,
    type = assert_type,
    contains = assert_contains
}

-- 创建测试套件
function _M.describe(suite_name, test_func)
    local suite = {
        name = suite_name,
        tests = {},
        before_each = nil,
        after_each = nil,
        before_all = nil,
        after_all = nil
    }
    
    current_suite = suite
    test_func()
    table.insert(test_suites, suite)
    current_suite = nil
end

-- 定义测试用例
function _M.it(test_name, test_func)
    if not current_suite then
        error("测试用例必须在describe块中定义")
    end
    
    table.insert(current_suite.tests, {
        name = test_name,
        func = test_func
    })
end

-- 设置钩子函数
function _M.before_each(func)
    if not current_suite then
        error("before_each必须在describe块中定义")
    end
    current_suite.before_each = func
end

function _M.after_each(func)
    if not current_suite then
        error("after_each必须在describe块中定义")
    end
    current_suite.after_each = func
end

function _M.before_all(func)
    if not current_suite then
        error("before_all必须在describe块中定义")
    end
    current_suite.before_all = func
end

function _M.after_all(func)
    if not current_suite then
        error("after_all必须在describe块中定义")
    end
    current_suite.after_all = func
end

-- 运行单个测试
local function run_test(suite, test)
    current_test = test
    
    -- 执行before_each
    if suite.before_each then
        suite.before_each()
    end
    
    local result = {
        name = test.name,
        status = TestResult.PASS,
        error = nil,
        duration = 0
    }
    
    local start_time = os.clock()
    
    local ok, err = pcall(test.func)
    
    result.duration = os.clock() - start_time
    
    if not ok then
        result.status = TestResult.FAIL
        result.error = err
        test_stats.failed = test_stats.failed + 1
    else
        test_stats.passed = test_stats.passed + 1
    end
    
    -- 执行after_each
    if suite.after_each then
        suite.after_each()
    end
    
    current_test = nil
    
    return result
end

-- 运行测试套件
local function run_suite(suite)
    -- 执行before_all
    if suite.before_all then
        local ok, err = pcall(suite.before_all)
        if not ok then
            ngx.log(ngx.ERR, "before_all failed for suite ", suite.name, ": ", err)
            return
        end
    end
    
    local results = {}
    
    for _, test in ipairs(suite.tests) do
        test_stats.total = test_stats.total + 1
        local result = run_test(suite, test)
        table.insert(results, result)
    end
    
    -- 执行after_all
    if suite.after_all then
        local ok, err = pcall(suite.after_all)
        if not ok then
            ngx.log(ngx.ERR, "after_all failed for suite ", suite.name, ": ", err)
        end
    end
    
    return results
end

-- 运行所有测试
function _M.run_all()
    test_stats = {
        total = 0,
        passed = 0,
        failed = 0,
        skipped = 0
    }
    
    local all_results = {}
    
    for _, suite in ipairs(test_suites) do
        local suite_results = run_suite(suite)
        all_results[suite.name] = suite_results
    end
    
    return all_results, test_stats
end

-- 获取测试统计
function _M.get_stats()
    return test_stats
end

-- 格式化测试结果
function _M.format_results(results, stats)
    local output = {}
    
    table.insert(output, "\n" .. string.rep("=", 60))
    table.insert(output, "测试结果")
    table.insert(output, string.rep("=", 60))
    
    for suite_name, suite_results in pairs(results) do
        table.insert(output, "\n[" .. suite_name .. "]")
        
        for _, result in ipairs(suite_results) do
            local status_icon = "✓"
            if result.status == TestResult.FAIL then
                status_icon = "✗"
            elseif result.status == TestResult.SKIP then
                status_icon = "-"
            end
            
            table.insert(output, string.format("  %s %s (%.3fs)", status_icon, result.name, result.duration))
            
            if result.error then
                table.insert(output, "    错误: " .. result.error)
            end
        end
    end
    
    table.insert(output, "\n" .. string.rep("-", 60))
    table.insert(output, string.format("总计: %d  通过: %d  失败: %d  跳过: %d", 
        stats.total, stats.passed, stats.failed, stats.skipped))
    table.insert(output, string.rep("=", 60) .. "\n")
    
    return table.concat(output, "\n")
end

-- 跳过测试
function _M.skip(reason)
    if current_test then
        current_test.status = TestResult.SKIP
        test_stats.skipped = test_stats.skipped + 1
        error("SKIP: " .. (reason or "测试被跳过"))
    end
end

return _M

