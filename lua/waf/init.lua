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
    
    -- 初始化规则备份定时器
    if config.rule_backup and config.rule_backup.enable then
        local rule_backup = require "waf.rule_backup"
        local backup_interval = config.rule_backup.backup_interval or 300
        
        local function periodic_backup(premature)
            if premature then
                return
            end
            
            local ok, result = rule_backup.backup_rules()
            if ok then
                ngx.log(ngx.INFO, "Rules backed up: ", result)
            else
                ngx.log(ngx.ERR, "Rule backup failed: ", result)
            end
            
            -- 设置下一次定时器
            local ok, err = ngx.timer.at(backup_interval, periodic_backup)
            if not ok then
                ngx.log(ngx.ERR, "failed to create backup timer: ", err)
            end
        end
        
        -- 启动定时器
        local ok, err = ngx.timer.at(backup_interval, periodic_backup)
        if not ok then
            ngx.log(ngx.ERR, "failed to create initial backup timer: ", err)
        else
            ngx.log(ngx.INFO, "Rule backup timer initialized")
        end
    end
    
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
    -- 重要：只在首次启动时生成配置，reload时不再生成
    local function init_proxy_configs(premature)
        if premature then
            return
        end
        
        -- 检查是否是首次启动（通过检查配置文件是否存在）
        -- 如果配置文件已存在，说明是reload，不需要重新生成
        local path_utils = require "waf.path_utils"
        local project_root = path_utils.get_project_root()
        if not project_root then
            ngx.log(ngx.ERR, "无法获取项目根目录，跳过配置生成检查")
            return
        end
        
        -- 检查是否有已存在的代理配置文件
        -- 注意：generate_all_configs() 会同时生成：
        --   1. upstream 配置文件（http_upstream_*.conf, stream_upstream_*.conf等）
        --   2. server 配置文件（proxy_http_*.conf, proxy_stream_*.conf等）
        --   3. SSL 证书文件（proxy_*.pem, proxy_*.key）
        -- 为了更准确地判断，我们同时检查这些配置文件
        -- 如果任一类型的配置文件存在，说明是reload，不需要重新生成
        
        local http_server_dir = project_root .. "/conf.d/vhost_conf/http_https"
        local tcp_server_dir = project_root .. "/conf.d/vhost_conf/tcp_udp"
        local http_upstream_dir = project_root .. "/conf.d/upstream/http_https"
        local tcp_upstream_dir = project_root .. "/conf.d/upstream/tcp_udp"
        local cert_dir = project_root .. "/conf.d/cert"
        local config_exists = false
        
        -- 检查HTTP/HTTPS server配置文件
        local http_server_dir_fd = io.open(http_server_dir, "r")
        if http_server_dir_fd then
            http_server_dir_fd:close()
            local find_cmd = "find " .. http_server_dir .. " -maxdepth 1 -name 'proxy_*.conf' 2>/dev/null | head -1"
            local find_result = io.popen(find_cmd)
            if find_result then
                local found_file = find_result:read("*line")
                find_result:close()
                if found_file and found_file ~= "" then
                    config_exists = true
                end
            end
        end
        
        -- 如果HTTP/HTTPS server没有，检查HTTP/HTTPS upstream配置文件
        if not config_exists then
            local http_upstream_dir_fd = io.open(http_upstream_dir, "r")
            if http_upstream_dir_fd then
                http_upstream_dir_fd:close()
                local find_cmd = "find " .. http_upstream_dir .. " -maxdepth 1 -name 'http_upstream_*.conf' 2>/dev/null | head -1"
                local find_result = io.popen(find_cmd)
                if find_result then
                    local found_file = find_result:read("*line")
                    find_result:close()
                    if found_file and found_file ~= "" then
                        config_exists = true
                    end
                end
            end
        end
        
        -- 如果HTTP/HTTPS都没有，检查TCP/UDP server配置文件
        if not config_exists then
            local tcp_server_dir_fd = io.open(tcp_server_dir, "r")
            if tcp_server_dir_fd then
                tcp_server_dir_fd:close()
                local find_cmd = "find " .. tcp_server_dir .. " -maxdepth 1 -name 'proxy_*.conf' 2>/dev/null | head -1"
                local find_result = io.popen(find_cmd)
                if find_result then
                    local found_file = find_result:read("*line")
                    find_result:close()
                    if found_file and found_file ~= "" then
                        config_exists = true
                    end
                end
            end
        end
        
        -- 如果TCP/UDP server没有，检查TCP/UDP upstream配置文件
        if not config_exists then
            local tcp_upstream_dir_fd = io.open(tcp_upstream_dir, "r")
            if tcp_upstream_dir_fd then
                tcp_upstream_dir_fd:close()
                local find_cmd = "find " .. tcp_upstream_dir .. " -maxdepth 1 -name '*_upstream_*.conf' 2>/dev/null | head -1"
                local find_result = io.popen(find_cmd)
                if find_result then
                    local found_file = find_result:read("*line")
                    find_result:close()
                    if found_file and found_file ~= "" then
                        config_exists = true
                    end
                end
            end
        end
        
        -- 如果以上都没有，检查SSL证书文件（proxy_*.pem 或 proxy_*.key）
        -- 注意：SSL证书文件是在generate_http_server_config()中生成的，也是generate_all_configs()的一部分
        if not config_exists then
            local cert_dir_fd = io.open(cert_dir, "r")
            if cert_dir_fd then
                cert_dir_fd:close()
                -- 检查是否有代理的SSL证书文件（排除管理端的admin_*.pem和admin_*.key）
                local find_cmd = "find " .. cert_dir .. " -maxdepth 1 -name 'proxy_*.pem' -o -name 'proxy_*.key' 2>/dev/null | head -1"
                local find_result = io.popen(find_cmd)
                if find_result then
                    local found_file = find_result:read("*line")
                    find_result:close()
                    if found_file and found_file ~= "" then
                        config_exists = true
                    end
                end
            end
        end
        
        -- 如果配置文件已存在，说明是reload，不需要重新生成
        if config_exists then
            ngx.log(ngx.INFO, "检测到配置文件已存在，这是reload操作，跳过配置生成")
            return
        end
        
        -- 首次启动，需要生成配置文件
        ngx.log(ngx.INFO, "首次启动检测：配置文件不存在，开始生成配置文件...")
        
        local ok, nginx_config_generator = pcall(require, "waf.nginx_config_generator")
        if ok and nginx_config_generator and nginx_config_generator.generate_all_configs then
            local gen_ok, gen_err = nginx_config_generator.generate_all_configs()
            if gen_ok then
                ngx.log(ngx.INFO, "Proxy configs initialized: ", gen_err or "success")
                
                -- 首次启动生成配置后，测试配置并执行reload，确保配置文件被加载
                local system_api = require "api.system"
                
                -- 测试配置
                local test_ok, test_err = system_api.test_nginx_config_internal()
                if not test_ok then
                    ngx.log(ngx.ERR, "首次启动配置测试失败: ", test_err or "unknown error")
                    ngx.log(ngx.ERR, "配置文件已生成，但测试失败，请手动检查配置")
                    return
                end
                
                ngx.log(ngx.INFO, "首次启动配置测试通过，开始执行reload...")
                
                -- 执行reload（注意：reload时不会再生成配置，因为配置文件已存在）
                local reload_ok, reload_err = system_api.reload_nginx_internal()
                if not reload_ok then
                    ngx.log(ngx.ERR, "首次启动reload失败: ", reload_err or "unknown error")
                    ngx.log(ngx.ERR, "配置文件已生成，但reload失败，请手动执行reload")
                else
                    ngx.log(ngx.INFO, "首次启动reload成功，配置文件已加载")
                end
            else
                -- 记录详细错误信息，但不阻止系统运行
                local error_msg = gen_err or "unknown error"
                ngx.log(ngx.WARN, "Failed to initialize proxy configs: ", error_msg)
                
                -- 如果是 DNS 解析错误，提供解决建议
                if error_msg:match("no resolver") or error_msg:match("failed to resolve") then
                    ngx.log(ngx.WARN, "DNS resolution error detected. Please check:")
                    ngx.log(ngx.WARN, "1. MySQL host configuration in lua/config.lua (use IP address instead of domain name if possible)")
                    ngx.log(ngx.WARN, "2. resolver directive in nginx.conf (should be configured in http block)")
                    ngx.log(ngx.WARN, "3. Network connectivity and DNS server availability")
                end
            end
        else
            ngx.log(ngx.WARN, "nginx_config_generator module not available, skipping proxy config initialization")
        end
    end
    
    -- 延迟1秒执行，确保数据库连接已建立
    local ok, err = ngx.timer.at(1, init_proxy_configs)
    if not ok then
        ngx.log(ngx.ERR, "failed to create proxy config initialization timer: ", err)
    else
        ngx.log(ngx.INFO, "Proxy config initialization timer created")
    end
end

return _M

