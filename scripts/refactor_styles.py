#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
批量重构页面样式脚本
删除指定页面的所有样式，然后重新生成统一的样式
"""

import re
import os
import sys

# 统一样式模板
UNIFIED_STYLES = """        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        /* 统一容器样式 */
        .container {
            width: 100%;
            max-width: 100%;
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
            padding: 30px;
        }
        
        /* 标题样式 */
        h1 {
            color: #333;
            font-size: 24px;
            margin-bottom: 30px;
            font-weight: 600;
        }
        
        /* 标签页样式 */
        .tabs {
            display: flex;
            border-bottom: 2px solid #e0e0e0;
            margin-bottom: 20px;
        }
        
        .tab {
            padding: 12px 24px;
            cursor: pointer;
            border: none;
            background: none;
            font-size: 16px;
            color: #666;
            transition: all 0.3s;
        }
        
        .tab.active {
            color: #4CAF50;
            border-bottom: 2px solid #4CAF50;
            font-weight: bold;
        }
        
        .tab:hover {
            color: #4CAF50;
        }
        
        .tab-content {
            display: none;
        }
        
        .tab-content.active {
            display: block;
        }
        
        /* 工具栏样式 */
        .toolbar {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
            flex-wrap: wrap;
            gap: 10px;
        }
        
        .filters {
            display: flex;
            gap: 10px;
            flex-wrap: wrap;
        }
        
        .filters select,
        .filters input {
            padding: 8px 12px;
            border: 1px solid #ddd;
            border-radius: 4px;
            font-size: 14px;
        }
        
        /* 按钮样式 */
        .btn {
            padding: 8px 16px;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 14px;
            transition: all 0.3s;
        }
        
        .btn-primary {
            background-color: #4CAF50;
            color: white;
        }
        
        .btn-primary:hover {
            background-color: #45a049;
        }
        
        .btn-danger {
            background-color: #f44336;
            color: white;
        }
        
        .btn-danger:hover {
            background-color: #da190b;
        }
        
        .btn-warning {
            background-color: #ff9800;
            color: white;
        }
        
        .btn-warning:hover {
            background-color: #e68900;
        }
        
        .btn-info {
            background-color: #2196F3;
            color: white;
        }
        
        .btn-info:hover {
            background-color: #0b7dda;
        }
        
        .btn-secondary {
            background-color: #757575;
            color: white;
        }
        
        .btn-secondary:hover {
            background-color: #616161;
        }
        
        /* 表格样式 */
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
        }
        
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #e0e0e0;
        }
        
        th {
            background-color: #f5f5f5;
            font-weight: 600;
            color: #333;
        }
        
        tr:hover {
            background-color: #f9f9f9;
        }
        
        /* 状态徽章 */
        .status-badge {
            padding: 4px 8px;
            border-radius: 4px;
            font-size: 12px;
            font-weight: bold;
        }
        
        .status-enabled {
            background-color: #4CAF50;
            color: white;
        }
        
        .status-disabled {
            background-color: #f44336;
            color: white;
        }
        
        /* 模态框样式 */
        .content-area {
            position: relative;
        }
        
        .modal {
            display: none;
            position: absolute;
            z-index: 1000;
            left: 0;
            top: 0;
            width: 100% !important;
            height: 100% !important;
            overflow: auto;
            background-color: rgba(0,0,0,0.5);
        }
        
        .modal[style*="display: block"],
        .modal[style*="display:flex"] {
            display: flex !important;
            align-items: center;
            justify-content: center;
        }
        
        .modal-content {
            background-color: white;
            padding: 30px;
            border-radius: 8px;
            width: 90%;
            max-width: 800px;
            max-height: 90vh;
            overflow-y: auto;
            position: relative;
        }
        
        .modal-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
        }
        
        .close {
            color: #aaa;
            font-size: 28px;
            font-weight: bold;
            cursor: pointer;
        }
        
        .close:hover {
            color: #000;
        }
        
        /* 表单样式 */
        .form-group {
            margin-bottom: 20px;
        }
        
        .form-group label {
            display: block;
            margin-bottom: 5px;
            color: #333;
            font-weight: 500;
        }
        
        .form-group input,
        .form-group select,
        .form-group textarea {
            width: 100%;
            padding: 10px;
            border: 1px solid #ddd;
            border-radius: 4px;
            font-size: 14px;
        }
        
        .form-group textarea {
            resize: vertical;
            min-height: 80px;
        }
        
        .form-row {
            display: flex;
            gap: 15px;
        }
        
        .form-row .form-group {
            flex: 1;
        }
        
        .form-actions {
            display: flex;
            justify-content: flex-end;
            gap: 10px;
            margin-top: 20px;
        }
        
        /* 分页样式 */
        .pagination {
            display: flex;
            justify-content: center;
            align-items: center;
            gap: 10px;
            margin-top: 20px;
        }
        
        .pagination button {
            padding: 8px 12px;
            border: 1px solid #ddd;
            background: white;
            cursor: pointer;
            border-radius: 4px;
        }
        
        .pagination button:hover:not(:disabled) {
            background-color: #f5f5f5;
        }
        
        .pagination button:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }
        
        /* 提示信息 */
        .alert {
            padding: 12px;
            margin-bottom: 20px;
            border-radius: 4px;
        }
        
        .alert-success {
            background-color: #d4edda;
            color: #155724;
            border: 1px solid #c3e6cb;
        }
        
        .alert-error {
            background-color: #f8d7da;
            color: #721c24;
            border: 1px solid #f5c6cb;
        }
        
        .action-buttons {
            display: flex;
            gap: 5px;
        }
        
        .action-buttons button {
            padding: 4px 8px;
            font-size: 12px;
        }"""

# 页面特定样式（需要添加到统一样式后面）
PAGE_SPECIFIC_STYLES = {
    'rule_management.html': """        
        /* 规则类型按钮组 */
        .rule-type-buttons {
            display: flex;
            gap: 10px;
            flex-wrap: wrap;
        }
        
        .rule-type-btn {
            padding: 12px 24px;
            border: 2px solid #ddd;
            border-radius: 6px;
            background: white;
            cursor: pointer;
            font-size: 14px;
            transition: all 0.3s;
            min-width: 120px;
        }
        
        .rule-type-btn:hover {
            border-color: #4CAF50;
            background: #f0f9f0;
        }
        
        .rule-type-btn.active {
            border-color: #4CAF50;
            background: #4CAF50;
            color: white;
        }
        
        /* 地域选择区域 */
        .geo-selector {
            display: none;
            margin-top: 15px;
            padding: 20px;
            border: 1px solid #e0e0e0;
            border-radius: 6px;
            background: #f9f9f9;
        }
        
        .geo-selector.active {
            display: block;
        }
        
        .geo-tabs {
            display: flex;
            gap: 10px;
            margin-bottom: 20px;
            border-bottom: 2px solid #e0e0e0;
        }
        
        .geo-tab {
            padding: 10px 20px;
            cursor: pointer;
            border: none;
            background: none;
            font-size: 14px;
            color: #666;
            transition: all 0.3s;
        }
        
        .geo-tab.active {
            color: #4CAF50;
            border-bottom: 2px solid #4CAF50;
            font-weight: bold;
        }
        
        .geo-content {
            display: none;
        }
        
        .geo-content.active {
            display: block;
        }
        
        .continent-section,
        .region-section {
            margin-bottom: 25px;
        }
        
        .continent-title,
        .region-title {
            font-size: 16px;
            font-weight: bold;
            color: #333;
            margin-bottom: 12px;
            padding-bottom: 8px;
            border-bottom: 1px solid #e0e0e0;
        }
        
        .country-buttons,
        .province-buttons,
        .city-buttons {
            display: flex;
            flex-wrap: wrap;
            gap: 8px;
        }
        
        .country-btn,
        .province-btn,
        .city-btn {
            padding: 8px 16px;
            border: 1px solid #ddd;
            border-radius: 4px;
            background: white;
            cursor: pointer;
            font-size: 13px;
            transition: all 0.3s;
        }
        
        .country-btn:hover,
        .province-btn:hover,
        .city-btn:hover {
            border-color: #4CAF50;
            background: #f0f9f0;
        }
        
        .country-btn.active,
        .province-btn.active,
        .city-btn.active {
            border-color: #4CAF50;
            background: #4CAF50;
            color: white;
        }
        
        .selected-geo {
            margin-top: 15px;
            padding: 15px;
            background: #e8f5e9;
            border-radius: 4px;
            font-size: 14px;
        }
        
        .selected-geo-item {
            display: inline-flex;
            align-items: center;
            margin: 5px;
            padding: 6px 12px;
            background: white;
            border: 1px solid #4CAF50;
            border-radius: 4px;
            font-size: 13px;
        }
        
        .selected-geo-item .remove-btn {
            margin-left: 8px;
            padding: 2px 6px;
            background: #f44336;
            color: white;
            border: none;
            border-radius: 3px;
            cursor: pointer;
            font-size: 12px;
            line-height: 1;
        }
        
        .selected-geo-item .remove-btn:hover {
            background: #d32f2f;
        }
        
        .selected-geo-empty {
            color: #999;
            font-style: italic;
        }
        
        /* IP黑白名单规则值输入框样式 */
        .rule-value-input {
            width: 200% !important;
            max-width: 2800px !important;
            min-height: 100px !important;
            padding: 15px !important;
            font-size: 15px !important;
            border: 1px solid #ddd;
            border-radius: 4px;
            resize: vertical;
            font-family: inherit;
            line-height: 1.5;
        }
        
        #rule-value-group {
            width: 100%;
            overflow-x: auto;
        }
        
        #rule-value-group .rule-value-input {
            display: block;
        }
        
        /* 创建成功提示框 */
        #create-success-modal {
            display: none;
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0,0,0,0.5);
            z-index: 10001;
            overflow: auto;
        }
        
        #create-success-modal.show {
            display: flex !important;
            align-items: center !important;
            justify-content: center !important;
        }
        
        #create-success-modal > div {
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.3);
            min-width: 400px;
            max-width: 90%;
            text-align: center;
            margin: 20px;
        }""",
    
    'proxy_management.html': """        
        .backends-list {
            margin-top: 10px;
            padding: 10px;
            background-color: #f9f9f9;
            border-radius: 4px;
        }
        
        .backend-item {
            display: flex;
            gap: 10px;
            margin-bottom: 10px;
            padding: 10px;
            background: white;
            border-radius: 4px;
            align-items: center;
        }
        
        .backend-item input {
            flex: 1;
        }
        
        .tcp-udp-mode .backend-address-field,
        .tcp-udp-mode .tcp-udp-backend-port-field {
            flex: 0 0 25%;
            max-width: 25%;
        }""",
    
    'features.html': """        
        .features-list {
            display: grid;
            gap: 20px;
        }
        
        .feature-card {
            border: 1px solid #e0e0e0;
            border-radius: 8px;
            padding: 20px;
            background: #fafafa;
            transition: all 0.3s;
        }
        
        .feature-card:hover {
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }
        
        .feature-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 10px;
        }
        
        .feature-name {
            font-size: 18px;
            font-weight: 600;
            color: #333;
        }
        
        .feature-description {
            color: #666;
            margin-bottom: 15px;
            font-size: 14px;
        }
        
        .switch {
            position: relative;
            display: inline-block;
            width: 60px;
            height: 34px;
        }
        
        .switch input {
            opacity: 0;
            width: 0;
            height: 0;
        }
        
        .slider {
            position: absolute;
            cursor: pointer;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background-color: #ccc;
            transition: .4s;
            border-radius: 34px;
        }
        
        .slider::before {
            position: absolute;
            content: "";
            height: 26px;
            width: 26px;
            left: 4px;
            bottom: 4px;
            background-color: white;
            transition: all 0.4s ease;
            border-radius: 13px;
            display: block;
            box-sizing: border-box;
            border: none;
            outline: none;
            margin: 0;
            padding: 0;
            -webkit-appearance: none;
            appearance: none;
        }
        
        input:checked + .slider {
            background-color: #4CAF50;
        }
        
        input:checked + .slider::before {
            transform: translateX(26px);
        }
        
        .loading {
            text-align: center;
            padding: 40px;
            color: #666;
        }""",
    
    'user_settings.html': """        
        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 30px;
            padding-bottom: 20px;
            border-bottom: 1px solid #eee;
        }
        
        .header h1 {
            color: #333;
            font-size: 24px;
            margin: 0;
            font-weight: 600;
        }
        
        .header .user-info {
            color: #666;
            font-size: 14px;
        }
        
        .section {
            margin-bottom: 40px;
        }
        
        .section-title {
            font-size: 18px;
            color: #333;
            margin-bottom: 15px;
            font-weight: 500;
        }
        
        .section-description {
            color: #666;
            font-size: 14px;
            margin-bottom: 20px;
            line-height: 1.6;
        }
        
        .totp-status {
            background: #f9f9f9;
            border: 1px solid #ddd;
            border-radius: 5px;
            padding: 20px;
            margin-bottom: 20px;
        }
        
        .totp-status.enabled {
            background: #e8f5e9;
            border-color: #4caf50;
        }
        
        .totp-status.disabled {
            background: #fff3e0;
            border-color: #ff9800;
        }
        
        .status-label {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 4px;
            font-size: 12px;
            font-weight: 500;
            margin-bottom: 10px;
        }
        
        .status-label.enabled {
            background: #4caf50;
            color: white;
        }
        
        .status-label.disabled {
            background: #ff9800;
            color: white;
        }
        
        .button {
            padding: 10px 20px;
            border: none;
            border-radius: 5px;
            font-size: 14px;
            font-weight: 500;
            cursor: pointer;
            transition: opacity 0.3s;
        }
        
        .button:hover {
            opacity: 0.9;
        }
        
        .button:active {
            opacity: 0.8;
        }
        
        .button:disabled {
            opacity: 0.6;
            cursor: not-allowed;
        }
        
        .button-primary {
            background: #0066cc;
            color: white;
        }
        
        .button-danger {
            background: #dc3545;
            color: white;
        }
        
        .button-secondary {
            background: #6c757d;
            color: white;
        }
        
        .qr-container {
            text-align: center;
            margin: 20px 0;
            padding: 20px;
            background: #f9f9f9;
            border-radius: 5px;
        }
        
        .qr-container img {
            max-width: 200px;
            margin-bottom: 10px;
        }
        
        .qr-container .secret-key {
            font-family: monospace;
            font-size: 14px;
            color: #333;
            word-break: break-all;
            margin: 10px 0;
            padding: 10px;
            background: white;
            border: 1px solid #ddd;
            border-radius: 4px;
        }
        
        .form-group input:focus {
            outline: none;
            border-color: #0066cc;
        }
        
        .error-message {
            background: #fee;
            color: #c33;
            padding: 10px;
            border-radius: 5px;
            margin-bottom: 20px;
            font-size: 14px;
            display: none;
        }
        
        .error-message.show {
            display: block;
        }
        
        .success-message {
            background: #efe;
            color: #3c3;
            padding: 10px;
            border-radius: 5px;
            margin-bottom: 20px;
            font-size: 14px;
            display: none;
        }
        
        .success-message.show {
            display: block;
        }
        
        .loading {
            display: inline-block;
            width: 16px;
            height: 16px;
            border: 2px solid #fff;
            border-top-color: transparent;
            border-radius: 50%;
            animation: spin 0.6s linear infinite;
            margin-right: 8px;
            vertical-align: middle;
        }
        
        @keyframes spin {
            to { transform: rotate(360deg); }
        }"""
}


def refactor_file(filepath):
    """重构单个文件的样式"""
    if not os.path.exists(filepath):
        print(f"文件不存在: {filepath}")
        return False
    
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 提取文件名
    filename = os.path.basename(filepath)
    
    # 查找<style>标签
    style_pattern = r'<style>([\s\S]*?)</style>'
    match = re.search(style_pattern, content)
    
    if not match:
        print(f"未找到<style>标签: {filepath}")
        return False
    
    # 构建新的样式内容
    new_styles = UNIFIED_STYLES
    if filename in PAGE_SPECIFIC_STYLES:
        new_styles += PAGE_SPECIFIC_STYLES[filename]
    
    # 替换样式
    new_content = re.sub(style_pattern, f'<style>\n{new_styles}\n    </style>', content, count=1)
    
    # 写回文件
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(new_content)
    
    print(f"✓ 已重构: {filepath}")
    return True


def main():
    """主函数"""
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    web_dir = os.path.join(base_dir, 'lua', 'web')
    
    files = [
        'rule_management.html',
        'proxy_management.html',
        'features.html',
        'user_settings.html'
    ]
    
    print("=" * 60)
    print("批量重构页面样式")
    print("=" * 60)
    print()
    
    success_count = 0
    for filename in files:
        filepath = os.path.join(web_dir, filename)
        if refactor_file(filepath):
            success_count += 1
    
    print()
    print("=" * 60)
    print(f"完成: {success_count}/{len(files)} 个文件已重构")
    print("=" * 60)


if __name__ == '__main__':
    main()

