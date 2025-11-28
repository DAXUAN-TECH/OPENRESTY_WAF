let features = [];
        
        // 使用公共函数 showAlert（已在 common.js 中定义）
        // 如果需要自定义显示位置，可以覆盖 showAlert 函数
        function showAlertCustom(message, type = 'success') {
            const container = document.getElementById('alert-container');
            if (container) {
                const alert = document.createElement('div');
                alert.className = `alert alert-${type}`;
                alert.textContent = message;
                container.innerHTML = '';
                container.appendChild(alert);
                setTimeout(() => {
                    alert.remove();
                }, 3000);
            } else {
                // 如果没有容器，使用全局的 showAlert
                window.showAlert(message, type);
            }
        }
        // 为兼容性，保留 showAlert 作为 showAlertCustom 的别名
        const showAlert = showAlertCustom;
        
        // 加载功能列表
        async function loadFeatures() {
            const container = document.getElementById('features-container');
            // 防御性检查：确保 escapeHtml 函数可用
            const escapeHtmlFn = window.escapeHtml || function(text) {
                if (!text) return '';
                const div = document.createElement('div');
                div.textContent = text;
                return div.innerHTML;
            };
            
            try {
                // 显示加载状态
                container.innerHTML = '<div class="loading">加载中...</div>';
                
                const response = await fetch('/api/features');
                
                // 检查响应状态
                if (!response.ok) {
                    const errorText = await response.text();
                    let errorData;
                    try {
                        errorData = JSON.parse(errorText);
                    } catch (e) {
                        errorData = { error: errorText || `HTTP ${response.status}: ${response.statusText}` };
                    }
                    throw new Error(errorData.error || errorData.message || `HTTP ${response.status}: ${response.statusText}`);
                }
                
                const data = await response.json();
                
                if (data.success) {
                    features = data.features || [];
                    renderFeatures();
                } else {
                    const errorMsg = data.error || data.message || '加载失败';
                    showAlert(errorMsg, 'error');
                    container.innerHTML = '<div class="loading" style="color: #e74c3c;">' + escapeHtmlFn(errorMsg) + '</div>';
                }
            } catch (error) {
                console.error('loadFeatures error:', error);
                showAlert('网络错误: ' + error.message, 'error');
                container.innerHTML = '<div class="loading" style="color: #e74c3c;">网络错误: ' + escapeHtmlFn(error.message) + '</div>';
            }
        }
        
        // 渲染功能列表
        function renderFeatures() {
            const container = document.getElementById('features-container');
            
            if (features.length === 0) {
                container.innerHTML = '<div class="loading">暂无功能</div>';
                return;
            }
            
            container.className = 'features-list';
            container.innerHTML = features.map(feature => `
                <div class="feature-card">
                    <div class="feature-header">
                        <div>
                            <span class="feature-name">${getFeatureName(feature.key)}</span>
                            <span class="status-badge ${feature.enable ? 'status-enabled' : 'status-disabled'}">
                                ${feature.enable ? '已启用' : '已禁用'}
                            </span>
                        </div>
                        <label class="switch">
                            <input type="checkbox" 
                                   ${feature.enable ? 'checked' : ''} 
                                   onchange="toggleFeature('${feature.key}', this.checked)">
                            <span class="slider"></span>
                        </label>
                    </div>
                    <div class="feature-description">${feature.description || ''}</div>
                </div>
            `).join('');
        }
        
        // 获取功能中文名称
        function getFeatureName(key) {
            const names = {
                'rule_management_ui': '规则管理界面',
                'testing': '测试功能',
                'config_validation': '配置验证',
                'config_check_api': '配置检查API'
            };
            return names[key] || key;
        }
        
        // 切换功能开关
        function toggleFeature(key, enabled) {
            const feature = features.find(f => f.key === key);
            if (feature) {
                feature.enable = enabled;
                // 实时更新显示
                renderFeatures();
            }
        }
        
        // 保存所有功能更改
        async function saveAllFeatures() {
            const featuresToUpdate = features.map(f => ({
                key: f.key,
                enable: f.enable
            }));
            
            try {
                const response = await fetch('/api/features/batch', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({ features: featuresToUpdate })
                });
                
                const data = await response.json();
                
                if (data.success) {
                    showAlert('所有功能开关已保存');
                    loadFeatures(); // 重新加载以确保同步
                } else {
                    showAlert(data.error || '保存失败', 'error');
                }
            } catch (error) {
                showAlert('网络错误: ' + error.message, 'error');
            }
        }
        
        // 初始化
        document.addEventListener('DOMContentLoaded', function() {
            loadFeatures();
        });