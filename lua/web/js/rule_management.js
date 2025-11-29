let currentPage = 1;
        const pageSize = 20;
        let validityTimer = null;
        
        // 切换标签页
        function switchTab(tab) {
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            document.querySelectorAll('.tab-content').forEach(c => {
                c.classList.remove('active');
                c.style.display = 'none'; // 确保隐藏
            });
            
            if (tab === 'rules') {
                document.querySelectorAll('.tab')[0].classList.add('active');
                const rulesTab = document.getElementById('rules-tab');
                rulesTab.classList.add('active');
                rulesTab.style.display = 'block'; // 确保显示
                loadRules();
            } else if (tab === 'create') {
                document.querySelectorAll('.tab')[1].classList.add('active');
                const createTab = document.getElementById('create-tab');
                createTab.classList.add('active');
                createTab.style.display = 'block'; // 确保显示
            }
        }
        
        // 应用筛选
        function applyFilters() {
            loadRules(1); // 重置到第一页并应用筛选
        }
        
        // 重置筛选
        function resetFilters() {
            document.getElementById('filter-type').value = '';
            document.getElementById('filter-status').value = '';
            document.getElementById('filter-group').value = '';
            document.getElementById('search-input').value = '';
            loadRules(1); // 重置到第一页并重新加载
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
        
        function formatDuration(totalSeconds) {
            if (totalSeconds <= 0) {
                return '已过期';
            }
            const days = Math.floor(totalSeconds / 86400);
            const hours = Math.floor((totalSeconds % 86400) / 3600);
            const minutes = Math.floor((totalSeconds % 3600) / 60);
            const seconds = totalSeconds % 60;
            return `${days}天${hours}时${minutes}分${seconds}秒`;
        }

        function initValidityCountdown() {
            // 清理旧的定时器，避免重复累积
            if (validityTimer) {
                clearInterval(validityTimer);
                validityTimer = null;
            }

            const cells = document.querySelectorAll('.validity-cell');
            if (!cells || cells.length === 0) {
                return;
            }

            validityTimer = setInterval(() => {
                cells.forEach(cell => {
                    const remainingAttr = cell.getAttribute('data-remaining');
                    if (remainingAttr === null || remainingAttr === '') {
                        // 无剩余时间（如永久有效），不做动态更新
                        return;
                    }
                    let remaining = parseInt(remainingAttr, 10);
                    if (isNaN(remaining)) {
                        return;
                    }
                    remaining -= 1;
                    cell.setAttribute('data-remaining', String(remaining));
                    cell.textContent = formatDuration(remaining);
                });
            }, 1000);
        }

        // 加载规则列表
        async function loadRules(page = 1) {
            currentPage = page;
            const ruleType = document.getElementById('filter-type').value;
            const status = document.getElementById('filter-status').value;
            const ruleGroup = document.getElementById('filter-group').value;
            
            let url = `/api/rules?page=${page}&page_size=${pageSize}`;
            if (ruleType) url += `&rule_type=${ruleType}`;
            if (status) url += `&status=${status}`;
            if (ruleGroup) url += `&rule_group=${encodeURIComponent(ruleGroup)}`;
            
            try {
                // 显示加载状态
                const tbody = document.getElementById('rules-tbody');
                tbody.innerHTML = '<tr><td colspan="10" style="text-align: center; padding: 20px;">加载中...</td></tr>';
                
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
                
                // 防御性检查：确保数据结构正确
                if (!data || typeof data !== 'object') {
                    throw new Error('响应数据格式错误：不是有效的JSON对象');
                }
                
                if (data.success) {
                    // 确保 data.data 存在且包含 rules 数组
                    if (!data.data) {
                        console.error('API response missing data field:', data);
                        console.error('Full response:', JSON.stringify(data, null, 2));
                        showAlert('响应数据格式错误：缺少 data 字段', 'error');
                        renderRulesTable([]);  // 确保更新表格，隐藏"加载中"
                        return;
                    }
                    
                    // 如果 data.data 存在但没有 rules 字段，使用空数组
                    if (!data.data.hasOwnProperty('rules')) {
                        console.warn('API response missing rules field, using empty array');
                        renderRulesTable([]);
                        if (data.data.total !== undefined) {
                            renderPagination(data.data, 'pagination', loadRules);
                        }
                        return;
                    }
                    
                    // 确保 rules 是数组
                    const rules = data.data.rules;
                    console.log('=== Rules Data Debug ===');
                    console.log('Received rules type:', typeof rules);
                    console.log('Is Array:', Array.isArray(rules));
                    console.log('Rules value:', rules);
                    console.log('Rules JSON:', JSON.stringify(rules, null, 2));
                    console.log('Full data.data:', JSON.stringify(data.data, null, 2));
                    console.log('Full response:', JSON.stringify(data, null, 2));
                    console.log('========================');
                    
                    if (rules === undefined || rules === null) {
                        console.error('API response rules is undefined or null');
                        showAlert('响应数据格式错误：rules 字段不存在', 'error');
                        renderRulesTable([]);  // 确保更新表格，隐藏"加载中"
                        return;
                    }
                    
                    // 处理各种可能的格式
                    let rulesArray = [];
                    
                    if (Array.isArray(rules)) {
                        // 已经是数组，直接使用
                        rulesArray = rules;
                    } else if (typeof rules === 'object') {
                        // 是对象，尝试转换
                        const keys = Object.keys(rules);
                        console.log('Object keys:', keys);
                        
                        if (keys.length === 0) {
                            // 空对象，转换为空数组
                            rulesArray = [];
                        } else {
                            // 检查是否是数字键（可能是序列化的数组对象）
                            const numericKeys = keys.filter(k => {
                                const num = parseInt(k);
                                return !isNaN(num) && num.toString() === k && num >= 0;
                            });
                            
                            if (numericKeys.length > 0) {
                                // 有数字键，按数字排序后转换为数组
                                numericKeys.sort((a, b) => parseInt(a) - parseInt(b));
                                rulesArray = numericKeys.map(k => rules[k]);
                                console.log('Converted object with numeric keys to array:', rulesArray);
                            } else if (keys.length === 1 && keys[0] === '0') {
                                // 特殊情况：只有 '0' 键
                                rulesArray = [rules['0']];
                                console.log('Converted object with single "0" key to array:', rulesArray);
                            } else {
                                // 非数字键，可能是单个规则对象，包装成数组
                                rulesArray = [rules];
                                console.log('Wrapped single object in array:', rulesArray);
                            }
                        }
                    } else {
                        // 既不是数组也不是对象
                        console.error('Rules is neither array nor object, type:', typeof rules);
                        showAlert('响应数据格式错误：rules 类型不正确 (' + typeof rules + ')', 'error');
                        renderRulesTable([]);  // 确保更新表格，隐藏"加载中"
                        return;
                    }
                    
                    // 验证转换后的数组
                    if (!Array.isArray(rulesArray)) {
                        console.error('Failed to convert rules to array, final type:', typeof rulesArray);
                        showAlert('响应数据格式错误：无法将 rules 转换为数组', 'error');
                        renderRulesTable([]);  // 确保更新表格，隐藏"加载中"
                        return;
                    }
                    
                    console.log('Final rules array length:', rulesArray.length);
                    
                    // 使用转换后的数组
                    renderRulesTable(rulesArray);
                    renderPagination(data.data, 'pagination', loadRules);
                } else {
                    // API 返回失败，显示错误并更新表格
                    const errorMsg = data.error || data.message || '加载失败';
                    console.error('API returned error:', errorMsg, data);
                    showAlert(errorMsg, 'error');
                    // 确保更新表格，隐藏"加载中"
                    const tbody = document.getElementById('rules-tbody');
                    // 防御性检查：确保 escapeHtml 函数可用
                    const escapeHtmlFn = window.escapeHtml || function(text) {
                        if (!text) return '';
                        const div = document.createElement('div');
                        div.textContent = text;
                        return div.innerHTML;
                    };
                    tbody.innerHTML = '<tr><td colspan="9" style="text-align: center; padding: 20px; color: #e74c3c;">' + escapeHtmlFn(errorMsg) + '</td></tr>';
                }
            } catch (error) {
                console.error('loadRules error:', error);
                showAlert('网络错误: ' + error.message, 'error');
                // 显示错误信息
                const tbody = document.getElementById('rules-tbody');
                // 防御性检查：确保 escapeHtml 函数可用
                const escapeHtmlFn = window.escapeHtml || function(text) {
                    if (!text) return '';
                    const div = document.createElement('div');
                    div.textContent = text;
                    return div.innerHTML;
                };
                tbody.innerHTML = '<tr><td colspan="9" style="text-align: center; padding: 20px; color: #e74c3c;">加载失败: ' + escapeHtmlFn(error.message) + '</td></tr>';
            }
        }
        
        // 渲染规则表格
        function renderRulesTable(rules) {
            const tbody = document.getElementById('rules-tbody');
            
            // 防御性检查：确保 rules 是数组，如果不是则尝试转换
            if (!rules) {
                tbody.innerHTML = '<tr><td colspan="10" style="text-align: center; padding: 20px;">暂无数据</td></tr>';
                return;
            }
            
            // 如果不是数组，尝试转换
            if (!Array.isArray(rules)) {
                console.warn('renderRulesTable: rules is not an array, attempting conversion', rules);
                
                let rulesArray = [];
                if (typeof rules === 'object') {
                    // 尝试从对象转换为数组
                    const keys = Object.keys(rules);
                    const numericKeys = keys.filter(k => {
                        const num = parseInt(k);
                        return !isNaN(num) && num.toString() === k && num >= 0;
                    });
                    
                    if (numericKeys.length > 0) {
                        numericKeys.sort((a, b) => parseInt(a) - parseInt(b));
                        rulesArray = numericKeys.map(k => rules[k]);
                    } else if (keys.length > 0) {
                        // 非数字键，可能是单个对象，包装成数组
                        rulesArray = [rules];
                    }
                }
                
                if (Array.isArray(rulesArray) && rulesArray.length > 0) {
                    rules = rulesArray;
                    console.log('Successfully converted rules to array in renderRulesTable');
                } else {
                    tbody.innerHTML = '<tr><td colspan="9" style="text-align: center; padding: 20px; color: #e74c3c;">数据格式错误：规则列表不是数组</td></tr>';
                    console.error('renderRulesTable: failed to convert rules to array', rules);
                    return;
                }
            }
            
            if (rules.length === 0) {
                tbody.innerHTML = '<tr><td colspan="10" style="text-align: center; padding: 20px;">暂无数据</td></tr>';
                // 清理倒计时（无数据）
                if (validityTimer) {
                    clearInterval(validityTimer);
                    validityTimer = null;
                }
                return;
            }
            
            tbody.innerHTML = rules.map(rule => `
                <tr>
                    <td>${rule.id}</td>
                    <td>${rule.rule_name}</td>
                    <td>${getRuleTypeName(rule.rule_type)}</td>
                    <td>${rule.rule_value}</td>
                    <td>${rule.rule_group || '<span style="color: #999;">未分组</span>'}</td>
                    <td>${rule.priority}</td>
                    <td>${getStatusBadge(rule.status)}</td>
                    <td class="validity-cell" data-remaining="${rule.remaining_seconds !== null && rule.remaining_seconds !== undefined ? rule.remaining_seconds : ''}">
                        ${rule.validity_text || '-'}
                    </td>
                    <td>${formatDateTime(rule.created_at)}</td>
                    <td>
                        <div class="action-buttons">
                            <button class="btn btn-info" onclick="editRule(${rule.id})">编辑</button>
                            ${rule.status == 1 ? 
                                `<button class="btn btn-warning" onclick="disableRule(${rule.id})">禁用</button>` :
                                `<button class="btn btn-primary" onclick="enableRule(${rule.id})">启用</button>`
                            }
                            <button class="btn btn-danger" onclick="deleteRule(${rule.id})">删除</button>
                        </div>
                    </td>
                </tr>
            `).join('');

            // 初始化规则有效期倒计时（前端动态展示，后端仍做一次计算校验）
            initValidityCountdown();
        }
        
        // 创建规则
        async function createRule(event) {
            event.preventDefault();
            
            // 验证规则类型
            const ruleType = document.getElementById('create-rule-type').value;
            if (!ruleType) {
                showAlert('请选择规则类型', 'error');
                // 高亮规则类型按钮组
                const ruleTypeButtons = document.querySelectorAll('.rule-type-btn');
                ruleTypeButtons.forEach(btn => {
                    btn.style.borderColor = '#e74c3c';
                    btn.style.borderWidth = '3px';
                });
                setTimeout(() => {
                    ruleTypeButtons.forEach(btn => {
                        btn.style.borderColor = '';
                        btn.style.borderWidth = '';
                    });
                }, 2000);
                return;
            }
            
            // 验证日期字段
            const startTime = document.getElementById('create-start-time').value;
            const endTime = document.getElementById('create-end-time').value;
            
            if (!startTime) {
                showAlert('请选择开始日期', 'error');
                document.getElementById('create-start-time').focus();
                return;
            }
            
            if (!endTime) {
                showAlert('请选择结束日期', 'error');
                document.getElementById('create-end-time').focus();
                return;
            }
            
            // 校验结束日期不能早于开始日期
            if (new Date(endTime) < new Date(startTime)) {
                showAlert('结束日期不能早于开始日期', 'error');
                document.getElementById('create-end-time').focus();
                return;
            }
            
            const ruleData = {
                rule_type: ruleType,
                rule_value: document.getElementById('create-rule-value').value,
                rule_name: document.getElementById('create-rule-name').value,
                description: document.getElementById('create-description').value,
                rule_group: document.getElementById('create-rule-group').value || null,
                priority: parseInt(document.getElementById('create-priority').value) || 0
            };
            
            if (startTime) ruleData.start_time = startTime.replace('T', ' ') + ':00';
            if (endTime) ruleData.end_time = endTime.replace('T', ' ') + ':00';
            
            try {
                const response = await fetch('/api/rules', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify(ruleData)
                });
                
                const data = await response.json();
                
                if (data.success) {
                    // 显示创建成功提示框
                    showCreateSuccessModal();
                    // 关闭创建规则弹出框
                    closeCreateRuleModal();
                    // 刷新分组列表和规则列表
                    loadGroups();
                    loadRules();
                } else {
                    showAlert(data.error || '创建失败', 'error');
                }
            } catch (error) {
                showAlert('网络错误: ' + error.message, 'error');
            }
        }
        
        // 编辑规则
        async function editRule(id) {
            try {
                const response = await fetch(`/api/rules/${id}`);
                const data = await response.json();
                
                if (data.success) {
                    const rule = data.rule;
                    document.getElementById('edit-id').value = rule.id;
                    document.getElementById('edit-rule-type').value = rule.rule_type;
                    document.getElementById('edit-rule-value').value = rule.rule_value;
                    document.getElementById('edit-rule-name').value = rule.rule_name;
                    document.getElementById('edit-description').value = rule.description || '';
                    document.getElementById('edit-rule-group').value = rule.rule_group || '';
                    document.getElementById('edit-priority').value = rule.priority;
                    
                    if (rule.start_time) {
                        document.getElementById('edit-start-time').value = rule.start_time.replace(' ', 'T').substring(0, 16);
                    }
                    if (rule.end_time) {
                        document.getElementById('edit-end-time').value = rule.end_time.replace(' ', 'T').substring(0, 16);
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
        
        // 更新规则
        async function updateRule(event) {
            event.preventDefault();
            
            const id = document.getElementById('edit-id').value;
            if (!id) {
                showAlert('规则ID不能为空', 'error');
                return;
            }
            
            const ruleValue = document.getElementById('edit-rule-value').value.trim();
            const ruleName = document.getElementById('edit-rule-name').value.trim();
            
            if (!ruleValue) {
                showAlert('规则值不能为空', 'error');
                document.getElementById('edit-rule-value').focus();
                return;
            }
            
            if (!ruleName) {
                showAlert('规则名称不能为空', 'error');
                document.getElementById('edit-rule-name').focus();
                return;
            }
            
            // 禁用保存按钮，防止重复提交
            const submitButton = event.target.querySelector('button[type="submit"]');
            const originalButtonText = submitButton ? submitButton.innerHTML : '';
            if (submitButton) {
                submitButton.disabled = true;
                submitButton.innerHTML = '保存中...';
            }
            
            const ruleData = {
                rule_value: ruleValue,
                rule_name: ruleName,
                description: document.getElementById('edit-description').value || '',
                rule_group: document.getElementById('edit-rule-group').value || '',
                priority: parseInt(document.getElementById('edit-priority').value) || 0
            };
            
            const startTime = document.getElementById('edit-start-time').value;
            const endTime = document.getElementById('edit-end-time').value;
            
            if (startTime) ruleData.start_time = startTime.replace('T', ' ') + ':00';
            else ruleData.start_time = '';
            if (endTime) ruleData.end_time = endTime.replace('T', ' ') + ':00';
            else ruleData.end_time = '';
            
            try {
                const response = await fetch(`/api/rules/${id}`, {
                    method: 'PUT',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify(ruleData)
                });
                
                const data = await response.json();
                
                if (data.success) {
                    showAlert('规则更新成功');
                    closeEditModal();
                    loadRules();
                } else {
                    showAlert(data.error || '更新失败', 'error');
                }
            } catch (error) {
                showAlert('网络错误: ' + error.message, 'error');
            } finally {
                // 恢复按钮状态
                if (submitButton) {
                    submitButton.disabled = false;
                    submitButton.innerHTML = originalButtonText;
                }
            }
        }
        
        // 启用规则
        async function enableRule(id) {
            showConfirmModal('确认启用', '确定要启用该规则吗？', async function() {
                try {
                    const response = await fetch(`/api/rules/${id}/enable`, { method: 'POST' });
                    const data = await response.json();
                    
                    if (data.success) {
                        showAlert('规则已启用');
                        // 保持当前页码和筛选条件重新加载
                        loadRules(currentPage);
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
        
        // 禁用规则
        async function disableRule(id) {
            showConfirmModal('确认禁用', '确定要禁用该规则吗？', async function() {
                try {
                    const response = await fetch(`/api/rules/${id}/disable`, { method: 'POST' });
                    const data = await response.json();
                    
                    if (data.success) {
                        showAlert('规则已禁用');
                        // 保持当前页码和筛选条件重新加载
                        loadRules(currentPage);
                    } else {
                        showAlert(data.error || '操作失败', 'error');
                    }
                } catch (error) {
                    showAlert('网络错误: ' + error.message, 'error');
                }
            });
        }
        
        // 删除规则
        async function deleteRule(id) {
            showConfirmModal('确认删除', '确定要删除该规则吗？此操作不可恢复！', async function() {
                try {
                    const response = await fetch(`/api/rules/${id}`, { method: 'DELETE' });
                    const data = await response.json();
                    
                    if (data.success) {
                        showAlert('规则已删除');
                        loadRules();
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
        
        // 全局变量：存储地域数据
        let geoData = null;
        // 多选支持：使用数组存储多个选择
        let selectedCountries = [];  // [{code, name}]
        let selectedProvinces = [];  // [{code, name, cities: []}]
        let selectedCities = [];    // [{provinceCode, provinceName, city}]
        
        // 选择规则类型
        function selectRuleType(type) {
            // 更新按钮状态
            document.querySelectorAll('.rule-type-btn').forEach(btn => {
                btn.classList.remove('active');
            });
            document.querySelector(`.rule-type-btn[data-type="${type}"]`).classList.add('active');
            
            // 设置隐藏输入框的值
            document.getElementById('create-rule-type').value = type;
            
            // 显示/隐藏地域选择器
            const geoSelector = document.getElementById('geo-selector');
            const ruleValueGroup = document.getElementById('rule-value-group');
            const ruleValueInput = document.getElementById('create-rule-value');
            const ruleValueHint = document.getElementById('rule-value-hint');
            
            // 判断是否为地域类型
            if (type === 'geo_whitelist' || type === 'geo_blacklist') {
                geoSelector.classList.add('active');
                ruleValueInput.style.display = 'none';
                ruleValueHint.style.display = 'none';
                // 加载地域数据
                loadGeoData();
            } else {
                // IP白名单或IP黑名单
                geoSelector.classList.remove('active');
                ruleValueInput.style.display = 'block';
                ruleValueHint.style.display = 'block';
                
                // 清空placeholder，保留提示文本
                ruleValueInput.placeholder = '';
                ruleValueHint.textContent = '支持单个IP（如：192.168.1.100）、多个IP（逗号分隔，如：192.168.1.1,192.168.1.2,192.168.1.3）或IP段（如：192.168.1.0/24 或 192.168.1.1-192.168.1.100）';
            }
            
            // 清空规则值
            ruleValueInput.value = '';
            selectedCountries = [];
            selectedProvinces = [];
            selectedCities = [];
            updateSelectedGeo();
        }
        
        // 切换地域标签（国外/国内）
        function switchGeoTab(tab) {
            document.querySelectorAll('.geo-tab').forEach(t => t.classList.remove('active'));
            document.querySelectorAll('.geo-content').forEach(c => c.classList.remove('active'));
            
            if (tab === 'foreign') {
                document.querySelector('.geo-tab:first-child').classList.add('active');
                document.getElementById('geo-foreign').classList.add('active');
            } else {
                document.querySelector('.geo-tab:last-child').classList.add('active');
                document.getElementById('geo-china').classList.add('active');
            }
            
            // 清空选择
            selectedCountry = null;
            selectedProvince = null;
            selectedCity = null;
            updateSelectedGeo();
        }
        
        // 加载地域数据
        async function loadGeoData() {
            if (geoData) {
                renderGeoData();
                return;
            }
            
            try {
                const response = await fetch('/api/geo/all');
                const data = await response.json();
                
                if (data.success) {
                    geoData = data.data;
                    renderGeoData();
                } else {
                    showAlert('加载地域数据失败: ' + (data.error || 'unknown error'), 'error');
                }
            } catch (error) {
                showAlert('网络错误: ' + error.message, 'error');
            }
        }
        
        // 渲染地域数据
        function renderGeoData() {
            if (!geoData) return;
            
            // 渲染国外国家
            const foreignContainer = document.getElementById('foreign-countries-container');
            foreignContainer.innerHTML = '';
            
            geoData.foreign.forEach(continent => {
                const section = document.createElement('div');
                section.className = 'continent-section';
                section.innerHTML = `
                    <div class="continent-title">${continent.continent}</div>
                    <div class="country-buttons">
                        ${continent.countries.map(country => {
                            const isSelected = selectedCountries.some(c => c.code === country.code);
                            return `
                            <button type="button" class="country-btn ${isSelected ? 'active' : ''}" 
                                    data-code="${country.code}" 
                                    onclick="selectCountry('${country.code}', '${country.name}')">
                                ${country.name}
                            </button>
                        `;
                        }).join('')}
                    </div>
                `;
                foreignContainer.appendChild(section);
            });
            
            // 渲染国内省份
            const chinaContainer = document.getElementById('china-provinces-container');
            chinaContainer.innerHTML = '';
            
            geoData.china.forEach(region => {
                const section = document.createElement('div');
                section.className = 'region-section';
                section.innerHTML = `
                    <div class="region-title">${region.region}</div>
                    <div class="province-buttons">
                        ${region.provinces.map(province => {
                            const isSelected = selectedProvinces.some(p => p.code === province.code);
                            return `
                            <button type="button" class="province-btn ${isSelected ? 'active' : ''}" 
                                    data-code="${province.code}" 
                                    onclick="selectProvince('${province.code}', '${province.name}')">
                                ${province.name}
                            </button>
                        `;
                        }).join('')}
                    </div>
                `;
                chinaContainer.appendChild(section);
            });
        }
        
        // 选择国家（国外）- 支持多选
        function selectCountry(code, name) {
            const btn = document.querySelector(`.country-btn[data-code="${code}"]`);
            const index = selectedCountries.findIndex(c => c.code === code);
            
            if (index >= 0) {
                // 已选中，取消选择
                selectedCountries.splice(index, 1);
                btn.classList.remove('active');
            } else {
                // 未选中，添加到选择列表
                selectedCountries.push({code, name});
                btn.classList.add('active');
            }
            
            // 隐藏城市选择
            document.getElementById('cities-container').style.display = 'none';
            
            updateSelectedGeo();
        }
        
        // 选择省份（国内）- 支持多选
        async function selectProvince(code, name) {
            const btn = document.querySelector(`.province-btn[data-code="${code}"]`);
            const index = selectedProvinces.findIndex(p => p.code === code);
            
            if (index >= 0) {
                // 已选中，取消选择
                selectedProvinces.splice(index, 1);
                // 同时移除该省份下的所有城市选择
                selectedCities = selectedCities.filter(c => c.provinceCode !== code);
                btn.classList.remove('active');
                // 如果当前显示的是该省份的城市，隐藏城市选择
                const currentProvince = document.querySelector('.province-btn.active');
                if (!currentProvince || currentProvince.dataset.code !== code) {
                    document.getElementById('cities-container').style.display = 'none';
                }
            } else {
                // 未选中，添加到选择列表
                selectedProvinces.push({code, name});
                btn.classList.add('active');
                
                // 加载城市列表
                try {
                    const response = await fetch(`/api/geo/cities?province_code=${code}`);
                    const data = await response.json();
                    
                    if (data.success && data.data && data.data.length > 0) {
                        const citiesContainer = document.getElementById('cities-container');
                        const citiesButtons = document.getElementById('cities-buttons');
                        
                        citiesButtons.innerHTML = data.data.map(city => {
                            const isSelected = selectedCities.some(c => c.provinceCode === code && c.city === city);
                            return `
                                <button type="button" class="city-btn ${isSelected ? 'active' : ''}" 
                                        data-city="${city}" 
                                        data-province="${code}"
                                        onclick="selectCity('${code}', '${name}', '${city}')">
                                    ${city}
                                </button>
                            `;
                        }).join('');
                        
                        citiesContainer.style.display = 'block';
                    } else {
                        document.getElementById('cities-container').style.display = 'none';
                    }
                } catch (error) {
                    console.error('Failed to load cities:', error);
                    document.getElementById('cities-container').style.display = 'none';
                }
            }
            
            updateSelectedGeo();
        }
        
        // 选择城市（国内）- 支持多选
        function selectCity(provinceCode, provinceName, city) {
            const btn = document.querySelector(`.city-btn[data-city="${city}"][data-province="${provinceCode}"]`);
            const index = selectedCities.findIndex(c => c.provinceCode === provinceCode && c.city === city);
            
            if (index >= 0) {
                // 已选中，取消选择
                selectedCities.splice(index, 1);
                btn.classList.remove('active');
            } else {
                // 未选中，添加到选择列表
                selectedCities.push({provinceCode, provinceName, city});
                btn.classList.add('active');
            }
            
            updateSelectedGeo();
        }
        
        // 更新选中的地域显示和规则值（支持多选）
        function updateSelectedGeo() {
            const selectedGeoDiv = document.getElementById('selected-geo');
            const selectedGeoList = document.getElementById('selected-geo-list');
            const ruleValueInput = document.getElementById('create-rule-value');
            
            let ruleValues = [];
            let displayItems = [];
            
            // 处理选中的国家
            selectedCountries.forEach(country => {
                ruleValues.push(country.code);
                displayItems.push({
                    type: 'country',
                    code: country.code,
                    name: country.name,
                    display: `${country.name} (${country.code})`
                });
            });
            
            // 处理选中的省份（不包括已选择城市的省份）
            selectedProvinces.forEach(province => {
                const hasCity = selectedCities.some(c => c.provinceCode === province.code);
                if (!hasCity) {
                    ruleValues.push(`CN:${province.code}`);
                    displayItems.push({
                        type: 'province',
                        code: province.code,
                        name: province.name,
                        display: `中国 - ${province.name}`
                    });
                }
            });
            
            // 处理选中的城市
            selectedCities.forEach(city => {
                ruleValues.push(`CN:${city.provinceCode}:${city.city}`);
                displayItems.push({
                    type: 'city',
                    code: city.provinceCode,
                    name: city.city,
                    provinceName: city.provinceName,
                    display: `中国 - ${city.provinceName} - ${city.city}`
                });
            });
            
            // 更新规则值（用逗号分隔）
            if (ruleValues.length > 0) {
                ruleValueInput.value = ruleValues.join(',');
                selectedGeoDiv.style.display = 'block';
                
                // 显示已选择的地域列表
                if (displayItems.length > 0) {
                    selectedGeoList.innerHTML = displayItems.map((item, index) => `
                        <div class="selected-geo-item">
                            <span>${item.display}</span>
                            <button type="button" class="remove-btn" onclick="removeSelectedGeo(${index}, '${item.type}')" title="移除">×</button>
                        </div>
                    `).join('');
                } else {
                    selectedGeoList.innerHTML = '<div class="selected-geo-empty">暂无选择</div>';
                }
            } else {
                ruleValueInput.value = '';
                selectedGeoDiv.style.display = 'none';
                selectedGeoList.innerHTML = '';
            }
        }
        
        // 移除选中的地域
        function removeSelectedGeo(index, type) {
            // 重新构建显示项列表以获取正确的索引
            let displayItems = [];
            
            // 处理选中的国家
            selectedCountries.forEach(country => {
                displayItems.push({type: 'country', code: country.code, name: country.name});
            });
            
            // 处理选中的省份（不包括已选择城市的省份）
            selectedProvinces.forEach(province => {
                const hasCity = selectedCities.some(c => c.provinceCode === province.code);
                if (!hasCity) {
                    displayItems.push({type: 'province', code: province.code, name: province.name});
                }
            });
            
            // 处理选中的城市
            selectedCities.forEach(city => {
                displayItems.push({type: 'city', code: city.provinceCode, name: city.city, provinceName: city.provinceName});
            });
            
            const item = displayItems[index];
            if (!item) return;
            
            if (item.type === 'country') {
                const countryIndex = selectedCountries.findIndex(c => c.code === item.code);
                if (countryIndex >= 0) {
                    selectedCountries.splice(countryIndex, 1);
                    // 更新按钮状态
                    const btn = document.querySelector(`.country-btn[data-code="${item.code}"]`);
                    if (btn) btn.classList.remove('active');
                }
            } else if (item.type === 'province') {
                const provinceIndex = selectedProvinces.findIndex(p => p.code === item.code);
                if (provinceIndex >= 0) {
                    selectedProvinces.splice(provinceIndex, 1);
                    // 更新按钮状态
                    const btn = document.querySelector(`.province-btn[data-code="${item.code}"]`);
                    if (btn) btn.classList.remove('active');
                }
            } else if (item.type === 'city') {
                const cityIndex = selectedCities.findIndex(c => c.provinceCode === item.code && c.city === item.name);
                if (cityIndex >= 0) {
                    selectedCities.splice(cityIndex, 1);
                    // 更新按钮状态
                    const btn = document.querySelector(`.city-btn[data-city="${item.name}"][data-province="${item.code}"]`);
                    if (btn) btn.classList.remove('active');
                }
            }
            
            updateSelectedGeo();
        }
        
        // 重置创建表单
        function resetCreateForm() {
            document.getElementById('create-form').reset();
            // 重置规则类型按钮
            document.querySelectorAll('.rule-type-btn').forEach(btn => {
                btn.classList.remove('active');
            });
            document.getElementById('create-rule-type').value = '';
            // 隐藏地域选择器
            document.getElementById('geo-selector').classList.remove('active');
            const ruleValueInput = document.getElementById('create-rule-value');
            const ruleValueHint = document.getElementById('rule-value-hint');
            ruleValueInput.style.display = 'block';
            ruleValueHint.style.display = 'block';
            ruleValueInput.placeholder = '';
            ruleValueHint.textContent = '支持单个IP（如：192.168.1.100）、多个IP（逗号分隔，如：192.168.1.1,192.168.1.2,192.168.1.3）或IP段（如：192.168.1.0/24 或 192.168.1.1-192.168.1.100）';
            // 重置日期为默认值
            setDefaultDates();
            // 清空地域选择
            selectedCountries = [];
            selectedProvinces = [];
            selectedCities = [];
            document.getElementById('selected-geo').style.display = 'none';
            document.getElementById('selected-geo-list').innerHTML = '';
            document.getElementById('cities-container').style.display = 'none';
            // 重置按钮状态
            document.querySelectorAll('.country-btn, .province-btn, .city-btn').forEach(btn => {
                btn.classList.remove('active');
            });
            // 重置地域标签
            switchGeoTab('foreign');
        }
        
        // 工具函数（使用公共函数，已在 common.js 中定义）
        // escapeHtml、formatDateTime 已在 common.js 中定义
        
        function getRuleTypeName(type) {
            const names = {
                'ip_whitelist': 'IP白名单',
                'ip_blacklist': 'IP黑名单',
                'geo_whitelist': '地域白名单',
                'geo_blacklist': '地域黑名单'
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
        
        // 加载分组列表
        async function loadGroups() {
            try {
                const response = await fetch('/api/rules/groups');
                
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
                
                // 防御性检查：确保数据结构正确
                if (!data || typeof data !== 'object') {
                    console.error('API response is not an object:', data);
                    showAlert('响应数据格式错误', 'error');
                    return;
                }
                
                if (!data.success) {
                    console.error('API response indicates failure:', data);
                    showAlert('加载分组列表失败: ' + (data.error || 'unknown error'), 'error');
                    return;
                }
                
                if (!data.data) {
                    console.error('API response missing data field:', data);
                    showAlert('响应数据格式错误：缺少 data 字段', 'error');
                    return;
                }
                
                // 确保 data.data 是数组
                let groupsArray = [];
                if (Array.isArray(data.data)) {
                    groupsArray = data.data;
                } else if (typeof data.data === 'object' && data.data !== null) {
                    // 如果是对象，尝试转换为数组
                    // 检查是否是空对象
                    const keys = Object.keys(data.data);
                    if (keys.length === 0) {
                        // 空对象，使用空数组（这是正常情况，不显示警告）
                        groupsArray = [];
                    } else {
                        // 非空对象，尝试转换（这种情况应该很少见）
                        console.warn('data.data is not an array, attempting to convert:', data.data);
                        groupsArray = Object.values(data.data);
                    }
                } else {
                    console.error('data.data is not an array or object:', typeof data.data, data.data);
                    showAlert('响应数据格式错误：data 字段不是数组', 'error');
                    return;
                }
                
                const filterGroup = document.getElementById('filter-group');
                const groupList = document.getElementById('group-list');
                const groupListEdit = document.getElementById('group-list-edit');
                
                // 检查DOM元素是否存在
                if (!filterGroup || !groupList || !groupListEdit) {
                    console.error('Required DOM elements not found');
                    return;
                }
                
                // 清空现有选项（保留"全部分组"）
                filterGroup.innerHTML = '<option value="">全部分组</option>';
                groupList.innerHTML = '';
                groupListEdit.innerHTML = '';
                
                // 添加分组选项
                groupsArray.forEach(group => {
                    if (group && group.group_name) {
                        const option = document.createElement('option');
                        option.value = group.group_name;
                        option.textContent = group.group_name + ' (' + (group.rule_count || 0) + ')';
                        filterGroup.appendChild(option);
                        
                        const optionList = document.createElement('option');
                        optionList.value = group.group_name;
                        groupList.appendChild(optionList);
                        
                        const optionListEdit = document.createElement('option');
                        optionListEdit.value = group.group_name;
                        groupListEdit.appendChild(optionListEdit);
                    }
                });
            } catch (error) {
                console.error('加载分组列表失败:', error);
                showAlert('加载分组列表失败: ' + error.message, 'error');
            }
        }
        
        // 设置日期默认值为当日
        function setDefaultDates() {
            const now = new Date();
            const year = now.getFullYear();
            const month = String(now.getMonth() + 1).padStart(2, '0');
            const day = String(now.getDate()).padStart(2, '0');
            const hours = String(now.getHours()).padStart(2, '0');
            const minutes = String(now.getMinutes()).padStart(2, '0');
            
            // 格式：YYYY-MM-DDTHH:mm (datetime-local格式)
            const defaultDateTime = `${year}-${month}-${day}T${hours}:${minutes}`;
            
            const startTimeInput = document.getElementById('create-start-time');
            const endTimeInput = document.getElementById('create-end-time');
            
            if (startTimeInput && !startTimeInput.value) {
                startTimeInput.value = defaultDateTime;
            }
            if (endTimeInput && !endTimeInput.value) {
                // 结束时间默认为当日23:59
                endTimeInput.value = `${year}-${month}-${day}T23:59`;
            }
        }
        
        // 显示创建成功提示框
        function showCreateSuccessModal() {
            const modal = document.getElementById('create-success-modal');
            modal.classList.add('show');
        }
        
        // 确定（关闭提示框）
        function confirmCreateRule() {
            // 关闭提示框
            const modal = document.getElementById('create-success-modal');
            modal.classList.remove('show');
            // 重置表单
            resetCreateForm();
        }
        
        // 显示创建规则弹出框
        function showCreateRuleModal() {
            const modal = document.getElementById('create-rule-modal');
            if (modal) {
                modal.style.display = 'flex';
                modal.classList.add('show');
                // 设置默认日期
                setDefaultDates();
            }
        }
        
        // 关闭创建规则弹出框
        function closeCreateRuleModal() {
            const modal = document.getElementById('create-rule-modal');
            if (modal) {
                modal.style.display = 'none';
                modal.classList.remove('show');
                // 重置表单
                resetCreateForm();
            }
        }
        
        // 初始化
        document.addEventListener('DOMContentLoaded', function() {
            loadGroups();
            loadRules();
            
            // 设置默认日期
            setDefaultDates();
            
            // 点击模态框外部关闭
            window.onclick = function(event) {
                const modal = document.getElementById('edit-modal');
                if (event.target == modal) {
                    closeEditModal();
                }
                
                const successModal = document.getElementById('create-success-modal');
                if (event.target == successModal) {
                    confirmCreateRule();
                }
                
                const confirmModal = document.getElementById('confirm-modal');
                if (event.target == confirmModal) {
                    closeConfirmModal();
                }
            }
        });
        
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
        });