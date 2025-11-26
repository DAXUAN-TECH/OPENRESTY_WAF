
// Web前端公共JavaScript函数
// 路径：项目目录下的 lua/web/common.js（保持在项目目录，不复制到系统目录）
// 功能：提供前端页面中常用的工具函数，避免重复代码

// 使用立即执行函数确保函数在全局作用域中定义
(function() {
    'use strict';
    
    // HTML转义函数
    window.escapeHtml = function(text) {
        if (!text) return '';
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    };
    
    // 格式化日期时间
    window.formatDateTime = function(datetime) {
        if (!datetime) return '-';
        const date = new Date(datetime);
        if (isNaN(date.getTime())) return datetime;
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        const hours = String(date.getHours()).padStart(2, '0');
        const minutes = String(date.getMinutes()).padStart(2, '0');
        const seconds = String(date.getSeconds()).padStart(2, '0');
        return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
    };
    
    // 解析Prometheus格式的指标
    window.parsePrometheusMetrics = function(text) {
        const metrics = {};
        const lines = text.split('\n');
        
        for (const line of lines) {
            if (line.startsWith('#') || !line.trim()) continue;
            
            // 匹配指标名称和值
            const match = line.match(/^(\w+)\s+([\d.]+)$/);
            if (match) {
                const [, name, value] = match;
                metrics[name] = parseFloat(value);
            }
        }
        
        return metrics;
    };
    
    // 显示提示消息
    window.showAlert = function(message, type = 'success') {
        // 创建提示框
        const alertDiv = document.createElement('div');
        alertDiv.className = `alert alert-${type}`;
        alertDiv.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            padding: 15px 20px;
            background: ${type === 'success' ? '#d4edda' : type === 'error' ? '#f8d7da' : '#fff3cd'};
            color: ${type === 'success' ? '#155724' : type === 'error' ? '#721c24' : '#856404'};
            border: 1px solid ${type === 'success' ? '#c3e6cb' : type === 'error' ? '#f5c6cb' : '#ffeaa7'};
            border-radius: 4px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.15);
            z-index: 10000;
            max-width: 400px;
            word-wrap: break-word;
        `;
        alertDiv.textContent = message;
        
        document.body.appendChild(alertDiv);
        
        // 3秒后自动移除
        setTimeout(() => {
            alertDiv.style.transition = 'opacity 0.3s';
            alertDiv.style.opacity = '0';
            setTimeout(() => {
                if (alertDiv.parentNode) {
                    alertDiv.parentNode.removeChild(alertDiv);
                }
            }, 300);
        }, 3000);
    };
    
    // 显示错误消息（showAlert的别名）
    window.showError = function(message) {
        window.showAlert(message, 'error');
    };
    
    // 为了向后兼容，也在全局作用域中定义（不使用window前缀）
    // 这样即使某些页面直接调用 escapeHtml() 也能工作
    if (typeof escapeHtml === 'undefined') {
        window.escapeHtml = window.escapeHtml;
    }
    if (typeof formatDateTime === 'undefined') {
        window.formatDateTime = window.formatDateTime;
    }
    if (typeof parsePrometheusMetrics === 'undefined') {
        window.parsePrometheusMetrics = window.parsePrometheusMetrics;
    }
    if (typeof showAlert === 'undefined') {
        window.showAlert = window.showAlert;
    }
    if (typeof showError === 'undefined') {
        window.showError = window.showError;
    }
})();

