-- 配置验证模块单元测试
-- 路径：项目目录下的 lua/tests/unit/config_validator_test.lua

local test_framework = require "waf.test_framework"
local config_validator = require "waf.config_validator"
local config = require "config"

local assert = test_framework.assert

-- 配置验证模块测试套件
test_framework.describe("配置验证模块测试", function()
    
    test_framework.it("配置验证模块应该存在", function()
        assert.not_nil(config_validator, "config_validator模块应该存在")
    end)
    
    test_framework.it("应该能够执行配置验证", function()
        local valid, results = config_validator.validate_all()
        assert.not_nil(valid, "验证应该返回结果")
        assert.not_nil(results, "验证应该返回结果列表")
        assert.type(results, "table", "结果应该是表类型")
    end)
    
    test_framework.it("应该能够获取验证结果", function()
        config_validator.validate_all()
        local results = config_validator.get_results()
        assert.not_nil(results, "应该能够获取验证结果")
        assert.type(results, "table", "结果应该是表类型")
    end)
    
    test_framework.it("应该能够检查是否有错误", function()
        config_validator.validate_all()
        local has_errors = config_validator.has_errors()
        assert.type(has_errors, "boolean", "has_errors应该返回布尔值")
    end)
    
    test_framework.it("应该能够检查是否有警告", function()
        config_validator.validate_all()
        local has_warnings = config_validator.has_warnings()
        assert.type(has_warnings, "boolean", "has_warnings应该返回布尔值")
    end)
    
    test_framework.it("应该能够格式化验证结果", function()
        config_validator.validate_all()
        local formatted = config_validator.format_results()
        assert.not_nil(formatted, "应该能够格式化验证结果")
        assert.type(formatted, "string", "格式化结果应该是字符串")
    end)
    
    test_framework.it("MySQL配置验证", function()
        -- 验证MySQL配置存在
        assert.not_nil(config.mysql, "MySQL配置应该存在")
        
        -- 执行验证
        config_validator.validate_all()
        
        -- 如果配置正确，不应该有错误
        -- 注意：这里只检查验证逻辑是否工作，不检查具体配置值
    end)
    
    test_framework.it("缓存配置验证", function()
        -- 验证缓存配置存在
        assert.not_nil(config.cache, "缓存配置应该存在")
        
        -- 执行验证
        config_validator.validate_all()
    end)
    
    test_framework.it("日志配置验证", function()
        -- 验证日志配置存在
        assert.not_nil(config.log, "日志配置应该存在")
        
        -- 执行验证
        config_validator.validate_all()
    end)
    
end)

return test_framework

