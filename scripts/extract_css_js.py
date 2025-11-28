#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
批量提取HTML文件中的CSS和JS到独立文件
使用方法: python3 extract_css_js.py
"""

import os
import re
import sys

# 项目根目录
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB_DIR = os.path.join(BASE_DIR, 'lua', 'web')
CSS_DIR = os.path.join(WEB_DIR, 'css')
JS_DIR = os.path.join(WEB_DIR, 'js')

def ensure_dirs():
    """确保目录存在"""
    os.makedirs(CSS_DIR, exist_ok=True)
    os.makedirs(JS_DIR, exist_ok=True)

def extract_css_js(html_file):
    """从HTML文件中提取CSS和JS"""
    html_path = os.path.join(WEB_DIR, html_file)
    
    if not os.path.exists(html_path):
        print(f"文件不存在: {html_path}")
        return False
    
    with open(html_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 获取文件名（不含扩展名）
    base_name = os.path.splitext(html_file)[0]
    css_file = os.path.join(CSS_DIR, f"{base_name}.css")
    js_file = os.path.join(JS_DIR, f"{base_name}.js")
    
    # 提取CSS（在<style>标签中）
    css_pattern = r'<style>(.*?)</style>'
    css_matches = re.findall(css_pattern, content, re.DOTALL)
    
    css_content = ''
    if css_matches:
        css_content = '\n'.join(css_matches)
        # 写入CSS文件
        with open(css_file, 'w', encoding='utf-8') as f:
            f.write(css_content)
        print(f"✓ 提取CSS: {css_file}")
    
    # 提取JS（在<script>标签中，排除外部引用）
    js_pattern = r'<script(?:\s+[^>]*)?>(.*?)</script>'
    js_matches = re.findall(js_pattern, content, re.DOTALL)
    
    js_content = ''
    if js_matches:
        # 过滤掉外部脚本引用（包含src属性的）
        for match in js_matches:
            # 检查前面的<script>标签是否有src属性
            script_start = content.find(match) - 100
            if script_start < 0:
                script_start = 0
            script_tag = content[script_start:content.find(match)]
            if 'src=' not in script_tag:
                js_content += match + '\n\n'
        
        if js_content.strip():
            # 写入JS文件
            with open(js_file, 'w', encoding='utf-8') as f:
                f.write(js_content.strip())
            print(f"✓ 提取JS: {js_file}")
    
    # 替换HTML中的CSS和JS
    new_content = content
    
    # 替换CSS
    if css_content:
        # 替换第一个<style>标签为外部引用
        new_content = re.sub(
            r'<style>.*?</style>',
            f'<link rel="stylesheet" href="/css/{base_name}.css">',
            new_content,
            count=1,
            flags=re.DOTALL
        )
        # 移除其他<style>标签（如果有多个）
        new_content = re.sub(r'<style>.*?</style>', '', new_content, flags=re.DOTALL)
    
    # 替换JS（需要更精确的处理）
    if js_content.strip():
        # 找到所有<script>标签
        script_pattern = r'<script(?:\s+[^>]*)?>(.*?)</script>'
        
        def replace_script(match):
            script_tag = match.group(0)
            # 如果有src属性，保留原样
            if 'src=' in script_tag:
                return script_tag
            # 否则替换为外部引用
            return f'<script src="/js/{base_name}.js"></script>'
        
        # 先替换第一个内联脚本
        new_content = re.sub(
            r'<script(?:\s+[^>]*)?>(?!.*src=).*?</script>',
            f'<script src="/js/{base_name}.js"></script>',
            new_content,
            count=1,
            flags=re.DOTALL
        )
        # 移除其他内联脚本（保留有src的）
        new_content = re.sub(
            r'<script(?:\s+[^>]*)?>(?!.*src=).*?</script>',
            '',
            new_content,
            flags=re.DOTALL
        )
    
    # 写回HTML文件
    with open(html_path, 'w', encoding='utf-8') as f:
        f.write(new_content)
    
    print(f"✓ 更新HTML: {html_path}")
    return True

def main():
    """主函数"""
    ensure_dirs()
    
    # 获取所有HTML文件
    html_files = [f for f in os.listdir(WEB_DIR) if f.endswith('.html')]
    
    if not html_files:
        print("未找到HTML文件")
        return
    
    print(f"找到 {len(html_files)} 个HTML文件")
    print("=" * 50)
    
    for html_file in sorted(html_files):
        print(f"\n处理: {html_file}")
        try:
            extract_css_js(html_file)
        except Exception as e:
            print(f"✗ 错误: {e}")
    
    print("\n" + "=" * 50)
    print("完成！")

if __name__ == '__main__':
    main()

