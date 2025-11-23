-- 配置模块单元测试
-- 路径：项目目录下的 lua/tests/unit/config_test.lua

local test_framework = require "waf.test_framework"
local config = require "config"
local config_validator = require "waf.config_validator"

local assert = test_framework.assert

-- 配置模块测试套件
test_framework.describe("配置模块测试", function()
    
    test_framework.it("配置模块应该存在", function()
        assert.not_nil(config, "config模块应该存在")
    end)
    
    test_framework.it("MySQL配置应该存在", function()
        assert.not_nil(config.mysql, "MySQL配置应该存在")
        assert.not_nil(config.mysql.host, "MySQL主机应该配置")
        assert.not_nil(config.mysql.port, "MySQL端口应该配置")
        assert.not_nil(config.mysql.database, "MySQL数据库应该配置")
    end)
    
    test_framework.it("缓存配置应该存在", function()
        assert.not_nil(config.cache, "缓存配置应该存在")
        assert.not_nil(config.cache.ttl, "缓存TTL应该配置")
        assert.not_nil(config.cache.max_items, "最大缓存项数应该配置")
    end)
    
    test_framework.it("日志配置应该存在", function()
        assert.not_nil(config.log, "日志配置应该存在")
        assert.not_nil(config.log.batch_size, "批量写入大小应该配置")
        assert.not_nil(config.log.batch_interval, "批量写入间隔应该配置")
    end)
    
    test_framework.it("封控配置应该存在", function()
        assert.not_nil(config.block, "封控配置应该存在")
        assert.not_nil(config.block.enable, "封控启用状态应该配置")
    end)
    
    test_framework.it("配置验证应该通过", function()
        local valid, results = config_validator.validate_all()
        assert.true(valid, "配置验证应该通过")
        
        if config_validator.has_errors() then
            local formatted = config_validator.format_results()
            error("配置验证失败:\n" .. formatted)
        end
    end)
    
end)

return test_framework

