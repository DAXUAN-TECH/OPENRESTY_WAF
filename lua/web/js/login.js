const loginForm = document.getElementById('loginForm');
const errorMessage = document.getElementById('errorMessage');
const loginButton = document.getElementById('loginButton');
const totpModal = document.getElementById('totpModal');
const totpCodeInput = document.getElementById('totpCodeInput');
const totpErrorMessage = document.getElementById('totpErrorMessage');

// 保存用户名和密码，用于后续TOTP验证
let savedUsername = '';
let savedPassword = '';

// 检查是否已登录
function checkAuth() {
    // 如果 URL 中有 redirect 参数，说明是从其他页面重定向来的，不应该自动跳转
    const urlParams = new URLSearchParams(window.location.search);
    if (urlParams.has('redirect')) {
        // 有 redirect 参数，说明是重定向来的，不自动跳转
        return;
    }
    
    fetch('/api/auth/check')
        .then(response => response.json())
        .then(data => {
            // 检查响应中的 authenticated 字段，而不是只检查 response.ok
            if (data && data.authenticated === true) {
                // 已登录，跳转到管理首页或 redirect 参数指定的页面
                const redirect = urlParams.get('redirect') || '/admin';
                window.location.href = redirect;
            }
            // 未登录，继续显示登录页面
        })
        .catch(() => {
            // 网络错误，继续显示登录页面
        });
}

// 显示错误信息
function showError(message) {
    errorMessage.textContent = message;
    errorMessage.classList.add('show');
}

// 隐藏错误信息
function hideError() {
    errorMessage.classList.remove('show');
}

// 显示2FA弹出框
function showTotpModal() {
    totpModal.style.display = 'flex';
    totpCodeInput.value = '';
    totpCodeInput.classList.remove('error');
    totpErrorMessage.textContent = '';
    // 聚焦输入框
    setTimeout(() => {
        totpCodeInput.focus();
    }, 100);
}

// 隐藏2FA弹出框
function hideTotpModal() {
    totpModal.style.display = 'none';
    totpCodeInput.value = '';
    totpCodeInput.classList.remove('error');
    totpErrorMessage.textContent = '';
}

// 显示TOTP错误（抖动、红色边框、错误提示）
function showTotpError(message) {
    totpCodeInput.classList.add('error');
    totpErrorMessage.textContent = message;
    // 清除错误状态（用于下次输入）
    setTimeout(() => {
        totpCodeInput.classList.remove('error');
    }, 500);
}

// 验证TOTP验证码
async function verifyTotpCode(code) {
    if (!code || code.length !== 6) {
        return false;
    }
    
    try {
        const response = await fetch('/api/auth/login', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                username: savedUsername,
                password: savedPassword,
                totp_code: code
            })
        });
        
        const data = await response.json();
        
        if (response.ok && data.success) {
            // 存储 CSRF Token（如果返回了）
            if (data.csrf_token) {
                // 如果页面中有 setCsrfToken 函数，调用它
                if (typeof window.setCsrfToken === 'function') {
                    window.setCsrfToken(data.csrf_token);
                } else {
                    // 否则存储到 sessionStorage，供其他页面使用
                    sessionStorage.setItem('csrf_token', data.csrf_token);
                }
            }
            
            // 登录成功，隐藏弹出框并跳转
            hideTotpModal();
            window.location.href = '/admin';
            return true;
        } else {
            // 验证失败
            showTotpError('2FA验证码输入错误，请重新输入');
            return false;
        }
    } catch (error) {
        showTotpError('网络错误，请稍后重试');
        return false;
    }
}

// TOTP输入框输入事件：自动验证
totpCodeInput.addEventListener('input', function(e) {
    // 只允许输入数字
    e.target.value = e.target.value.replace(/\D/g, '');
    
    // 清除之前的错误状态
    if (e.target.classList.contains('error')) {
        e.target.classList.remove('error');
        totpErrorMessage.textContent = '';
    }
    
    // 如果输入了6位数字，自动验证
    if (e.target.value.length === 6) {
        verifyTotpCode(e.target.value);
    }
});

// 处理登录表单提交
loginForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    hideError();
    
    const username = document.getElementById('username').value.trim();
    const password = document.getElementById('password').value;
    
    if (!username || !password) {
        showError('请输入用户名和密码');
        return;
    }
    
    // 保存用户名和密码
    savedUsername = username;
    savedPassword = password;
    
    // 禁用按钮并显示加载状态
    loginButton.disabled = true;
    loginButton.innerHTML = '<span class="loading"></span>登录中...';
    
    try {
        const response = await fetch('/api/auth/login', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                username: username,
                password: password
            })
        });
        
        const data = await response.json();
        
        if (response.ok) {
            // 检查是否需要 TOTP
            if (data.requires_totp) {
                // 显示2FA弹出框
                loginButton.disabled = false;
                loginButton.innerHTML = '登录';
                showTotpModal();
                return;
            }
            
            // 存储 CSRF Token（如果返回了）
            if (data.csrf_token) {
                // 如果页面中有 setCsrfToken 函数，调用它
                if (typeof window.setCsrfToken === 'function') {
                    window.setCsrfToken(data.csrf_token);
                } else {
                    // 否则存储到 sessionStorage，供其他页面使用
                    sessionStorage.setItem('csrf_token', data.csrf_token);
                }
            }
            
            // 登录成功，跳转到管理首页
            window.location.href = '/admin';
        } else {
            // 登录失败，显示错误信息
            showError(data.message || data.error || '登录失败，请检查用户名和密码');
            loginButton.disabled = false;
            loginButton.innerHTML = '登录';
        }
    } catch (error) {
        showError('网络错误，请稍后重试');
        loginButton.disabled = false;
        loginButton.innerHTML = '登录';
    }
});

// 密码显示/隐藏功能
const togglePassword = document.getElementById('togglePassword');
const passwordInput = document.getElementById('password');

togglePassword.addEventListener('click', function() {
    const type = passwordInput.getAttribute('type') === 'password' ? 'text' : 'password';
    passwordInput.setAttribute('type', type);
    
    // 切换图标（使用简单的文本图标，也可以使用 SVG）
    if (type === 'password') {
        togglePassword.textContent = '👁️';
        togglePassword.title = '显示密码';
    } else {
        togglePassword.textContent = '🙈';
        togglePassword.title = '隐藏密码';
    }
});

// 页面加载时检查是否已登录
checkAuth();

