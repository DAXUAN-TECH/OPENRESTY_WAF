// 注意：变量声明已移至 user_settings.html 中，避免重复声明
// 如果HTML中未声明，则在此声明
if (typeof window.currentSecret === 'undefined') {
    window.currentSecret = null;
}
if (typeof window.totpEnabled === 'undefined') {
    window.totpEnabled = false;
}
        
        // 检查认证状态
        function checkAuth() {
            fetch('/api/auth/check')
                .then(response => response.json())
                .then(data => {
                    if (data && data.authenticated === true) {
                        document.getElementById('username').textContent = data.username || '用户';
                        loadTotpStatus();
                    } else {
                        window.location.href = '/login?redirect=' + encodeURIComponent(window.location.pathname);
                    }
                })
                .catch(() => {
                    window.location.href = '/login?redirect=' + encodeURIComponent(window.location.pathname);
                });
        }
        
        // 加载 TOTP 状态
        function loadTotpStatus() {
            fetch('/api/auth/totp/status')
                .then(response => response.json())
                .then(data => {
                    if (data && data.enabled === true) {
                        totpEnabled = true;
                        updateStatus(true);
                    } else {
                        totpEnabled = false;
                        updateStatus(false);
                    }
                })
                .catch(err => {
                    console.error('Failed to load TOTP status:', err);
                    updateStatus(false);
                });
        }
        
        // 更新状态显示
        function updateStatus(enabled) {
            const statusDiv = document.getElementById('totpStatus');
            const statusLabel = document.getElementById('statusLabel');
            const statusText = document.getElementById('statusText');
            const setupButton = document.getElementById('setupButton');
            const disableButton = document.getElementById('disableButton');
            
            if (enabled) {
                statusDiv.className = 'totp-status enabled';
                statusLabel.className = 'status-label enabled';
                statusLabel.textContent = '已启用';
                statusText.textContent = '双因素认证已启用，登录时需要输入验证码';
                setupButton.style.display = 'none';
                disableButton.style.display = 'inline-block';
            } else {
                statusDiv.className = 'totp-status disabled';
                statusLabel.className = 'status-label disabled';
                statusLabel.textContent = '未启用';
                statusText.textContent = '双因素认证未启用，建议启用以提高账户安全性';
                setupButton.style.display = 'inline-block';
                disableButton.style.display = 'none';
            }
        }
        
        // 设置 TOTP
        function setupTotp() {
            hideMessages();
            
            fetch('/api/auth/totp/setup', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                }
            })
                .then(response => response.json())
                .then(data => {
                    if (data.secret) {
                        currentSecret = data.secret;
                        showQrCode(data);
                        document.getElementById('setupSection').style.display = 'block';
                        document.getElementById('actionSection').style.display = 'none';
                        document.getElementById('totpCode').focus();
                    } else {
                        showError(data.message || '设置失败，请重试');
                    }
                })
                .catch(err => {
                    showError('网络错误，请稍后重试');
                });
        }
        
        // 显示二维码
        function showQrCode(data) {
            const qrContainer = document.getElementById('qrContainer');
            
            // 清空容器
            qrContainer.innerHTML = '';
            
            // 检查数据
            console.log('showQrCode data:', data);
            
            // 获取 otpauth URL
            let otpauthUrl = null;
            if (data.qr_data && typeof data.qr_data === 'object' && data.qr_data.otpauth_url) {
                // qr_data 是对象，包含 otpauth_url
                otpauthUrl = data.qr_data.otpauth_url;
                console.log('otpauth_url from qr_data:', otpauthUrl);
            } else if (data.otpauth_url) {
                // 直接包含 otpauth_url
                otpauthUrl = data.otpauth_url;
                console.log('otpauth_url from data:', otpauthUrl);
            } else if (data.qr_url) {
                // 使用外部 QR 码服务（如果配置了）
                const html = '<img src="' + data.qr_url + '" alt="QR Code" style="max-width: 200px; height: auto; display: block; margin: 0 auto;">' +
                    (data.secret ? '<div class="secret-key">密钥（手动输入）: ' + data.secret + '</div>' : '') +
                    '<div style="color: #666; font-size: 12px; margin-top: 10px;">' +
                    '请使用 Google Authenticator 扫描二维码或手动输入密钥，然后输入生成的6位验证码' +
                    '</div>';
                qrContainer.innerHTML = html;
                return;
            }
            
            // 检查 QRCode 库是否加载
            if (typeof QRCode === 'undefined') {
                console.error('QRCode library not loaded');
                qrContainer.innerHTML = '<div style="color: #dc3545; padding: 20px;">二维码生成失败：QRCode 库未加载，请检查网络连接或刷新页面</div>' +
                    (data.secret ? '<div class="secret-key">密钥（手动输入）: ' + data.secret + '</div>' : '');
                return;
            }
            
            // 检查 otpauthUrl 是否存在
            if (!otpauthUrl) {
                console.error('otpauth_url is missing');
                qrContainer.innerHTML = '<div style="color: #dc3545; padding: 20px;">二维码生成失败：缺少 otpauth_url</div>' +
                    (data.secret ? '<div class="secret-key">密钥（手动输入）: ' + data.secret + '</div>' : '');
                return;
            }
            
            // 创建二维码容器
            const qrCanvas = document.createElement('canvas');
            qrCanvas.id = 'qrCanvas';
            qrCanvas.style.display = 'block';
            qrCanvas.style.margin = '0 auto';
            qrCanvas.style.maxWidth = '200px';
            qrCanvas.style.height = 'auto';
            qrContainer.appendChild(qrCanvas);
            
            // 使用 qrcode.js 生成二维码
            // 检查是否使用 qrcodejs（本地文件或 CDN 备用）- 支持离线模式
            if (typeof QRCode !== 'undefined' && !QRCode.toCanvas && QRCode.prototype && QRCode.prototype.makeCode) {
                // 使用 qrcodejs API（本地文件，支持离线模式）
                try {
                    // qrcodejs 需要一个容器元素，我们使用一个隐藏的 div
                    const tempDiv = document.createElement('div');
                    tempDiv.style.position = 'absolute';
                    tempDiv.style.left = '-9999px';
                    tempDiv.style.width = '200px';
                    tempDiv.style.height = '200px';
                    document.body.appendChild(tempDiv);
                    
                    const qr = new QRCode(tempDiv, {
                        text: otpauthUrl,
                        width: 200,
                        height: 200,
                        colorDark: '#000000',
                        colorLight: '#FFFFFF',
                        correctLevel: QRCode.CorrectLevel.M
                    });
                    
                    // 等待 QRCode 生成完成
                    setTimeout(function() {
                        try {
                            const ctx = qrCanvas.getContext('2d');
                            qrCanvas.width = 200;
                            qrCanvas.height = 200;
                            
                            // qrcodejs 可能使用 canvas 或 image 渲染
                            if (qr._elCanvas) {
                                // 如果使用 canvas，直接复制
                                const img = new Image();
                                img.onload = function() {
                                    ctx.drawImage(img, 0, 0, 200, 200);
                                    document.body.removeChild(tempDiv);
                                    
                                    // 二维码生成成功，继续显示密钥等信息
                                    if (data.secret) {
                                        const secretDiv = document.createElement('div');
                                        secretDiv.className = 'secret-key';
                                        secretDiv.textContent = '密钥（手动输入）: ' + data.secret;
                                        qrContainer.appendChild(secretDiv);
                                    }
                                    
                                    const tipDiv = document.createElement('div');
                                    tipDiv.style.cssText = 'color: #666; font-size: 12px; margin-top: 10px;';
                                    tipDiv.textContent = '请使用 Google Authenticator 扫描二维码或手动输入密钥，然后输入生成的6位验证码';
                                    qrContainer.appendChild(tipDiv);
                                };
                                img.onerror = function(err) {
                                    console.error('QR code image load failed:', err);
                                    document.body.removeChild(tempDiv);
                                    qrContainer.innerHTML = '<div style="color: #dc3545; padding: 20px;">二维码生成失败，请使用手动输入密钥的方式</div>';
                                    if (data.secret) {
                                        const secretDiv = document.createElement('div');
                                        secretDiv.className = 'secret-key';
                                        secretDiv.textContent = '密钥（手动输入）: ' + data.secret;
                                        qrContainer.appendChild(secretDiv);
                                    }
                                };
                                img.src = qr._elCanvas.toDataURL('image/png');
                            } else if (qr._elImage && qr._elImage.src) {
                                // 如果使用 image，直接绘制
                                const img = new Image();
                                img.onload = function() {
                                    ctx.drawImage(img, 0, 0, 200, 200);
                                    document.body.removeChild(tempDiv);
                                    
                                    if (data.secret) {
                                        const secretDiv = document.createElement('div');
                                        secretDiv.className = 'secret-key';
                                        secretDiv.textContent = '密钥（手动输入）: ' + data.secret;
                                        qrContainer.appendChild(secretDiv);
                                    }
                                    
                                    const tipDiv = document.createElement('div');
                                    tipDiv.style.cssText = 'color: #666; font-size: 12px; margin-top: 10px;';
                                    tipDiv.textContent = '请使用 Google Authenticator 扫描二维码或手动输入密钥，然后输入生成的6位验证码';
                                    qrContainer.appendChild(tipDiv);
                                };
                                img.onerror = function(err) {
                                    console.error('QR code image load failed:', err);
                                    document.body.removeChild(tempDiv);
                                    qrContainer.innerHTML = '<div style="color: #dc3545; padding: 20px;">二维码生成失败，请使用手动输入密钥的方式</div>';
                                    if (data.secret) {
                                        const secretDiv = document.createElement('div');
                                        secretDiv.className = 'secret-key';
                                        secretDiv.textContent = '密钥（手动输入）: ' + data.secret;
                                        qrContainer.appendChild(secretDiv);
                                    }
                                };
                                img.src = qr._elImage.src;
                            } else {
                                // 如果都没有，尝试从 tempDiv 中获取
                                const img = tempDiv.querySelector('img');
                                if (img && img.src) {
                                    const loadImg = new Image();
                                    loadImg.onload = function() {
                                        ctx.drawImage(loadImg, 0, 0, 200, 200);
                                        document.body.removeChild(tempDiv);
                                        
                                        if (data.secret) {
                                            const secretDiv = document.createElement('div');
                                            secretDiv.className = 'secret-key';
                                            secretDiv.textContent = '密钥（手动输入）: ' + data.secret;
                                            qrContainer.appendChild(secretDiv);
                                        }
                                        
                                        const tipDiv = document.createElement('div');
                                        tipDiv.style.cssText = 'color: #666; font-size: 12px; margin-top: 10px;';
                                        tipDiv.textContent = '请使用 Google Authenticator 扫描二维码或手动输入密钥，然后输入生成的6位验证码';
                                        qrContainer.appendChild(tipDiv);
                                    };
                                    loadImg.onerror = function(err) {
                                        console.error('QR code image load failed:', err);
                                        document.body.removeChild(tempDiv);
                                        qrContainer.innerHTML = '<div style="color: #dc3545; padding: 20px;">二维码生成失败，请使用手动输入密钥的方式</div>';
                                        if (data.secret) {
                                            const secretDiv = document.createElement('div');
                                            secretDiv.className = 'secret-key';
                                            secretDiv.textContent = '密钥（手动输入）: ' + data.secret;
                                            qrContainer.appendChild(secretDiv);
                                        }
                                    };
                                    loadImg.src = img.src;
                                } else {
                                    throw new Error('QRCode generation failed: unable to get QR code image');
                                }
                            }
                        } catch (err) {
                            console.error('QR code generation exception:', err);
                            if (tempDiv.parentNode) {
                                document.body.removeChild(tempDiv);
                            }
                            qrContainer.innerHTML = '<div style="color: #dc3545; padding: 20px;">二维码生成失败: ' + (err.message || err) + '，请使用手动输入密钥的方式</div>';
                            if (data.secret) {
                                const secretDiv = document.createElement('div');
                                secretDiv.className = 'secret-key';
                                secretDiv.textContent = '密钥（手动输入）: ' + data.secret;
                                qrContainer.appendChild(secretDiv);
                            }
                        }
                    }, 100);
                } catch (err) {
                    console.error('QR code generation exception:', err);
                    qrContainer.innerHTML = '<div style="color: #dc3545; padding: 20px;">二维码生成失败: ' + (err.message || err) + '，请使用手动输入密钥的方式</div>';
                    if (data.secret) {
                        const secretDiv = document.createElement('div');
                        secretDiv.className = 'secret-key';
                        secretDiv.textContent = '密钥（手动输入）: ' + data.secret;
                        qrContainer.appendChild(secretDiv);
                    }
                }
            } else if (typeof QRCode !== 'undefined' && QRCode.toCanvas) {
                // 使用 qrcode npm 包的 API（如果 CDN 加载成功）
                try {
                    QRCode.toCanvas(qrCanvas, otpauthUrl, {
                        width: 200,
                        margin: 2,
                        color: {
                            dark: '#000000',
                            light: '#FFFFFF'
                        },
                        errorCorrectionLevel: 'M'
                    }, function (error) {
                        if (error) {
                            console.error('QR code generation failed:', error);
                            qrContainer.innerHTML = '<div style="color: #dc3545; padding: 20px;">二维码生成失败: ' + (error.message || error) + '，请使用手动输入密钥的方式</div>';
                            if (data.secret) {
                                const secretDiv = document.createElement('div');
                                secretDiv.className = 'secret-key';
                                secretDiv.textContent = '密钥（手动输入）: ' + data.secret;
                                qrContainer.appendChild(secretDiv);
                            }
                        } else {
                            // 二维码生成成功，继续显示密钥等信息
                            if (data.secret) {
                                const secretDiv = document.createElement('div');
                                secretDiv.className = 'secret-key';
                                secretDiv.textContent = '密钥（手动输入）: ' + data.secret;
                                qrContainer.appendChild(secretDiv);
                            }
                            
                            const tipDiv = document.createElement('div');
                            tipDiv.style.cssText = 'color: #666; font-size: 12px; margin-top: 10px;';
                            tipDiv.textContent = '请使用 Google Authenticator 扫描二维码或手动输入密钥，然后输入生成的6位验证码';
                            qrContainer.appendChild(tipDiv);
                        }
                    });
                } catch (err) {
                    console.error('QR code generation exception:', err);
                    qrContainer.innerHTML = '<div style="color: #dc3545; padding: 20px;">二维码生成失败: ' + (err.message || err) + '，请使用手动输入密钥的方式</div>';
                    if (data.secret) {
                        const secretDiv = document.createElement('div');
                        secretDiv.className = 'secret-key';
                        secretDiv.textContent = '密钥（手动输入）: ' + data.secret;
                        qrContainer.appendChild(secretDiv);
                    }
                }
            } else {
                // QRCode 库未加载
                console.error('QRCode library not loaded');
                qrContainer.innerHTML = '<div style="color: #dc3545; padding: 20px;">二维码生成失败：QRCode 库未加载，请检查网络连接或刷新页面</div>' +
                    (data.secret ? '<div class="secret-key">密钥（手动输入）: ' + data.secret + '</div>' : '');
            }
        }
        
        // 启用 TOTP
        function enableTotp() {
            const code = document.getElementById('totpCode').value.trim();
            
            if (!code || code.length !== 6) {
                showError('请输入6位验证码');
                return;
            }
            
            if (!currentSecret) {
                showError('请先设置双因素认证');
                return;
            }
            
            const button = document.getElementById('enableButton');
            button.disabled = true;
            button.innerHTML = '<span class="loading"></span>启用中...';
            
            fetch('/api/auth/totp/enable', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    secret: currentSecret,
                    code: code
                })
            })
                .then(response => response.json())
                .then(data => {
                    if (data.success) {
                        showSuccess('双因素认证已启用');
                        currentSecret = null;
                        document.getElementById('setupSection').style.display = 'none';
                        document.getElementById('actionSection').style.display = 'block';
                        loadTotpStatus();
                    } else {
                        showError(data.message || '启用失败，请检查验证码是否正确');
                        button.disabled = false;
                        button.innerHTML = '启用双因素认证';
                    }
                })
                .catch(err => {
                    showError('网络错误，请稍后重试');
                    button.disabled = false;
                    button.innerHTML = '启用双因素认证';
                });
        }
        
        // 取消设置
        function cancelSetup() {
            currentSecret = null;
            document.getElementById('setupSection').style.display = 'none';
            document.getElementById('actionSection').style.display = 'block';
            document.getElementById('qrContainer').innerHTML = '';
            document.getElementById('totpCode').value = '';
        }
        
        // 禁用 TOTP
        function disableTotp() {
            if (!confirm('确定要禁用双因素认证吗？禁用后您的账户安全性将降低。')) {
                return;
            }
            
            const code = prompt('请输入当前验证码以确认禁用：');
            if (!code || code.length !== 6) {
                showError('请输入6位验证码');
                return;
            }
            
            const button = document.getElementById('disableButton');
            button.disabled = true;
            button.innerHTML = '<span class="loading"></span>禁用中...';
            
            fetch('/api/auth/totp/disable', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    code: code
                })
            })
                .then(response => response.json())
                .then(data => {
                    if (data.success) {
                        showSuccess('双因素认证已禁用');
                        loadTotpStatus();
                    } else {
                        showError(data.message || '禁用失败，请检查验证码是否正确');
                        button.disabled = false;
                        button.innerHTML = '禁用双因素认证';
                    }
                })
                .catch(err => {
                    showError('网络错误，请稍后重试');
                    button.disabled = false;
                    button.innerHTML = '禁用双因素认证';
                });
        }
        
        // 显示错误信息
        function showError(message) {
            const errorDiv = document.getElementById('errorMessage');
            errorDiv.textContent = message;
            errorDiv.classList.add('show');
            setTimeout(() => {
                errorDiv.classList.remove('show');
            }, 5000);
        }
        
        // 显示成功信息
        function showSuccess(message) {
            const successDiv = document.getElementById('successMessage');
            successDiv.textContent = message;
            successDiv.classList.add('show');
            setTimeout(() => {
                successDiv.classList.remove('show');
            }, 3000);
        }
        
        // 隐藏消息
        function hideMessages() {
            document.getElementById('errorMessage').classList.remove('show');
            document.getElementById('successMessage').classList.remove('show');
        }
        
        // 修改密码
        function changePassword(event) {
            event.preventDefault();
            hideMessages();
            
            // 去除前后空格
            const oldPassword = document.getElementById('oldPassword').value.trim();
            const newPassword = document.getElementById('newPassword').value.trim();
            const confirmPassword = document.getElementById('confirmPassword').value.trim();
            
            // 验证新密码和确认密码是否一致
            if (newPassword !== confirmPassword) {
                showError('新密码和确认密码不一致');
                return;
            }
            
            // 验证新密码强度
            const strength = checkPasswordStrength(newPassword);
            if (!strength.valid) {
                showError(strength.message || '新密码不符合要求');
                return;
            }
            
            const button = document.getElementById('changePasswordButton');
            button.disabled = true;
            button.innerHTML = '<span class="loading"></span>修改中...';
            
            fetch('/api/auth/password/change', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    old_password: oldPassword,
                    new_password: newPassword
                })
            })
                .then(response => {
                    // 检查响应状态
                    if (!response.ok) {
                        // HTTP状态码不是2xx，尝试解析错误信息
                        return response.json().then(data => {
                            throw new Error(data.message || data.error || '修改密码失败');
                        }).catch(() => {
                            throw new Error('修改密码失败，HTTP状态码: ' + response.status);
                        });
                    }
                    return response.json();
                })
                .then(data => {
                    if (data.success) {
                        showSuccess('密码修改成功');
                        // 清空表单
                        document.getElementById('changePasswordForm').reset();
                        document.getElementById('passwordStrength').textContent = '';
                        document.getElementById('passwordMatch').textContent = '';
                        // 恢复按钮状态
                        button.disabled = false;
                        button.innerHTML = '修改密码';
                    } else {
                        showError(data.message || data.error || '修改密码失败');
                        button.disabled = false;
                        button.innerHTML = '修改密码';
                    }
                })
                .catch(err => {
                    showError(err.message || '网络错误，请稍后重试');
                    button.disabled = false;
                    button.innerHTML = '修改密码';
                });
        }
        
        // 检查密码强度
        function checkPasswordStrength(password) {
            if (!password) {
                return { valid: false, message: '密码不能为空' };
            }
            
            const checks = {
                length: password.length >= 8,
                hasUpper: /[A-Z]/.test(password),
                hasLower: /[a-z]/.test(password),
                hasDigit: /[0-9]/.test(password),
                hasSpecial: /[^A-Za-z0-9]/.test(password)
            };
            
            const valid = checks.length && checks.hasUpper && checks.hasLower && checks.hasDigit && checks.hasSpecial;
            
            if (!valid) {
                const missing = [];
                if (!checks.length) missing.push('至少8位');
                if (!checks.hasUpper) missing.push('大写字母');
                if (!checks.hasLower) missing.push('小写字母');
                if (!checks.hasDigit) missing.push('数字');
                if (!checks.hasSpecial) missing.push('符号');
                return { valid: false, message: '密码必须包含：' + missing.join('、') };
            }
            
            return { valid: true };
        }
        
        // 页面加载时检查认证状态
        checkAuth();
        
        // 实时检查密码强度
        (function() {
            const newPasswordInput = document.getElementById('newPassword');
            const confirmPasswordInput = document.getElementById('confirmPassword');
            const passwordStrengthDiv = document.getElementById('passwordStrength');
            const passwordMatchDiv = document.getElementById('passwordMatch');
            
            if (newPasswordInput && passwordStrengthDiv) {
                newPasswordInput.addEventListener('input', function() {
                    const password = this.value;
                    if (password) {
                        const strength = checkPasswordStrength(password);
                        if (strength.valid) {
                            passwordStrengthDiv.textContent = '✓ 密码强度符合要求';
                            passwordStrengthDiv.style.color = '#4caf50';
                        } else {
                            passwordStrengthDiv.textContent = strength.message || '密码不符合要求';
                            passwordStrengthDiv.style.color = '#dc3545';
                        }
                    } else {
                        passwordStrengthDiv.textContent = '';
                    }
                });
            }
            
            if (confirmPasswordInput && newPasswordInput && passwordMatchDiv) {
                confirmPasswordInput.addEventListener('input', function() {
                    const newPassword = newPasswordInput.value;
                    const confirmPassword = this.value;
                    if (confirmPassword) {
                        if (newPassword === confirmPassword) {
                            passwordMatchDiv.textContent = '✓ 密码一致';
                            passwordMatchDiv.style.color = '#4caf50';
                        } else {
                            passwordMatchDiv.textContent = '✗ 密码不一致';
                            passwordMatchDiv.style.color = '#dc3545';
                        }
                    } else {
                        passwordMatchDiv.textContent = '';
                    }
                });
            }
        })();