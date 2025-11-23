-- 路径工具模块
-- 路径：项目目录下的 lua/waf/path_utils.lua（保持在项目目录，不复制到系统目录）
-- 功能：提供路径相关的工具函数，确保代码可移植性

local _M = {}

-- 获取项目根目录
function _M.get_project_root()
    -- 优先从nginx变量获取
    local project_root = ngx.var.project_root
    if project_root and project_root ~= "" then
        return project_root
    end
    
    -- 从lua_package_path推断
    local first_path = package.path:match("([^;]+)")
    if first_path then
        -- 提取路径：从 lua/?.lua 推断项目根目录
        project_root = first_path:match("(.+)/lua/%?%.lua")
        if project_root and project_root ~= "" then
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
        ngx.log(ngx.INFO, "Using log path from environment variable: ", log_path)
        return log_path
    end
    
    -- 最后的后备方案：使用当前工作目录下的logs（相对路径）
    ngx.log(ngx.WARN, "Cannot determine project root, using relative path 'logs' as fallback")
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
        ngx.log(ngx.INFO, "Using backup path from environment variable: ", backup_path)
        return backup_path
    end
    
    -- 最后的后备方案：使用当前工作目录下的backup（相对路径）
    ngx.log(ngx.WARN, "Cannot determine project root, using relative path 'backup' as fallback")
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

