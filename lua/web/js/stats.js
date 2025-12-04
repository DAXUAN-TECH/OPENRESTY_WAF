let timeseriesChart = null;
        
        // 设置默认时间范围（最近24小时）
        function setDefaultTimeRange() {
            const now = new Date();
            const yesterday = new Date(now.getTime() - 24 * 60 * 60 * 1000);
            
            document.getElementById('endTime').value = now.toISOString().slice(0, 16);
            document.getElementById('startTime').value = yesterday.toISOString().slice(0, 16);
        }
        
        // 加载统计数据
        async function loadStats() {
            const startTime = document.getElementById('startTime').value;
            const endTime = document.getElementById('endTime').value;
            const interval = document.getElementById('interval').value;
            
            if (!startTime || !endTime) {
                showError('请选择时间范围');
                return;
            }
            
            document.getElementById('loading').style.display = 'block';
            document.getElementById('content').style.display = 'none';
            document.getElementById('error').style.display = 'none';
            
            try {
                // 加载概览统计
                const overviewRes = await fetch(`/api/stats/overview?start_time=${encodeURIComponent(startTime)}&end_time=${encodeURIComponent(endTime)}`);
                
                // 检查响应状态
                if (!overviewRes.ok) {
                    const errorText = await overviewRes.text();
                    let errorData;
                    try {
                        errorData = JSON.parse(errorText);
                    } catch (e) {
                        errorData = { error: errorText || `HTTP ${overviewRes.status}: ${overviewRes.statusText}` };
                    }
                    throw new Error(errorData.error || errorData.message || `HTTP ${overviewRes.status}: ${overviewRes.statusText}`);
                }
                
                const overviewData = await overviewRes.json();
                
                if (!overviewData.success) {
                    throw new Error(overviewData.error || overviewData.message || '查询失败');
                }
                
                // 更新概览卡片
                const totalBlocks = overviewData.data.total_blocks || 0;
                const uniqueIPs = overviewData.data.unique_blocked_ips || 0;
                const manualBlocks = overviewData.data.by_reason.manual || 0;
                const autoBlocks = (overviewData.data.by_reason.auto_frequency || 0) + 
                                 (overviewData.data.by_reason.auto_error || 0) + 
                                 (overviewData.data.by_reason.auto_scan || 0);
                
                document.getElementById('totalBlocks').textContent = totalBlocks;
                document.getElementById('uniqueIPs').textContent = uniqueIPs;
                document.getElementById('manualBlocks').textContent = manualBlocks;
                document.getElementById('autoBlocks').textContent = autoBlocks;
                
                // 如果所有数据都是0，显示提示信息
                if (totalBlocks === 0 && uniqueIPs === 0 && manualBlocks === 0 && autoBlocks === 0) {
                    // 不显示错误，只是记录到控制台
                    console.info('统计报表：在选定时间范围内没有封控数据');
                }
                
                // 加载时间序列数据
                const timeseriesRes = await fetch(`/api/stats/timeseries?start_time=${encodeURIComponent(startTime)}&end_time=${encodeURIComponent(endTime)}&interval=${interval}`);
                if (timeseriesRes.ok) {
                    const timeseriesData = await timeseriesRes.json();
                    if (timeseriesData.success) {
                        updateTimeseriesChart(timeseriesData.data);
                    }
                } else {
                    console.warn('Failed to load timeseries data:', timeseriesRes.status, timeseriesRes.statusText);
                }
                
                // 加载规则统计
                const rulesRes = await fetch(`/api/stats/rules?start_time=${encodeURIComponent(startTime)}&end_time=${encodeURIComponent(endTime)}&limit=10`);
                if (rulesRes.ok) {
                    const rulesData = await rulesRes.json();
                    if (rulesData.success) {
                        updateRulesTable(rulesData.data);
                    }
                } else {
                    console.warn('Failed to load rules stats:', rulesRes.status, rulesRes.statusText);
                }
                
                // 加载IP统计
                const ipsRes = await fetch(`/api/stats/ip?start_time=${encodeURIComponent(startTime)}&end_time=${encodeURIComponent(endTime)}&limit=20`);
                if (ipsRes.ok) {
                    const ipsData = await ipsRes.json();
                    if (ipsData.success) {
                        updateIPsTable(ipsData.data);
                    }
                } else {
                    console.warn('Failed to load IP stats:', ipsRes.status, ipsRes.statusText);
                }
                
                document.getElementById('loading').style.display = 'none';
                document.getElementById('content').style.display = 'block';
            } catch (error) {
                document.getElementById('loading').style.display = 'none';
                document.getElementById('content').style.display = 'none';
                
                // 检查是否是功能被禁用的错误
                if (error.message && (error.message.includes('统计功能已禁用') || error.message.includes('403'))) {
                    showError('统计功能已被禁用，请在系统设置中启用统计报表功能');
                } else {
                showError('加载失败：' + error.message);
                }
            }
        }
        
        // 更新时间序列图表
        function updateTimeseriesChart(data) {
            // 防御性检查：确保 data 是数组
            if (!data) {
                console.warn('updateTimeseriesChart: data is null or undefined');
                // 显示空图表提示
                const ctx = document.getElementById('timeseriesChart').getContext('2d');
                if (timeseriesChart) {
                    timeseriesChart.destroy();
                }
                timeseriesChart = new Chart(ctx, {
                    type: 'line',
                    data: {
                        labels: [],
                        datasets: []
                    },
                    options: {
                        responsive: true,
                        plugins: {
                            title: {
                                display: true,
                                text: '在选定时间范围内没有数据'
                            }
                        }
                    }
                });
                return;
            }
            
            let dataArray = [];
            if (Array.isArray(data)) {
                dataArray = data;
            } else if (typeof data === 'object') {
                // 尝试转换为数组
                const keys = Object.keys(data);
                const numericKeys = keys.filter(k => {
                    const num = parseInt(k);
                    return !isNaN(num) && num.toString() === k && num >= 0;
                });
                
                if (numericKeys.length > 0) {
                    numericKeys.sort((a, b) => parseInt(a) - parseInt(b));
                    dataArray = numericKeys.map(k => data[k]);
                } else {
                    console.warn('updateTimeseriesChart: data is not an array and cannot be converted');
                    return;
                }
            } else {
                console.warn('updateTimeseriesChart: data is not an array or object');
                return;
            }
            
            const ctx = document.getElementById('timeseriesChart').getContext('2d');
            
            if (timeseriesChart) {
                timeseriesChart.destroy();
            }
            
            // 如果没有数据，显示空图表提示
            if (dataArray.length === 0) {
                timeseriesChart = new Chart(ctx, {
                    type: 'line',
                    data: {
                        labels: [],
                        datasets: []
                    },
                    options: {
                        responsive: true,
                        plugins: {
                            title: {
                                display: true,
                                text: '在选定时间范围内没有封控数据'
                            }
                        },
                        scales: {
                            y: {
                                beginAtZero: true
                            }
                        }
                    }
                });
                return;
            }
            
            timeseriesChart = new Chart(ctx, {
                type: 'line',
                data: {
                    labels: dataArray.map(item => item.time),
                    datasets: [{
                        label: '封控次数',
                        data: dataArray.map(item => item.block_count),
                        borderColor: '#0066cc',
                        backgroundColor: 'rgba(0, 102, 204, 0.1)',
                        tension: 0.4
                    }, {
                        label: '被封控IP数',
                        data: dataArray.map(item => item.unique_ips),
                        borderColor: '#cc6600',
                        backgroundColor: 'rgba(204, 102, 0, 0.1)',
                        tension: 0.4
                    }]
                },
                options: {
                    responsive: true,
                    scales: {
                        y: {
                            beginAtZero: true
                        }
                    }
                }
            });
        }
        
        // 更新规则表格
        function updateRulesTable(data) {
            const tbody = document.querySelector('#topRulesTable tbody');
            tbody.innerHTML = '';
            
            // 防御性检查：确保 data 是数组
            if (!data) {
                console.warn('updateRulesTable: data is null or undefined');
                return;
            }
            
            let dataArray = [];
            if (Array.isArray(data)) {
                dataArray = data;
            } else if (typeof data === 'object') {
                // 尝试转换为数组
                const keys = Object.keys(data);
                const numericKeys = keys.filter(k => {
                    const num = parseInt(k);
                    return !isNaN(num) && num.toString() === k && num >= 0;
                });
                
                if (numericKeys.length > 0) {
                    numericKeys.sort((a, b) => parseInt(a) - parseInt(b));
                    dataArray = numericKeys.map(k => data[k]);
                } else {
                    console.warn('updateRulesTable: data is not an array and cannot be converted');
                    return;
                }
            } else {
                console.warn('updateRulesTable: data is not an array or object');
                return;
            }
            
            if (dataArray.length === 0) {
                tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; padding: 20px; color: #999;">在选定时间范围内没有规则命中数据</td></tr>';
                return;
            }
            
            // 过滤掉命中次数为0的规则（可选，如果需要显示所有规则，可以注释掉这行）
            // dataArray = dataArray.filter(row => (row.hit_count || 0) > 0);
            
            // 如果过滤后没有数据，显示提示
            if (dataArray.length === 0) {
                tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; padding: 20px; color: #999;">在选定时间范围内没有规则命中数据</td></tr>';
                return;
            }
            
            dataArray.forEach(row => {
                const tr = document.createElement('tr');
                // 确保数值字段正确显示
                const hitCount = parseInt(row.hit_count) || 0;
                const blockedIPs = parseInt(row.blocked_ips) || 0;
                const lastHitTime = row.last_hit_time || '-';
                
                tr.innerHTML = `
                    <td>${escapeHtml(row.rule_name || '-')}</td>
                    <td>${escapeHtml(row.rule_type || '-')}</td>
                    <td>${hitCount}</td>
                    <td>${blockedIPs}</td>
                    <td>${lastHitTime}</td>
                `;
                tbody.appendChild(tr);
            });
        }
        
        // 更新IP表格
        function updateIPsTable(data) {
            const tbody = document.querySelector('#topIPsTable tbody');
            tbody.innerHTML = '';
            
            // 防御性检查：确保 data 是数组
            if (!data) {
                console.warn('updateIPsTable: data is null or undefined');
                return;
            }
            
            let dataArray = [];
            if (Array.isArray(data)) {
                dataArray = data;
            } else if (typeof data === 'object') {
                // 尝试转换为数组
                const keys = Object.keys(data);
                const numericKeys = keys.filter(k => {
                    const num = parseInt(k);
                    return !isNaN(num) && num.toString() === k && num >= 0;
                });
                
                if (numericKeys.length > 0) {
                    numericKeys.sort((a, b) => parseInt(a) - parseInt(b));
                    dataArray = numericKeys.map(k => data[k]);
                } else {
                    console.warn('updateIPsTable: data is not an array and cannot be converted');
                    return;
                }
            } else {
                console.warn('updateIPsTable: data is not an array or object');
                return;
            }
            
            if (dataArray.length === 0) {
                tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; padding: 20px; color: #999;">在选定时间范围内没有被封控的IP数据</td></tr>';
                return;
            }
            
            dataArray.forEach(row => {
                const tr = document.createElement('tr');
                tr.innerHTML = `
                    <td>${escapeHtml(row.client_ip)}</td>
                    <td>${row.block_count || 0}</td>
                    <td>${row.rule_count || 0}</td>
                    <td>${row.first_block_time || '-'}</td>
                    <td>${row.last_block_time || '-'}</td>
                `;
                tbody.appendChild(tr);
            });
        }
        
        // 使用公共函数 showError 和 escapeHtml（已在 common.js 中定义）
        // 如果需要自定义错误显示位置，可以覆盖 showError 函数
        function showErrorCustom(message) {
            const errorDiv = document.getElementById('error');
            if (errorDiv) {
                errorDiv.textContent = message;
                errorDiv.style.display = 'block';
            } else {
                // 如果没有容器，使用全局的 showError
                window.showError(message);
            }
        }
        // 为兼容性，保留 showError 作为 showErrorCustom 的别名
        const showError = showErrorCustom;
        
        // 页面加载时设置默认时间并加载数据
        window.onload = function() {
            setDefaultTimeRange();
            loadStats();
        };