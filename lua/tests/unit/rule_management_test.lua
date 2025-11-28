-- 规则管理模块单元测试
-- 路径：项目目录下的 lua/tests/unit/rule_management_test.lua
-- 注意：这些测试主要测试验证逻辑，通过create_rule函数间接测试验证

local test_framework = require "waf.test_framework"
local rule_management = require "waf.rule_management"

local assert = test_framework.assert

-- 规则管理模块测试套件
test_framework.describe("规则管理模块测试", function()
    
    test_framework.it("规则管理模块应该存在", function()
        assert.not_nil(rule_management, "rule_management模块应该存在")
    end)
    
    test_framework.it("创建规则验证 - 必填字段", function()
        -- 测试缺少必填字段
        local result, err = rule_management.create_rule({})
        assert.nil(result, "缺少必填字段应该失败")
        assert.not_nil(err, "应该返回错误信息")
    end)
    
    test_framework.it("创建规则验证 - 单个IP格式", function()
        -- 测试有效IP
        local rule_data = {
            rule_type = "single_ip",
            rule_value = "192.168.1.1",
            rule_name = "测试规则"
        }
        -- 注意：这里不实际创建规则（需要数据库），只测试验证逻辑
        -- 如果返回错误且不是数据库相关错误，说明验证失败
        local result, err = rule_management.create_rule(rule_data)
        -- 如果err包含"无效的IP地址格式"，说明验证失败
        if err and not err:match("数据库") and not err:match("连接") then
            assert.false(err:match("无效的IP地址格式"), "有效IP应该通过验证")
        end
        
        -- 测试无效IP
        local invalid_rule_data = {
            rule_type = "single_ip",
            rule_value = "invalid_ip",
            rule_name = "测试规则"
        }
        local result2, err2 = rule_management.create_rule(invalid_rule_data)
        assert.nil(result2, "无效IP应该失败")
        if err2 then
            assert.true(err2:match("无效的IP地址格式") ~= nil, "应该返回IP格式错误")
        end
    end)
    
    test_framework.it("创建规则验证 - IP段格式", function()
        -- 测试CIDR格式
        local rule_data = {
            rule_type = "ip_range",
            rule_value = "192.168.1.0/24",
            rule_name = "测试规则"
        }
        local result, err = rule_management.create_rule(rule_data)
        -- 如果err包含"无效的IP段格式"，说明验证失败
        if err and not err:match("数据库") and not err:match("连接") then
            assert.false(err:match("无效的IP段格式"), "有效CIDR应该通过验证")
        end
        
        -- 测试IP范围格式
        local range_rule_data = {
            rule_type = "ip_range",
            rule_value = "192.168.1.1-192.168.1.100",
            rule_name = "测试规则"
        }
        local result2, err2 = rule_management.create_rule(range_rule_data)
        if err2 and not err2:match("数据库") and not err2:match("连接") then
            assert.false(err2:match("无效的IP段格式"), "有效IP范围应该通过验证")
        end
        
        -- 测试无效格式
        local invalid_rule_data = {
            rule_type = "ip_range",
            rule_value = "invalid",
            rule_name = "测试规则"
        }
        local result3, err3 = rule_management.create_rule(invalid_rule_data)
        assert.nil(result3, "无效IP段应该失败")
        if err3 then
            assert.true(err3:match("无效的IP段格式") ~= nil, "应该返回IP段格式错误")
        end
    end)
    
    test_framework.it("创建规则验证 - 地域格式", function()
        -- 测试国家代码
        local rule_data = {
            rule_type = "geo",
            rule_value = "CN",
            rule_name = "测试规则"
        }
        local result, err = rule_management.create_rule(rule_data)
        if err and not err:match("数据库") and not err:match("连接") then
            assert.false(err:match("无效的地域代码格式"), "有效国家代码应该通过验证")
        end
        
        -- 测试国家:省份
        local geo_rule_data = {
            rule_type = "geo",
            rule_value = "CN:Beijing",
            rule_name = "测试规则"
        }
        local result2, err2 = rule_management.create_rule(geo_rule_data)
        if err2 and not err2:match("数据库") and not err2:match("连接") then
            assert.false(err2:match("无效的地域代码格式"), "有效国家:省份应该通过验证")
        end
        
        -- 测试无效格式
        local invalid_rule_data = {
            rule_type = "geo",
            rule_value = "invalid",
            rule_name = "测试规则"
        }
        local result3, err3 = rule_management.create_rule(invalid_rule_data)
        assert.nil(result3, "无效地域代码应该失败")
        if err3 then
            assert.true(err3:match("无效的地域代码格式") ~= nil, "应该返回地域代码格式错误")
        end
    end)
    
    test_framework.it("创建规则验证 - 无效类型", function()
        local rule_data = {
            rule_type = "invalid_type",
            rule_value = "value",
            rule_name = "测试规则"
        }
        local result, err = rule_management.create_rule(rule_data)
        assert.nil(result, "无效规则类型应该失败")
        if err then
            assert.true(err:match("无效的规则类型") ~= nil, "应该返回规则类型错误")
        end
    end)
    
end)

-- 注意：实际的CRUD操作测试在集成测试中，因为需要数据库连接
return test_framework

