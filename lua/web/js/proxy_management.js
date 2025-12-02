let currentPage = 1;
const pageSize = 20;
        
        // 切换标签页
        function switchTab(tab) {
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            document.querySelectorAll('.tab-content').forEach(c => {
                c.classList.remove('active');
                c.style.display = 'none'; // 确保隐藏
            });
            
            if (tab === 'proxies') {
                document.querySelectorAll('.tab')[0].classList.add('active');
                const proxiesTab = document.getElementById('proxies-tab');
                proxiesTab.classList.add('active');
                proxiesTab.style.display = 'block'; // 确保显示
                loadProxies();
            } else if (tab === 'create') {
                document.querySelectorAll('.tab')[1].classList.add('active');
                const createTab = document.getElementById('create-tab');
                createTab.classList.add('active');
                createTab.style.display = 'block'; // 确保显示
            }
        }
        
        // 应用筛选
        function applyFilters() {
            loadProxies(1); // 重置到第一页并应用筛选
        }
        
        // 重置筛选
        function resetFilters() {
            document.getElementById('filter-type').value = '';
            document.getElementById('filter-status').value = '';
            loadProxies(1); // 重置到第一页并重新加载
        }
        
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
        
        // 切换代理类型相关字段
        function toggleProxyFields() {
            const proxyType = document.getElementById('create-proxy-type').value;
            const httpFields = document.getElementById('http-fields');
            const tcpUdpFields = document.getElementById('tcp-udp-fields');
            const createListenPort = document.getElementById('create-listen-port');
            const createTcpUdpListenPort = document.getElementById('create-tcp-udp-listen-port');
            
            if (proxyType === 'http') {
                httpFields.style.display = 'flex';
                tcpUdpFields.style.display = 'none';
                // 显示路径匹配输入框
                document.querySelectorAll('#location-path-input-wrapper, #location-backend-path-input-wrapper').forEach(wrapper => {
                    wrapper.style.display = 'flex';
                });
                // 显示后端路径输入框
                document.querySelectorAll('#backend-path-input-wrapper').forEach(wrapper => {
                    wrapper.style.display = 'flex';
                });
                // 显示后端服务器配置区域
                const upstreamFields = document.getElementById('upstream-fields');
                if (upstreamFields) {
                    upstreamFields.style.display = 'block';
                }
                // 为显示的字段添加required属性
                createListenPort.setAttribute('required', 'required');
                // 为隐藏的字段移除required属性
                createTcpUdpListenPort.removeAttribute('required');
                // 同步监听端口和监听地址的值
                document.getElementById('create-tcp-udp-listen-port').value = document.getElementById('create-listen-port').value;
                document.getElementById('create-tcp-udp-listen-address').value = document.getElementById('create-listen-address').value;
            } else if (proxyType === 'tcp' || proxyType === 'udp') {
                httpFields.style.display = 'none';
                tcpUdpFields.style.display = 'flex';
                // 隐藏路径匹配输入框
                document.querySelectorAll('#location-path-input-wrapper, #location-backend-path-input-wrapper').forEach(wrapper => {
                    wrapper.style.display = 'none';
                });
                // 隐藏后端路径输入框
                document.querySelectorAll('#backend-path-input-wrapper').forEach(wrapper => {
                    wrapper.style.display = 'none';
                });
                // 显示后端服务器配置区域（TCP/UDP也需要）
                const upstreamFields = document.getElementById('upstream-fields');
                if (upstreamFields) {
                    upstreamFields.style.display = 'block';
                }
                // 为隐藏的字段移除required属性
                createListenPort.removeAttribute('required');
                // 为显示的字段添加required属性
                createTcpUdpListenPort.setAttribute('required', 'required');
                // 同步监听端口和监听地址的值
                document.getElementById('create-listen-port').value = document.getElementById('create-tcp-udp-listen-port').value;
                document.getElementById('create-listen-address').value = document.getElementById('create-tcp-udp-listen-address').value;
            } else {
                httpFields.style.display = 'none';
                tcpUdpFields.style.display = 'none';
                // 当没有选择代理类型时，移除所有required属性
                createListenPort.removeAttribute('required');
                createTcpUdpListenPort.removeAttribute('required');
            }
        }
        
        // 切换后端类型相关字段
        
        // 添加后端服务器配置项
        function addBackend() {
            const list = document.getElementById('config-items-list');
            if (!list) return;
            
            const proxyType = document.getElementById('create-proxy-type').value;
            const item = document.createElement('div');
            item.className = 'config-item';
            
            let locationPathWrapper = '';
            if (proxyType === 'http') {
                locationPathWrapper = `
                    <div class="input-with-add">
                        <input type="text" placeholder="匹配路径：/PATH" class="location-path-input" title="匹配路径：/PATH">
                        <button type="button" class="btn-add" onclick="addLocationPath()" title="添加路径匹配">+</button>
                    </div>
                    <div class="input-with-add">
                        <input type="text" placeholder="目标路径：/PATH（可选）" class="location-backend-path-input" title="目标路径：/PATH（可选）">
                        <button type="button" class="btn-add" onclick="addLocationPath()" title="添加路径匹配">+</button>
                    </div>
                `;
            }
            
            item.innerHTML = `
                <div class="config-item-row">
                    ${locationPathWrapper}
                    <div class="input-with-add">
                        <input type="text" placeholder="IP地址" class="backend-address">
                        <button type="button" class="btn-add" onclick="addBackend()" title="添加后端服务器">+</button>
                    </div>
                    <div class="input-with-add">
                        <input type="number" placeholder="端口" class="backend-port" min="1" max="65535">
                        <button type="button" class="btn-add" onclick="addBackend()" title="添加后端服务器">+</button>
                    </div>
                    <div class="input-with-add" style="display: ${proxyType === 'http' ? 'flex' : 'none'};">
                        <input type="text" placeholder="目标路径：/PATH" class="backend-path" title="目标路径：/PATH">
                        <button type="button" class="btn-add" onclick="addBackend()" title="添加后端服务器">+</button>
                    </div>
                    <div class="input-with-add">
                        <input type="number" placeholder="权重" class="backend-weight" value="1" min="1">
                        <button type="button" class="btn-add" onclick="addBackend()" title="添加后端服务器">+</button>
                    </div>
                    <button type="button" class="btn btn-danger btn-sm" onclick="removeConfigItem(this)">删除</button>
                </div>
            `;
            list.appendChild(item);
        }
        
        // 删除后端服务器（保留用于向后兼容）
        function removeBackend(button) {
            removeConfigItem(button);
        }
        
        function addEditBackend() {
            const list = document.getElementById('edit-backends-list');
            // 获取原始代理类型值（从显示值反向转换）
            const displayValue = document.getElementById('edit-proxy-type').value;
            const proxyType = currentEditingProxy ? currentEditingProxy.proxy_type : getProxyTypeFromName(displayValue);
            const item = document.createElement('div');
            item.className = 'backend-item';
            
            // HTTP/HTTPS代理显示路径匹配字段（在IP地址前）和代理路径字段，TCP/UDP代理不显示
            const locationPathField = proxyType === 'http' 
                ? '<input type="text" placeholder="匹配路径：/PATH" class="backend-location-path" title="匹配路径：/PATH" >'
                : '<input type="text" placeholder="匹配路径：/PATH" class="backend-location-path" title="匹配路径：/PATH" style="display: none;">';
            const backendPathField = proxyType === 'http' 
                ? '<input type="text" placeholder="目标路径：/PATH" class="backend-path" title="目标路径：/PATH">'
                : '<input type="text" placeholder="目标路径：/PATH" class="backend-path" title="目标路径：/PATH" style="display: none;">';
            
            item.innerHTML = `
                ${locationPathField}
                <input type="text" placeholder="IP地址" class="backend-address">
                <input type="number" placeholder="端口" class="backend-port" min="1" max="65535">
                ${backendPathField}
                <input type="number" placeholder="权重" class="backend-weight" value="1" min="1">
                <button type="button" class="btn btn-danger" onclick="removeBackend(this)">删除</button>
            `;
            list.appendChild(item);
            
            // 如果是HTTP代理，添加路径输入框的事件监听
            if (proxyType === 'http') {
                const locationPathInput = item.querySelector('.backend-location-path');
                const backendPathInput = item.querySelector('.backend-path');
                // 路径匹配字段：同步所有后端服务器的路径匹配值
                if (locationPathInput) {
                    locationPathInput.addEventListener('input', function() {
                        syncEditLocationPaths();
                    });
                }
                // 代理路径字段：检查一致性
                if (backendPathInput) {
                    backendPathInput.addEventListener('input', checkEditBackendPaths);
                }
            }
        }
        
        // 删除后端服务器
        function removeBackend(btn) {
            btn.parentElement.remove();
            // 删除后重新检查路径一致性（如果列表存在）
            try {
                const createList = document.getElementById('backends-list');
                if (createList) {
                    checkBackendPaths();
                }
                const editList = document.getElementById('edit-backends-list');
                if (editList) {
                    checkEditBackendPaths();
                }
            } catch (e) {
                // 忽略错误，避免影响其他功能
                console.debug('checkBackendPaths error:', e);
            }
        }
        
        // 添加路径匹配配置项
        function addLocationPath() {
            const list = document.getElementById('config-items-list');
            if (!list) return;
            
            const proxyType = document.getElementById('create-proxy-type').value;
            const item = document.createElement('div');
            item.className = 'config-item';
            
            let locationPathWrapper = '';
            if (proxyType === 'http') {
                locationPathWrapper = `
                    <div class="input-with-add">
                        <input type="text" placeholder="匹配路径：/PATH" class="location-path-input" title="匹配路径：/PATH">
                        <button type="button" class="btn-add" onclick="addLocationPath()" title="添加路径匹配">+</button>
                    </div>
                    <div class="input-with-add">
                        <input type="text" placeholder="目标路径：/PATH（可选）" class="location-backend-path-input" title="目标路径：/PATH（可选）">
                        <button type="button" class="btn-add" onclick="addLocationPath()" title="添加路径匹配">+</button>
                    </div>
                `;
            }
            
            item.innerHTML = `
                <div class="config-item-row">
                    ${locationPathWrapper}
                    <div class="input-with-add">
                        <input type="text" placeholder="IP地址" class="backend-address">
                        <button type="button" class="btn-add" onclick="addBackend()" title="添加后端服务器">+</button>
                    </div>
                    <div class="input-with-add">
                        <input type="number" placeholder="端口" class="backend-port" min="1" max="65535">
                        <button type="button" class="btn-add" onclick="addBackend()" title="添加后端服务器">+</button>
                    </div>
                    <div class="input-with-add" style="display: ${proxyType === 'http' ? 'flex' : 'none'};">
                        <input type="text" placeholder="目标路径：/PATH" class="backend-path" title="目标路径：/PATH">
                        <button type="button" class="btn-add" onclick="addBackend()" title="添加后端服务器">+</button>
                    </div>
                    <div class="input-with-add">
                        <input type="number" placeholder="权重" class="backend-weight" value="1" min="1">
                        <button type="button" class="btn-add" onclick="addBackend()" title="添加后端服务器">+</button>
                    </div>
                    <button type="button" class="btn btn-danger btn-sm" onclick="removeConfigItem(this)">删除</button>
                </div>
            `;
            list.appendChild(item);
        }
        
        // 删除配置项
        function removeConfigItem(button) {
            const item = button.closest('.config-item');
            if (item) {
                const list = document.getElementById('config-items-list');
                if (list && list.children.length > 1) {
                    item.remove();
                } else {
                    // 至少保留一个
                    alert('至少需要保留一个配置项');
                }
            }
        }
        
        // 删除路径匹配（保留用于向后兼容）
        function removeLocationPath(button) {
            removeConfigItem(button);
        }
        
        // 添加编辑路径匹配
        function addEditLocationPath() {
            const list = document.getElementById('edit-location-paths-list');
            if (!list) return;
            
            const item = document.createElement('div');
            item.className = 'location-path-item';
            item.innerHTML = `
                <input type="text" placeholder="匹配路径：/PATH" class="location-path-input" title="匹配路径：/PATH">
                <input type="text" placeholder="目标路径：/PATH（可选）" class="location-backend-path-input" title="目标路径：/PATH（可选）">
                <button type="button" class="btn btn-danger" onclick="removeEditLocationPath(this)">删除</button>
            `;
            list.appendChild(item);
        }
        
        // 删除编辑路径匹配
        function removeEditLocationPath(button) {
            const item = button.closest('.location-path-item');
            if (item) {
                const list = document.getElementById('edit-location-paths-list');
                if (list && list.children.length > 1) {
                    item.remove();
                } else {
                    // 至少保留一个
                    alert('至少需要保留一个路径匹配');
                }
            }
        }
        
        // 同步创建代理时所有后端服务器的路径匹配值（使用第一个的值）
        function syncLocationPaths() {
            try {
                const list = document.getElementById('backends-list');
                if (!list) return;
                
                const proxyType = document.getElementById('create-proxy-type');
                if (!proxyType || proxyType.value !== 'http') return;
                
                const locationPathInputs = list.querySelectorAll('.backend-location-path');
                if (locationPathInputs.length === 0) return;
                
                // 获取第一个路径匹配值（如果为空，不设置值，让placeholder显示）
                const firstInput = locationPathInputs[0];
                const firstValue = firstInput ? firstInput.value.trim() : '';
                
                // 只有当第一个输入框有实际值时才同步，否则清空所有输入框让placeholder显示
                locationPathInputs.forEach(input => {
                    if (input.style.display !== 'none') {
                        if (firstValue) {
                            input.value = firstValue;
                        } else {
                            input.value = '';
                        }
                    }
                });
            } catch (e) {
                console.debug('syncLocationPaths error:', e);
            }
        }
        
        // 同步编辑代理时所有后端服务器的路径匹配值（使用第一个的值）
        function syncEditLocationPaths() {
            try {
                const list = document.getElementById('edit-backends-list');
                if (!list) return;
                
                const displayValue = document.getElementById('edit-proxy-type').value;
                const proxyType = currentEditingProxy ? currentEditingProxy.proxy_type : getProxyTypeFromName(displayValue);
                if (proxyType !== 'http') return;
                
                const locationPathInputs = list.querySelectorAll('.backend-location-path');
                if (locationPathInputs.length === 0) return;
                
                // 获取第一个路径匹配值（如果为空，不设置值，让placeholder显示）
                const firstInput = locationPathInputs[0];
                const firstValue = firstInput ? firstInput.value.trim() : '';
                
                // 只有当第一个输入框有实际值时才同步，否则清空所有输入框让placeholder显示
                locationPathInputs.forEach(input => {
                    if (input.style.display !== 'none') {
                        if (firstValue) {
                            input.value = firstValue;
                        } else {
                            input.value = '';
                        }
                    }
                });
            } catch (e) {
                console.debug('syncEditLocationPaths error:', e);
            }
        }
        
        // 检查创建代理时后端服务器路径是否一致
        function checkBackendPaths() {
            try {
                const list = document.getElementById('backends-list');
                if (!list) return;
                
                const proxyType = document.getElementById('create-proxy-type');
                if (!proxyType || proxyType.value !== 'http') return;
                
                const pathInputs = list.querySelectorAll('.backend-path');
                if (pathInputs.length === 0) return;
                
                // 收集所有路径值（去除空白）
                const paths = [];
                pathInputs.forEach(input => {
                    if (input.style.display !== 'none') {
                        const path = input.value.trim();
                        paths.push(path);
                    }
                });
                
                // 检查路径是否一致
                const firstPath = paths[0];
                const allSame = paths.every(path => path === firstPath);
                
                // 移除之前所有的错误提示div（只移除div元素，不包含input元素）
                const existingErrors = list.querySelectorAll('.backend-path-error');
                existingErrors.forEach(el => {
                    if (el.tagName === 'DIV') {
                        el.remove();
                    }
                });
                
                // 更新所有路径输入框的样式
                pathInputs.forEach(input => {
                    if (input.style.display !== 'none') {
                        if (!allSame && paths.length > 1 && paths.some(p => p !== '')) {
                            input.classList.add('backend-path-error');
                        } else {
                            input.classList.remove('backend-path-error');
                        }
                    }
                });
                
                // 如果路径不一致，显示错误提示（只显示一条）
                if (!allSame && paths.length > 1 && paths.some(p => p !== '')) {
                    // 再次检查是否已有错误提示div，避免重复添加
                    const hasErrorDiv = Array.from(list.querySelectorAll('.backend-path-error')).some(el => el.tagName === 'DIV');
                    if (!hasErrorDiv) {
                        const errorDiv = document.createElement('div');
                        errorDiv.className = 'backend-path-error';
                        errorDiv.style.color = 'red';
                        errorDiv.style.fontSize = '12px';
                        errorDiv.style.marginTop = '5px';
                        errorDiv.textContent = '请保持所有服务器被代理路径一致';
                        list.appendChild(errorDiv);
                    }
                }
            } catch (e) {
                // 忽略错误，避免影响其他功能
                console.debug('checkBackendPaths error:', e);
            }
        }
        
        // 检查编辑代理时后端服务器路径是否一致
        function checkEditBackendPaths() {
            try {
                const list = document.getElementById('edit-backends-list');
                if (!list) return;
                
                // 获取原始代理类型值（从显示值反向转换）
                const proxyTypeEl = document.getElementById('edit-proxy-type');
                if (!proxyTypeEl) return;
                const displayValue = proxyTypeEl.value;
                const proxyType = currentEditingProxy ? currentEditingProxy.proxy_type : getProxyTypeFromName(displayValue);
                if (proxyType !== 'http') return;
                
                const pathInputs = list.querySelectorAll('.backend-path');
                if (pathInputs.length === 0) return;
                
                // 收集所有路径值（去除空白）
                const paths = [];
                pathInputs.forEach(input => {
                    if (input.style.display !== 'none') {
                        const path = input.value.trim();
                        paths.push(path);
                    }
                });
                
                // 检查路径是否一致
                const firstPath = paths[0];
                const allSame = paths.every(path => path === firstPath);
                
                // 移除之前所有的错误提示div（只移除div元素，不包含input元素）
                const existingErrors = list.querySelectorAll('.backend-path-error');
                existingErrors.forEach(el => {
                    if (el.tagName === 'DIV') {
                        el.remove();
                    }
                });
                
                // 更新所有路径输入框的样式
                pathInputs.forEach(input => {
                    if (input.style.display !== 'none') {
                        if (!allSame && paths.length > 1 && paths.some(p => p !== '')) {
                            input.classList.add('backend-path-error');
                        } else {
                            input.classList.remove('backend-path-error');
                        }
                    }
                });
                
                // 如果路径不一致，显示错误提示（只显示一条）
                if (!allSame && paths.length > 1 && paths.some(p => p !== '')) {
                    // 再次检查是否已有错误提示div，避免重复添加
                    const hasErrorDiv = Array.from(list.querySelectorAll('.backend-path-error')).some(el => el.tagName === 'DIV');
                    if (!hasErrorDiv) {
                        const errorDiv = document.createElement('div');
                        errorDiv.className = 'backend-path-error';
                        errorDiv.style.color = 'red';
                        errorDiv.style.fontSize = '12px';
                        errorDiv.style.marginTop = '5px';
                        errorDiv.textContent = '请保持所有服务器被代理路径一致';
                        list.appendChild(errorDiv);
                    }
                }
            } catch (e) {
                // 忽略错误，避免影响其他功能
                console.debug('checkEditBackendPaths error:', e);
            }
        }
        
        // 加载代理列表
        async function loadProxies(page = 1) {
            try {
                currentPage = page;
                const filterTypeEl = document.getElementById('filter-type');
                const filterStatusEl = document.getElementById('filter-status');
                const proxyType = filterTypeEl ? filterTypeEl.value : '';
                const status = filterStatusEl ? filterStatusEl.value : '';
                
                let url = `/api/proxy?page=${page}&page_size=${pageSize}`;
                if (proxyType) url += `&proxy_type=${proxyType}`;
                if (status) url += `&status=${status}`;
                
                const tbody = document.getElementById('proxies-tbody');
                if (!tbody) {
                    console.error('proxies-tbody element not found');
                    return;
                }
                
                // 防御性检查：确保 escapeHtml 函数可用
                const escapeHtmlFn = window.escapeHtml || function(text) {
                    if (!text) return '';
                    const div = document.createElement('div');
                    div.textContent = text;
                    return div.innerHTML;
                };
                
                // 显示加载状态
                tbody.innerHTML = '<tr><td colspan="11" style="text-align: center; padding: 20px;">加载中...</td></tr>';
                
                const response = await fetch(url);
                
                // 检查响应状态
                if (!response.ok) {
                    // 如果是 401 错误，自动刷新页面
                    if (response.status === 401) {
                        window.location.reload();
                        return; // 不继续执行
                    }
                    
                    const errorText = await response.text();
                    let errorData;
                    try {
                        errorData = JSON.parse(errorText);
                        // 检查是否是 Unauthorized 错误
                        if (errorData && (
                            errorData.error === 'Unauthorized' || 
                            errorData.message === '请先登录' ||
                            (typeof errorData.error === 'string' && errorData.error.toLowerCase().includes('unauthorized')) ||
                            (typeof errorData.message === 'string' && errorData.message.includes('请先登录'))
                        )) {
                            // 自动刷新页面，不显示错误信息
                            window.location.reload();
                            return; // 不继续执行
                        }
                    } catch (e) {
                        errorData = { error: errorText || `HTTP ${response.status}: ${response.statusText}` };
                    }
                    throw new Error(errorData.error || errorData.message || `HTTP ${response.status}: ${response.statusText}`);
                }
                
                const data = await response.json();
                
                if (data.success) {
                    // 确保 data.data 存在
                    if (!data.data) {
                        console.error('API response missing data field:', data);
                        showAlert('响应数据格式错误：缺少 data 字段', 'error');
                        tbody.innerHTML = '<tr><td colspan="11" style="text-align: center; padding: 20px; color: #e74c3c;">响应数据格式错误</td></tr>';
                        return;
                    }
                    
                    // 获取 proxies 数据
                    let proxies = data.data.proxies;
                    console.log('=== Proxies Data Debug ===');
                    console.log('Received proxies type:', typeof proxies);
                    console.log('Is Array:', Array.isArray(proxies));
                    console.log('Proxies value:', proxies);
                    console.log('========================');
                    
                    // 处理各种可能的格式
                    let proxiesArray = [];
                    
                    if (proxies === undefined || proxies === null) {
                        proxiesArray = [];
                    } else if (Array.isArray(proxies)) {
                        // 已经是数组，直接使用
                        proxiesArray = proxies;
                    } else if (typeof proxies === 'object') {
                        // 是对象，尝试转换
                        const keys = Object.keys(proxies);
                        console.log('Object keys:', keys);
                        
                        if (keys.length === 0) {
                            // 空对象，转换为空数组
                            proxiesArray = [];
                        } else {
                            // 检查是否是数字键（可能是序列化的数组对象）
                            const numericKeys = keys.filter(k => {
                                const num = parseInt(k);
                                return !isNaN(num) && num.toString() === k && num >= 0;
                            });
                            
                            if (numericKeys.length > 0) {
                                // 有数字键，按数字排序后转换为数组
                                numericKeys.sort((a, b) => parseInt(a) - parseInt(b));
                                proxiesArray = numericKeys.map(k => proxies[k]);
                                console.log('Converted object with numeric keys to array:', proxiesArray);
                            } else {
                                // 非数字键，可能是单个对象，包装成数组
                                proxiesArray = [proxies];
                                console.log('Wrapped single object in array:', proxiesArray);
                            }
                        }
                    } else {
                        // 既不是数组也不是对象
                        console.error('Proxies is neither array nor object, type:', typeof proxies);
                        showAlert('响应数据格式错误：proxies 类型不正确 (' + typeof proxies + ')', 'error');
                        tbody.innerHTML = '<tr><td colspan="11" style="text-align: center; padding: 20px; color: #e74c3c;">数据格式错误</td></tr>';
                        return;
                    }
                    
                    // 验证转换后的数组
                    if (!Array.isArray(proxiesArray)) {
                        console.error('Failed to convert proxies to array, final type:', typeof proxiesArray);
                        showAlert('响应数据格式错误：无法将 proxies 转换为数组', 'error');
                        tbody.innerHTML = '<tr><td colspan="11" style="text-align: center; padding: 20px; color: #e74c3c;">数据格式错误</td></tr>';
                        return;
                    }
                    
                    console.log('Final proxies array length:', proxiesArray.length);
                    
                    // 使用转换后的数组
                    renderProxiesTable(proxiesArray);
                    if (data.data) {
                        renderPagination(data.data, 'pagination', loadProxies);
                    }
                } else {
                    const errorMsg = data.error || data.message || '加载失败';
                    showAlert(errorMsg, 'error');
                    tbody.innerHTML = '<tr><td colspan="11" style="text-align: center; padding: 20px; color: #e74c3c;">' + escapeHtmlFn(errorMsg) + '</td></tr>';
                }
            } catch (error) {
                console.error('loadProxies error:', error);
                const tbody = document.getElementById('proxies-tbody');
                if (tbody) {
                    const escapeHtmlFn = window.escapeHtml || function(text) {
                        if (!text) return '';
                        const div = document.createElement('div');
                        div.textContent = text;
                        return div.innerHTML;
                    };
                    showAlert('网络错误: ' + error.message, 'error');
                    tbody.innerHTML = '<tr><td colspan="11" style="text-align: center; padding: 20px; color: #e74c3c;">加载失败: ' + escapeHtmlFn(error.message) + '</td></tr>';
                }
            }
        }
        
        // 渲染代理表格
        function renderProxiesTable(proxies) {
            const tbody = document.getElementById('proxies-tbody');
            if (proxies.length === 0) {
                tbody.innerHTML = '<tr><td colspan="11" style="text-align: center; padding: 20px;">暂无数据</td></tr>';
                return;
            }
            
            tbody.innerHTML = proxies.map(proxy => {
                // 格式化后端地址显示
                let backendDisplay = '-';
                if (proxy.backends && proxy.backends.length > 0) {
                    const backendList = proxy.backends.map(backend => {
                        let addr = backend.backend_address;
                        if (backend.backend_port) {
                            addr += ':' + backend.backend_port;
                        }
                        if (backend.backend_path && proxy.proxy_type === 'http') {
                            addr += backend.backend_path;
                        }
                        if (backend.weight && backend.weight !== 1) {
                            addr += ` (权重:${backend.weight})`;
                        }
                        return addr;
                    });
                    // 使用 <br> 标签分隔，每个后端地址显示在单独一行
                    backendDisplay = backendList.join('<br>');
                }
                
                return `
                <tr>
                    <td>${proxy.id}</td>
                    <td>${proxy.proxy_name}</td>
                    <td>${getProxyTypeName(proxy.proxy_type)}</td>
                    <td>${proxy.listen_address}:${proxy.listen_port}</td>
                    <td>${proxy.server_name || '-'}</td>
                    <td>${backendDisplay}</td>
                    <td>${proxy.rule_name || '-'}</td>
                    <td>${getRuleTypeName(proxy.rule_type) || '-'}</td>
                    <td>${getStatusBadge(proxy.status)}</td>
                    <td>${formatDateTime(proxy.created_at)}</td>
                    <td>
                        <div class="action-buttons">
                            <button class="btn btn-info" onclick="editProxy(${proxy.id})">编辑</button>
                            ${proxy.status == 1 ? 
                                `<button class="btn btn-warning" onclick="disableProxy(${proxy.id})">禁用</button>` :
                                `<button class="btn btn-primary" onclick="enableProxy(${proxy.id})">启用</button>`
                            }
                            <button class="btn btn-danger" onclick="deleteProxy(${proxy.id})">删除</button>
                        </div>
                    </td>
                </tr>
            `;
            }).join('');
        }
        
        // 创建代理
        async function createProxy(event) {
            event.preventDefault();
            
            // 获取已选择的规则ID列表
            const ipRuleIds = [];
            const rulesList = document.getElementById('rules-list');
            if (rulesList) {
                const ruleItems = rulesList.querySelectorAll('.rule-item');
                ruleItems.forEach(item => {
                    const typeSelect = item.querySelector('.rule-type');
                    const ruleIdSelect = item.querySelector('.rule-id');
                    if (typeSelect && typeSelect.value && ruleIdSelect && ruleIdSelect.value) {
                        ipRuleIds.push(parseInt(ruleIdSelect.value));
                    }
                });
            }
            
            const proxyType = document.getElementById('create-proxy-type').value;
            
            // 根据代理类型获取监听端口和监听地址
            let listenPort, listenAddress;
            if (proxyType === 'http') {
                listenPort = parseInt(document.getElementById('create-listen-port').value);
                listenAddress = document.getElementById('create-listen-address').value || '0.0.0.0';
            } else if (proxyType === 'tcp' || proxyType === 'udp') {
                listenPort = parseInt(document.getElementById('create-tcp-udp-listen-port').value);
                listenAddress = document.getElementById('create-tcp-udp-listen-address').value || '0.0.0.0';
            } else {
                // 默认值（不应该到达这里，因为代理类型是必选的）
                listenPort = parseInt(document.getElementById('create-listen-port').value) || parseInt(document.getElementById('create-tcp-udp-listen-port').value);
                listenAddress = document.getElementById('create-listen-address').value || document.getElementById('create-tcp-udp-listen-address').value || '0.0.0.0';
            }
            
            const proxyData = {
                proxy_name: document.getElementById('create-proxy-name').value,
                proxy_type: proxyType,
                listen_port: listenPort,
                listen_address: listenAddress,
                backend_type: 'upstream',
                description: document.getElementById('create-description').value || null,
                proxy_connect_timeout: parseInt(document.getElementById('create-proxy-connect-timeout').value) || 60,
                proxy_send_timeout: parseInt(document.getElementById('create-proxy-send-timeout').value) || 60,
                proxy_read_timeout: parseInt(document.getElementById('create-proxy-read-timeout').value) || 60,
                ip_rule_ids: ipRuleIds.length > 0 ? ipRuleIds : null
            };
            
            if (proxyData.proxy_type === 'http') {
                const serverName = document.getElementById('create-server-name').value.trim();
                proxyData.server_name = serverName || null;
                
                // 从融合的配置列表中收集路径匹配和后端服务器数据
                const configItemsList = document.getElementById('config-items-list');
                const locationPaths = [];
                const backends = [];
                
                if (configItemsList) {
                    const configItems = configItemsList.querySelectorAll('.config-item');
                    configItems.forEach(item => {
                        // 收集路径匹配
                        const locationPathInput = item.querySelector('.location-path-input');
                        const locationBackendPathInput = item.querySelector('.location-backend-path-input');
                        if (locationPathInput && locationPathInput.value.trim()) {
                            const locationPath = locationPathInput.value.trim();
                            const backendPath = locationBackendPathInput ? locationBackendPathInput.value.trim() : '';
                            locationPaths.push({
                                location_path: locationPath,
                                backend_path: backendPath || null
                            });
                        }
                        
                        // 收集后端服务器
                        const address = item.querySelector('.backend-address')?.value;
                        const port = item.querySelector('.backend-port')?.value;
                        const weight = item.querySelector('.backend-weight')?.value || '1';
                        const backendPathField = item.querySelector('.backend-path');
                        const backendPath = backendPathField ? backendPathField.value.trim() : '';
                        
                        if (address && port) {
                            const backend = {
                                backend_address: address,
                                backend_port: parseInt(port),
                                weight: parseInt(weight) || 1
                            };
                            // HTTP/HTTPS代理时，如果有路径，添加到后端配置中
                            if (proxyData.proxy_type === 'http' && backendPath) {
                                backend.backend_path = backendPath;
                            }
                            backends.push(backend);
                        }
                    });
                }
                
                // 如果location_paths有值，使用它；否则使用location_path（向后兼容）
                if (locationPaths.length > 0) {
                    proxyData.location_paths = locationPaths;
                    // 为了向后兼容，也设置location_path为第一个值
                    proxyData.location_path = locationPaths[0].location_path;
                } else {
                    // 向后兼容：如果没有location_paths，使用location_path
                    proxyData.location_path = '/';
                    proxyData.location_paths = null;
                }
                
                proxyData.backends = backends;
            } else if (proxyData.proxy_type === 'tcp' || proxyData.proxy_type === 'udp') {
                // TCP/UDP 代理不支持监听域名，设置为 null
                proxyData.server_name = null;
                
                // 从融合的配置列表中收集后端服务器数据
                const configItemsList = document.getElementById('config-items-list');
                const backends = [];
                
                if (configItemsList) {
                    const configItems = configItemsList.querySelectorAll('.config-item');
                    configItems.forEach(item => {
                        const address = item.querySelector('.backend-address')?.value;
                        const port = item.querySelector('.backend-port')?.value;
                        const weight = item.querySelector('.backend-weight')?.value || '1';
                        
                        if (address && port) {
                            backends.push({
                                backend_address: address,
                                backend_port: parseInt(port),
                                weight: parseInt(weight) || 1
                            });
                        }
                    });
                }
                
                proxyData.backends = backends;
            }
            proxyData.load_balance = document.getElementById('create-load-balance').value;
            
            try {
                const response = await fetch('/api/proxy', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify(proxyData)
                });
                
                const data = await response.json();
                
                if (data.success) {
                    showAlert('代理配置创建成功');
                    // 关闭创建代理弹出框
                    closeCreateProxyModal();
                    // 重置表单
                    resetCreateForm();
                    // 刷新代理列表
                    loadProxies();
                } else {
                    showAlert(data.error || '创建失败', 'error');
                }
            } catch (error) {
                showAlert('网络错误: ' + error.message, 'error');
            }
        }
        
        // 编辑代理
        let currentEditingProxy = null; // 保存当前正在编辑的代理数据
        async function editProxy(id) {
            try {
                const response = await fetch(`/api/proxy/${id}`);
                const data = await response.json();
                
                if (data.success) {
                    const proxy = data.proxy;
                    currentEditingProxy = proxy; // 保存代理数据
                    document.getElementById('edit-id').value = proxy.id;
                    document.getElementById('edit-proxy-name').value = proxy.proxy_name;
                    // 显示友好名称（HTTP/HTTPS、TCP、UDP）
                    document.getElementById('edit-proxy-type').value = getProxyTypeName(proxy.proxy_type);
                    
                    // 根据代理类型填充不同的字段
                    if (proxy.proxy_type === 'http') {
                        document.getElementById('edit-listen-port').value = proxy.listen_port;
                        document.getElementById('edit-listen-address').value = proxy.listen_address || '0.0.0.0';
                        document.getElementById('edit-server-name').value = proxy.server_name || '';
                        // location_path 将在填充后端服务器列表时设置到第一个后端服务器的路径匹配输入框
                    } else if (proxy.proxy_type === 'tcp' || proxy.proxy_type === 'udp') {
                        document.getElementById('edit-tcp-udp-listen-port').value = proxy.listen_port;
                        document.getElementById('edit-tcp-udp-listen-address').value = proxy.listen_address || '0.0.0.0';
                        // TCP/UDP 代理不支持监听域名，不需要设置
                    }
                    document.getElementById('edit-load-balance').value = proxy.load_balance || 'round_robin';
                    document.getElementById('edit-proxy-connect-timeout').value = proxy.proxy_connect_timeout || 60;
                    document.getElementById('edit-proxy-send-timeout').value = proxy.proxy_send_timeout || 60;
                    document.getElementById('edit-proxy-read-timeout').value = proxy.proxy_read_timeout || 60;
                    document.getElementById('edit-description').value = proxy.description || '';
                    
                    // 加载防护规则列表
                    const editRulesList = document.getElementById('edit-rules-list');
                    editRulesList.innerHTML = '';
                    if (proxy.ip_rule_ids && Array.isArray(proxy.ip_rule_ids) && proxy.ip_rule_ids.length > 0) {
                        // 如果有规则ID，需要先加载规则列表，然后填充
                        if (allIpRules.length === 0) {
                            await loadIpRules();
                        }
                        // 填充规则列表
                        proxy.ip_rule_ids.forEach(ruleId => {
                            const rule = allIpRules.find(r => r.id == ruleId);
                            if (rule) {
                                addEditRule();
                                const ruleItems = editRulesList.querySelectorAll('.rule-item');
                                const lastItem = ruleItems[ruleItems.length - 1];
                                const typeSelect = lastItem.querySelector('.rule-type');
                                const ruleIdSelect = lastItem.querySelector('.rule-id');
                                typeSelect.value = rule.rule_type;
                                filterRulesByType(typeSelect, ruleIdSelect);
                                ruleIdSelect.value = rule.id;
                            }
                        });
                    } else {
                        // 如果没有规则，至少添加一个空规则项
                        addEditRule();
                    }
                    
                    // 显示/隐藏相关字段，并动态管理required属性
                    const editListenPort = document.getElementById('edit-listen-port');
                    const editTcpUdpListenPort = document.getElementById('edit-tcp-udp-listen-port');
                    
                    if (proxy.proxy_type === 'http') {
                        document.getElementById('edit-http-fields').style.display = 'flex';
                        document.getElementById('edit-tcp-udp-fields').style.display = 'none';
                        // 显示路径匹配列表
                        const editLocationPathsFields = document.getElementById('edit-location-paths-fields');
                        if (editLocationPathsFields) {
                            editLocationPathsFields.style.display = 'block';
                        }
                        // 为显示的字段添加required属性
                        editListenPort.setAttribute('required', 'required');
                        // 为隐藏的字段移除required属性
                        editTcpUdpListenPort.removeAttribute('required');
                    } else if (proxy.proxy_type === 'tcp' || proxy.proxy_type === 'udp') {
                        document.getElementById('edit-http-fields').style.display = 'none';
                        document.getElementById('edit-tcp-udp-fields').style.display = 'flex';
                        // 隐藏路径匹配列表
                        const editLocationPathsFields = document.getElementById('edit-location-paths-fields');
                        if (editLocationPathsFields) {
                            editLocationPathsFields.style.display = 'none';
                        }
                        // 为隐藏的字段移除required属性
                        editListenPort.removeAttribute('required');
                        // 为显示的字段添加required属性
                        editTcpUdpListenPort.setAttribute('required', 'required');
                    } else {
                        document.getElementById('edit-http-fields').style.display = 'none';
                        document.getElementById('edit-tcp-udp-fields').style.display = 'none';
                        // 当没有选择代理类型时，移除所有required属性
                        editListenPort.removeAttribute('required');
                        editTcpUdpListenPort.removeAttribute('required');
                    }
                    
                    // 加载路径匹配列表（HTTP代理）
                    if (proxy.proxy_type === 'http') {
                        const locationPathsList = document.getElementById('edit-location-paths-list');
                        if (locationPathsList) {
                            locationPathsList.innerHTML = '';
                            // 如果location_paths有值，使用它；否则使用location_path（向后兼容）
                            if (proxy.location_paths && Array.isArray(proxy.location_paths) && proxy.location_paths.length > 0) {
                                proxy.location_paths.forEach(loc => {
                                    addEditLocationPath();
                                    const items = locationPathsList.querySelectorAll('.location-path-item');
                                    const lastItem = items[items.length - 1];
                                    lastItem.querySelector('.location-path-input').value = loc.location_path || '';
                                    const backendPathInput = lastItem.querySelector('.location-backend-path-input');
                                    if (backendPathInput) {
                                        backendPathInput.value = loc.backend_path || '';
                                    }
                                });
                            } else {
                                // 向后兼容：如果没有location_paths，使用location_path
                                addEditLocationPath();
                                const items = locationPathsList.querySelectorAll('.location-path-item');
                                const lastItem = items[items.length - 1];
                                lastItem.querySelector('.location-path-input').value = proxy.location_path || '/';
                            }
                        }
                    }
                    
                    // 加载后端服务器列表
                    const list = document.getElementById('edit-backends-list');
                    list.innerHTML = '';
                    if (proxy.backends && proxy.backends.length > 0) {
                        proxy.backends.forEach((backend, index) => {
                            addEditBackend();
                            const items = list.querySelectorAll('.backend-item');
                            const lastItem = items[items.length - 1];
                            lastItem.querySelector('.backend-address').value = backend.backend_address;
                            lastItem.querySelector('.backend-port').value = backend.backend_port;
                            lastItem.querySelector('.backend-weight').value = backend.weight || 1;
                            // 设置代理路径字段（如果存在）
                            const pathField = lastItem.querySelector('.backend-path');
                            if (pathField && backend.backend_path) {
                                pathField.value = backend.backend_path;
                            }
                        });
                    } else {
                        // 如果没有后端服务器，至少添加一个空的后端项
                        addEditBackend();
                        // 设置路径匹配字段
                        const firstItem = list.querySelector('.backend-item');
                        if (firstItem && proxy.proxy_type === 'http') {
                            const locationPathField = firstItem.querySelector('.backend-location-path');
                            if (locationPathField) {
                                locationPathField.value = proxy.location_path || '/';
                            }
                        }
                    }
                    
                    // 根据代理类型显示/隐藏路径字段
                    if (proxy.proxy_type === 'http') {
                        // 隐藏后端服务器列表中的匹配路径字段，使用独立的路径匹配列表
                        document.querySelectorAll('#edit-backends-list .backend-location-path').forEach(field => {
                            field.style.display = 'none';
                        });
                        document.querySelectorAll('#edit-backends-list .backend-path').forEach(field => {
                            field.style.display = 'block';
                            field.addEventListener('input', checkEditBackendPaths);
                        });
                        // 重新检查代理路径一致性
                        checkEditBackendPaths();
                    } else {
                        document.querySelectorAll('#edit-backends-list .backend-path').forEach(field => {
                            field.style.display = 'none';
                        });
                        // 移除错误提示
                        const errorDiv = document.getElementById('edit-backends-list')?.querySelector('.backend-path-error');
                        if (errorDiv) {
                            errorDiv.remove();
                        }
                        // 移除错误样式
                        document.querySelectorAll('#edit-backends-list .backend-path').forEach(field => {
                            field.classList.remove('backend-path-error');
                        });
                    }
                    
                    const editModal = document.getElementById('edit-modal');
                    // 明确设置width和height，确保居中
                    editModal.style.width = '100%';
                    editModal.style.height = '100%';
                    editModal.style.display = 'flex';
                    editModal.style.alignItems = 'center';
                    editModal.style.justifyContent = 'center';
                } else {
                    showAlert(data.error || '加载失败', 'error');
                }
            } catch (error) {
                showAlert('网络错误: ' + error.message, 'error');
            }
        }
        
        // 更新代理
        async function updateProxy(event) {
            event.preventDefault();
            
            const id = document.getElementById('edit-id').value;
            // 使用保存的原始代理类型值，而不是显示值（因为显示值可能是"HTTP/HTTPS"等友好名称）
            // 如果 currentEditingProxy 不存在，则从输入框获取并反向转换
            let proxyType;
            if (currentEditingProxy && currentEditingProxy.proxy_type) {
                proxyType = currentEditingProxy.proxy_type;
            } else {
                const displayValue = document.getElementById('edit-proxy-type').value;
                proxyType = getProxyTypeFromName(displayValue);
            }
            
            // 获取已选择的规则ID列表
            const ipRuleIds = [];
            const editRulesList = document.getElementById('edit-rules-list');
            if (editRulesList) {
                const ruleItems = editRulesList.querySelectorAll('.rule-item');
                ruleItems.forEach(item => {
                    const typeSelect = item.querySelector('.rule-type');
                    const ruleIdSelect = item.querySelector('.rule-id');
                    if (typeSelect && typeSelect.value && ruleIdSelect && ruleIdSelect.value) {
                        ipRuleIds.push(parseInt(ruleIdSelect.value));
                    }
                });
            }
            
            const proxyData = {
                proxy_name: document.getElementById('edit-proxy-name').value,
                backend_type: 'upstream',
                description: document.getElementById('edit-description').value || '',
                proxy_connect_timeout: parseInt(document.getElementById('edit-proxy-connect-timeout').value) || 60,
                proxy_send_timeout: parseInt(document.getElementById('edit-proxy-send-timeout').value) || 60,
                proxy_read_timeout: parseInt(document.getElementById('edit-proxy-read-timeout').value) || 60,
                ip_rule_ids: ipRuleIds.length > 0 ? ipRuleIds : null,
                status: currentEditingProxy ? currentEditingProxy.status : 1
            };
            
            if (proxyType === 'http') {
                proxyData.listen_port = parseInt(document.getElementById('edit-listen-port').value);
                proxyData.listen_address = document.getElementById('edit-listen-address').value;
                const serverName = document.getElementById('edit-server-name').value.trim();
                proxyData.server_name = serverName || null;
                
                // 收集路径匹配列表
                const locationPathsList = document.getElementById('edit-location-paths-list');
                const locationPaths = [];
                if (locationPathsList) {
                    const items = locationPathsList.querySelectorAll('.location-path-item');
                    items.forEach(item => {
                        const locationPathInput = item.querySelector('.location-path-input');
                        const backendPathInput = item.querySelector('.location-backend-path-input');
                        if (locationPathInput && locationPathInput.value.trim()) {
                            const locationPath = locationPathInput.value.trim();
                            const backendPath = backendPathInput ? backendPathInput.value.trim() : '';
                            locationPaths.push({
                                location_path: locationPath,
                                backend_path: backendPath || null
                            });
                        }
                    });
                }
                
                // 如果location_paths有值，使用它；否则使用location_path（向后兼容）
                if (locationPaths.length > 0) {
                    proxyData.location_paths = locationPaths;
                    // 为了向后兼容，也设置location_path为第一个值
                    proxyData.location_path = locationPaths[0].location_path;
                } else {
                    // 向后兼容：如果没有location_paths，使用location_path
                    proxyData.location_path = '/';
                    proxyData.location_paths = null;
                }
            } else if (proxyType === 'tcp' || proxyType === 'udp') {
                proxyData.listen_port = parseInt(document.getElementById('edit-tcp-udp-listen-port').value);
                proxyData.listen_address = document.getElementById('edit-tcp-udp-listen-address').value;
                // TCP/UDP 代理不支持监听域名，设置为 null
                proxyData.server_name = null;
            }
            
            // 获取后端服务器列表
            const backends = [];
            const backendItems = document.querySelectorAll('#edit-backends-list .backend-item');
            backendItems.forEach(item => {
                const address = item.querySelector('.backend-address').value;
                const port = parseInt(item.querySelector('.backend-port').value);
                const weight = parseInt(item.querySelector('.backend-weight').value) || 1;
                const pathField = item.querySelector('.backend-path');
                const path = pathField ? pathField.value.trim() : '';
                if (address && port) {
                    const backend = {backend_address: address, backend_port: port, weight: weight};
                    // HTTP/HTTPS代理时，如果有路径，添加到后端配置中
                    if (proxyType === 'http' && path) {
                        backend.backend_path = path;
                    }
                    backends.push(backend);
                }
            });
            proxyData.backends = backends;
            proxyData.load_balance = document.getElementById('edit-load-balance').value;
            
            try {
                const response = await fetch(`/api/proxy/${id}`, {
                    method: 'PUT',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify(proxyData)
                });
                
                const data = await response.json();
                
                if (data.success) {
                    showAlert('代理配置更新成功');
                    closeEditModal();
                    loadProxies();
                } else {
                    showAlert(data.error || '更新失败', 'error');
                }
            } catch (error) {
                showAlert('网络错误: ' + error.message, 'error');
            }
        }
        
        // 启用代理
        async function enableProxy(id) {
            showConfirmModal('确认启用', '确定要启用该配置吗？', async function() {
                try {
                    const response = await fetch(`/api/proxy/${id}/enable`, { method: 'POST' });
                    const data = await response.json();
                    
                    if (data.success) {
                        showAlert('代理配置已启用');
                        loadProxies();
                    } else {
                        showAlert(data.error || '操作失败', 'error');
                    }
                } catch (error) {
                    showAlert('网络错误: ' + error.message, 'error');
                }
            });
        }
        
        // 确认对话框相关函数
        let confirmCallback = null;
        
        function showConfirmModal(title, message, callback) {
            document.getElementById('confirm-title').textContent = title;
            document.getElementById('confirm-message').textContent = message;
            confirmCallback = callback;
            const modal = document.getElementById('confirm-modal');
            modal.style.display = 'flex';
        }
        
        function closeConfirmModal() {
            const modal = document.getElementById('confirm-modal');
            modal.style.display = 'none';
            confirmCallback = null;
        }
        
        // 确认对话框确定按钮
        document.addEventListener('DOMContentLoaded', function() {
            const confirmOkBtn = document.getElementById('confirm-ok-btn');
            if (confirmOkBtn) {
                confirmOkBtn.addEventListener('click', function() {
                    if (confirmCallback) {
                        confirmCallback();
                    }
                    closeConfirmModal();
                });
            }
            
            // 点击确认模态框外部关闭
            const confirmModal = document.getElementById('confirm-modal');
            if (confirmModal) {
                confirmModal.addEventListener('click', function(event) {
                    if (event.target === confirmModal) {
                        closeConfirmModal();
                    }
                });
            }
        });
        
        // 禁用代理
        async function disableProxy(id) {
            showConfirmModal('确认禁用', '确定要禁用该配置吗？', async function() {
                try {
                    const response = await fetch(`/api/proxy/${id}/disable`, { method: 'POST' });
                    const data = await response.json();
                    
                    if (data.success) {
                        showAlert('代理配置已禁用');
                        loadProxies();
                    } else {
                        showAlert(data.error || '操作失败', 'error');
                    }
                } catch (error) {
                    showAlert('网络错误: ' + error.message, 'error');
                }
            });
        }
        
        // 删除代理
        async function deleteProxy(id) {
            showConfirmModal('确认删除', '确定要删除该配置吗？此操作不可恢复！', async function() {
                try {
                    const response = await fetch(`/api/proxy/${id}`, { method: 'DELETE' });
                    const data = await response.json();
                    
                    if (data.success) {
                        showAlert('代理配置已删除');
                        loadProxies();
                    } else {
                        showAlert(data.error || '删除失败', 'error');
                    }
                } catch (error) {
                    showAlert('网络错误: ' + error.message, 'error');
                }
            });
        }
        
        // 关闭编辑模态框
        function closeEditModal() {
            document.getElementById('edit-modal').style.display = 'none';
        }
        
        // 重置创建表单
        function resetCreateForm() {
            document.getElementById('create-form').reset();
            // 重置后设置默认代理类型为HTTP/HTTPS
            const proxyTypeSelect = document.getElementById('create-proxy-type');
            if (proxyTypeSelect) {
                proxyTypeSelect.value = 'http';
            }
            const proxyType = document.getElementById('create-proxy-type').value;
            
            // 重置配置列表
            const configItemsList = document.getElementById('config-items-list');
            if (configItemsList) {
                const locationPathWrapper = proxyType === 'http' ? `
                    <div class="input-with-add">
                        <input type="text" placeholder="匹配路径：/PATH" class="location-path-input" title="匹配路径：/PATH">
                        <button type="button" class="btn-add" onclick="addLocationPath()" title="添加路径匹配">+</button>
                    </div>
                    <div class="input-with-add">
                        <input type="text" placeholder="目标路径：/PATH（可选）" class="location-backend-path-input" title="目标路径：/PATH（可选）">
                        <button type="button" class="btn-add" onclick="addLocationPath()" title="添加路径匹配">+</button>
                    </div>
                ` : '';
                
                const backendPathWrapper = proxyType === 'http' ? `
                    <div class="input-with-add">
                        <input type="text" placeholder="目标路径：/PATH" class="backend-path" title="目标路径：/PATH">
                        <button type="button" class="btn-add" onclick="addBackend()" title="添加后端服务器">+</button>
                    </div>
                ` : '';
                
                configItemsList.innerHTML = `
                    <div class="config-item">
                        <div class="config-item-row">
                            ${locationPathWrapper}
                            <div class="input-with-add">
                                <input type="text" placeholder="IP地址" class="backend-address">
                                <button type="button" class="btn-add" onclick="addBackend()" title="添加后端服务器">+</button>
                            </div>
                            <div class="input-with-add">
                                <input type="number" placeholder="端口" class="backend-port" min="1" max="65535">
                                <button type="button" class="btn-add" onclick="addBackend()" title="添加后端服务器">+</button>
                            </div>
                            ${backendPathWrapper}
                            <div class="input-with-add">
                                <input type="number" placeholder="权重" class="backend-weight" value="1" min="1">
                                <button type="button" class="btn-add" onclick="addBackend()" title="添加后端服务器">+</button>
                            </div>
                            <button type="button" class="btn btn-danger btn-sm" onclick="removeConfigItem(this)">删除</button>
                        </div>
                    </div>
                `;
            }
            toggleProxyFields();
            // 清空规则列表，只保留一个空规则条目
            const rulesList = document.getElementById('rules-list');
            if (rulesList) {
                rulesList.innerHTML = `
                    <div class="rule-item">
                        <select class="rule-type" onchange="onRuleTypeChange(this)">
                            <option value="">请选择规则类型</option>
                            <option value="ip_whitelist">IP白名单</option>
                            <option value="ip_blacklist">IP黑名单</option>
                            <option value="geo_whitelist">地域白名单</option>
                            <option value="geo_blacklist">地域黑名单</option>
                        </select>
                        <select class="rule-id">
                            <option value="">请选择规则条目</option>
                        </select>
                        <button type="button" class="btn btn-danger" onclick="removeRule(this)">删除</button>
                    </div>
                `;
            }
        }
        
        // 显示创建代理弹出框
        function showCreateProxyModal() {
            const modal = document.getElementById('create-proxy-modal');
            if (modal) {
                modal.style.display = 'flex';
                modal.classList.add('show');
                // 设置默认代理类型为HTTP/HTTPS
                const proxyTypeSelect = document.getElementById('create-proxy-type');
                if (proxyTypeSelect) {
                    proxyTypeSelect.value = 'http';
                    // 触发字段切换，显示HTTP/HTTPS相关字段
                    toggleProxyFields();
                }
                // 清空规则列表，只保留一个空规则条目
                const rulesList = document.getElementById('rules-list');
                if (rulesList) {
                    rulesList.innerHTML = `
                        <div class="rule-item">
                            <select class="rule-type" onchange="onRuleTypeChange(this)">
                                <option value="">请选择规则类型</option>
                                <option value="ip_whitelist">IP白名单</option>
                                <option value="ip_blacklist">IP黑名单</option>
                                <option value="geo_whitelist">地域白名单</option>
                                <option value="geo_blacklist">地域黑名单</option>
                            </select>
                            <select class="rule-id">
                                <option value="">请选择规则条目</option>
                            </select>
                            <button type="button" class="btn btn-danger" onclick="removeRule(this)">删除</button>
                        </div>
                    `;
                }
                // 如果规则列表未加载，先加载
                if (allIpRules.length === 0) {
                    loadIpRules();
                }
            }
        }
        
        // 关闭创建代理弹出框
        function closeCreateProxyModal() {
            const modal = document.getElementById('create-proxy-modal');
            if (modal) {
                modal.style.display = 'none';
                modal.classList.remove('show');
                // 重置表单
                resetCreateForm();
            }
        }
        
        // 工具函数
        function getProxyTypeName(type) {
            const names = {
                'http': 'HTTP/HTTPS',
                'tcp': 'TCP',
                'udp': 'UDP'
            };
            return names[type] || type;
        }
        
        // 反向转换：从友好名称转换为原始类型值
        function getProxyTypeFromName(name) {
            const reverseMap = {
                'HTTP/HTTPS': 'http',
                'TCP': 'tcp',
                'UDP': 'udp'
            };
            return reverseMap[name] || name;
        }
        
        function getStatusBadge(status) {
            if (status == 1) {
                return '<span class="status-badge status-enabled">已启用</span>';
            } else {
                return '<span class="status-badge status-disabled">已禁用</span>';
            }
        }
        
        // 获取规则类型中文名称
        function getRuleTypeName(ruleType) {
            if (!ruleType) return '';
            const typeNames = {
                'ip_whitelist': 'IP白名单',
                'ip_blacklist': 'IP黑名单',
                'geo_whitelist': '地域白名单',
                'geo_blacklist': '地域黑名单'
            };
            return typeNames[ruleType] || ruleType;
        }
        
        function formatDateTime(datetime) {
            if (!datetime) return '-';
            return datetime.replace('T', ' ').substring(0, 19);
        }
        
        function renderPagination(data, containerId, loadFunc) {
            const container = document.getElementById(containerId);
            if (data.total_pages <= 1) {
                container.innerHTML = '';
                return;
            }
            
            const html = `
                <button onclick="${loadFunc.name}(${data.page - 1})" ${data.page <= 1 ? 'disabled' : ''}>上一页</button>
                <span>第 ${data.page} / ${data.total_pages} 页 (共 ${data.total} 条)</span>
                <button onclick="${loadFunc.name}(${data.page + 1})" ${data.page >= data.total_pages ? 'disabled' : ''}>下一页</button>
            `;
            container.innerHTML = html;
        }
        
        // 初始化
        // 加载IP相关规则列表（用于防护规则选择）
        async function loadIpRules() {
            try {
                // 获取所有已启用的IP相关的规则（ip_whitelist, ip_blacklist, geo_whitelist, geo_blacklist）
                // 只获取status=1（已启用）的规则
                const response = await fetch('/api/rules?page=1&page_size=1000&status=1');
                const data = await response.json();
                
                if (data.success && data.data && data.data.rules) {
                    const rules = data.data.rules;
                    // 过滤：只保留IP相关类型且已启用的规则
                    const ipRules = rules.filter(rule => 
                        (rule.rule_type === 'ip_whitelist' || 
                         rule.rule_type === 'ip_blacklist' || 
                         rule.rule_type === 'geo_whitelist' || 
                         rule.rule_type === 'geo_blacklist') &&
                        rule.status == 1  // 只保留已启用的规则
                    );
                    
                    // 保存所有IP相关规则到全局变量
                    allIpRules = ipRules;
                    
                    // 更新所有规则条目的选择框（创建和编辑）
                    updateAllRuleSelects('rules-list');
                    updateAllRuleSelects('edit-rules-list');
                }
            } catch (error) {
                console.error('加载规则列表失败:', error);
            }
        }
        
        // 全局变量：存储所有IP相关规则
        let allIpRules = [];
        
        // 规则互斥关系定义
        const ruleConflicts = {
            'ip_whitelist': ['ip_blacklist'],
            'ip_blacklist': ['ip_whitelist'],
            'geo_whitelist': ['geo_blacklist'],
            'geo_blacklist': ['geo_whitelist']
        };
        
        // 获取已选择规则的所有类型（支持创建和编辑）
        function getSelectedRuleTypes(rulesListId) {
            const listId = rulesListId || 'rules-list';
            const rulesList = document.getElementById(listId);
            if (!rulesList) return [];
            const ruleItems = rulesList.querySelectorAll('.rule-item');
            const types = [];
            ruleItems.forEach(item => {
                const typeSelect = item.querySelector('.rule-type');
                const ruleIdSelect = item.querySelector('.rule-id');
                if (typeSelect && typeSelect.value && ruleIdSelect && ruleIdSelect.value) {
                    types.push(typeSelect.value);
                }
            });
            return types;
        }
        
        // 检查规则类型是否冲突（支持创建和编辑）
        function checkRuleConflict(newType, rulesListId) {
            if (!newType) return false;
            const selectedTypes = getSelectedRuleTypes(rulesListId);
            const conflicts = ruleConflicts[newType] || [];
            return conflicts.some(conflictType => selectedTypes.includes(conflictType));
        }
        
        // 根据规则类型筛选规则（用于单个规则条目，支持创建和编辑）
        function filterRulesByType(ruleTypeSelect, ruleIdSelect) {
            if (!ruleIdSelect) return;
            
            const ruleType = ruleTypeSelect.value;
            ruleIdSelect.innerHTML = '<option value="">请选择规则条目</option>';
            
            if (!ruleType) {
                return;
            }
            
            // 获取当前规则列表容器（创建或编辑）
            const ruleItem = ruleTypeSelect.closest('.rule-item');
            const rulesList = ruleItem ? ruleItem.closest('.rules-list') : null;
            const selectedIds = [];
            if (rulesList) {
                const ruleItems = rulesList.querySelectorAll('.rule-item');
                ruleItems.forEach(item => {
                    const idSelect = item.querySelector('.rule-id');
                    if (idSelect && idSelect !== ruleIdSelect && idSelect.value) {
                        selectedIds.push(parseInt(idSelect.value));
                    }
                });
            }
            
            // 筛选同类型的规则，且只保留已启用的规则
            const filteredRules = allIpRules.filter(rule => 
                rule.rule_type === ruleType && 
                !selectedIds.includes(rule.id) &&
                rule.status == 1  // 只保留已启用的规则
            );
            
            filteredRules.forEach(rule => {
                const option = document.createElement('option');
                option.value = rule.id;
                const typeNames = {
                    'ip_whitelist': 'IP白名单',
                    'ip_blacklist': 'IP黑名单',
                    'geo_whitelist': '地域白名单',
                    'geo_blacklist': '地域黑名单'
                };
                option.textContent = `${rule.rule_name} (${typeNames[rule.rule_type] || rule.rule_type})`;
                ruleIdSelect.appendChild(option);
            });
        }
        
        // 规则类型改变事件（支持创建和编辑）
        function onRuleTypeChange(typeSelect) {
            const ruleItem = typeSelect.closest('.rule-item');
            if (!ruleItem) return;
            
            const ruleIdSelect = ruleItem.querySelector('.rule-id');
            if (!ruleIdSelect) return;
            
            const newType = typeSelect.value;
            
            // 获取当前规则列表ID（创建或编辑）
            const rulesList = ruleItem.closest('.rules-list');
            const rulesListId = rulesList ? rulesList.id : 'rules-list';
            
            // 检查是否冲突
            if (checkRuleConflict(newType, rulesListId)) {
                const typeNames = {
                    'ip_whitelist': 'IP白名单',
                    'ip_blacklist': 'IP黑名单',
                    'geo_whitelist': '地域白名单',
                    'geo_blacklist': '地域黑名单'
                };
                const conflicts = ruleConflicts[newType] || [];
                const conflictNames = conflicts.map(t => typeNames[t] || t).join('、');
                showAlert(`不能同时选择${typeNames[newType] || newType}和${conflictNames}`, 'error');
                typeSelect.value = '';
                ruleIdSelect.innerHTML = '<option value="">请选择规则条目</option>';
                return;
            }
            
            // 更新规则条目选择框
            filterRulesByType(typeSelect, ruleIdSelect);
        }
        
        // 添加规则条目（支持创建和编辑）
        function addRule(rulesListId) {
            const listId = rulesListId || 'rules-list';
            const rulesList = document.getElementById(listId);
            if (!rulesList) return;
            
            const ruleItem = document.createElement('div');
            ruleItem.className = 'rule-item';
            ruleItem.innerHTML = `
                <select class="rule-type" onchange="onRuleTypeChange(this)">
                    <option value="">请选择规则类型</option>
                    <option value="ip_whitelist">IP白名单</option>
                    <option value="ip_blacklist">IP黑名单</option>
                    <option value="geo_whitelist">地域白名单</option>
                    <option value="geo_blacklist">地域黑名单</option>
                </select>
                <select class="rule-id">
                    <option value="">请选择规则条目</option>
                </select>
                <button type="button" class="btn btn-danger" onclick="removeRule(this)">删除</button>
            `;
            rulesList.appendChild(ruleItem);
        }
        
        // 删除规则条目（支持创建和编辑）
        function removeRule(button) {
            const ruleItem = button.closest('.rule-item');
            if (ruleItem) {
                const rulesList = ruleItem.closest('.rules-list');
                ruleItem.remove();
                // 更新所有规则条目的选择框（移除已删除的规则）
                updateAllRuleSelects(rulesList ? rulesList.id : 'rules-list');
            }
        }
        
        // 更新所有规则条目的选择框（支持创建和编辑）
        function updateAllRuleSelects(rulesListId) {
            const listId = rulesListId || 'rules-list';
            const rulesList = document.getElementById(listId);
            if (!rulesList) return;
            const ruleItems = rulesList.querySelectorAll('.rule-item');
            ruleItems.forEach(item => {
                const typeSelect = item.querySelector('.rule-type');
                const ruleIdSelect = item.querySelector('.rule-id');
                if (typeSelect && ruleIdSelect) {
                    const currentType = typeSelect.value;
                    const currentId = ruleIdSelect.value;
                    filterRulesByType(typeSelect, ruleIdSelect);
                    if (currentType && currentId) {
                        ruleIdSelect.value = currentId;
                    }
                }
            });
        }
        
        // 添加编辑代理的规则条目
        function addEditRule() {
            addRule('edit-rules-list');
        }
        
        document.addEventListener('DOMContentLoaded', function() {
            loadProxies();
            loadIpRules(); // 加载规则列表
            
            // 点击模态框外部关闭
            window.onclick = function(event) {
                const modal = document.getElementById('edit-modal');
                if (event.target == modal) {
                    closeEditModal();
                }
            }
        });