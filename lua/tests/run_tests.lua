-- 测试运行器
-- 路径：项目目录下的 lua/tests/run_tests.lua
-- 功能：运行所有测试并输出结果

local test_framework = require "waf.test_framework"

-- 加载所有测试文件
local function load_tests()
    -- 单元测试
    require "tests.unit.ip_utils_test"
    require "tests.unit.config_test"
    require "tests.unit.config_validator_test"
    require "tests.unit.rule_management_test"
    
    -- 集成测试（需要数据库连接）
    -- require "tests.integration.rule_management_test"
end

-- 运行测试
local function run()
    -- 加载测试
    load_tests()
    
    -- 运行所有测试
    local results, stats = test_framework.run_all()
    
    -- 格式化并输出结果
    local formatted = test_framework.format_results(results, stats)
    
    -- 输出结果
    if ngx then
        ngx.say(formatted)
    else
        print(formatted)
    end
    
    -- 返回退出码
    if stats.failed > 0 then
        return 1
    end
    
    return 0
end

-- 如果直接运行此文件
if not ngx then
    -- 非OpenResty环境，直接运行
    os.exit(run())
end

return {
    run = run
}

