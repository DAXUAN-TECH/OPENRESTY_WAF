let blockTrendChart = null;
    let refreshInterval = null;
    let previousMetrics = {};
    
    // 加载监控数据
    async function loadMetrics() {
        try {
            // 获取Prometheus指标
            const metricsRes = await fetch('/metrics');
            const metricsText = await metricsRes.text();
            
            // 解析Prometheus格式的指标
            const metrics = parsePrometheusMetrics(metricsText);
            
            // 更新指标卡片
            updateMetrics(metrics);
            
            // 更新图表（从API获取真实数据）
            await updateBlockTrendChart();
            
            // 更新系统信息
            updateSystemInfo(metrics);
            
            // 保存当前指标用于趋势计算
            previousMetrics = metrics;
            
            document.getElementById('loading').style.display = 'none';
            document.getElementById('content').style.display = 'block';
        } catch (error) {
            console.error('加载监控数据失败：', error);
            document.getElementById('loading').textContent = '加载失败，请刷新页面重试';
        }
    }
    
    // 使用公共函数 parsePrometheusMetrics（已在 common.js 中定义）
    
    // 更新指标卡片
    function updateMetrics(metrics) {
        // 数据库健康状态
        const dbHealth = metrics.waf_database_health || 0;
        document.getElementById('dbHealth').textContent = dbHealth === 1 ? '健康' : '异常';
        const dbStatusEl = document.getElementById('dbStatus');
        dbStatusEl.textContent = dbHealth === 1 ? '健康' : '异常';
        dbStatusEl.className = 'status ' + (dbHealth === 1 ? 'healthy' : 'unhealthy');
        
        // 总封控次数
        const totalBlocks = Math.floor(metrics.waf_blocks_total || 0);
        document.getElementById('totalBlocks').textContent = totalBlocks;
        updateTrend('blocksTrend', totalBlocks, previousMetrics.waf_blocks_total || 0);
        
        // 缓存命中率
        const hitRate = (metrics.waf_cache_hit_rate || 0) * 100;
        document.getElementById('cacheHitRate').textContent = hitRate.toFixed(2) + '%';
        const prevHitRate = (previousMetrics.waf_cache_hit_rate || 0) * 100;
        updateTrend('cacheTrend', hitRate, prevHitRate, '%');
        
        // 当前被封控IP数
        const blockedIPs = Math.floor(metrics.waf_blocked_ips || 0);
        document.getElementById('blockedIPs').textContent = blockedIPs;
        updateTrend('ipsTrend', blockedIPs, previousMetrics.waf_blocked_ips || 0);
        
        // 规则匹配耗时
        const duration = (metrics.waf_rule_match_duration_seconds || 0) * 1000;
        document.getElementById('matchDuration').textContent = duration.toFixed(2) + 'ms';
        const prevDuration = (previousMetrics.waf_rule_match_duration_seconds || 0) * 1000;
        updateTrend('durationTrend', duration, prevDuration, 'ms');
        
        // 降级模式
        const fallback = metrics.waf_fallback_enabled || 0;
        document.getElementById('fallbackMode').textContent = fallback === 1 ? '已启用' : '未启用';
        const fallbackStatusEl = document.getElementById('fallbackStatus');
        fallbackStatusEl.textContent = fallback === 1 ? '已启用' : '未启用';
        fallbackStatusEl.className = 'status ' + (fallback === 1 ? 'warning' : 'healthy');
        
        // 自动封控次数
        const autoBlocks = Math.floor(metrics.waf_auto_blocks_total || 0);
        document.getElementById('autoBlocks').textContent = autoBlocks;
        updateTrend('autoBlocksTrend', autoBlocks, previousMetrics.waf_auto_blocks_total || 0);
        
        // 缓存命中次数
        const cacheHits = Math.floor(metrics.waf_cache_hits_total || 0);
        document.getElementById('cacheHits').textContent = cacheHits;
        updateTrend('cacheHitsTrend', cacheHits, previousMetrics.waf_cache_hits_total || 0);
    }
    
    // 更新趋势指示
    function updateTrend(elementId, current, previous, unit = '') {
        const trendEl = document.getElementById(elementId);
        if (!trendEl) return;
        
        if (previous === 0 || previous === undefined) {
            trendEl.textContent = '';
            trendEl.className = 'metric-trend';
            return;
        }
        
        const diff = current - previous;
        const percent = ((diff / previous) * 100).toFixed(1);
        
        if (diff > 0) {
            trendEl.textContent = `↑ +${diff}${unit} (+${percent}%)`;
            trendEl.className = 'metric-trend up';
        } else if (diff < 0) {
            trendEl.textContent = `↓ ${diff}${unit} (${percent}%)`;
            trendEl.className = 'metric-trend down';
        } else {
            trendEl.textContent = `→ 无变化`;
            trendEl.className = 'metric-trend';
        }
    }
    
    // 更新封控趋势图表（从API获取真实数据）
    async function updateBlockTrendChart() {
        const ctx = document.getElementById('blockTrendChart').getContext('2d');
        
        if (blockTrendChart) {
            blockTrendChart.destroy();
        }
        
        try {
            // 计算时间范围（最近1小时）
            const endTime = new Date();
            const startTime = new Date(endTime.getTime() - 60 * 60 * 1000); // 1小时前
            
            // 格式化时间为MySQL格式
            const formatTime = (date) => {
                const year = date.getFullYear();
                const month = String(date.getMonth() + 1).padStart(2, '0');
                const day = String(date.getDate()).padStart(2, '0');
                const hours = String(date.getHours()).padStart(2, '0');
                const minutes = String(date.getMinutes()).padStart(2, '0');
                const seconds = String(date.getSeconds()).padStart(2, '0');
                return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
            };
            
            const startTimeStr = formatTime(startTime);
            const endTimeStr = formatTime(endTime);
            
            // 从API获取时间序列数据（按小时分组，最近1小时）
            const timeseriesRes = await fetch(`/api/stats/timeseries?start_time=${encodeURIComponent(startTimeStr)}&end_time=${encodeURIComponent(endTimeStr)}&interval=hour`);
            
            if (!timeseriesRes.ok) {
                throw new Error('获取时间序列数据失败');
            }
            
            const timeseriesData = await timeseriesRes.json();
            
            let labels = [];
            let data = [];
            
            if (timeseriesData.success && timeseriesData.data && Array.isArray(timeseriesData.data)) {
                // 使用API返回的真实数据
                timeseriesData.data.forEach(item => {
                    // 格式化时间显示
                    const time = new Date(item.time);
                    labels.push(time.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' }));
                    data.push(item.block_count || 0);
                });
            }
            
            // 如果没有数据，生成空的时间点（最近1小时，每5分钟一个点）
            if (labels.length === 0) {
                const now = new Date();
                for (let i = 11; i >= 0; i--) {
                    const time = new Date(now.getTime() - i * 5 * 60 * 1000);
                    labels.push(time.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' }));
                    data.push(0);
                }
            }
            
            blockTrendChart = new Chart(ctx, {
                type: 'line',
                data: {
                    labels: labels,
                    datasets: [{
                        label: '封控次数',
                        data: data,
                        borderColor: '#3498db',
                        backgroundColor: 'rgba(52, 152, 219, 0.1)',
                        tension: 0.4,
                        fill: true
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: true,
                    scales: {
                        y: {
                            beginAtZero: true,
                            ticks: {
                                precision: 0
                            }
                        }
                    },
                    plugins: {
                        legend: {
                            display: true,
                            position: 'top'
                        }
                    }
                }
            });
        } catch (error) {
            console.error('更新图表失败：', error);
            // 如果API调用失败，显示空图表
            const now = new Date();
            const labels = [];
            const data = [];
            for (let i = 11; i >= 0; i--) {
                const time = new Date(now.getTime() - i * 5 * 60 * 1000);
                labels.push(time.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' }));
                data.push(0);
            }
            
            blockTrendChart = new Chart(ctx, {
                type: 'line',
                data: {
                    labels: labels,
                    datasets: [{
                        label: '封控次数',
                        data: data,
                        borderColor: '#3498db',
                        backgroundColor: 'rgba(52, 152, 219, 0.1)',
                        tension: 0.4,
                        fill: true
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: true,
                    scales: {
                        y: {
                            beginAtZero: true,
                            ticks: {
                                precision: 0
                            }
                        }
                    },
                    plugins: {
                        legend: {
                            display: true,
                            position: 'top'
                        }
                    }
                }
            });
        }
    }
    
    // 更新系统信息
    function updateSystemInfo(metrics) {
        document.getElementById('currentTime').textContent = new Date().toLocaleString('zh-CN');
        document.getElementById('dbConnection').textContent = (metrics.waf_database_health || 0) === 1 ? '已连接' : '未连接';
        document.getElementById('cacheStatus').textContent = '正常';
        document.getElementById('autoBlockStatus').textContent = (metrics.waf_auto_blocks_total || 0) > 0 ? '已启用' : '未启用';
        // 系统运行时间（简化处理）
        document.getElementById('uptime').textContent = '运行中';
    }
    
    // 设置自动刷新
    function setupAutoRefresh() {
        const checkbox = document.getElementById('autoRefresh');
        
        checkbox.addEventListener('change', function() {
            if (this.checked) {
                refreshInterval = setInterval(loadMetrics, 30000);
            } else {
                if (refreshInterval) {
                    clearInterval(refreshInterval);
                    refreshInterval = null;
                }
            }
        });
        
        if (checkbox.checked) {
            refreshInterval = setInterval(loadMetrics, 30000);
        }
    }
    
    // 页面加载时初始化
    window.addEventListener('DOMContentLoaded', function() {
        loadMetrics();
        setupAutoRefresh();
    });