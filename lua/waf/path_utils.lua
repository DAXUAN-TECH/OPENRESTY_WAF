-- 路径工具模块
-- 路径：项目目录下的 lua/waf/path_utils.lua（保持在项目目录，不复制到系统目录）
-- 功能：提供路径相关的工具函数，确保代码可移植性

local _M = {}

-- 获取项目根目录
-- 注意：此函数必须在所有阶段（包括 init_worker）都能正常工作
-- 因此完全避免在 init_worker 阶段访问任何 ngx API
function _M.get_project_root()
    -- 优先从lua_package_path推断（适用于所有阶段，包括 init_worker）
    -- 这是最可靠的方法，不依赖任何 nginx API，可以在任何阶段使用
    -- 遍历所有路径，找到包含项目目录特征的路径
    for path in package.path:gmatch("([^;]+)") do
        -- 提取路径：从 lua/?.lua 推断项目根目录
        local project_root = path:match("(.+)/lua/%?%.lua")
        if project_root and project_root ~= "" then
            -- 验证路径是否合理（不应该是系统目录）
            -- 排除常见的系统目录
            if not project_root:match("^/usr/local/share") and 
               not project_root:match("^/usr/share") and
               not project_root:match("^/usr/lib") then
                -- 验证路径是否存在 conf.d 目录（项目目录的特征）
                local confd_path = project_root .. "/conf.d"
                local test_file = io.open(confd_path, "r")
                if test_file then
                    test_file:close()
                    return project_root
                end
            end
        end
    end
    
    -- 如果上面的方法没找到，尝试第一个路径（向后兼容）
    local first_path = package.path:match("([^;]+)")
    if first_path then
        local project_root = first_path:match("(.+)/lua/%?%.lua")
        if project_root and project_root ~= "" then
            return project_root
        end
    end
    
    -- 尝试从nginx变量获取（仅在明确可以访问时）
    -- 使用多重保护：先检测阶段，再安全访问 ngx.var
    -- 如果阶段检测失败，完全跳过 ngx.var 访问（安全策略）
    local can_access_var = false
    local phase_check_ok = false
    local ok, phase = pcall(function()
        phase_check_ok = true
        return ngx.get_phase()
    end)
    
    -- 只有在阶段检测成功且不是受限阶段时，才尝试访问 ngx.var
    if phase_check_ok and ok and phase and phase ~= "init_worker" and phase ~= "init" then
        can_access_var = true
    end
    
    if can_access_var then
        local var_ok, project_root = pcall(function()
            return ngx.var.project_root
        end)
        if var_ok and project_root and project_root ~= "" then
            return project_root
        end
    end
    
    -- 如果都无法获取，返回nil
    return nil
end

-- 获取日志目录路径（相对于项目根目录）
function _M.get_log_path()
    local project_root = _M.get_project_root()
    if project_root then
        return project_root .. "/logs"
    end
    
    -- 如果无法获取项目根目录，尝试从环境变量获取
    local log_path = os.getenv("WAF_LOG_PATH")
    if log_path and log_path ~= "" then
        -- 使用 pcall 安全调用 ngx.log（在 init_worker 阶段可能不可用）
        pcall(function()
            ngx.log(ngx.INFO, "Using log path from environment variable: ", log_path)
        end)
        return log_path
    end
    
    -- 最后的后备方案：使用当前工作目录下的logs（相对路径）
    -- 使用 pcall 安全调用 ngx.log（在 init_worker 阶段可能不可用）
    pcall(function()
        ngx.log(ngx.WARN, "Cannot determine project root, using relative path 'logs' as fallback")
    end)
    return "logs"
end

-- 获取备份目录路径（相对于项目根目录）
function _M.get_backup_path()
    local project_root = _M.get_project_root()
    if project_root then
        return project_root .. "/backup"
    end
    
    -- 如果无法获取项目根目录，尝试从环境变量获取
    local backup_path = os.getenv("WAF_BACKUP_PATH")
    if backup_path and backup_path ~= "" then
        -- 使用 pcall 安全调用 ngx.log（在 init_worker 阶段可能不可用）
        pcall(function()
            ngx.log(ngx.INFO, "Using backup path from environment variable: ", backup_path)
        end)
        return backup_path
    end
    
    -- 最后的后备方案：使用当前工作目录下的backup（相对路径）
    -- 使用 pcall 安全调用 ngx.log（在 init_worker 阶段可能不可用）
    pcall(function()
        ngx.log(ngx.WARN, "Cannot determine project root, using relative path 'backup' as fallback")
    end)
    return "backup"
end

-- 确保目录存在
function _M.ensure_dir(path)
    if not path then
        return false
    end
    
    -- 安全检查：防止路径注入攻击
    -- 检查路径中是否包含危险字符
    if path:match("[;&|`$(){}]") then
        ngx.log(ngx.ERR, "Invalid characters in path: ", path)
        return false
    end
    
    -- 转义路径中的特殊字符（防止shell注入）
    -- 将单引号转义为 '\''
    local escaped_path = path:gsub("'", "'\\''")
    
    -- 使用shell命令创建目录（路径已通过安全转义）
    -- 使用单引号包裹路径，防止shell注入
    local cmd = "mkdir -p '" .. escaped_path .. "'"
    local result = os.execute(cmd)
    return result == 0 or result == true
end

return _M

