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
                // 为显示的字段添加required属性
                createListenPort.setAttribute('required', 'required');
                // 为隐藏的字段移除required属性
                createTcpUdpListenPort.removeAttribute('required');
                // 显示所有后端服务器列表中的路径字段
                document.querySelectorAll('#backends-list .backend-path').forEach(field => {
                    field.style.display = 'block';
                });
                // 同步监听端口和监听地址的值
                document.getElementById('create-tcp-udp-listen-port').value = document.getElementById('create-listen-port').value;
                document.getElementById('create-tcp-udp-listen-address').value = document.getElementById('create-listen-address').value;
            } else if (proxyType === 'tcp' || proxyType === 'udp') {
                httpFields.style.display = 'none';
                tcpUdpFields.style.display = 'flex';
                // 为隐藏的字段移除required属性
                createListenPort.removeAttribute('required');
                // 为显示的字段添加required属性
                createTcpUdpListenPort.setAttribute('required', 'required');
                // 隐藏所有后端服务器列表中的路径字段
                document.querySelectorAll('#backends-list .backend-path').forEach(field => {
                    field.style.display = 'none';
                });
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
        
        // 添加后端服务器
        function addBackend() {
            const list = document.getElementById('backends-list');
            const proxyType = document.getElementById('create-proxy-type').value;
            const item = document.createElement('div');
            item.className = 'backend-item';
            
            // HTTP/HTTPS代理显示路径字段，TCP/UDP代理不显示
            const pathField = proxyType === 'http' 
                ? '<input type="text" placeholder="/path" class="backend-path" title="/path">'
                : '<input type="text" placeholder="路径（HTTP/HTTPS）" class="backend-path" style="display: none;">';
            
            item.innerHTML = `
                <input type="text" placeholder="IP地址" class="backend-address">
                <input type="number" placeholder="端口" class="backend-port" min="1" max="65535">
                ${pathField}
                <input type="number" placeholder="权重" class="backend-weight" value="1" min="1">
                <button type="button" class="btn btn-danger" onclick="removeBackend(this)">删除</button>
            `;
            list.appendChild(item);
        }
        
        function addEditBackend() {
            const list = document.getElementById('edit-backends-list');
            const item = document.createElement('div');
            item.className = 'backend-item';
            item.innerHTML = `
                <input type="text" placeholder="IP地址" class="backend-address">
                <input type="number" placeholder="端口" class="backend-port" min="1" max="65535">
                <input type="number" placeholder="权重" class="backend-weight" value="1" min="1">
                <button type="button" class="btn btn-danger" onclick="removeBackend(this)">删除</button>
            `;
            list.appendChild(item);
        }
        
        // 删除后端服务器
        function removeBackend(btn) {
            btn.parentElement.remove();
        }
        
        // 加载代理列表
        async function loadProxies(page = 1) {
            currentPage = page;
            const proxyType = document.getElementById('filter-type').value;
            const status = document.getElementById('filter-status').value;
            
            let url = `/api/proxy?page=${page}&page_size=${pageSize}`;
            if (proxyType) url += `&proxy_type=${proxyType}`;
            if (status) url += `&status=${status}`;
            
            const tbody = document.getElementById('proxies-tbody');
            // 防御性检查：确保 escapeHtml 函数可用
            const escapeHtmlFn = window.escapeHtml || function(text) {
                if (!text) return '';
                const div = document.createElement('div');
                div.textContent = text;
                return div.innerHTML;
            };
            
            try {
                // 显示加载状态
                tbody.innerHTML = '<tr><td colspan="11" style="text-align: center; padding: 20px;">加载中...</td></tr>';
                
                const response = await fetch(url);
                
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
                showAlert('网络错误: ' + error.message, 'error');
                tbody.innerHTML = '<tr><td colspan="11" style="text-align: center; padding: 20px; color: #e74c3c;">加载失败: ' + escapeHtmlFn(error.message) + '</td></tr>';
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
            
            const ipRuleId = document.getElementById('create-ip-rule-id').value;
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
                ip_rule_id: ipRuleId ? parseInt(ipRuleId) : null
            };
            
            if (proxyData.proxy_type === 'http') {
                const serverName = document.getElementById('create-server-name').value.trim();
                proxyData.server_name = serverName || null;
                proxyData.location_path = document.getElementById('create-location-path').value || '/';
            } else if (proxyData.proxy_type === 'tcp' || proxyData.proxy_type === 'udp') {
                const serverName = document.getElementById('create-tcp-udp-server-name').value.trim();
                proxyData.server_name = serverName || null;
            }
            
            // 获取后端服务器列表
            const backends = [];
            const backendItems = document.querySelectorAll('#backends-list .backend-item');
            backendItems.forEach(item => {
                const address = item.querySelector('.backend-address').value;
                const port = parseInt(item.querySelector('.backend-port').value);
                const weight = parseInt(item.querySelector('.backend-weight').value) || 1;
                const pathField = item.querySelector('.backend-path');
                const path = pathField ? pathField.value.trim() : '';
                if (address && port) {
                    const backend = {backend_address: address, backend_port: port, weight: weight};
                    // HTTP/HTTPS代理时，如果有路径，添加到后端配置中
                    if (proxyData.proxy_type === 'http' && path) {
                        backend.backend_path = path;
                    }
                    backends.push(backend);
                }
            });
            proxyData.backends = backends;
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
                    document.getElementById('edit-proxy-type').value = proxy.proxy_type;
                    
                    // 根据代理类型填充不同的字段
                    if (proxy.proxy_type === 'http') {
                        document.getElementById('edit-listen-port').value = proxy.listen_port;
                        document.getElementById('edit-listen-address').value = proxy.listen_address || '0.0.0.0';
                        document.getElementById('edit-server-name').value = proxy.server_name || '';
                        document.getElementById('edit-location-path').value = proxy.location_path || '/';
                    } else if (proxy.proxy_type === 'tcp' || proxy.proxy_type === 'udp') {
                        document.getElementById('edit-tcp-udp-listen-port').value = proxy.listen_port;
                        document.getElementById('edit-tcp-udp-listen-address').value = proxy.listen_address || '0.0.0.0';
                        document.getElementById('edit-tcp-udp-server-name').value = proxy.server_name || '';
                    }
                    document.getElementById('edit-load-balance').value = proxy.load_balance || 'round_robin';
                    document.getElementById('edit-proxy-connect-timeout').value = proxy.proxy_connect_timeout || 60;
                    document.getElementById('edit-proxy-send-timeout').value = proxy.proxy_send_timeout || 60;
                    document.getElementById('edit-proxy-read-timeout').value = proxy.proxy_read_timeout || 60;
                    document.getElementById('edit-description').value = proxy.description || '';
                    document.getElementById('edit-ip-rule-id').value = proxy.ip_rule_id || '';
                    
                    // 显示/隐藏相关字段，并动态管理required属性
                    const editListenPort = document.getElementById('edit-listen-port');
                    const editTcpUdpListenPort = document.getElementById('edit-tcp-udp-listen-port');
                    
                    if (proxy.proxy_type === 'http') {
                        document.getElementById('edit-http-fields').style.display = 'flex';
                        document.getElementById('edit-tcp-udp-fields').style.display = 'none';
                        // 为显示的字段添加required属性
                        editListenPort.setAttribute('required', 'required');
                        // 为隐藏的字段移除required属性
                        editTcpUdpListenPort.removeAttribute('required');
                    } else if (proxy.proxy_type === 'tcp' || proxy.proxy_type === 'udp') {
                        document.getElementById('edit-http-fields').style.display = 'none';
                        document.getElementById('edit-tcp-udp-fields').style.display = 'flex';
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
                    
                    // 加载后端服务器列表
                    const list = document.getElementById('edit-backends-list');
                    list.innerHTML = '';
                    if (proxy.backends && proxy.backends.length > 0) {
                        proxy.backends.forEach(backend => {
                            addEditBackend();
                            const items = list.querySelectorAll('.backend-item');
                            const lastItem = items[items.length - 1];
                            lastItem.querySelector('.backend-address').value = backend.backend_address;
                            lastItem.querySelector('.backend-port').value = backend.backend_port;
                            lastItem.querySelector('.backend-weight').value = backend.weight || 1;
                            // 设置路径字段（如果存在）
                            const pathField = lastItem.querySelector('.backend-path');
                            if (pathField && backend.backend_path) {
                                pathField.value = backend.backend_path;
                            }
                        });
                    } else {
                        // 如果没有后端服务器，至少添加一个空的后端项
                        addEditBackend();
                    }
                    
                    // 根据代理类型显示/隐藏路径字段
                    if (proxy.proxy_type === 'http') {
                        document.querySelectorAll('#edit-backends-list .backend-path').forEach(field => {
                            field.style.display = 'block';
                        });
                    } else {
                        document.querySelectorAll('#edit-backends-list .backend-path').forEach(field => {
                            field.style.display = 'none';
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
            const ipRuleId = document.getElementById('edit-ip-rule-id').value;
            const proxyType = document.getElementById('edit-proxy-type').value;
            const proxyData = {
                proxy_name: document.getElementById('edit-proxy-name').value,
                backend_type: 'upstream',
                description: document.getElementById('edit-description').value || '',
                proxy_connect_timeout: parseInt(document.getElementById('edit-proxy-connect-timeout').value) || 60,
                proxy_send_timeout: parseInt(document.getElementById('edit-proxy-send-timeout').value) || 60,
                proxy_read_timeout: parseInt(document.getElementById('edit-proxy-read-timeout').value) || 60,
                ip_rule_id: ipRuleId ? parseInt(ipRuleId) : null,
                status: currentEditingProxy ? currentEditingProxy.status : 1
            };
            
            if (proxyType === 'http') {
                proxyData.listen_port = parseInt(document.getElementById('edit-listen-port').value);
                proxyData.listen_address = document.getElementById('edit-listen-address').value;
                const serverName = document.getElementById('edit-server-name').value.trim();
                proxyData.server_name = serverName || null;
                proxyData.location_path = document.getElementById('edit-location-path').value || '/';
            } else if (proxyType === 'tcp' || proxyType === 'udp') {
                proxyData.listen_port = parseInt(document.getElementById('edit-tcp-udp-listen-port').value);
                proxyData.listen_address = document.getElementById('edit-tcp-udp-listen-address').value;
                const serverName = document.getElementById('edit-tcp-udp-server-name').value.trim();
                proxyData.server_name = serverName || null;
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
            if (!confirm('确定要启用该代理配置吗？')) return;
            
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
        }
        
        // 禁用代理
        async function disableProxy(id) {
            if (!confirm('确定要禁用该代理配置吗？')) return;
            
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
        }
        
        // 删除代理
        async function deleteProxy(id) {
            if (!confirm('确定要删除该代理配置吗？此操作不可恢复！')) return;
            
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
        }
        
        // 关闭编辑模态框
        function closeEditModal() {
            document.getElementById('edit-modal').style.display = 'none';
        }
        
        // 重置创建表单
        function resetCreateForm() {
            document.getElementById('create-form').reset();
            const proxyType = document.getElementById('create-proxy-type').value;
            const pathField = proxyType === 'http' 
                ? '<input type="text" placeholder="路径" class="backend-path">'
                : '<input type="text" placeholder="路径（HTTP/HTTPS）" class="backend-path" style="display: none;">';
            document.getElementById('backends-list').innerHTML = `<div class="backend-item"><input type="text" placeholder="IP地址" class="backend-address"><input type="number" placeholder="端口" class="backend-port" min="1" max="65535">${pathField}<input type="number" placeholder="权重" class="backend-weight" value="1" min="1"><button type="button" class="btn btn-danger" onclick="removeBackend(this)">删除</button></div>`;
            toggleProxyFields();
        }
        
        // 显示创建代理弹出框
        function showCreateProxyModal() {
            const modal = document.getElementById('create-proxy-modal');
            if (modal) {
                modal.style.display = 'flex';
                modal.classList.add('show');
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
                // 获取所有IP相关的规则（ip_whitelist, ip_blacklist, geo_whitelist, geo_blacklist）
                const response = await fetch('/api/rules?page=1&page_size=1000');
                const data = await response.json();
                
                if (data.success && data.data && data.data.rules) {
                    const rules = data.data.rules;
                    const ipRules = rules.filter(rule => 
                        rule.rule_type === 'ip_whitelist' || 
                        rule.rule_type === 'ip_blacklist' || 
                        rule.rule_type === 'geo_whitelist' || 
                        rule.rule_type === 'geo_blacklist'
                    );
                    
                    // 保存所有IP相关规则到全局变量
                    allIpRules = ipRules;
                    
                    // 初始化创建表单的规则选择（显示所有规则）
                    filterIpRulesByType();
                    
                    // 更新编辑表单的规则选择
                    const editSelect = document.getElementById('edit-ip-rule-id');
                    if (editSelect) {
                        editSelect.innerHTML = '<option value="">不选择（不使用防护规则）</option>';
                        ipRules.forEach(rule => {
                            const option = document.createElement('option');
                            option.value = rule.id;
                            const typeNames = {
                                'ip_whitelist': 'IP白名单',
                                'ip_blacklist': 'IP黑名单',
                                'geo_whitelist': '地域白名单',
                                'geo_blacklist': '地域黑名单'
                            };
                            option.textContent = `${rule.rule_name} (${typeNames[rule.rule_type] || rule.rule_type})`;
                            editSelect.appendChild(option);
                        });
                    }
                }
            } catch (error) {
                console.error('加载规则列表失败:', error);
            }
        }
        
        // 全局变量：存储所有IP相关规则
        let allIpRules = [];
        
        // 根据规则类型筛选规则
        function filterIpRulesByType() {
            const ruleType = document.getElementById('create-ip-rule-type').value;
            const createSelect = document.getElementById('create-ip-rule-id');
            
            if (!createSelect) return;
            
            createSelect.innerHTML = '<option value="">不选择（不使用防护规则）</option>';
            
            const filteredRules = ruleType 
                ? allIpRules.filter(rule => rule.rule_type === ruleType)
                : allIpRules;
            
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
                createSelect.appendChild(option);
            });
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