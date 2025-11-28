-- 规则模板模块
-- 路径：项目目录下的 lua/waf/rule_templates.lua（保持在项目目录，不复制到系统目录）
-- 功能：提供常用封控规则模板库

local mysql_pool = require "waf.mysql_pool"
local batch_operations = require "waf.batch_operations"
local cjson = require "cjson"

local _M = {}

-- 预定义的规则模板
local TEMPLATES = {
    {
        name = "常见攻击IP段",
        description = "封控常见的攻击IP段（包括Tor节点、VPN节点等）",
        category = "security",
        rules = {
            {
                rule_type = "ip_range",
                rule_value = "10.0.0.0/8",
                rule_name = "私有网络A类",
                description = "封控私有网络A类地址段",
                status = 0,  -- 默认禁用，需要手动启用
                priority = 10
            },
            {
                rule_type = "ip_range",
                rule_value = "172.16.0.0/12",
                rule_name = "私有网络B类",
                description = "封控私有网络B类地址段",
                status = 0,
                priority = 10
            },
            {
                rule_type = "ip_range",
                rule_value = "192.168.0.0/16",
                rule_name = "私有网络C类",
                description = "封控私有网络C类地址段",
                status = 0,
                priority = 10
            }
        }
    },
    {
        name = "常见扫描IP段",
        description = "封控常见的扫描行为IP段",
        category = "security",
        rules = {
            {
                rule_type = "ip_range",
                rule_value = "1.0.0.0/8",
                rule_name = "扫描IP段1",
                description = "常见扫描IP段",
                status = 0,
                priority = 20
            }
        }
    },
    {
        name = "IPv6私有地址段",
        description = "封控IPv6私有地址段",
        category = "security",
        rules = {
            {
                rule_type = "ip_range",
                rule_value = "fc00::/7",
                rule_name = "IPv6私有地址段",
                description = "封控IPv6私有地址段（fc00::/7）",
                status = 0,
                priority = 10
            },
            {
                rule_type = "ip_range",
                rule_value = "fe80::/10",
                rule_name = "IPv6链路本地地址",
                description = "封控IPv6链路本地地址（fe80::/10）",
                status = 0,
                priority = 10
            }
        }
    },
    {
        name = "测试环境封控",
        description = "封控测试环境常用IP段",
        category = "testing",
        rules = {
            {
                rule_type = "ip_range",
                rule_value = "127.0.0.0/8",
                rule_name = "本地回环地址",
                description = "封控本地回环地址段",
                status = 0,
                priority = 5
            }
        }
    }
}

-- 获取所有模板列表
function _M.list_templates()
    local templates = {}
    for _, template in ipairs(TEMPLATES) do
        table.insert(templates, {
            name = template.name,
            description = template.description,
            category = template.category,
            rule_count = #template.rules
        })
    end
    return templates
end

-- 获取指定模板的详细信息
function _M.get_template(template_name)
    for _, template in ipairs(TEMPLATES) do
        if template.name == template_name then
            return template
        end
    end
    return nil
end

-- 应用模板（将模板规则导入到数据库）
function _M.apply_template(template_name, options)
    options = options or {}
    local update_existing = options.update_existing or false
    local enable_rules = options.enable_rules or false
    
    local template = _M.get_template(template_name)
    if not template then
        return nil, "template not found: " .. template_name
    end
    
    -- 复制规则并应用选项
    local rules = {}
    for _, rule in ipairs(template.rules) do
        local rule_copy = {}
        for k, v in pairs(rule) do
            rule_copy[k] = v
        end
        
        -- 如果启用规则，覆盖状态
        if enable_rules then
            rule_copy.status = 1
        end
        
        table.insert(rules, rule_copy)
    end
    
    -- 使用批量导入功能
    local results, err = batch_operations.import_rules_json(rules, {
        skip_invalid = true,
        update_existing = update_existing
    })
    
    if err then
        return nil, err
    end
    
    return {
        template_name = template_name,
        template_description = template.description,
        import_results = results
    }, nil
end

-- 从数据库加载模板到模板表（如果模板表存在）
function _M.load_templates_to_db()
    -- 检查模板表是否存在
    local sql_check = [[
        SELECT COUNT(*) as cnt FROM information_schema.tables
        WHERE table_schema = DATABASE()
        AND table_name = 'waf_rule_templates'
    ]]
    
    local res, err = mysql_pool.query(sql_check)
    if err or not res or #res == 0 or tonumber(res[1].cnt) == 0 then
        -- 模板表不存在，跳过
        return nil, "template table not exists"
    end
    
    -- 清空模板表
    local sql_truncate = "TRUNCATE TABLE waf_rule_templates"
    mysql_pool.query(sql_truncate)
    
    -- 插入模板
    for _, template in ipairs(TEMPLATES) do
        local sql_insert = [[
            INSERT INTO waf_rule_templates
            (template_name, template_description, category, template_data, status, created_at)
            VALUES (?, ?, ?, ?, 1, NOW())
        ]]
        
        local template_data = cjson.encode(template.rules)
        mysql_pool.insert(sql_insert,
            template.name,
            template.description,
            template.category,
            template_data
        )
    end
    
    return true, nil
end

-- 从数据库获取模板列表
function _M.list_templates_from_db()
    local sql = [[
        SELECT id, template_name, template_description, category, status, created_at
        FROM waf_rule_templates
        WHERE status = 1
        ORDER BY category, template_name
    ]]
    
    local res, err = mysql_pool.query(sql)
    if err then
        ngx.log(ngx.ERR, "list templates from db error: ", err)
        return nil, err
    end
    
    return res or {}, nil
end

-- 从数据库获取模板详情
function _M.get_template_from_db(template_id)
    local sql = [[
        SELECT id, template_name, template_description, category, template_data, status
        FROM waf_rule_templates
        WHERE id = ?
        AND status = 1
        LIMIT 1
    ]]
    
    local res, err = mysql_pool.query(sql, template_id)
    if err then
        ngx.log(ngx.ERR, "get template from db error: ", err)
        return nil, err
    end
    
    if not res or #res == 0 then
        return nil, "template not found"
    end
    
    local template = res[1]
    local ok, rules = pcall(cjson.decode, template.template_data)
    if not ok then
        return nil, "invalid template data"
    end
    
    return {
        id = template.id,
        name = template.template_name,
        description = template.template_description,
        category = template.category,
        status = template.status,
        rules = rules
    }, nil
end

-- 应用数据库中的模板
function _M.apply_template_from_db(template_id, options)
    local template, err = _M.get_template_from_db(template_id)
    if err then
        return nil, err
    end
    
    options = options or {}
    local update_existing = options.update_existing or false
    local enable_rules = options.enable_rules or false
    
    -- 复制规则并应用选项
    local rules = {}
    for _, rule in ipairs(template.rules) do
        local rule_copy = {}
        for k, v in pairs(rule) do
            rule_copy[k] = v
        end
        
        -- 如果启用规则，覆盖状态
        if enable_rules then
            rule_copy.status = 1
        end
        
        table.insert(rules, rule_copy)
    end
    
    -- 使用批量导入功能
    local results, err = batch_operations.import_rules_json(rules, {
        skip_invalid = true,
        update_existing = update_existing
    })
    
    if err then
        return nil, err
    end
    
    return {
        template_id = template.id,
        template_name = template.name,
        template_description = template.description,
        import_results = results
    }, nil
end

return _M

