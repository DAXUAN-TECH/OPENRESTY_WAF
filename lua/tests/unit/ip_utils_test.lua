-- IP工具函数单元测试
-- 路径：项目目录下的 lua/tests/unit/ip_utils_test.lua

local test_framework = require "waf.test_framework"
local ip_utils = require "waf.ip_utils"

local assert = test_framework.assert

-- IP工具函数测试套件
test_framework.describe("IP工具函数测试", function()
    
    test_framework.it("IPv4转整数", function()
        local ip = "192.168.1.1"
        local int = ip_utils.ipv4_to_int(ip)
        assert.not_nil(int, "IPv4转整数应该成功")
        assert.equal(int, 3232235777, "IPv4转整数结果应该正确")
    end)
    
    test_framework.it("整数转IPv4", function()
        local int = 3232235777
        local ip = ip_utils.int_to_ipv4(int)
        assert.equal(ip, "192.168.1.1", "整数转IPv4结果应该正确")
    end)
    
    test_framework.it("CIDR匹配 - IPv4", function()
        assert.true(ip_utils.match_cidr("192.168.1.100", "192.168.1.0/24"), "应该在CIDR范围内")
        assert.false(ip_utils.match_cidr("192.168.2.100", "192.168.1.0/24"), "不应该在CIDR范围内")
    end)
    
    test_framework.it("IP范围匹配", function()
        assert.true(ip_utils.match_ip_range("192.168.1.50", "192.168.1.1", "192.168.1.100"), "应该在IP范围内")
        assert.false(ip_utils.match_ip_range("192.168.1.200", "192.168.1.1", "192.168.1.100"), "不应该在IP范围内")
    end)
    
    test_framework.it("解析IP范围", function()
        local start_ip, end_ip = ip_utils.parse_ip_range("192.168.1.1-192.168.1.100")
        assert.not_nil(start_ip, "应该能解析起始IP")
        assert.not_nil(end_ip, "应该能解析结束IP")
        assert.equal(start_ip, "192.168.1.1", "起始IP应该正确")
        assert.equal(end_ip, "192.168.1.100", "结束IP应该正确")
    end)
    
    test_framework.it("验证IP地址格式", function()
        assert.true(ip_utils.is_valid_ip("192.168.1.1"), "有效IPv4应该通过验证")
        assert.true(ip_utils.is_valid_ip("2001:db8::1"), "有效IPv6应该通过验证")
        assert.false(ip_utils.is_valid_ip("invalid"), "无效IP应该失败")
        assert.false(ip_utils.is_valid_ip("256.256.256.256"), "无效IPv4应该失败")
    end)
    
    test_framework.it("判断IP版本", function()
        assert.equal(ip_utils.get_ip_version("192.168.1.1"), 4, "IPv4应该返回4")
        assert.equal(ip_utils.get_ip_version("2001:db8::1"), 6, "IPv6应该返回6")
        assert.nil(ip_utils.get_ip_version("invalid"), "无效IP应该返回nil")
    end)
    
    test_framework.it("验证CIDR格式", function()
        assert.true(ip_utils.is_valid_cidr("192.168.1.0/24"), "有效CIDR应该通过验证")
        assert.true(ip_utils.is_valid_cidr("2001:db8::/32"), "有效IPv6 CIDR应该通过验证")
        assert.false(ip_utils.is_valid_cidr("192.168.1.0/33"), "无效掩码应该失败")
        assert.false(ip_utils.is_valid_cidr("invalid"), "无效格式应该失败")
    end)
    
end)

return test_framework

