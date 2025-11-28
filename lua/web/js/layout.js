// 立即执行，防止闪烁 - 在DOM解析时就开始计算
        (function() {
            // 使用立即执行函数，不等待DOMContentLoaded
            function syncSidebarWidthImmediate() {
                // 尝试获取sidebar元素
                var sidebar = document.querySelector('.sidebar');
                var topBanner = document.querySelector('.top-banner');
                var contentArea = document.querySelector('.content-area');
                
                if (sidebar) {
                    var sidebarRect = sidebar.getBoundingClientRect();
                    var sidebarWidth = sidebarRect.width;
                    var viewportWidth = window.innerWidth;
                    var availableWidth = viewportWidth - sidebarWidth;
                    
                    // 更新CSS变量
                    document.documentElement.style.setProperty('--sidebar-width', sidebarWidth + 'px');
                    
                    // 只设置margin-left，不设置width，让CSS的calc()来处理宽度
                    // 这样可以避免内联样式覆盖CSS样式，确保子元素的width: 100%能够正确工作
                    if (topBanner) {
                        topBanner.style.marginLeft = sidebarWidth + 'px';
                        // 移除width设置，使用CSS calc()
                        topBanner.style.width = '';
                    }
                    if (contentArea) {
                        contentArea.style.marginLeft = sidebarWidth + 'px';
                        // 移除width设置，使用CSS calc()，确保子元素的width: 100%能够正确工作
                        contentArea.style.width = '';
                    }
                    
                    // 显示元素（防止闪烁）
                    if (topBanner) {
                        topBanner.classList.add('layout-ready');
                    }
                    if (contentArea) {
                        contentArea.classList.add('layout-ready');
                    }
                } else {
                    // 如果sidebar还没加载，使用默认值
                    document.documentElement.style.setProperty('--sidebar-width', '200px');
                    // 即使sidebar没加载，也显示元素（避免一直隐藏）
                    if (topBanner) {
                        topBanner.classList.add('layout-ready');
                    }
                    if (contentArea) {
                        contentArea.classList.add('layout-ready');
                    }
                }
            }
            
            // 立即执行一次
            syncSidebarWidthImmediate();
            
            // 如果DOM已经加载，立即执行
            if (document.readyState === 'complete' || document.readyState === 'interactive') {
                syncSidebarWidthImmediate();
            }
            
            // DOMContentLoaded时执行
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', syncSidebarWidthImmediate);
            }
            
            // 窗口大小改变时执行
            window.addEventListener('resize', syncSidebarWidthImmediate);
            
            // 使用MutationObserver监听DOM变化，确保sidebar加载后立即更新
            if (typeof MutationObserver !== 'undefined') {
                var observer = new MutationObserver(function(mutations) {
                    var sidebar = document.querySelector('.sidebar');
                    if (sidebar) {
                        syncSidebarWidthImmediate();
                        // 延迟一点再停止观察，确保所有元素都已加载
                        setTimeout(function() {
                            observer.disconnect();
                        }, 100);
                    }
                });
                // 如果body还没加载，等待body加载
                if (document.body) {
                    observer.observe(document.body, { childList: true, subtree: true });
                } else {
                    // 等待body加载
                    if (document.readyState === 'loading') {
                        document.addEventListener('DOMContentLoaded', function() {
                            if (document.body) {
                                observer.observe(document.body, { childList: true, subtree: true });
                            }
                        });
                    }
                }
            }
            
            // 使用requestAnimationFrame确保在下一帧执行（更早的时机）
            if (typeof requestAnimationFrame !== 'undefined') {
                requestAnimationFrame(function() {
                    syncSidebarWidthImmediate();
                });
            }
        })();
    


        // 设置当前页面的菜单项为激活状态
        (function() {
            const currentPath = window.location.pathname;
            const menuItems = document.querySelectorAll('.menu-item');
            menuItems.forEach(item => {
                const href = item.getAttribute('href');
                if (href && (currentPath === href || currentPath.startsWith(href + '/'))) {
                    item.classList.add('active');
                }
            });
        })();
        
        // 确保顶部banner高度与左侧logo栏高度一致，并完美对齐
        // 同时确保top-banner和content-area紧贴sidebar，无间隙
        (function() {
            function syncBannerHeight() {
                const sidebarHeader = document.querySelector('.sidebar-header');
                const topBanner = document.querySelector('.top-banner');
                if (sidebarHeader && topBanner) {
                    // 使用getBoundingClientRect获取精确高度（包括padding和border）
                    const headerRect = sidebarHeader.getBoundingClientRect();
                    const headerHeight = headerRect.height;
                    
                    // 在Grid布局中，设置min-height确保对齐，同时保持Grid的自动高度管理
                    topBanner.style.minHeight = headerHeight + 'px';
                    
                    // 确保垂直居中对齐
                    topBanner.style.display = 'flex';
                    topBanner.style.alignItems = 'center';
                }
            }
            
            // 同步sidebar宽度，使top-banner和content-area紧贴sidebar
            function syncSidebarWidth() {
                const sidebar = document.querySelector('.sidebar');
                const topBanner = document.querySelector('.top-banner');
                const contentArea = document.querySelector('.content-area');
                
                if (sidebar && topBanner && contentArea) {
                    // 获取sidebar的实际宽度（包括所有边框和padding）
                    const sidebarRect = sidebar.getBoundingClientRect();
                    const sidebarWidth = sidebarRect.width;
                    
                    // 获取视口宽度
                    const viewportWidth = window.innerWidth;
                    
                    // 计算content-area和top-banner的可用宽度
                    // 确保不会超出屏幕
                    const availableWidth = viewportWidth - sidebarWidth;
                    
                    // 更新CSS变量（与head中的脚本保持一致）
                    document.documentElement.style.setProperty('--sidebar-width', sidebarWidth + 'px');
                    
                    // 设置top-banner和content-area的左边距等于sidebar宽度
                    // 这样它们就会紧贴sidebar的右边，无间隙
                    // 不设置width，使用CSS calc()来处理宽度，避免内联样式覆盖CSS样式
                    topBanner.style.marginLeft = sidebarWidth + 'px';
                    topBanner.style.width = '';
                    contentArea.style.marginLeft = sidebarWidth + 'px';
                    // 移除width设置，使用CSS calc()，确保子元素的width: 100%能够正确工作
                    contentArea.style.width = '';
                }
            }
            
            // 页面加载时同步（延迟一点确保DOM完全渲染）
            function initSync() {
                // 立即执行一次，防止闪烁
                syncBannerHeight();
                syncSidebarWidth();
                // 再次同步，确保字体加载后高度正确
                setTimeout(function() {
                    syncBannerHeight();
                    syncSidebarWidth();
                }, 100);
                // 第三次同步，确保所有资源加载完成（防止网络卡顿时的闪烁）
                setTimeout(function() {
                    syncBannerHeight();
                    syncSidebarWidth();
                }, 300);
            }
            
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', initSync);
            } else {
                initSync();
            }
            
            // 窗口大小改变时重新同步
            window.addEventListener('resize', function() {
                syncBannerHeight();
                syncSidebarWidth();
            });
            
            // 字体加载完成后重新同步
            if (document.fonts && document.fonts.ready) {
                document.fonts.ready.then(function() {
                    syncBannerHeight();
                    syncSidebarWidth();
                });
            }
        })();
        
        // CSRF Token 管理
        (function() {
            let csrfToken = null;
            
            // 获取 CSRF Token
            window.getCsrfToken = function() {
                return csrfToken;
            };
            
            // 设置 CSRF Token
            window.setCsrfToken = function(token) {
                csrfToken = token;
            };
            
            // 从服务器获取 CSRF Token
            function fetchCsrfToken() {
                // 先检查 sessionStorage（从登录页面存储的）
                const storedToken = sessionStorage.getItem('csrf_token');
                if (storedToken) {
                    csrfToken = storedToken;
                    sessionStorage.removeItem('csrf_token'); // 使用后清除
                    console.log('CSRF token loaded from sessionStorage');
                    return;
                }
                
                // 从服务器获取
                fetch('/api/auth/check')
                    .then(response => response.json())
                    .then(data => {
                        if (data && data.authenticated && data.csrf_token) {
                            csrfToken = data.csrf_token;
                            console.log('CSRF token loaded from server');
                        }
                    })
                    .catch(err => {
                        console.warn('Failed to fetch CSRF token:', err);
                    });
            }
            
            // 页面加载时获取 CSRF Token
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', fetchCsrfToken);
            } else {
                fetchCsrfToken();
            }
            
            // 重写 fetch 函数，自动添加 CSRF Token
            const originalFetch = window.fetch;
            window.fetch = function(url, options = {}) {
                // 检查是否需要 CSRF Token（POST、PUT、DELETE、PATCH）
                const method = (options.method || 'GET').toUpperCase();
                if (['POST', 'PUT', 'DELETE', 'PATCH'].includes(method)) {
                    // 确保 headers 存在
                    if (!options.headers) {
                        options.headers = {};
                    }
                    
                    // 如果还没有设置 X-CSRF-Token，添加它
                    if (!options.headers['X-CSRF-Token'] && !options.headers['x-csrf-token']) {
                        const token = getCsrfToken();
                        if (token) {
                            // 处理 Headers 对象或普通对象
                            if (options.headers instanceof Headers) {
                                options.headers.set('X-CSRF-Token', token);
                            } else {
                                options.headers['X-CSRF-Token'] = token;
                            }
                        }
                    }
                }
                
                return originalFetch.call(this, url, options);
            };
        })();
        
        // 处理登出链接点击（确保跳转到登录页面）
        (function() {
            const logoutLinks = document.querySelectorAll('a[href="/api/auth/logout"]');
            logoutLinks.forEach(link => {
                link.addEventListener('click', function(e) {
                    // 允许默认行为（GET请求会重定向），但也可以使用fetch确保跳转
                    // 如果链接被阻止，使用fetch处理
                    if (e.defaultPrevented) {
                        e.preventDefault();
                        fetch('/api/auth/logout', { method: 'POST' })
                            .then(() => {
                                window.location.href = '/login';
                            })
                            .catch(() => {
                                window.location.href = '/login';
                            });
                    }
                });
            });
        })();