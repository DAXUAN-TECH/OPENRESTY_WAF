-- WAF 初始化模块
-- 路径：项目目录下的 lua/waf/init.lua（保持在项目目录，不复制到系统目录）

local _M = {}
local config = require "config"

-- 初始化函数（在init_by_lua阶段调用）
function _M.init()
    ngx.log(ngx.INFO, "WAF module initialized")
    
    -- 启动时配置验证（如果功能启用）
    -- 注意：在init阶段无法访问数据库，所以先检查配置文件
    -- 实际运行时会在相关模块中从数据库读取
    local config_validation_enabled = true
    if config.features and config.features.config_validation then
        config_validation_enabled = config.features.config_validation.enable == true
    end
    
    if config_validation_enabled then
        local config_validator = require "waf.config_validator"
        local valid, results = config_validator.validate_all()
        
        if not valid or config_validator.has_errors() then
            local formatted = config_validator.format_results()
            ngx.log(ngx.ERR, "配置验证失败:\n", formatted)
            -- 如果有严重错误，可以选择阻止启动或仅记录警告
            -- 这里选择记录错误但继续启动（可以根据需要修改）
        elseif config_validator.has_warnings() then
            local formatted = config_validator.format_results()
            ngx.log(ngx.WARN, "配置验证警告:\n", formatted)
        else
            ngx.log(ngx.INFO, "配置验证通过")
        end
    else
        ngx.log(ngx.INFO, "配置验证功能已禁用，跳过配置验证")
    end
    
    -- 动态设置 GeoIP2 数据库路径（如果未配置）
    if config.geo.enable and not config.geo.geoip_db_path then
        -- 获取项目根目录（从 nginx 变量）
        local project_root = ngx.var.project_root
        if not project_root or project_root == "" then
            -- 如果变量未设置，尝试从 lua_package_path 推断
            -- package.path 中第一个路径通常是项目根目录下的 lua
            local first_path = package.path:match("([^;]+)")
            if first_path then
                -- 提取路径：从 lua/?.lua 推断项目根目录
                project_root = first_path:match("(.+)/lua/%?%.lua")
            end
        end
        
        if project_root and project_root ~= "" then
            config.geo.geoip_db_path = project_root .. "/lua/geoip/GeoLite2-City.mmdb"
            ngx.log(ngx.INFO, "GeoIP2 database path auto-configured: ", config.geo.geoip_db_path)
        else
            ngx.log(ngx.WARN, "GeoIP2 database path not configured and cannot auto-detect project root")
        end
    end
    
    -- 预加载 GeoIP2 数据库（如果启用）
    -- 注意：在 init_by_lua 阶段无法访问 ngx.shared，所以这里只做基本检查
    if config.geo.enable then
        if not config.geo.geoip_db_path then
            ngx.log(ngx.WARN, "GeoIP2 database path not configured")
        else
            ngx.log(ngx.INFO, "GeoIP2 enabled, database path: ", config.geo.geoip_db_path)
        end
    end
end

-- 初始化工作进程（在init_worker阶段调用）
function _M.init_worker()
    ngx.log(ngx.INFO, "WAF worker initialized")
    
    -- 初始化自动解封定时器
    if config.auto_block.enable then
        local auto_unblock = require "waf.auto_unblock"
        auto_unblock.init_worker()
        ngx.log(ngx.INFO, "Auto unblock timer initialized")
    end
    
    -- 初始化数据库健康检查定时器
    if config.fallback and config.fallback.enable then
        local health_check = require "waf.health_check"
        local check_interval = config.fallback.health_check_interval or 10
        
        local function periodic_health_check(premature)
            if premature then
                return
            end
            
            health_check.check_health()
            
            -- 设置下一次定时器
            local ok, err = ngx.timer.at(check_interval, periodic_health_check)
            if not ok then
                ngx.log(ngx.ERR, "failed to create health check timer: ", err)
            end
        end
        
        -- 启动定时器
        local ok, err = ngx.timer.at(check_interval, periodic_health_check)
        if not ok then
            ngx.log(ngx.ERR, "failed to create initial health check timer: ", err)
        else
            ngx.log(ngx.INFO, "Database health check timer initialized")
        end
    end
    
    -- 初始化缓存预热定时器
    if config.cache_warmup and config.cache_warmup.enable then
        local cache_warmup = require "waf.cache_warmup"
        local warmup_interval = config.cache_warmup.interval or 300
        
        local function periodic_warmup(premature)
            if premature then
                return
            end
            
            -- 检查是否需要预热
            if cache_warmup.should_warmup() then
                ngx.log(ngx.INFO, "Starting cache warmup")
                local results = cache_warmup.do_warmup()
                for _, result in ipairs(results) do
                    if result.success then
                        ngx.log(ngx.INFO, "Cache warmup completed: ", result.type)
                    else
                        ngx.log(ngx.ERR, "Cache warmup failed: ", result.type, " - ", result.error)
                    end
                end
            end
            
            -- 设置下一次定时器
            local ok, err = ngx.timer.at(warmup_interval, periodic_warmup)
            if not ok then
                ngx.log(ngx.ERR, "failed to create warmup timer: ", err)
            end
        end
        
        -- 启动定时器
        local ok, err = ngx.timer.at(warmup_interval, periodic_warmup)
        if not ok then
            ngx.log(ngx.ERR, "failed to create initial warmup timer: ", err)
        else
            ngx.log(ngx.INFO, "Cache warmup timer initialized")
        end
    end
    
    -- 初始化LRU缓存清理定时器
    if config.cache and config.cache.max_items then
        local lru_cache = require "waf.lru_cache"
        local cleanup_interval = 60  -- 每分钟清理一次
        
        local function periodic_cleanup(premature)
            if premature then
                return
            end
            
            local cleaned = lru_cache.cleanup()
            if cleaned > 0 then
                ngx.log(ngx.INFO, "LRU cache cleanup: removed ", cleaned, " expired items")
            end
            
            -- 设置下一次定时器
            local ok, err = ngx.timer.at(cleanup_interval, periodic_cleanup)
            if not ok then
                ngx.log(ngx.ERR, "failed to create cleanup timer: ", err)
            end
        end
        
        -- 启动定时器
        local ok, err = ngx.timer.at(cleanup_interval, periodic_cleanup)
        if not ok then
            ngx.log(ngx.ERR, "failed to create initial cleanup timer: ", err)
        else
            ngx.log(ngx.INFO, "LRU cache cleanup timer initialized")
        end
    end
    
    -- 初始化日志队列处理定时器
    if config.log and config.log.enable_async then
        -- 使用 pcall 安全加载 log_queue（在 init_worker 阶段可能有问题）
        local ok, log_queue = pcall(require, "waf.log_queue")
        if not ok or not log_queue then
            ngx.log(ngx.ERR, "failed to load log_queue module: ", log_queue or "unknown error")
            -- 如果加载失败，跳过日志队列初始化，但不影响其他功能
            return
        end
        local queue_process_interval = 5  -- 每5秒处理一次队列
        
        local function periodic_queue_process(premature)
            if premature then
                return
            end
            
            -- 处理重试队列
            local processed = log_queue.process_retry_queue()
            if processed > 0 then
                ngx.log(ngx.INFO, "Log queue processed: ", processed, " retry items")
            end
            
            -- 设置下一次定时器
            local ok, err = ngx.timer.at(queue_process_interval, periodic_queue_process)
            if not ok then
                ngx.log(ngx.ERR, "failed to create queue process timer: ", err)
            end
        end
        
        -- 启动定时器
        local ok, err = ngx.timer.at(queue_process_interval, periodic_queue_process)
        if not ok then
            ngx.log(ngx.ERR, "failed to create initial queue process timer: ", err)
        else
            ngx.log(ngx.INFO, "Log queue process timer initialized")
        end
    end
    
    -- 规则备份定时器已移除
    -- 现在只在规则新增、删除、修改时触发备份（在rule_management.lua中调用）
    -- 这样可以减少备份文件数量，只在规则变更时备份
    
    -- 初始化告警检查定时器
    if config.alert and config.alert.enable then
        local alert = require "waf.alert"
        local alert_interval = 60  -- 每分钟检查一次
        
        local function periodic_alert_check(premature)
            if premature then
                return
            end
            
            alert.check_all()
            
            -- 设置下一次定时器
            local ok, err = ngx.timer.at(alert_interval, periodic_alert_check)
            if not ok then
                ngx.log(ngx.ERR, "failed to create alert check timer: ", err)
            end
        end
        
        -- 启动定时器
        local ok, err = ngx.timer.at(alert_interval, periodic_alert_check)
        if not ok then
            ngx.log(ngx.ERR, "failed to create initial alert check timer: ", err)
        else
            ngx.log(ngx.INFO, "Alert check timer initialized")
        end
    end
    
    -- 初始化性能监控定时器
    local performance_monitor = require "waf.performance_monitor"
    if performance_monitor then
        local monitor_interval = 300  -- 每5分钟检查一次
        
        local function periodic_monitor_check(premature)
            if premature then
                return
            end
            
            -- 清理过期慢查询记录
            performance_monitor.cleanup_old_queries()
            
            -- 设置下一次定时器
            local ok, err = ngx.timer.at(monitor_interval, periodic_monitor_check)
            if not ok then
                ngx.log(ngx.ERR, "failed to create performance monitor timer: ", err)
            end
        end
        
        -- 启动定时器
        local ok, err = ngx.timer.at(monitor_interval, periodic_monitor_check)
        if not ok then
            ngx.log(ngx.ERR, "failed to create initial performance monitor timer: ", err)
        else
            ngx.log(ngx.INFO, "Performance monitor timer initialized")
        end
    end
    
    -- 初始化缓存调优定时器
    local cache_tuner = require "waf.cache_tuner"
    if cache_tuner then
        local config_manager = require "waf.config_manager"
        local tuning_interval = tonumber(config_manager.get_config("cache_tuner_interval", 300, "number")) or 300
        
        local function periodic_cache_tuning(premature)
            if premature then
                return
            end
            
            -- 执行缓存调优
            cache_tuner.tune_cache_ttl()
            
            -- 设置下一次定时器
            local ok, err = ngx.timer.at(tuning_interval, periodic_cache_tuning)
            if not ok then
                ngx.log(ngx.ERR, "failed to create cache tuning timer: ", err)
            end
        end
        
        -- 启动定时器
        local ok, err = ngx.timer.at(tuning_interval, periodic_cache_tuning)
        if not ok then
            ngx.log(ngx.ERR, "failed to create initial cache tuning timer: ", err)
        else
            ngx.log(ngx.INFO, "Cache tuning timer initialized")
        end
    end
    
    -- 初始化nginx代理配置生成（确保配置文件存在）
    -- 使用定时器延迟执行，避免在init_worker阶段阻塞
    -- 重要：每次init_worker执行时都重新生成配置文件（包括首次启动和reload）
    -- 这样确保配置文件始终与数据库配置保持一致
    -- 添加重试机制，确保数据库连接成功时能够读取到配置
    local function init_proxy_configs(premature, retry_count)
        if premature then
            return
        end
        
        retry_count = retry_count or 0
        local max_retries = 5  -- 最大重试次数
        local retry_interval = 3  -- 重试间隔（秒）
        
        local path_utils = require "waf.path_utils"
        local project_root = path_utils.get_project_root()
        if not project_root then
            ngx.log(ngx.ERR, "无法获取项目根目录，跳过配置生成")
            return
        end
        
        -- 每次init_worker执行时都重新生成配置文件
        -- 这样确保配置文件始终与数据库配置保持一致
        if retry_count == 0 then
            ngx.log(ngx.INFO, "开始生成/更新代理配置文件...")
        else
            ngx.log(ngx.INFO, "重试生成/更新代理配置文件... (第 ", retry_count, " 次重试)")
        end
        
        local ok, nginx_config_generator = pcall(require, "waf.nginx_config_generator")
        if ok and nginx_config_generator and nginx_config_generator.generate_all_configs then
            local gen_ok, gen_err = nginx_config_generator.generate_all_configs()
            if gen_ok then
                ngx.log(ngx.INFO, "Proxy configs generated: ", gen_err or "success")
            else
                -- 记录详细错误信息
                local error_msg = gen_err or "unknown error"
                
                -- 检查是否是数据库连接错误
                local is_connection_error = error_msg:match("failed to connect") or 
                                          error_msg:match("timeout") or 
                                          error_msg:match("Connection refused") or
                                          error_msg:match("Can't connect") or
                                          error_msg:match("查询代理配置失败")
                
                if is_connection_error and retry_count < max_retries then
                    -- 如果是连接错误且未达到最大重试次数，则重试
                    ngx.log(ngx.WARN, "数据库连接失败，", retry_interval, " 秒后重试 (", retry_count + 1, "/", max_retries, "): ", error_msg)
                    local retry_ok, retry_err = ngx.timer.at(retry_interval, init_proxy_configs, retry_count + 1)
                    if not retry_ok then
                        ngx.log(ngx.ERR, "failed to create retry timer: ", retry_err)
                    end
                else
                    -- 如果不是连接错误，或者已达到最大重试次数，记录错误但不阻止系统运行
                    if retry_count >= max_retries then
                        ngx.log(ngx.ERR, "Failed to generate proxy configs after ", max_retries, " retries: ", error_msg)
                        
                        -- 检查是否有已有配置文件，如果有，说明系统可以继续使用已有配置
                        local http_config_dir = project_root .. "/conf.d/vhost_conf/http_https"
                        local tcp_config_dir = project_root .. "/conf.d/vhost_conf/tcp_udp"
                        local has_existing_configs = false
                        
                        -- 检查HTTP/HTTPS代理配置文件
                        -- 使用更安全的方法：先检查目录是否存在，再查找配置文件
                        local http_dir = io.open(http_config_dir, "r")
                        if http_dir then
                            http_dir:close()
                            -- 使用find命令查找配置文件（更安全，避免shell注入）
                            -- 转义路径中的特殊字符，防止命令注入
                            local escaped_dir = http_config_dir:gsub("'", "'\\''")
                            local find_cmd = "find '" .. escaped_dir .. "' -maxdepth 1 -name 'proxy_http_*.conf' 2>/dev/null | head -1"
                            local test_file = io.popen(find_cmd)
                            if test_file then
                                local first_file = test_file:read("*line")
                                test_file:close()
                                if first_file and first_file ~= "" then
                                    -- 验证文件路径是否在预期目录内（防止路径遍历攻击）
                                    if first_file:match("^" .. http_config_dir:gsub("%-", "%%-") .. "/") then
                                        has_existing_configs = true
                                    end
                                end
                            end
                        end
                        
                        -- 检查TCP/UDP代理配置文件
                        if not has_existing_configs then
                            local tcp_dir = io.open(tcp_config_dir, "r")
                            if tcp_dir then
                                tcp_dir:close()
                                -- 使用find命令查找配置文件（更安全，避免shell注入）
                                -- 转义路径中的特殊字符，防止命令注入
                                local escaped_dir = tcp_config_dir:gsub("'", "'\\''")
                                local find_cmd = "find '" .. escaped_dir .. "' -maxdepth 1 -name 'proxy_*.conf' 2>/dev/null | head -1"
                                local test_file = io.popen(find_cmd)
                                if test_file then
                                    local first_file = test_file:read("*line")
                                    test_file:close()
                                    if first_file and first_file ~= "" then
                                        -- 验证文件路径是否在预期目录内（防止路径遍历攻击）
                                        if first_file:match("^" .. tcp_config_dir:gsub("%-", "%%-") .. "/") then
                                            has_existing_configs = true
                                        end
                                    end
                                end
                            end
                        end
                        
                        if has_existing_configs then
                            ngx.log(ngx.WARN, "检测到已有配置文件，系统将继续使用已有配置，服务不会中断")
                            ngx.log(ngx.WARN, "请尽快修复数据库连接问题，以便更新配置。数据库连接恢复后，配置会自动更新")
                        else
                            ngx.log(ngx.ERR, "未检测到已有配置文件，代理配置可能不可用")
                            ngx.log(ngx.ERR, "请尽快修复数据库连接问题，以便生成代理配置")
                        end
                    else
                        ngx.log(ngx.WARN, "Failed to generate proxy configs: ", error_msg)
                    end
                    
                    -- 如果是 DNS 解析错误，提供解决建议
                    if error_msg:match("no resolver") or error_msg:match("failed to resolve") then
                        ngx.log(ngx.WARN, "DNS resolution error detected. Please check:")
                        ngx.log(ngx.WARN, "1. MySQL host configuration in lua/config.lua (use IP address instead of domain name if possible)")
                        ngx.log(ngx.WARN, "2. resolver directive in nginx.conf (should be configured in http block)")
                        ngx.log(ngx.WARN, "3. Network connectivity and DNS server availability")
                    end
                end
            end
        else
            ngx.log(ngx.WARN, "nginx_config_generator module not available, skipping proxy config generation")
        end
    end
    
    -- 延迟1秒执行，确保数据库连接已建立
    local ok, err = ngx.timer.at(1, init_proxy_configs, 0)
    if not ok then
        ngx.log(ngx.ERR, "failed to create proxy config initialization timer: ", err)
    else
        ngx.log(ngx.INFO, "Proxy config initialization timer created")
    end
end

return _M

