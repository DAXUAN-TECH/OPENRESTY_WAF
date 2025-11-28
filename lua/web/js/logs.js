// 当前页数据
        let currentTab = 'access';
        let accessPage = 1;
        let blockPage = 1;
        let auditPage = 1;
        
        // 标签切换
        document.querySelectorAll('.tab').forEach(tab => {
            tab.addEventListener('click', function() {
                document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
                document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
                this.classList.add('active');
                const tabId = this.getAttribute('data-tab');
                document.getElementById(tabId + '-tab').classList.add('active');
                currentTab = tabId;
                
                // 加载对应标签的数据
                if (tabId === 'access') {
                    loadAccessLogs();
                } else if (tabId === 'block') {
                    loadBlockLogs();
                } else if (tabId === 'audit') {
                    loadAuditLogs();
                }
            });
        });
        
        // 加载访问日志
        function loadAccessLogs(page = 1) {
            accessPage = page;
            const loading = document.getElementById('access-loading');
            const error = document.getElementById('access-error');
            const tbody = document.getElementById('access-tbody');
            const pagination = document.getElementById('access-pagination');
            
            loading.style.display = 'block';
            error.style.display = 'none';
            tbody.innerHTML = '';
            pagination.innerHTML = '';
            
            const params = new URLSearchParams({
                page: page,
                page_size: 50
            });
            
            const clientIp = document.getElementById('access-client-ip').value;
            const domain = document.getElementById('access-domain').value;
            const path = document.getElementById('access-path').value;
            const status = document.getElementById('access-status').value;
            const startTime = document.getElementById('access-start-time').value;
            const endTime = document.getElementById('access-end-time').value;
            
            if (clientIp) params.append('client_ip', clientIp);
            if (domain) params.append('request_domain', domain);
            if (path) params.append('request_path', path);
            if (status) params.append('status_code', status);
            if (startTime) params.append('start_time', startTime.replace('T', ' '));
            if (endTime) params.append('end_time', endTime.replace('T', ' '));
            
            fetch('/api/logs/access?' + params.toString())
                .then(res => res.json())
                .then(data => {
                    loading.style.display = 'none';
                    if (data.error) {
                        error.textContent = data.message || data.error;
                        error.style.display = 'block';
                        return;
                    }
                    
                    if (data.data && data.data.length > 0) {
                        data.data.forEach(log => {
                            const row = document.createElement('tr');
                            const statusClass = getStatusClass(log.status_code);
                            row.innerHTML = `
                                <td>${log.request_time || ''}</td>
                                <td>${log.client_ip || ''}</td>
                                <td>${log.request_domain || '-'}</td>
                                <td>${log.request_path || ''}</td>
                                <td>${log.request_method || ''}</td>
                                <td><span class="status-code ${statusClass}">${log.status_code || ''}</span></td>
                                <td>${log.response_time ? log.response_time + 'ms' : '-'}</td>
                                <td title="${log.user_agent || ''}">${truncate(log.user_agent, 50) || '-'}</td>
                            `;
                            tbody.appendChild(row);
                        });
                        
                        renderPagination(pagination, data.pagination, loadAccessLogs);
                    } else {
                        tbody.innerHTML = '<tr><td colspan="8" class="empty">暂无数据</td></tr>';
                    }
                    // 数据加载后强制设置表格宽度
                    setTimeout(forceTableWidths, 50);
                })
                .catch(err => {
                    loading.style.display = 'none';
                    error.textContent = '加载失败: ' + err.message;
                    error.style.display = 'block';
                });
        }
        
        // 加载封控日志
        function loadBlockLogs(page = 1) {
            blockPage = page;
            const loading = document.getElementById('block-loading');
            const error = document.getElementById('block-error');
            const tbody = document.getElementById('block-tbody');
            const pagination = document.getElementById('block-pagination');
            
            loading.style.display = 'block';
            error.style.display = 'none';
            tbody.innerHTML = '';
            pagination.innerHTML = '';
            
            const params = new URLSearchParams({
                page: page,
                page_size: 50
            });
            
            const clientIp = document.getElementById('block-client-ip').value;
            const reason = document.getElementById('block-reason').value;
            const ruleName = document.getElementById('block-rule-name').value;
            const startTime = document.getElementById('block-start-time').value;
            const endTime = document.getElementById('block-end-time').value;
            
            if (clientIp) params.append('client_ip', clientIp);
            if (reason) params.append('block_reason', reason);
            if (ruleName) params.append('rule_name', ruleName);
            if (startTime) params.append('start_time', startTime.replace('T', ' '));
            if (endTime) params.append('end_time', endTime.replace('T', ' '));
            
            fetch('/api/logs/block?' + params.toString())
                .then(res => res.json())
                .then(data => {
                    loading.style.display = 'none';
                    if (data.error) {
                        error.textContent = data.message || data.error;
                        error.style.display = 'block';
                        return;
                    }
                    
                    if (data.data && data.data.length > 0) {
                        data.data.forEach(log => {
                            const row = document.createElement('tr');
                            row.innerHTML = `
                                <td>${log.block_time || ''}</td>
                                <td>${log.client_ip || ''}</td>
                                <td>${log.rule_name || '-'}</td>
                                <td>${getBlockReasonText(log.block_reason)}</td>
                                <td>${log.request_path || '-'}</td>
                                <td title="${log.user_agent || ''}">${truncate(log.user_agent, 50) || '-'}</td>
                            `;
                            tbody.appendChild(row);
                        });
                        
                        renderPagination(pagination, data.pagination, loadBlockLogs);
                    } else {
                        tbody.innerHTML = '<tr><td colspan="6" class="empty">暂无数据</td></tr>';
                    }
                    // 数据加载后强制设置表格宽度
                    setTimeout(forceTableWidths, 50);
                })
                .catch(err => {
                    loading.style.display = 'none';
                    error.textContent = '加载失败: ' + err.message;
                    error.style.display = 'block';
                });
        }
        
        // 加载审计日志
        function loadAuditLogs(page = 1) {
            auditPage = page;
            const loading = document.getElementById('audit-loading');
            const error = document.getElementById('audit-error');
            const tbody = document.getElementById('audit-tbody');
            const pagination = document.getElementById('audit-pagination');
            
            loading.style.display = 'block';
            error.style.display = 'none';
            tbody.innerHTML = '';
            pagination.innerHTML = '';
            
            const params = new URLSearchParams({
                page: page,
                page_size: 50
            });
            
            const username = document.getElementById('audit-username').value;
            const actionType = document.getElementById('audit-action-type').value;
            const resourceType = document.getElementById('audit-resource-type').value;
            const status = document.getElementById('audit-status').value;
            const startTime = document.getElementById('audit-start-time').value;
            const endTime = document.getElementById('audit-end-time').value;
            
            if (username) params.append('username', username);
            if (actionType) params.append('action_type', actionType);
            if (resourceType) params.append('resource_type', resourceType);
            if (status) params.append('status', status);
            if (startTime) params.append('start_time', startTime.replace('T', ' '));
            if (endTime) params.append('end_time', endTime.replace('T', ' '));
            
            fetch('/api/logs/audit?' + params.toString())
                .then(res => res.json())
                .then(data => {
                    loading.style.display = 'none';
                    if (data.error) {
                        error.textContent = data.message || data.error;
                        error.style.display = 'block';
                        return;
                    }
                    
                    if (data.data && data.data.length > 0) {
                        data.data.forEach(log => {
                            const row = document.createElement('tr');
                            const statusClass = log.status === 'success' ? 'status-2xx' : 
                                               log.status === 'failed' ? 'status-4xx' : 'status-5xx';
                            row.innerHTML = `
                                <td>${log.created_at || ''}</td>
                                <td>${log.username || '-'}</td>
                                <td>${log.action_type || ''}</td>
                                <td>${log.resource_type || '-'}</td>
                                <td title="${log.action_description || ''}">${truncate(log.action_description, 50) || '-'}</td>
                                <td><span class="status-code ${statusClass}">${getStatusText(log.status)}</span></td>
                                <td>${log.ip_address || '-'}</td>
                            `;
                            tbody.appendChild(row);
                        });
                        
                        renderPagination(pagination, data.pagination, loadAuditLogs);
                    } else {
                        tbody.innerHTML = '<tr><td colspan="7" class="empty">暂无数据</td></tr>';
                    }
                    // 数据加载后强制设置表格宽度
                    setTimeout(forceTableWidths, 50);
                })
                .catch(err => {
                    loading.style.display = 'none';
                    error.textContent = '加载失败: ' + err.message;
                    error.style.display = 'block';
                });
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
            
            // 添加跳转页数输入框
            const jumpContainer = document.createElement('span');
            jumpContainer.style.cssText = 'display: inline-flex; align-items: center; gap: 5px; margin: 0 10px;';
            
            const jumpLabel = document.createElement('span');
            jumpLabel.textContent = '跳转到';
            jumpLabel.style.cssText = 'font-size: 14px; color: #666;';
            
            const jumpInput = document.createElement('input');
            jumpInput.type = 'number';
            jumpInput.min = 1;
            jumpInput.max = pagination.total_pages;
            jumpInput.value = pagination.page;
            jumpInput.style.cssText = 'width: 60px; padding: 5px; border: 1px solid #ddd; border-radius: 4px; text-align: center;';
            
            const jumpBtn = document.createElement('button');
            jumpBtn.className = 'pagination-btn';
            jumpBtn.textContent = '跳转';
            jumpBtn.style.cssText = 'padding: 5px 15px; font-size: 14px;';
            jumpBtn.onclick = () => {
                const targetPage = parseInt(jumpInput.value);
                if (targetPage >= 1 && targetPage <= pagination.total_pages) {
                    loadFn(targetPage);
                } else {
                    alert(`请输入1到${pagination.total_pages}之间的页数`);
                    jumpInput.value = pagination.page;
                }
            };
            
            // 回车键跳转
            jumpInput.onkeypress = (e) => {
                if (e.key === 'Enter') {
                    jumpBtn.onclick();
                }
            };
            
            jumpContainer.appendChild(jumpLabel);
            jumpContainer.appendChild(jumpInput);
            jumpContainer.appendChild(jumpBtn);
            
            const nextBtn = document.createElement('button');
            nextBtn.className = 'pagination-btn';
            nextBtn.textContent = '下一页';
            nextBtn.disabled = pagination.page >= pagination.total_pages;
            nextBtn.onclick = () => loadFn(pagination.page + 1);
            
            controls.appendChild(prevBtn);
            controls.appendChild(jumpContainer);
            controls.appendChild(nextBtn);
            
            container.appendChild(info);
            container.appendChild(controls);
        }
        
        // 工具函数
        function getStatusClass(code) {
            if (!code) return '';
            if (code >= 200 && code < 300) return 'status-2xx';
            if (code >= 300 && code < 400) return 'status-3xx';
            if (code >= 400 && code < 500) return 'status-4xx';
            if (code >= 500) return 'status-5xx';
            return '';
        }
        
        function getBlockReasonText(reason) {
            const map = {
                'manual': '手动封控',
                'auto_frequency': '自动频率封控',
                'auto_error': '自动错误率封控',
                'auto_scan': '自动扫描封控'
            };
            return map[reason] || reason;
        }
        
        function getStatusText(status) {
            const map = {
                'success': '成功',
                'failed': '失败',
                'error': '错误'
            };
            return map[status] || status;
        }
        
        function truncate(str, len) {
            if (!str) return '';
            return str.length > len ? str.substring(0, len) + '...' : str;
        }
        
        // 重置过滤器
        function resetAccessFilters() {
            document.getElementById('access-client-ip').value = '';
            document.getElementById('access-domain').value = '';
            document.getElementById('access-path').value = '';
            document.getElementById('access-status').value = '';
            document.getElementById('access-start-time').value = '';
            document.getElementById('access-end-time').value = '';
            loadAccessLogs(1);
        }
        
        function resetBlockFilters() {
            document.getElementById('block-client-ip').value = '';
            document.getElementById('block-reason').value = '';
            document.getElementById('block-rule-name').value = '';
            document.getElementById('block-start-time').value = '';
            document.getElementById('block-end-time').value = '';
            loadBlockLogs(1);
        }
        
        function resetAuditFilters() {
            document.getElementById('audit-username').value = '';
            document.getElementById('audit-action-type').value = '';
            document.getElementById('audit-resource-type').value = '';
            document.getElementById('audit-status').value = '';
            document.getElementById('audit-start-time').value = '';
            document.getElementById('audit-end-time').value = '';
            loadAuditLogs(1);
        }
        
        // 强制设置表格相关元素的宽度，确保对齐
        // 直接计算并设置固定宽度，不依赖CSS的100%，避免CSS冲突
        function forceTableWidths() {
            // 获取content-area
            const contentArea = document.querySelector('.content-area');
            if (!contentArea) {
                // 如果content-area还没加载，延迟重试
                setTimeout(forceTableWidths, 100);
                return;
            }
            
            // 获取content-area的实际宽度（包括padding）
            const contentAreaRect = contentArea.getBoundingClientRect();
            let contentAreaWidth = contentAreaRect.width;
            
            // 如果content-area宽度为0或无效，尝试从CSS变量计算
            if (contentAreaWidth <= 0) {
                const sidebarWidth = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--sidebar-width')) || 200;
                contentAreaWidth = window.innerWidth - sidebarWidth;
            }
            
            // 如果还是无效，延迟重试
            if (contentAreaWidth <= 0) {
                setTimeout(forceTableWidths, 100);
                return;
            }
            
            // 获取container
            const container = document.querySelector('.container');
            if (!container) {
                setTimeout(forceTableWidths, 100);
                return;
            }
            
            // container使用box-sizing: border-box，所以宽度已经包含padding
            // container的宽度应该是contentAreaWidth（100%相对于content-area）
            // 先清除可能存在的内联样式
            container.style.removeProperty('width');
            container.style.removeProperty('max-width');
            container.style.removeProperty('min-width');
            // container使用100%宽度，让CSS来处理
            container.style.setProperty('width', '100%', 'important');
            container.style.setProperty('max-width', '100%', 'important');
            container.style.setProperty('min-width', '100%', 'important');
            
            // 获取container的实际内容宽度（减去padding，因为box-sizing: border-box）
            // container的实际宽度 = contentAreaWidth（因为100%）
            // container的内容宽度 = container实际宽度 - padding（左右各30px）
            const containerRect = container.getBoundingClientRect();
            const containerActualWidth = containerRect.width;
            const containerPadding = 30 * 2; // 左右各30px
            const containerContentWidth = containerActualWidth - containerPadding;
            
            // 强制设置所有tab-content的宽度（使用container的内容宽度，不包含padding）
            document.querySelectorAll('.tab-content').forEach(tabContent => {
                tabContent.style.removeProperty('width');
                tabContent.style.removeProperty('max-width');
                tabContent.style.removeProperty('min-width');
                tabContent.style.setProperty('width', containerContentWidth + 'px', 'important');
                tabContent.style.setProperty('max-width', containerContentWidth + 'px', 'important');
                tabContent.style.setProperty('min-width', containerContentWidth + 'px', 'important');
            });
            
            // 强制设置所有table-container的宽度（使用container的内容宽度）
            document.querySelectorAll('.table-container').forEach(tableContainer => {
                tableContainer.style.removeProperty('width');
                tableContainer.style.removeProperty('max-width');
                tableContainer.style.removeProperty('min-width');
                tableContainer.style.setProperty('width', containerContentWidth + 'px', 'important');
                tableContainer.style.setProperty('max-width', containerContentWidth + 'px', 'important');
                tableContainer.style.setProperty('min-width', containerContentWidth + 'px', 'important');
            });
            
            // 强制设置所有table-wrapper的宽度（使用container的内容宽度）
            document.querySelectorAll('.table-wrapper').forEach(tableWrapper => {
                tableWrapper.style.removeProperty('width');
                tableWrapper.style.removeProperty('max-width');
                tableWrapper.style.removeProperty('min-width');
                tableWrapper.style.setProperty('width', containerContentWidth + 'px', 'important');
                tableWrapper.style.setProperty('max-width', containerContentWidth + 'px', 'important');
                tableWrapper.style.setProperty('min-width', containerContentWidth + 'px', 'important');
            });
            
            // 强制设置所有表格的宽度（使用container的内容宽度）
            document.querySelectorAll('#access-table, #block-table, #audit-table').forEach(table => {
                table.style.removeProperty('width');
                table.style.removeProperty('max-width');
                table.style.removeProperty('min-width');
                table.style.setProperty('width', containerContentWidth + 'px', 'important');
                table.style.setProperty('max-width', containerContentWidth + 'px', 'important');
                table.style.setProperty('min-width', containerContentWidth + 'px', 'important');
            });
        }
        
        // 使用MutationObserver监听DOM变化，确保新创建的元素也能正确设置宽度
        if (typeof MutationObserver !== 'undefined') {
            const observer = new MutationObserver(function(mutations) {
                // 检查是否有新的表格元素被创建
                const hasNewTables = document.querySelectorAll('#access-table, #block-table, #audit-table').length > 0;
                const hasTableContainers = document.querySelectorAll('.table-container').length > 0;
                if (hasNewTables || hasTableContainers) {
                    setTimeout(forceTableWidths, 50);
                }
            });
            
            // 观察content-area的变化
            const contentArea = document.querySelector('.content-area');
            if (contentArea) {
                observer.observe(contentArea, {
                    childList: true,
                    subtree: true
                });
            } else {
                // 如果content-area还没加载，等待DOMContentLoaded
                document.addEventListener('DOMContentLoaded', function() {
                    const contentArea = document.querySelector('.content-area');
                    if (contentArea) {
                        observer.observe(contentArea, {
                            childList: true,
                            subtree: true
                        });
                    }
                });
            }
        }
        
        // 页面加载时初始化
        window.addEventListener('DOMContentLoaded', function() {
            // 时间筛选默认为空，不设置默认时间范围
            // 用户可以根据需要自行设置时间范围进行筛选
            
            // 等待layout-ready类添加后再设置宽度
            const checkLayoutReady = setInterval(function() {
                const contentArea = document.querySelector('.content-area.layout-ready');
                if (contentArea) {
                    clearInterval(checkLayoutReady);
                    // layout-ready后立即设置宽度
                    forceTableWidths();
                    setTimeout(forceTableWidths, 50);
                    setTimeout(forceTableWidths, 100);
                    setTimeout(forceTableWidths, 200);
                    setTimeout(forceTableWidths, 500);
                }
            }, 50);
            
            // 强制设置表格宽度（不等待layout-ready）
            forceTableWidths();
            
            // 延迟再次设置，确保所有元素都已渲染
            setTimeout(forceTableWidths, 100);
            setTimeout(forceTableWidths, 300);
            setTimeout(forceTableWidths, 500);
            setTimeout(forceTableWidths, 1000);
            
            // 窗口大小改变时重新设置
            window.addEventListener('resize', function() {
                setTimeout(forceTableWidths, 100);
            });
            
            // 加载访问日志
            loadAccessLogs();
        });
        
        // 在layout-ready后也设置一次
        if (document.readyState === 'complete' || document.readyState === 'interactive') {
            setTimeout(forceTableWidths, 100);
            setTimeout(forceTableWidths, 500);
        }
        
        // 监听layout-ready类的添加
        if (typeof MutationObserver !== 'undefined') {
            const layoutObserver = new MutationObserver(function(mutations) {
                mutations.forEach(function(mutation) {
                    if (mutation.type === 'attributes' && mutation.attributeName === 'class') {
                        const target = mutation.target;
                        if (target.classList && target.classList.contains('layout-ready')) {
                            // layout-ready类添加后，立即设置宽度
                            setTimeout(forceTableWidths, 10);
                            setTimeout(forceTableWidths, 50);
                            setTimeout(forceTableWidths, 100);
                        }
                    }
                });
            });
            
            // 观察content-area的class变化
            const contentArea = document.querySelector('.content-area');
            if (contentArea) {
                layoutObserver.observe(contentArea, {
                    attributes: true,
                    attributeFilter: ['class']
                });
            } else {
                document.addEventListener('DOMContentLoaded', function() {
                    const contentArea = document.querySelector('.content-area');
                    if (contentArea) {
                        layoutObserver.observe(contentArea, {
                            attributes: true,
                            attributeFilter: ['class']
                        });
                    }
                });
            }
        }