const loginForm = document.getElementById('loginForm');
const errorMessage = document.getElementById('errorMessage');
const loginButton = document.getElementById('loginButton');

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

// 处理登录表单提交
loginForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    hideError();
    
    const username = document.getElementById('username').value.trim();
    const password = document.getElementById('password').value;
    const totpCode = document.getElementById('totp_code').value.trim();
    
    if (!username || !password) {
        showError('请输入用户名和密码');
        return;
    }
    
    // 禁用按钮并显示加载状态
    loginButton.disabled = true;
    loginButton.innerHTML = '<span class="loading"></span>登录中...';
    
    try {
        const requestBody = {
            username: username,
            password: password
        };
        
        // 如果显示了 TOTP 输入框，添加验证码
        if (document.getElementById('totpGroup').style.display !== 'none') {
            if (!totpCode || totpCode.length !== 6) {
                showError('请输入6位双因素认证代码');
                loginButton.disabled = false;
                loginButton.innerHTML = '登录';
                return;
            }
            requestBody.totp_code = totpCode;
        }
        
        const response = await fetch('/api/auth/login', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(requestBody)
        });
        
        const data = await response.json();
        
        if (response.ok) {
            // 检查是否需要 TOTP
            if (data.requires_totp) {
                // 显示 TOTP 输入框
                document.getElementById('totpGroup').style.display = 'block';
                document.getElementById('totp_code').focus();
                showError('请输入双因素认证代码');
                loginButton.disabled = false;
                loginButton.innerHTML = '登录';
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

