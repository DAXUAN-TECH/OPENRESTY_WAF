-- 规则管理集成测试
-- 路径：项目目录下的 lua/tests/integration/rule_management_test.lua
-- 注意：集成测试需要数据库连接，在非OpenResty环境中可能无法运行

local test_framework = require "waf.test_framework"
local rule_management = require "waf.rule_management"

local assert = test_framework.assert

-- 规则管理集成测试套件
test_framework.describe("规则管理集成测试", function()
    
    local test_rule_id = nil
    
    test_framework.before_all(function()
        -- 清理测试数据（如果需要）
    end)
    
    test_framework.after_all(function()
        -- 清理测试数据
        if test_rule_id then
            rule_management.delete_rule(test_rule_id)
        end
    end)
    
    test_framework.it("创建规则 - 单个IP", function()
        local rule_data = {
            rule_type = "single_ip",
            rule_value = "192.168.100.1",
            rule_name = "测试规则-单元测试",
            description = "用于单元测试的规则",
            priority = 10,
            status = 1
        }
        
        local result, err = rule_management.create_rule(rule_data)
        assert.not_nil(result, "创建规则应该成功")
        assert.not_nil(result.id, "应该返回规则ID")
        
        test_rule_id = result.id
    end)
    
    test_framework.it("查询规则详情", function()
        if not test_rule_id then
            test_framework.skip("需要先创建规则")
            return
        end
        
        local rule, err = rule_management.get_rule(test_rule_id)
        assert.not_nil(rule, "应该能查询到规则")
        assert.equal(rule.rule_type, "single_ip", "规则类型应该正确")
        assert.equal(rule.rule_value, "192.168.100.1", "规则值应该正确")
    end)
    
    test_framework.it("更新规则", function()
        if not test_rule_id then
            test_framework.skip("需要先创建规则")
            return
        end
        
        local update_data = {
            rule_name = "测试规则-已更新",
            priority = 20
        }
        
        local result, err = rule_management.update_rule(test_rule_id, update_data)
        assert.not_nil(result, "更新规则应该成功")
        
        -- 验证更新
        local rule, err = rule_management.get_rule(test_rule_id)
        assert.equal(rule.rule_name, "测试规则-已更新", "规则名称应该已更新")
        assert.equal(rule.priority, 20, "优先级应该已更新")
    end)
    
    test_framework.it("查询规则列表", function()
        local params = {
            rule_type = "single_ip",
            page = 1,
            page_size = 10
        }
        
        local result, err = rule_management.list_rules(params)
        assert.not_nil(result, "查询规则列表应该成功")
        assert.not_nil(result.rules, "应该返回规则列表")
        assert.not_nil(result.total, "应该返回总数")
    end)
    
    test_framework.it("创建规则 - IP段", function()
        local rule_data = {
            rule_type = "ip_range",
            rule_value = "192.168.200.0/24",
            rule_name = "测试规则-IP段",
            description = "用于集成测试的IP段规则",
            priority = 5,
            status = 1
        }
        
        local result, err = rule_management.create_rule(rule_data)
        assert.not_nil(result, "创建IP段规则应该成功")
        
        -- 清理测试数据
        if result.id then
            rule_management.delete_rule(result.id)
        end
    end)
    
    test_framework.it("启用和禁用规则", function()
        if not test_rule_id then
            test_framework.skip("需要先创建规则")
            return
        end
        
        -- 禁用规则
        local disable_result, disable_err = rule_management.disable_rule(test_rule_id)
        assert.not_nil(disable_result, "禁用规则应该成功")
        
        local disabled_rule, _ = rule_management.get_rule(test_rule_id)
        assert.equal(disabled_rule.status, 0, "规则状态应该为禁用")
        
        -- 启用规则
        local enable_result, enable_err = rule_management.enable_rule(test_rule_id)
        assert.not_nil(enable_result, "启用规则应该成功")
        
        local enabled_rule, _ = rule_management.get_rule(test_rule_id)
        assert.equal(enabled_rule.status, 1, "规则状态应该为启用")
    end)
    
    
    test_framework.it("删除规则", function()
        if not test_rule_id then
            test_framework.skip("需要先创建规则")
            return
        end
        
        local result, err = rule_management.delete_rule(test_rule_id)
        assert.not_nil(result, "删除规则应该成功")
        
        test_rule_id = nil
    end)
    
end)

return test_framework

