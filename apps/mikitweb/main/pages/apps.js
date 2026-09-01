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

let statusTimer = null;
let loadedApps = [];

/**
 * 1. 渲染页面基础 HTML 结构（已更新为统一的蓝色渐变 Banner Header）
 */
export function render() {
    return `
    <div class="max-w-7xl mx-auto space-y-5 animate-fade-in">
        
        <!-- 统一风格的头部 Banner 与操作区 -->
        <div class="relative overflow-hidden bg-gradient-to-r from-blue-600 to-indigo-700 rounded-3xl p-6 sm:p-8 text-white shadow-xl shadow-blue-500/10">
            <div class="relative z-10 flex flex-col md:flex-row md:items-center justify-between gap-4">
                <div class="space-y-1.5">
                    <h1 class="text-2xl sm:text-3xl font-extrabold tracking-tight">应用管理</h1>
                    <p class="text-blue-100/90 text-xs sm:text-sm max-w-xl">
                        查看并控制已安装插件与应用服务的运行状态，快捷配置网络扩展。
                    </p>
                </div>
                
                <!-- 右侧搜索与刷新 -->
                <div class="flex items-center gap-2.5 w-full md:w-auto">
                    <!-- 搜索框 -->
                    <div class="relative w-full md:w-56">
                        <input type="text" id="appSearchInput" placeholder="搜索已安装应用..." class="w-full pl-8 pr-3 py-2 bg-white/10 hover:bg-white/15 focus:bg-white text-white placeholder-blue-200 focus:placeholder-slate-400 border border-white/20 focus:border-white rounded-xl text-xs focus:outline-none focus:text-slate-800 transition backdrop-blur-md">
                        <svg class="w-3.5 h-3.5 text-blue-200 absolute left-2.5 top-1/2 -translate-y-1/2 pointer-events-none" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/>
                        </svg>
                    </div>

                    <!-- 刷新按钮 -->
                    <button id="refreshBtn" onclick="window.appModule.manualRefresh()" title="刷新应用状态" class="p-2 border border-white/20 hover:bg-white/10 rounded-xl text-white backdrop-blur-md transition shadow-xs active:scale-95 shrink-0">
                        <svg id="refreshIcon" class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                        </svg>
                    </button>
                </div>
            </div>
            <div class="absolute -right-10 -bottom-10 w-64 h-64 bg-white/5 rounded-full blur-2xl pointer-events-none"></div>
        </div>

        <!-- 应用卡片网格容器 -->
        <div id="appListContainer" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-2 xl:grid-cols-2 gap-3.5">
            <div class="col-span-full flex justify-center py-12 text-slate-400 text-xs">正在获取应用列表...</div>
        </div>

    </div>
    `;
}

// 独立构建全屏 Modal 容器
function buildModalHtml() {
    return `
    <div id="appDetailModal" class="fixed inset-0 z-[9999] flex items-center justify-center p-4 bg-slate-900/50 backdrop-blur-xs hidden transition-opacity">
        <div class="bg-white w-full max-w-sm sm:max-w-md rounded-2xl shadow-xl border border-slate-100 overflow-hidden transform transition-all" onclick="event.stopPropagation()">
            
            <!-- Modal Header -->
            <div class="px-5 py-4 border-b border-slate-100/80 bg-slate-50/50">
                <div class="flex items-center justify-between gap-3">
                    
                    <!-- 左侧：图标 + 标题与元信息 -->
                    <div class="flex items-center gap-3 min-w-0">
                        <div id="modalAppIcon" class="w-10 h-10 bg-white rounded-xl flex items-center justify-center text-xl border border-slate-200/70 shadow-2xs shrink-0 overflow-hidden">
                            📦
                        </div>
                        
                        <div class="min-w-0 flex flex-col justify-center">
                            <div class="flex items-center gap-1.5">
                                <h4 id="modalAppName" class="text-sm font-bold text-slate-800 leading-snug truncate">
                                    应用名称
                                </h4>
                                <span id="modalAppVersion" class="text-[10px] text-slate-500 font-mono font-medium px-1.5 py-0.2 bg-slate-100 rounded border border-slate-200/60 leading-none shrink-0">
                                    v1.0.0
                                </span>
                            </div>
                            
                            <div id="modalAppId" class="text-[11px] text-slate-400 font-mono leading-tight truncate mt-0.5">
                                app_id
                            </div>
                        </div>
                    </div>
                    
                    <!-- 右侧：状态胶囊 + 关闭按钮 -->
                    <div class="flex items-center gap-2.5 shrink-0">
                        <div id="modalAppStatus" class="flex items-center"></div>
            
                        <button 
                            onclick="window.appModule.closeDetailModal()" 
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
                
                <!-- 访问入口 (URL) -->
                <div id="modalUrlWrapper" class="space-y-1">
                    <label class="text-[10px] font-semibold text-slate-400 uppercase tracking-wider block">
                        应用地址
                    </label>
                    <div class="flex items-center justify-between gap-2 px-3 py-1.5 bg-slate-50 border border-slate-200/70 rounded-xl hover:border-slate-300 transition">
                        <div class="flex items-center gap-2 min-w-0 flex-1">
                            <svg class="w-3.5 h-3.5 text-slate-400 shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                                <path stroke-linecap="round" stroke-linejoin="round" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"/>
                            </svg>
                            <a id="modalAppUrl" href="#" target="_blank" class="text-blue-600 font-mono text-[11px] hover:underline truncate flex-1">
                                https://github.com
                            </a>
                        </div>
                    </div>
                </div>
            
                <!-- 应用简介 -->
                <div class="space-y-1">
                    <label class="text-[10px] font-semibold text-slate-400 uppercase tracking-wider block">
                        应用简介
                    </label>
                    <div class="p-2.5 bg-slate-50/80 border border-slate-100 rounded-xl text-slate-600 text-xs leading-relaxed">
                        <p id="modalAppDesc">暂无详细描述</p>
                    </div>
                </div>
            
                <!-- 快捷操作 -->
                <div class="pt-0.5 space-y-1.5">
                    <label class="text-[10px] font-semibold text-slate-400 uppercase tracking-wider block">
                        快捷操作
                    </label>
                    <div id="modalActionContainer" class="grid grid-cols-2 gap-2.5">
                        <!-- 动态按键 -->
                    </div>
                </div>
            
            </div>

        </div>
    </div>
    `;
}

export function mount(container) {
    window.appModule = {
        toggleApp,
        uninstallApp,
        manualRefresh,
        openDetailModal,
        closeDetailModal
    };

    if (!document.getElementById('appDetailModal')) {
        document.body.insertAdjacentHTML('beforeend', buildModalHtml());
    }

    fetchAppList();

    if (statusTimer) clearInterval(statusTimer);
    statusTimer = setInterval(() => {
        checkStatuses();
    }, 8000);

    const searchInput = document.getElementById('appSearchInput');
    if (searchInput) {
        searchInput.addEventListener('input', (e) => filterApps(e.target.value));
    }
}

export function unmount() {
    if (statusTimer) {
        clearInterval(statusTimer);
        statusTimer = null;
    }
    const modal = document.getElementById('appDetailModal');
    if (modal) modal.remove();

    delete window.appModule;
}

async function fetchAppList() {
    // 1. 刚进入时开启转圈动画
    const refreshIcon = document.getElementById('refreshIcon');
    if (refreshIcon) refreshIcon.classList.add('animate-spin');

    try {
        const res = await window.requestApi('/app/list', { showError: false }).catch(() => null);

        if (res && res.code === 0 && Array.isArray(res.data)) {
            loadedApps = res.data.map(app => ({ ...app, status: 'unknown' }));
        } else {
            loadedApps = [];
        }

        renderAppGrid(loadedApps);

        if (loadedApps.length > 0) {
            checkStatuses(true);
        }
    } finally {
        // 2. 加载完成（无论成功失败）停止转圈动画
        setTimeout(() => {
            if (refreshIcon) refreshIcon.classList.remove('animate-spin');
        }, 500);
    }
}

async function checkStatuses(isFirstLoad = false) {
    if (!loadedApps || loadedApps.length === 0) return;

    const targetApps = loadedApps.filter(app => app.status !== 'loading');

    targetApps.forEach(async (app) => {
        const res = await window.requestApi(`/app/status?id=${app.id}`, { showError: false }).catch(() => null);

        if (app.status === 'loading') return;

        const newStatus = (res && res.code === 0 && res.data)
            ? (typeof res.data === 'string' ? res.data : (res.data.status || 'stopped'))
            : 'stopped';

        if (app.status !== newStatus || isFirstLoad) {
            app.status = newStatus;
            updateSingleAppCard(app);
        }
    });
}

async function manualRefresh() {
    const icon = document.getElementById('refreshIcon');
    if (icon) icon.classList.add('animate-spin');

    await checkStatuses();

    setTimeout(() => {
        if (icon) icon.classList.remove('animate-spin');
    }, 500);
}

function renderAppGrid(apps) {
    const listEl = document.getElementById('appListContainer');
    if (!listEl) return;

    if (apps.length === 0) {
        listEl.innerHTML = `<div class="col-span-full text-center py-12 text-slate-400 text-xs">未找到相关应用</div>`;
        return;
    }

    listEl.innerHTML = apps.map(app => buildAppCardHtml(app)).join('');
}

function buildAppCardHtml(app) {
    const isRunning = app.status === 'running';
    const isUnknown = app.status === 'unknown';
    const isLoading = app.status === 'loading';

    let buttonText = '启动';
    let buttonClass = 'bg-blue-600 hover:bg-blue-700 text-white border-transparent shadow-2xs';

    if (isUnknown || isLoading) {
        buttonText = isUnknown ? '加载中' : '处理中';
        buttonClass = 'bg-slate-100 border-slate-200 text-slate-400';
    } else if (isRunning) {
        buttonText = '停止';
        buttonClass = 'bg-rose-50 hover:bg-rose-100 text-rose-600 border-rose-200/80';
    }

    let statusText = '已停止';
    let badgeClass = 'bg-slate-100 text-slate-400';
    let dotClass = 'bg-slate-400';

    if (isUnknown) {
        statusText = '检查中';
        badgeClass = 'bg-slate-50 text-slate-400';
        dotClass = 'bg-slate-300 animate-pulse';
    } else if (isLoading) {
        statusText = '切换中';
        badgeClass = 'bg-blue-50 text-blue-500';
        dotClass = 'bg-blue-500 animate-pulse';
    } else if (isRunning) {
        statusText = '运行中';
        badgeClass = 'bg-emerald-50 text-emerald-600';
        dotClass = 'bg-emerald-500 animate-pulse';
    }

    const versionTag = app.version ? `v${app.version.replace(/^v/, '')}` : '';

    return `
    <div class="bg-white p-3.5 rounded-2xl border border-slate-200/80 shadow-2xs hover:shadow-xs hover:border-slate-300 transition flex items-center justify-between gap-3 group" id="app-card-${app.id}">
        <!-- 左侧：图标 + 名称/版本 + 简介 -->
        <div class="flex items-center gap-3 min-w-0 flex-1 cursor-pointer" onclick="window.appModule.openDetailModal('${app.id}')">
            <div class="w-10 h-10 bg-slate-50 group-hover:bg-blue-50/50 rounded-xl flex items-center justify-center text-xl border border-slate-100 group-hover:border-blue-100 transition shrink-0 overflow-hidden">
                ${renderAppIcon(app.icon)}
            </div>
            
            <div class="min-w-0 flex-1">
                <div class="flex items-center gap-1.5">
                    <span class="font-bold text-slate-800 text-xs truncate group-hover:text-blue-600 transition">
                        ${app.name}
                    </span>
                    ${versionTag ? `
                        <span class="text-[9px] text-slate-400 font-mono px-1 py-0.2 bg-slate-50 rounded border border-slate-200/50 leading-none shrink-0">
                            ${versionTag}
                        </span>
                    ` : ''}
                </div>
                <p class="text-[11px] text-slate-400 truncate mt-0.5 leading-tight" title="${app.desc || app.id}">
                    ${app.desc || app.id}
                </p>
            </div>
        </div>
        
        <!-- 右侧：状态胶囊 + 区分样式的操作按钮 -->
        <div class="flex items-center gap-2 shrink-0">
            <span class="inline-flex items-center justify-center gap-1.5 px-2.5 py-1 rounded-full text-[10px] font-medium transition-all ${badgeClass}">
                <span class="w-1.5 h-1.5 rounded-full shrink-0 ${dotClass}"></span>
                <span>${statusText}</span>
            </span>

            <button 
                onclick="window.appModule.toggleApp('${app.id}', '${app.status}')" 
                class="w-14 py-1 border rounded-lg text-[11px] font-semibold transition active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center shrink-0 ${buttonClass}" 
                ${(isUnknown || isLoading) ? 'disabled' : ''}
            >
                ${buttonText}
            </button>
        </div>
    </div>
    `;
}

function updateSingleAppCard(app) {
    const cardEl = document.getElementById(`app-card-${app.id}`);
    if (!cardEl) return;

    cardEl.outerHTML = buildAppCardHtml(app);
}

// 展开 Modal 详情
function openDetailModal(appId) {
    const app = loadedApps.find(a => a.id === appId);
    if (!app) return;

    const modal = document.getElementById('appDetailModal');
    if (!modal) return;

    // 1. 填充基础数据 (图标使用 renderAppIcon)
    document.getElementById('modalAppIcon').innerHTML = renderAppIcon(app.icon);
    document.getElementById('modalAppName').innerText = app.name || '未知应用';
    document.getElementById('modalAppVersion').innerText = app.version ? `v${app.version.replace(/^v/, '')}` : 'v1.0.0';
    document.getElementById('modalAppDesc').innerText = app.desc || '暂无详细描述';
    document.getElementById('modalAppId').innerText = `${app.id} by ${app.author || '未知作者'}`;

    // 2. 状态标签
    const badgeMap = {
        running: '<span class="inline-flex items-center gap-1 px-2 py-0.5 bg-emerald-50 text-emerald-600 rounded-full text-[10px] font-medium"><span class="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse"></span>运行中</span>',
        stopped: '<span class="inline-flex items-center gap-1 px-2 py-0.5 bg-slate-100 text-slate-500 rounded-full text-[10px] font-medium"><span class="w-1.5 h-1.5 rounded-full bg-slate-400"></span>已停止</span>',
        loading: '<span class="inline-flex items-center gap-1 px-2 py-0.5 bg-blue-50 text-blue-500 rounded-full text-[10px] font-medium"><span class="w-1.5 h-1.5 rounded-full bg-blue-500 animate-pulse"></span>切换中</span>',
        unknown: '<span class="inline-flex items-center gap-1 px-2 py-0.5 bg-slate-50 text-slate-400 rounded-full text-[10px] font-medium"><span class="w-1.5 h-1.5 rounded-full bg-slate-300 animate-pulse"></span>检查中</span>'
    };
    document.getElementById('modalAppStatus').innerHTML = badgeMap[app.status] || badgeMap.unknown;

    // 3. URL 处理
    const urlWrapper = document.getElementById('modalUrlWrapper');
    const urlEl = document.getElementById('modalAppUrl');
    const targetUrl = app.url || (app.port ? `http://${window.location.hostname}:${app.port}` : null);

    if (targetUrl) {
        urlEl.href = targetUrl;
        urlEl.innerText = targetUrl;
        urlWrapper.classList.remove('hidden');
    } else {
        urlWrapper.classList.add('hidden');
    }

    // 4. 动态构建快捷操作菜单
    const isRunning = app.status === 'running';
    const isBusy = app.status === 'loading' || app.status === 'unknown';

    const playIconSvg = `<svg class="w-3.5 h-3.5 fill-current" viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>`;
    const stopIconSvg = `<svg class="w-3.5 h-3.5 fill-current" viewBox="0 0 24 24"><path d="M6 6h12v12H6z"/></svg>`;
    const trashIconSvg = `<svg class="w-3.5 h-3.5 fill-none stroke-current" viewBox="0 0 24 24" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/></svg>`;

    const actions = [
        {
            id: 'toggle',
            label: isRunning ? '停止应用' : '启动应用',
            icon: isRunning ? stopIconSvg : playIconSvg,
            style: isRunning
                ? 'bg-amber-500 text-white hover:bg-amber-600 border-transparent shadow-xs shadow-amber-500/20'
                : 'bg-blue-600 text-white hover:bg-blue-700 border-transparent shadow-xs shadow-blue-500/20',
            disabled: isBusy,
            onClick: () => {
                closeDetailModal();
                toggleApp(app.id, app.status);
            }
        },
        {
            id: 'uninstall',
            label: '卸载应用',
            icon: trashIconSvg,
            style: 'bg-rose-50 border border-rose-200 text-rose-600 hover:bg-rose-100 hover:border-rose-300',
            disabled: isBusy,
            onClick: () => {
                uninstallApp(app.id, app.name);
            }
        }
    ];

    const actionContainer = document.getElementById('modalActionContainer');
    if (actionContainer) {
        actionContainer.innerHTML = actions.map((act) => `
            <button 
                id="modalBtn_${act.id}"
                class="py-2 px-3 rounded-xl text-xs font-semibold transition-all flex items-center justify-center gap-1.5 disabled:opacity-50 disabled:cursor-not-allowed ${act.style}"
                ${act.disabled ? 'disabled' : ''}
            >
                ${act.icon}
                <span>${act.label}</span>
            </button>
        `).join('');

        actions.forEach(act => {
            const btn = document.getElementById(`modalBtn_${act.id}`);
            if (btn && act.onClick) {
                btn.onclick = act.onClick;
            }
        });
    }

    modal.classList.remove('hidden');
    modal.onclick = closeDetailModal;
}

function closeDetailModal() {
    const modal = document.getElementById('appDetailModal');
    if (modal) modal.classList.add('hidden');
}

// 卸载应用
async function uninstallApp(appId, appName) {
    window.showToast(`功能正在开发中...`, 'info');
    return;
    if (!confirm(`确定要卸载应用【${appName || appId}】吗？此操作不可撤销！`)) {
        return;
    }

    closeDetailModal();

}

function filterApps(keyword) {
    const term = keyword.toLowerCase().trim();
    const filtered = loadedApps.filter(app =>
        (app.name && app.name.toLowerCase().includes(term)) ||
        (app.id && app.id.toLowerCase().includes(term)) ||
        (app.desc && app.desc.toLowerCase().includes(term))
    );
    renderAppGrid(filtered);
}

async function toggleApp(appId, currentStatus) {
    const app = loadedApps.find(a => a.id === appId);
    if (!app || app.status === 'loading' || app.status === 'unknown') return;

    const oldStatus = app.status;
    app.status = 'loading';
    updateSingleAppCard(app);

    const nextStatus = oldStatus === 'running' ? 'stopped' : 'running';

    try {
        const res = await window.requestApi('/app/toggle', {
            method: 'POST',
            body: JSON.stringify({ id: appId, status: nextStatus })
        });

        if (res && res.code === 0) {
            await new Promise(resolve => setTimeout(resolve, 800));

            const ares = await window.requestApi(`/app/status?id=${app.id}`, { showError: false }).catch(() => null);

            if (ares && ares.code === 0 && ares.data) {
                app.status = typeof ares.data === 'string' ? ares.data : (ares.data.status || nextStatus);
            } else {
                app.status = nextStatus;
            }

            if (window.showToast) {
                window.showToast(`${app.name || '应用'} 操作成功！`, 'info');
            }
        } else {
            throw new Error(res?.msg || '操作失败！');
        }
    } catch (err) {
        app.status = oldStatus;
        if (window.showToast) {
            window.showToast(err?.message || '操作失败！', 'error');
        }
    } finally {
        updateSingleAppCard(app);
    }
}