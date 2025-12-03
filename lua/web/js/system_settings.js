let currentPage = 1;
        const pageSize = 20;
        let editingId = null;
        
        // 切换标签页
        function switchTab(tab) {
            const tabs = document.querySelectorAll('.tab');
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            document.querySelectorAll('.tab-content').forEach(c => {
                c.classList.remove('active');
                c.style.display = 'none';
            });
            
            if (tab === 'whitelist') {
                if (tabs[0]) {
                    tabs[0].classList.add('active');
                }
                const whitelistTab = document.getElementById('whitelist-tab');
                whitelistTab.classList.add('active');
                whitelistTab.style.display = 'block';
                loadWhitelist();
            } else if (tab === 'admin_ssl') {
                if (tabs[1]) {
                    tabs[1].classList.add('active');
                }
                const adminSslTab = document.getElementById('admin-ssl-tab');
                adminSslTab.classList.add('active');
                adminSslTab.style.display = 'block';
                loadAdminSslConfig();
            }
        }
        
        // 使用公共函数 showAlert
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
                window.showAlert(message, type);
            }
        }
        const showAlert = showAlertCustom;
        
        // 加载白名单列表
        async function loadWhitelist(page = 1) {
            currentPage = page;
            const tbody = document.getElementById('whitelist-tbody');
            const pagination = document.getElementById('whitelist-pagination');
            
            tbody.innerHTML = '<tr><td colspan="7" style="text-align: center; padding: 20px;">加载中...</td></tr>';
            pagination.innerHTML = '';
            
            const params = new URLSearchParams({
                page: page,
                page_size: pageSize
            });
            
            const status = document.getElementById('filter-status').value;
            if (status) {
                params.append('status', status);
            }
            
            try {
                const response = await fetch('/api/system/access/whitelist?' + params.toString());
                const data = await response.json();
                
                if (data.success && data.data) {
                    // 确保 data.data 是数组
                    const dataArray = Array.isArray(data.data) ? data.data : [];
                    
                    if (dataArray.length === 0) {
                        tbody.innerHTML = '<tr><td colspan="7" class="empty">暂无数据</td></tr>';
                    } else {
                        tbody.innerHTML = '';
                        dataArray.forEach(item => {
                            const row = document.createElement('tr');
                            row.innerHTML = `
                                <td>${item.id}</td>
                                <td>${escapeHtml(item.ip_address)}</td>
                                <td>${escapeHtml(item.description || '-')}</td>
                                <td><span class="status-badge ${item.status == 1 ? 'status-enabled' : 'status-disabled'}">${item.status == 1 ? '已启用' : '已禁用'}</span></td>
                                <td>${item.created_at || '-'}</td>
                                <td>${item.updated_at || '-'}</td>
                                <td>
                                    <div class="action-buttons">
                                        <button class="btn btn-info" onclick="editWhitelist(${item.id})">编辑</button>
                                        ${item.status == 1 ? 
                                            `<button class="btn btn-warning" onclick="toggleWhitelistStatus(${item.id}, 0)">禁用</button>` :
                                            `<button class="btn btn-primary" onclick="toggleWhitelistStatus(${item.id}, 1)">启用</button>`
                                        }
                                        <button class="btn btn-danger" onclick="deleteWhitelist(${item.id})">删除</button>
                                    </div>
                                </td>
                            `;
                            tbody.appendChild(row);
                        });
                    }
                    
                    if (data.pagination) {
                        renderPagination(pagination, data.pagination, loadWhitelist);
                    }
                } else {
                    showAlert(data.error || '加载失败', 'error');
                    tbody.innerHTML = '<tr><td colspan="7" class="empty">加载失败</td></tr>';
                }
            } catch (error) {
                console.error('loadWhitelist error:', error);
                showAlert('网络错误: ' + error.message, 'error');
                tbody.innerHTML = '<tr><td colspan="7" class="empty">加载失败</td></tr>';
            }
        }

        // 加载管理端 SSL 与域名配置
        async function loadAdminSslConfig() {
            try {
                const response = await fetch('/api/system/admin-ssl/config');
                if (!response.ok) {
                    if (response.status === 401) {
                        window.location.reload();
                        return;
                    }
                    throw new Error('HTTP ' + response.status);
                }
                const data = await response.json();
                if (data && data.success && data.data) {
                    const cfg = data.data;
                    const enableEl = document.getElementById('admin-ssl-enable');
                    const forceEl = document.getElementById('admin-force-https');
                    const nameEl = document.getElementById('admin-server-name');
                    const pemEl = document.getElementById('admin-ssl-pem');
                    const keyEl = document.getElementById('admin-ssl-key');
                    if (enableEl) enableEl.checked = cfg.ssl_enable == 1;
                    if (forceEl) forceEl.checked = cfg.force_https == 1;
                    if (nameEl) nameEl.value = cfg.server_name || '';
                    if (pemEl) pemEl.value = cfg.ssl_pem || '';
                    if (keyEl) keyEl.value = cfg.ssl_key || '';
                } else {
                    showAlert((data && data.error) || '加载管理端SSL配置失败', 'error');
                }
            } catch (e) {
                console.error('loadAdminSslConfig error:', e);
                showAlert('加载管理端SSL配置失败: ' + e.message, 'error');
            }
        }
        
        // 渲染分页
        function renderPagination(container, pagination, loadFn) {
            if (!pagination || pagination.total_pages <= 1) return;
            
            const info = document.createElement('div');
            info.className = 'pagination-info';
            info.textContent = `共 ${pagination.total} 条，第 ${pagination.page}/${pagination.total_pages} 页`;
            
            const controls = document.createElement('div');
            controls.className = 'pagination-controls';
            
            const prevBtn = document.createElement('button');
            prevBtn.className = 'pagination-btn';
            prevBtn.textContent = '上一页';
            prevBtn.disabled = pagination.page <= 1;
            prevBtn.onclick = () => loadFn(pagination.page - 1);
            
            const nextBtn = document.createElement('button');
            nextBtn.className = 'pagination-btn';
            nextBtn.textContent = '下一页';
            nextBtn.disabled = pagination.page >= pagination.total_pages;
            nextBtn.onclick = () => loadFn(pagination.page + 1);
            
            controls.appendChild(prevBtn);
            controls.appendChild(nextBtn);
            
            container.appendChild(info);
            container.appendChild(controls);
        }
        
        // 显示添加模态框
        function showAddModal() {
            editingId = null;
            document.getElementById('modal-title').textContent = '添加IP';
            document.getElementById('edit-form').reset();
            const modal = document.getElementById('edit-modal');
            modal.classList.add('show');
            // 强制设置样式，确保模态框正确显示
            modal.style.display = 'flex';
            modal.style.position = 'fixed';
            modal.style.zIndex = '10000';
            modal.style.left = '0';
            modal.style.top = '0';
            modal.style.right = '0';
            modal.style.bottom = '0';
            modal.style.width = '100vw';
            modal.style.height = '100vh';
            modal.style.alignItems = 'center';
            modal.style.justifyContent = 'center';
            // 防止body滚动
            document.body.style.overflow = 'hidden';
        }

        // 保存管理端 SSL 与域名配置
        async function saveAdminSslConfig() {
            const enableEl = document.getElementById('admin-ssl-enable');
            const forceEl = document.getElementById('admin-force-https');
            const nameEl = document.getElementById('admin-server-name');
            const pemEl = document.getElementById('admin-ssl-pem');
            const keyEl = document.getElementById('admin-ssl-key');

            const sslEnable = enableEl && enableEl.checked ? 1 : 0;
            const forceHttps = forceEl && forceEl.checked ? 1 : 0;
            const serverName = nameEl ? nameEl.value.trim() : '';
            const sslPem = pemEl ? pemEl.value.trim() : '';
            const sslKey = keyEl ? keyEl.value.trim() : '';

            if (sslEnable === 1) {
                if (!serverName) {
                    showAlert('启用管理端HTTPS时，管理端域名不能为空', 'error');
                    return;
                }
                if (!sslPem) {
                    showAlert('启用管理端HTTPS时，SSL证书内容不能为空', 'error');
                    return;
                }
                if (!sslKey) {
                    showAlert('启用管理端HTTPS时，SSL私钥内容不能为空', 'error');
                    return;
                }
            }

            const btn = document.querySelector('#admin-ssl-tab .form-actions .btn-primary');
            if (btn) {
                btn.disabled = true;
                btn.textContent = '保存中...';
            }

            try {
                const params = new URLSearchParams();
                params.append('ssl_enable', String(sslEnable));
                params.append('server_name', serverName);
                params.append('ssl_pem', sslPem);
                params.append('ssl_key', sslKey);
                params.append('force_https', String(forceHttps));

                const response = await fetch('/api/system/admin-ssl/config', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/x-www-form-urlencoded',
                    },
                    body: params.toString(),
                });

                const text = await response.text();
                let data;
                try {
                    data = JSON.parse(text);
                } catch (e) {
                    console.error('saveAdminSslConfig JSON parse error:', e, 'raw:', text);
                    showAlert('保存失败: 后端返回非JSON响应', 'error');
                    return;
                }

                if (response.ok && data.success) {
                    showAlert(data.message || '保存成功', 'success');
                    // 保存成功后重新加载一次，以确保表单与后端状态一致
                    loadAdminSslConfig();
                } else {
                    showAlert(data.error || '保存失败', 'error');
                }
            } catch (e) {
                console.error('saveAdminSslConfig error:', e);
                showAlert('保存失败: ' + e.message, 'error');
            } finally {
                if (btn) {
                    btn.disabled = false;
                    btn.textContent = '保存';
                }
            }
        }

        // 页面初始化
        document.addEventListener('DOMContentLoaded', () => {
            // 默认加载白名单标签页，同时预加载一次管理端SSL配置以便快速切换
            try {
                loadWhitelist();
                loadAdminSslConfig();
            } catch (e) {
                console.error('init system_settings error:', e);
            }
        });
        
        // 编辑白名单
        async function editWhitelist(id) {
            editingId = id;
            document.getElementById('modal-title').textContent = '编辑IP';
            
            try {
                // 从当前列表中查找
                const tbody = document.getElementById('whitelist-tbody');
                const rows = tbody.querySelectorAll('tr');
                let found = false;
                
                for (const row of rows) {
                    const cells = row.querySelectorAll('td');
                    if (cells.length > 0 && parseInt(cells[0].textContent) === id) {
                        document.getElementById('edit-ip-address').value = cells[1].textContent.trim();
                        document.getElementById('edit-description').value = cells[2].textContent.trim() === '-' ? '' : cells[2].textContent.trim();
                        found = true;
                        break;
                    }
                }
                
                if (!found) {
                    showAlert('未找到该记录', 'error');
                    return;
                }
                
                const modal = document.getElementById('edit-modal');
                modal.classList.add('show');
                // 强制设置样式，确保模态框正确显示
                modal.style.display = 'flex';
                modal.style.position = 'fixed';
                modal.style.zIndex = '10000';
                modal.style.left = '0';
                modal.style.top = '0';
                modal.style.right = '0';
                modal.style.bottom = '0';
                modal.style.width = '100vw';
                modal.style.height = '100vh';
                modal.style.alignItems = 'center';
                modal.style.justifyContent = 'center';
                // 防止body滚动
                document.body.style.overflow = 'hidden';
            } catch (error) {
                console.error('editWhitelist error:', error);
                showAlert('加载失败: ' + error.message, 'error');
            }
        }
        
        // 保存白名单
        async function saveWhitelist(event) {
            event.preventDefault();
            
            const ipAddress = document.getElementById('edit-ip-address').value.trim();
            const description = document.getElementById('edit-description').value.trim();
            
            if (!ipAddress) {
                showAlert('IP地址不能为空', 'error');
                return;
            }
            
            const submitBtn = event.target.querySelector('button[type="submit"]');
            submitBtn.disabled = true;
            submitBtn.textContent = '保存中...';
            
            try {
                let url = '/api/system/access/whitelist';
                let method = 'POST';
                
                if (editingId) {
                    url = '/api/system/access/whitelist/' + editingId;
                    method = 'PUT';
                }
                
                const params = new URLSearchParams({
                    ip_address: ipAddress,
                    description: description
                });
                
                const response = await fetch(url, {
                    method: method,
                    headers: {
                        'Content-Type': 'application/x-www-form-urlencoded',
                    },
                    body: params.toString()
                });
                
                // 检查响应状态
                if (!response.ok) {
                    // 如果是401错误，自动刷新页面
                    if (response.status === 401) {
                        window.location.reload();
                        return; // 不继续执行
                    }
                    
                    // 如果是403错误，说明当前IP已被拒绝访问，需要刷新页面
                    if (response.status === 403) {
                        showAlert('系统白名单已启用，当前IP不在白名单中，页面将自动刷新', 'warning');
                        setTimeout(() => {
                            window.location.reload();
                        }, 2000);
                        return;
                    }
                    
                    // 尝试解析错误响应
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
                    // 检查是否需要刷新页面（系统白名单已启用，但当前IP不在白名单中）
                    if (data.requires_refresh) {
                        showAlert(data.warning || '系统白名单已启用，当前IP不在白名单中，页面将自动刷新', 'warning');
                        setTimeout(() => {
                            window.location.reload();
                        }, 2000);
                        return;
                    }
                    
                    showAlert(editingId ? '更新成功' : '创建成功', 'success');
                    closeEditModal();
                    loadWhitelist(currentPage);
                } else {
                    showAlert(data.error || '操作失败', 'error');
                }
            } catch (error) {
                console.error('saveWhitelist error:', error);
                // 检查是否是JSON解析错误（可能是403 HTML页面）
                if (error.message && error.message.includes('JSON')) {
                    showAlert('系统白名单已启用，当前IP不在白名单中，页面将自动刷新', 'warning');
                    setTimeout(() => {
                        window.location.reload();
                    }, 2000);
                } else {
                    showAlert('网络错误: ' + error.message, 'error');
                }
            } finally {
                submitBtn.disabled = false;
                submitBtn.textContent = '保存';
            }
        }
        
        // 删除白名单
        async function deleteWhitelist(id) {
            if (!confirm('确定要删除这条白名单记录吗？')) {
                return;
            }
            
            try {
                const response = await fetch('/api/system/access/whitelist/' + id, {
                    method: 'DELETE'
                });
                
                const data = await response.json();
                
                if (data.success) {
                    showAlert('删除成功', 'success');
                    loadWhitelist(currentPage);
                } else {
                    showAlert(data.error || '删除失败', 'error');
                }
            } catch (error) {
                console.error('deleteWhitelist error:', error);
                showAlert('网络错误: ' + error.message, 'error');
            }
        }
        
        // 关闭编辑模态框
        function closeEditModal() {
            const modal = document.getElementById('edit-modal');
            modal.classList.remove('show');
            // 恢复样式
            modal.style.display = 'none';
            // 恢复body滚动
            document.body.style.overflow = '';
            editingId = null;
        }
        
        // 应用筛选
        function applyFilters() {
            loadWhitelist(1);
        }
        
        // 重置筛选
        function resetFilters() {
            document.getElementById('filter-status').value = '';
            loadWhitelist(1);
        }
        
        // 切换白名单状态
        async function toggleWhitelistStatus(id, newStatus) {
            const statusText = newStatus == 1 ? '启用' : '禁用';
            if (!confirm(`确定要${statusText}这条白名单记录吗？`)) {
                return;
            }
            
            try {
                const response = await fetch('/api/system/access/whitelist/' + id, {
                    method: 'PUT',
                    headers: {
                        'Content-Type': 'application/x-www-form-urlencoded',
                    },
                    body: `status=${newStatus}`
                });
                
                const data = await response.json();
                
                if (data.success) {
                    showAlert(`${statusText}成功`, 'success');
                    loadWhitelist(currentPage);
                } else {
                    showAlert(data.error || `${statusText}失败`, 'error');
                }
            } catch (error) {
                console.error('toggleWhitelistStatus error:', error);
                showAlert('网络错误: ' + error.message, 'error');
            }
        }
        
        // HTML转义
        function escapeHtml(text) {
            if (!text) return '';
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }
        
        // 页面加载时初始化
        window.addEventListener('DOMContentLoaded', function() {
            loadWhitelist();
            
            // 点击模态框外部关闭
            window.onclick = function(event) {
                const modal = document.getElementById('edit-modal');
                if (event.target == modal) {
                    closeEditModal();
                }
            }
            
            // 监听ESC键关闭模态框
            document.addEventListener('keydown', function(event) {
                if (event.key === 'Escape') {
                    const modal = document.getElementById('edit-modal');
                    if (modal.classList.contains('show')) {
                        closeEditModal();
                    }
                }
            });
        });