-- IP段匹配Trie树优化模块
-- 路径：项目目录下的 lua/waf/ip_trie.lua（保持在项目目录，不复制到系统目录）
-- 功能：使用Trie树优化IP段匹配效率

local ip_utils = require "waf.ip_utils"
local cjson = require "cjson"

-- 检查 bit 库是否可用（LuaJIT 内置）
local bit = bit
if not bit then
    local ok, bit_module = pcall(require, "bit")
    if ok then
        bit = bit_module
    else
        error("bit library is required for Trie tree")
    end
end

local _M = {}

-- Trie树节点
local TrieNode = {}
TrieNode.__index = TrieNode

function TrieNode:new()
    local node = {
        children = {},
        rules = {},  -- 存储匹配的规则（按优先级排序）
        is_leaf = false
    }
    setmetatable(node, TrieNode)
    return node
end

function TrieNode:add_rule(rule, priority)
    table.insert(self.rules, {
        rule = rule,
        priority = priority or 0
    })
    
    -- 按优先级排序
    table.sort(self.rules, function(a, b)
        return a.priority > b.priority
    end)
    
    self.is_leaf = true
end

function TrieNode:get_best_rule()
    if #self.rules > 0 then
        return self.rules[1].rule
    end
    return nil
end

-- IPv4 Trie树
local IPv4Trie = {}
IPv4Trie.__index = IPv4Trie

function IPv4Trie:new()
    local trie = {
        root = TrieNode:new()
    }
    setmetatable(trie, IPv4Trie)
    return trie
end

-- 添加CIDR规则到Trie树
function IPv4Trie:add_cidr(cidr, rule, priority)
    local base_ip, mask_str = cidr:match("^([^/]+)/(%d+)$")
    if not base_ip then
        return false
    end
    
    local mask = tonumber(mask_str)
    if not mask or mask < 0 or mask > 32 then
        return false
    end
    
    local ip_int = ip_utils.ipv4_to_int(base_ip)
    if not ip_int then
        return false
    end
    
    -- 计算网络地址
    local network_mask = bit.lshift(0xFFFFFFFF, 32 - mask)
    local network_addr = bit.band(ip_int, network_mask)
    
    -- 将IP地址转换为二进制路径
    local node = self.root
    for i = 31, 32 - mask, -1 do
        local bit_val = bit.band(bit.rshift(network_addr, i), 1)
        local key = tostring(bit_val)
        
        if not node.children[key] then
            node.children[key] = TrieNode:new()
        end
        node = node.children[key]
    end
    
    -- 在叶子节点添加规则
    node:add_rule(rule, priority)
    
    return true
end

-- 匹配IP地址
function IPv4Trie:match(ip)
    local ip_int = ip_utils.ipv4_to_int(ip)
    if not ip_int then
        return nil
    end
    
    local node = self.root
    local best_rule = nil
    local best_priority = -1
    
    -- 遍历Trie树
    for i = 31, 0, -1 do
        local bit_val = bit.band(bit.rshift(ip_int, i), 1)
        local key = tostring(bit_val)
        
        if node.children[key] then
            node = node.children[key]
            
            -- 检查当前节点是否有规则
            if node.is_leaf and #node.rules > 0 then
                local rule = node:get_best_rule()
                if rule then
                    best_rule = rule
                    best_priority = rule.priority or 0
                end
            end
        else
            -- 路径不存在，返回最佳匹配
            break
        end
    end
    
    return best_rule
end

-- IPv6 Trie树（简化版，使用前64位）
local IPv6Trie = {}
IPv6Trie.__index = IPv6Trie

function IPv6Trie:new()
    local trie = {
        root = TrieNode:new()
    }
    setmetatable(trie, IPv6Trie)
    return trie
end

-- 添加IPv6 CIDR规则
function IPv6Trie:add_cidr(cidr, rule, priority)
    local base_ip, mask_str = cidr:match("^([^/]+)/(%d+)$")
    if not base_ip then
        return false
    end
    
    local mask = tonumber(mask_str)
    if not mask or mask < 0 or mask > 128 then
        return false
    end
    
    local ip_high, ip_low = ip_utils.ipv6_to_int128(base_ip)
    if not ip_high then
        return false
    end
    
    -- 只使用前64位（高64位）进行Trie树匹配
    local node = self.root
    local max_bits = math.min(64, mask)
    
    for i = 63, 64 - max_bits, -1 do
        local bit_val = bit.band(bit.rshift(ip_high, i), 1)
        local key = tostring(bit_val)
        
        if not node.children[key] then
            node.children[key] = TrieNode:new()
        end
        node = node.children[key]
    end
    
    node:add_rule(rule, priority)
    
    return true
end

-- 匹配IPv6地址
function IPv6Trie:match(ip)
    local ip_high, ip_low = ip_utils.ipv6_to_int128(ip)
    if not ip_high then
        return nil
    end
    
    local node = self.root
    local best_rule = nil
    
    -- 遍历前64位
    for i = 63, 0, -1 do
        local bit_val = bit.band(bit.rshift(ip_high, i), 1)
        local key = tostring(bit_val)
        
        if node.children[key] then
            node = node.children[key]
            
            if node.is_leaf and #node.rules > 0 then
                best_rule = node:get_best_rule()
            end
        else
            break
        end
    end
    
    return best_rule
end

-- 规则Trie树管理器
local RuleTrieManager = {}
RuleTrieManager.__index = RuleTrieManager

function RuleTrieManager:new()
    local manager = {
        ipv4_trie = IPv4Trie:new(),
        ipv6_trie = IPv6Trie:new(),
        range_rules = {}  -- IP范围规则（无法用Trie树优化）
    }
    setmetatable(manager, RuleTrieManager)
    return manager
end

-- 添加规则
function RuleTrieManager:add_rule(rule)
    local rule_value = rule.rule_value
    local rule_type = rule.rule_type
    local priority = rule.priority or 0
    
    -- 检查CIDR格式
    if rule_value:match("^([^/]+)/(%d+)$") then
        local ip_version = ip_utils.get_ip_version(rule_value:match("^([^/]+)/"))
        if ip_version == 4 then
            self.ipv4_trie:add_cidr(rule_value, rule, priority)
        elseif ip_version == 6 then
            self.ipv6_trie:add_cidr(rule_value, rule, priority)
        end
    else
        -- IP范围格式，添加到范围规则列表
        table.insert(self.range_rules, rule)
    end
end

-- 匹配IP地址
function RuleTrieManager:match(ip)
    local ip_version = ip_utils.get_ip_version(ip)
    if not ip_version then
        return nil
    end
    
    local matched_rule = nil
    local best_priority = -1
    
    -- 使用Trie树匹配CIDR规则
    if ip_version == 4 then
        matched_rule = self.ipv4_trie:match(ip)
    elseif ip_version == 6 then
        matched_rule = self.ipv6_trie:match(ip)
    end
    
    if matched_rule then
        best_priority = matched_rule.priority or 0
    end
    
    -- 检查IP范围规则
    for _, rule in ipairs(self.range_rules) do
        local start_ip, end_ip = ip_utils.parse_ip_range(rule.rule_value)
        if start_ip and end_ip then
            if ip_utils.match_ip_range(ip, start_ip, end_ip) then
                local priority = rule.priority or 0
                if priority > best_priority then
                    matched_rule = rule
                    best_priority = priority
                end
            end
        end
    end
    
    return matched_rule
end

-- 构建规则Trie树（从规则列表）
function _M.build_trie(rules)
    local manager = RuleTrieManager:new()
    
    for _, rule in ipairs(rules) do
        manager:add_rule(rule)
    end
    
    return manager
end

-- 序列化Trie树（用于缓存）
function _M.serialize_trie(trie_manager)
    -- 简化序列化（只序列化规则列表，重建Trie树）
    return {
        range_rules = trie_manager.range_rules
    }
end

-- 反序列化Trie树（从缓存）
function _M.deserialize_trie(data, all_rules)
    local manager = RuleTrieManager:new()
    
    -- 重建Trie树
    for _, rule in ipairs(all_rules) do
        manager:add_rule(rule)
    end
    
    return manager
end

return _M

