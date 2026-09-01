let timer = null;
let loadedStoreApps = []; // 本地缓存商店数据，用于实时搜索

/**
 * 通用图标渲染函数：自动区分 Base64、网络图片与普通 Emoji/字符
 */
function renderAppIcon(iconData) {
    if (!iconData) return '📦';

    // 判断是否为 Base64 图片或图片链接
    const isImage = iconData.startsWith('data:image/') ||
        iconData.startsWith('http://') ||
        iconData.startsWith('https://') ||
        iconData.startsWith('/');

    if (isImage) {
        return `<img src="${iconData}" class="w-full h-full object-contain p-1" alt="App Icon" />`;
    }

    return iconData;
}

/**
 * 1. 渲染页面基础 HTML 结构
 */
export function render() {
    return `
    <div class="max-w-7xl mx-auto space-y-5 animate-fade-in">
        
        <!-- 头部 Banner 与操作区 -->
        <div class="relative overflow-hidden bg-gradient-to-r from-blue-600 to-indigo-700 rounded-3xl p-6 sm:p-8 text-white shadow-xl shadow-blue-500/10">
            <div class="relative z-10 flex flex-col md:flex-row md:items-center justify-between gap-4">
                <div class="space-y-1.5">
                    <h1 class="text-2xl sm:text-3xl font-extrabold tracking-tight">插件商店</h1>
                    <p class="text-blue-100/90 text-xs sm:text-sm max-w-xl">
                        探索并安装丰富的功能扩展，一键提升您的路由器与网络服务体验。
                    </p>
                </div>
                
                <!-- 右侧搜索与刷新 -->
                <div class="flex items-center gap-2.5 w-full md:w-auto">
                    <!-- 搜索框 -->
                    <div class="relative w-full md:w-56">
                        <input type="text" id="storeSearchInput" placeholder="搜索商店应用..." class="w-full pl-8 pr-3 py-2 bg-white/10 hover:bg-white/15 focus:bg-white text-white placeholder-blue-200 focus:placeholder-slate-400 border border-white/20 focus:border-white rounded-xl text-xs focus:outline-none focus:text-slate-800 transition backdrop-blur-md">
                        <svg class="w-3.5 h-3.5 text-blue-200 absolute left-2.5 top-1/2 -translate-y-1/2 pointer-events-none" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/>
                        </svg>
                    </div>

                    <!-- 刷新按钮 -->
                    <button id="storeRefreshBtn" onclick="window.storeModule.fetchStoreApps()" title="刷新应用列表" class="p-2 border border-white/20 hover:bg-white/10 rounded-xl text-white backdrop-blur-md transition shadow-xs active:scale-95 shrink-0">
                        <svg id="storeRefreshIcon" class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                        </svg>
                    </button>
                </div>
            </div>
            <div class="absolute -right-10 -bottom-10 w-64 h-64 bg-white/5 rounded-full blur-2xl pointer-events-none"></div>
        </div>

        <!-- 应用网格列表容器 -->
        <div id="storeGrid" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-2 xl:grid-cols-2 gap-3.5">
            ${renderSkeleton()}
        </div>

    </div>
    `;
}

/**
 * 构建全屏 Modal 详情弹窗 HTML
 */
function buildModalHtml() {
    return `
    <div id="storeDetailModal" class="fixed inset-0 z-[9999] flex items-center justify-center p-4 bg-slate-900/50 backdrop-blur-xs hidden transition-opacity">
        <div class="bg-white w-full max-w-sm sm:max-w-md rounded-2xl shadow-xl border border-slate-100 overflow-hidden transform transition-all" onclick="event.stopPropagation()">
            
            <!-- Modal Header -->
            <div class="px-5 py-4 border-b border-slate-100/80 bg-slate-50/50">
                <div class="flex items-center justify-between gap-3">
                    
                    <div class="flex items-center gap-3 min-w-0">
                        <div id="modalStoreAppIcon" class="w-10 h-10 bg-white rounded-xl flex items-center justify-center text-xl border border-slate-200/70 shadow-2xs shrink-0 overflow-hidden">
                            📦
                        </div>
                        
                        <div class="min-w-0 flex flex-col justify-center">
                            <div class="flex items-center gap-1.5">
                                <h4 id="modalStoreAppName" class="text-sm font-bold text-slate-800 leading-snug truncate">
                                    应用名称
                                </h4>
                                <span id="modalStoreAppVersion" class="text-[9px] text-slate-500 font-mono font-medium px-1 py-0.2 bg-slate-100 rounded border border-slate-200/60 leading-none shrink-0">
                                    v1.0.0
                                </span>
                            </div>
                            
                            <div id="modalStoreAppAuthor" class="text-[11px] text-slate-400 leading-tight truncate mt-0.5">
                                作者
                            </div>
                        </div>
                    </div>
                    
                    <div class="flex items-center gap-2.5 shrink-0">
                        <div id="modalStoreAppBadge" class="flex items-center"></div>
            
                        <button 
                            onclick="window.storeModule.closeDetailModal()" 
                            class="w-7 h-7 flex items-center justify-center rounded-lg text-slate-400 hover:text-slate-600 hover:bg-slate-200/50 transition active:scale-95"
                            title="关闭"
                        >
                            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                                <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12"/>
                            </svg>
                        </button>
                    </div>
            
                </div>
            </div>

            <!-- Modal Content -->
            <div class="p-5 space-y-4 text-xs">
                
                <!-- 源地址信息 -->
                <div id="modalStoreUrlWrapper" class="space-y-1">
                    <label class="text-[10px] font-semibold text-slate-400 uppercase tracking-wider block">
                        应用源码
                    </label>
                    <div class="flex items-center justify-between gap-2 px-3 py-1.5 bg-slate-50 border border-slate-200/70 rounded-xl hover:border-slate-300 transition">
                        <div class="flex items-center gap-2 min-w-0 flex-1">
                            <svg class="w-3.5 h-3.5 text-slate-400 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                                <path stroke-linecap="round" stroke-linejoin="round" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"/>
                            </svg>
                            <a id="modalStoreAppUrl" href="#" target="_blank" class="text-blue-600 font-mono text-[11px] hover:underline truncate flex-1">
                                https://github.com
                            </a>
                        </div>
                    </div>
                </div>
            
                <!-- 应用描述 -->
                <div class="space-y-1">
                    <label class="text-[10px] font-semibold text-slate-400 uppercase tracking-wider block">
                        应用简介
                    </label>
                    <div class="p-2.5 bg-slate-50/80 border border-slate-100 rounded-xl text-slate-600 text-xs leading-relaxed">
                        <p id="modalStoreAppDesc">暂无详细描述</p>
                    </div>
                </div>

                <!-- 架构兼容性警告提示 (若不兼容显示) -->
                <div id="modalStoreCompatWarn" class="hidden px-3 py-2 bg-rose-50 border border-rose-200/80 rounded-xl text-rose-600 text-[11px] font-medium flex items-center gap-2">
                    <svg class="w-4 h-4 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/></svg>
                    <span id="modalStoreCompatText">当前硬件架构可能与此插件不兼容</span>
                </div>
            
                <!-- 底部操作按钮 -->
                <div class="pt-1">
                    <div id="modalStoreActionBtnContainer">
                        <!-- 动态生成安装/更新按钮 -->
                    </div>
                </div>
            
            </div>

        </div>
    </div>
    `;
}

/**
 * 2. 挂载完成
 */
export function mount(container) {
    // 挂载全局方法
    window.storeModule = {
        fetchStoreApps,
        handleAppAction,
        openDetailModal,
        closeDetailModal
    };

    // 动态注入 Modal 弹窗（防止重复插入）
    if (!document.getElementById('storeDetailModal')) {
        document.body.insertAdjacentHTML('beforeend', buildModalHtml());
    }

    // 搜索绑定
    const searchInput = document.getElementById('storeSearchInput');
    if (searchInput) {
        searchInput.addEventListener('input', (e) => filterStoreApps(e.target.value));
    }

    // 首次获取数据
    fetchStoreApps();

    // 10秒轮询
    if (timer) clearInterval(timer);
    timer = setInterval(fetchStoreApps, 10000);
}

/**
 * 3. 卸载清除
 */
export function unmount() {
    if (timer) {
        clearInterval(timer);
        timer = null;
    }
    const modal = document.getElementById('storeDetailModal');
    if (modal) modal.remove();

    delete window.storeModule;
}

/**
 * 拉取应用商店数据
 */
async function fetchStoreApps() {
    const refreshIcon = document.getElementById('storeRefreshIcon');
    if (refreshIcon) refreshIcon.classList.add('animate-spin');

    try {
        const res = await window.requestApi('/store/apps', { showError: false }).catch(() => null);

        if (res && res.code === 0 && Array.isArray(res.data)) {
            loadedStoreApps = res.data;
        } else {
            loadedStoreApps = [];
        }

        renderStoreGrid(loadedStoreApps);
    } catch (e) {
        console.error('获取商店列表失败:', e);
        renderError('无法连接到服务端，请稍后重试');
    } finally {
        setTimeout(() => {
            if (refreshIcon) refreshIcon.classList.remove('animate-spin');
        }, 500);
    }
}

/**
 * 渲染网格列表
 */
function renderStoreGrid(apps) {
    const grid = document.getElementById('storeGrid');
    if (!grid) return;

    if (apps.length === 0) {
        grid.innerHTML = `
            <div class="col-span-full text-center py-12 text-slate-400 text-xs">
                未找到可用的应用或插件
            </div>
        `;
        return;
    }

    grid.innerHTML = apps.map(app => buildCardHtml(app)).join('');
}

/**
 * 单个应用卡片 HTML 构建
 */
function buildCardHtml(app) {
    const versionTag = app.version ? `v${app.version.replace(/^v/, '')}` : '';

    // 1. 按钮样式
    let actionBtn = '';

    if (app.status === 'upgradable') {
        actionBtn = `
            <button onclick="event.stopPropagation(); window.storeModule.handleAppAction('${app.id}', 'upgrade', '${app.name}')" class="w-14 py-1 bg-amber-500 hover:bg-amber-600 text-white rounded-lg text-[11px] font-semibold transition active:scale-95 shrink-0 shadow-2xs">
                更新
            </button>`;
    } else if (app.status === 'installed') {
        actionBtn = `
            <button disabled class="w-14 py-1 bg-slate-100 text-slate-400 border border-slate-200/60 rounded-lg text-[11px] font-semibold shrink-0 cursor-not-allowed">
                已安装
            </button>`;
    } else {
        actionBtn = `
            <button onclick="event.stopPropagation(); window.storeModule.handleAppAction('${app.id}', 'install', '${app.name}')" class="w-14 py-1 bg-blue-600 hover:bg-blue-700 text-white rounded-lg text-[11px] font-semibold transition active:scale-95 shrink-0 shadow-2xs">
                安装
            </button>`;
    }

    // 2. 架构不匹配提示
    let compatBadge = '';
    if (app.is_compatible === false) {
        compatBadge = `
            <span class="inline-flex items-center gap-0.5 px-1 py-0.2 bg-rose-50 border border-rose-200/60 text-rose-500 rounded text-[9px] leading-none shrink-0" title="架构不匹配 (${app.arch || '未知'})">
                <svg class="w-2.5 h-2.5 shrink-0 text-rose-500" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
                </svg>
                <span>架构不匹配</span>
            </span>
        `;
    }

    return `
    <div class="bg-white p-3.5 rounded-2xl border border-slate-200/80 shadow-2xs hover:shadow-xs hover:border-slate-300 transition flex items-center justify-between gap-3 group" id="store-card-${app.id}">
        <!-- 左侧：图标 + 名称/版本/架构警告 + 描述 -->
        <div class="flex items-center gap-3 min-w-0 flex-1 cursor-pointer" onclick="window.storeModule.openDetailModal('${app.id}')">
            <!-- 动态图标容器 -->
            <div class="w-10 h-10 bg-slate-50 group-hover:bg-blue-50/50 rounded-xl flex items-center justify-center text-xl border border-slate-100 group-hover:border-blue-100 transition shrink-0 overflow-hidden">
                ${renderAppIcon(app.icon)}
            </div>
            
            <div class="min-w-0 flex-1">
                <!-- 头部第一行：名称 + 版本号 + 架构不匹配 -->
                <div class="flex items-center gap-1.5">
                    <span class="font-bold text-slate-800 text-xs truncate group-hover:text-blue-600 transition">
                        ${app.name}
                    </span>
                    ${versionTag ? `
                        <span class="text-[9px] text-slate-400 font-mono px-1 py-0.2 bg-slate-50 rounded border border-slate-200/50 leading-none shrink-0">
                            ${versionTag}
                        </span>
                    ` : ''}
                    ${compatBadge}
                </div>
                <!-- 头部第二行：简介 -->
                <p class="text-[11px] text-slate-400 truncate mt-0.5 leading-tight" title="${app.desc || app.id}">
                    ${app.desc || app.id}
                </p>
            </div>
        </div>
        
        <!-- 右侧：操作按钮 -->
        <div class="flex items-center gap-2 shrink-0">
            ${actionBtn}
        </div>
    </div>
    `;
}

/**
 * 展开 Modal 详情
 */
function openDetailModal(appId) {
    const app = loadedStoreApps.find(a => a.id === appId);
    if (!app) return;

    const modal = document.getElementById('storeDetailModal');
    if (!modal) return;

    // 1. 基础数据填充
    document.getElementById('modalStoreAppIcon').innerHTML = renderAppIcon(app.icon);
    document.getElementById('modalStoreAppName').innerText = app.name || '未知应用';
    document.getElementById('modalStoreAppVersion').innerText = app.version ? `v${app.version.replace(/^v/, '')}` : 'v1.0.0';
    document.getElementById('modalStoreAppAuthor').innerText = `${app.id} by ${app.author || '未知作者'} · [${app.source_id || 'mikit'}]`;
    document.getElementById('modalStoreAppDesc').innerText = app.desc || '暂无详细描述';

    // 2. URL
    const urlWrapper = document.getElementById('modalStoreUrlWrapper');
    const urlEl = document.getElementById('modalStoreAppUrl');
    if (app.url || app.source_url) {
        const targetUrl = app.url || app.source_url;
        urlEl.href = targetUrl;
        urlEl.innerText = targetUrl;
        urlWrapper.classList.remove('hidden');
    } else {
        urlWrapper.classList.add('hidden');
    }

    // 3. 状态标签
    const badgeMap = {
        upgradable: '<span class="inline-flex items-center gap-1 px-2 py-0.5 bg-amber-50 text-amber-600 rounded-full text-[10px] font-medium"><span class="w-1.5 h-1.5 rounded-full bg-amber-500 animate-pulse"></span>可更新</span>',
        installed: '<span class="inline-flex items-center gap-1 px-2 py-0.5 bg-emerald-50 text-emerald-600 rounded-full text-[10px] font-medium"><span class="w-1.5 h-1.5 rounded-full bg-emerald-500"></span>已安装</span>',
        uninstalled: '<span class="inline-flex items-center gap-1 px-2 py-0.5 bg-slate-100 text-slate-400 rounded-full text-[10px] font-medium"><span class="w-1.5 h-1.5 rounded-full bg-slate-400"></span>未安装</span>'
    };
    document.getElementById('modalStoreAppBadge').innerHTML = badgeMap[app.status] || badgeMap.uninstalled;

    // 4. 兼容性警告
    const compatWarn = document.getElementById('modalStoreCompatWarn');
    if (app.is_compatible === false) {
        document.getElementById('modalStoreCompatText').innerText = `硬件架构不匹配 (${app.arch || '未知'})，强行安装可能无法运行`;
        compatWarn.classList.remove('hidden');
    } else {
        compatWarn.classList.add('hidden');
    }

    // 5. 动态按键渲染
    const actionContainer = document.getElementById('modalStoreActionBtnContainer');
    if (actionContainer) {
        let actionBtnHtml = '';

        if (app.status === 'upgradable') {
            actionBtnHtml = `
                <button onclick="window.storeModule.closeDetailModal(); window.storeModule.handleAppAction('${app.id}', 'upgrade', '${app.name}')" class="w-full py-2.5 bg-amber-500 hover:bg-amber-600 text-white rounded-xl text-xs font-bold transition shadow-xs">
                    立即更新插件
                </button>`;
        } else if (app.status === 'installed') {
            actionBtnHtml = `
                <button disabled class="w-full py-2.5 bg-slate-100 text-slate-400 rounded-xl text-xs font-bold cursor-not-allowed">
                    插件已安装
                </button>`;
        } else {
            actionBtnHtml = `
                <button onclick="window.storeModule.closeDetailModal(); window.storeModule.handleAppAction('${app.id}', 'install', '${app.name}')" class="w-full py-2.5 bg-blue-600 hover:bg-blue-700 text-white rounded-xl text-xs font-bold transition shadow-xs">
                    安装插件
                </button>`;
        }
        actionContainer.innerHTML = actionBtnHtml;
    }

    modal.classList.remove('hidden');
    modal.onclick = closeDetailModal;
}

function closeDetailModal() {
    const modal = document.getElementById('storeDetailModal');
    if (modal) modal.classList.add('hidden');
}

/**
 * 触发安装/更新操作
 */
async function handleAppAction(appId, action, appName) {
    window.showToast(`功能正在开发中...`, 'info');
    return;
    const actionTextMap = { install: '安装', upgrade: '更新' };
    const actionText = actionTextMap[action] || '操作';

    if (!confirm(`确定要${actionText}【${appName || appId}】吗？`)) return;

    if (window.showToast) {
        window.showToast(`正在${actionText}【${appName || appId}】...`, 'info');
    }

    try {
        const res = await window.requestApi(`/store/app/${action}`, {
            method: 'POST',
            body: JSON.stringify({ id: appId })
        });

        if (res && res.code === 0) {
            if (window.showToast) {
                window.showToast(`【${appName || appId}】${actionText}成功！`, 'info');
            }
            fetchStoreApps(); // 刷新数据
        } else {
            throw new Error(res?.msg || `${actionText}失败！`);
        }
    } catch (err) {
        if (window.showToast) {
            window.showToast(err?.message || `${actionText}失败，请检查系统日志`, 'error');
        }
    }
}

/**
 * 本地搜索筛选
 */
function filterStoreApps(keyword) {
    const term = keyword.toLowerCase().trim();
    const filtered = loadedStoreApps.filter(app =>
        (app.name && app.name.toLowerCase().includes(term)) ||
        (app.id && app.id.toLowerCase().includes(term)) ||
        (app.desc && app.desc.toLowerCase().includes(term)) ||
        (app.author && app.author.toLowerCase().includes(term))
    );
    renderStoreGrid(filtered);
}

/**
 * 骨架屏
 */
function renderSkeleton() {
    return Array(4).fill(0).map(() => `
        <div class="bg-white p-3.5 rounded-2xl border border-slate-200/80 shadow-2xs animate-pulse flex items-center justify-between gap-3">
            <div class="flex items-center gap-3 flex-1">
                <div class="w-10 h-10 bg-slate-100 rounded-xl shrink-0"></div>
                <div class="space-y-1.5 flex-1">
                    <div class="h-3 bg-slate-100 rounded w-1/3"></div>
                    <div class="h-2.5 bg-slate-100 rounded w-2/3"></div>
                </div>
            </div>
            <div class="w-14 h-6 bg-slate-100 rounded-lg shrink-0"></div>
        </div>
    `).join('');
}

/**
 * 渲染错误提示
 */
function renderError(msg) {
    const grid = document.getElementById('storeGrid');
    if (!grid) return;

    grid.innerHTML = `
        <div class="col-span-full py-12 text-center space-y-3">
            <div class="text-rose-500 font-medium text-xs">❌ ${msg}</div>
            <button onclick="window.storeModule.fetchStoreApps()" class="px-3 py-1.5 bg-slate-100 hover:bg-slate-200 text-slate-600 rounded-xl text-xs font-semibold transition active:scale-95">
                重试
            </button>
        </div>
    `;
}