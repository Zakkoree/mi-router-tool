let timer = null;

/**
 * 1. 渲染 HTML 结构
 */
export function render() {
    return `
    <div class="space-y-6 animate-fade-in">
        
        <div class="relative overflow-hidden bg-gradient-to-r from-blue-600 to-indigo-700 rounded-3xl p-6 sm:p-8 text-white shadow-xl shadow-blue-500/10">
            <!-- 使用 flex-col md:flex-row 实现移动端上下堆叠、大屏左右分列 -->
            <div class="relative z-10 flex flex-col md:flex-row md:items-center justify-between gap-4">
                
                <!-- 左侧：标题与描述 -->
                <div class="space-y-1.5">
                    <h1 class="text-2xl sm:text-3xl font-extrabold tracking-tight">欢迎使用 MIKIT</h1>
                    <p class="text-blue-100/90 text-sm max-w-xl">
                        通过统一控制台管理您的轻量化网络服务、应用状态及系统配置。
                    </p>
                </div>
        
                <!-- 右侧：警告标签（独立居右） -->
                <div class="shrink-0">
                    <div class="inline-flex items-center gap-2.5 px-3.5 py-2 rounded-xl bg-amber-500/15 border border-amber-400/30 text-amber-200 text-xs sm:text-sm font-medium backdrop-blur-md shadow-sm transition-all hover:bg-amber-500/20">
                        <!-- 警示动画圆点 -->
                        <span class="relative flex h-2 w-2">
                            <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-amber-400 opacity-75"></span>
                            <span class="relative inline-flex rounded-full h-2 w-2 bg-amber-400"></span>
                        </span>
                        
                        <!-- 警告文字 -->
                        <span>
                            <strong class="font-medium text-amber-300">安全提示：</strong><span class="text-amber-200/90">未鉴权 · 注意风险</span>
                        </span>
                    </div>
                </div>
        
            </div>
        
            <!-- 背景装饰气泡 -->
            <div class="absolute -right-10 -bottom-10 w-64 h-64 bg-white/5 rounded-full blur-2xl pointer-events-none"></div>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5 gap-4">
            
            <div class="bg-white p-5 rounded-2xl border border-slate-200/80 shadow-sm hover:shadow-md transition-shadow flex items-center justify-between">
                <div>
                    <span class="text-xs font-bold text-slate-400 tracking-wider uppercase">系统版本</span>
                    <div class="text-2xl font-black text-slate-900 mt-1" id="statVersion">--</div>
                    <span class="text-xs text-slate-400 font-medium">MIKIT Core</span>
                </div>
                <div class="w-12 h-12 rounded-2xl bg-blue-50 text-blue-600 flex items-center justify-center shrink-0">
                    <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                    </svg>
                </div>
            </div>

            <div class="bg-white p-5 rounded-2xl border border-slate-200/80 shadow-sm hover:shadow-md transition-shadow flex items-center justify-between">
                <div>
                    <span class="text-xs font-bold text-slate-400 tracking-wider uppercase">运行时间</span>
                    <div class="text-2xl font-black text-slate-900 mt-1" id="statUptime">--</div>
                    <span class="text-xs text-emerald-600 font-medium">连续在线</span>
                </div>
                <div class="w-12 h-12 rounded-2xl bg-blue-50 text-blue-600 flex items-center justify-center shrink-0">
                    <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                </div>
            </div>
            
            <div class="bg-white p-5 rounded-2xl border border-slate-200/80 shadow-sm hover:shadow-md transition-shadow flex items-center justify-between">
                <div>
                    <span class="text-xs font-bold text-slate-400 tracking-wider uppercase">设备温度</span>
                    <div class="text-2xl font-black text-slate-900 mt-1" id="statTemp">--</div>
                    <span class="text-xs text-emerald-600 font-medium">状态良好</span>
                </div>
                <div class="w-12 h-12 rounded-2xl bg-blue-50 text-blue-600 flex items-center justify-center shrink-0">
                    <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
                    </svg>
                </div>
            </div>

            <div class="bg-white p-5 rounded-2xl border border-slate-200/80 shadow-sm hover:shadow-md transition-shadow flex items-center justify-between">
                <div>
                    <span class="text-xs font-bold text-slate-400 tracking-wider uppercase">内存占用</span>
                    <div class="text-2xl font-black text-slate-900 mt-1" id="statMem">--</div>
                    <span class="text-xs text-slate-400 font-medium" id="statMemPct">已用 --%</span>
                </div>
                <div class="w-12 h-12 rounded-2xl bg-blue-50 text-blue-600 flex items-center justify-center shrink-0">
                    <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M9 17v-2m3 2v-4m3 4v-6m2 10H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                    </svg>
                </div>
            </div>

            <div class="bg-white p-5 rounded-2xl border border-slate-200/80 shadow-sm hover:shadow-md transition-shadow flex items-center justify-between sm:col-span-2 lg:col-span-1">
                <div>
                    <span class="text-xs font-bold text-slate-400 tracking-wider uppercase">已装应用</span>
                    <div class="text-2xl font-black text-slate-900 mt-1" id="appSum">--</div>
                    <span class="text-xs text-slate-400 font-medium">MIKIT Apps</span>
                </div>
                <div class="w-12 h-12 rounded-2xl bg-blue-50 text-blue-600 flex items-center justify-center shrink-0">
                    <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
                    </svg>
                </div>
            </div>

        </div>

        <div class="bg-white p-6 rounded-2xl border border-slate-200/80 shadow-sm space-y-4">
            <h2 class="font-bold text-slate-900 text-base">快捷入口</h2>
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                
                <a href="javascript:void(0)" onclick="navTo('apps')" class="p-4 rounded-xl border border-slate-100 bg-slate-50/50 hover:bg-blue-50/50 hover:border-blue-200 transition-all duration-200 group flex items-center gap-3">
                    <div class="w-10 h-10 rounded-lg bg-white border border-slate-200 flex items-center justify-center text-slate-600 group-hover:text-blue-600 group-hover:border-blue-300 transition-colors shrink-0">
                        <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z" />
                        </svg>
                    </div>
                    <div>
                        <div class="font-bold text-sm text-slate-800 group-hover:text-blue-600">应用管理</div>
                        <div class="text-xs text-slate-400">插件启动、停止与配置</div>
                    </div>
                </a>

                <a href="javascript:void(0)" onclick="navTo('store')" class="p-4 rounded-xl border border-slate-100 bg-slate-50/50 hover:bg-blue-50/50 hover:border-blue-200 transition-all duration-200 group flex items-center gap-3">
                    <div class="w-10 h-10 rounded-lg bg-white border border-slate-200 flex items-center justify-center text-slate-600 group-hover:text-blue-600 group-hover:border-blue-300 transition-colors shrink-0">
                        <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M16 11V7a4 4 0 00-8 0v4M5 9h14l1 12H4L5 9z" />
                        </svg>
                    </div>
                    <div>
                        <div class="font-bold text-sm text-slate-800 group-hover:text-blue-600">插件商店</div>
                        <div class="text-xs text-slate-400">扩展更多实用工具与服务</div>
                    </div>
                </a>

                <a href="javascript:void(0)" onclick="navTo('system')" class="p-4 rounded-xl border border-slate-100 bg-slate-50/50 hover:bg-blue-50/50 hover:border-blue-200 transition-all duration-200 group flex items-center gap-3 sm:col-span-2 lg:col-span-1">
                    <div class="w-10 h-10 rounded-lg bg-white border border-slate-200 flex items-center justify-center text-slate-600 group-hover:text-blue-600 group-hover:border-blue-300 transition-colors shrink-0">
                        <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                            <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                        </svg>
                    </div>
                    <div>
                        <div class="font-bold text-sm text-slate-800 group-hover:text-blue-600">系统设置</div>
                        <div class="text-xs text-slate-400">调整系统基础参数及网络配置</div>
                    </div>
                </a>

            </div>
        </div>

    </div>
    `;
}

/**
 * 2. 挂载完成
 */
export function mount(container) {
    fetchStats();
    // 开启 3 秒轮询
    timer = setInterval(fetchStats, 3000);
}

/**
 * 3. 卸载清除
 */
export function unmount() {
    if (timer) {
        clearInterval(timer);
        timer = null;
    }
}

// 私有数据请求
async function fetchStats() {
    try {
        const res = await window.requestApi('/main/info?target=all');

        if (res && res.data) {
            const version = document.getElementById('statVersion');
            const temp = document.getElementById('statTemp');
            const mem = document.getElementById('statMem');
            const memPct = document.getElementById('statMemPct');
            const uptime = document.getElementById('statUptime');
            const appSum = document.getElementById('appSum');


            // 1. 系统版本动态绑定
            if (version) version.innerText = "v" + res.data.version || 'v0.0.0';

            // 2. 自动处理温度单位
            if (temp) {
                const rawTemp = res.data.temp || '42';
                temp.innerText = String(rawTemp).includes('°C') ? rawTemp : `${rawTemp}°C`;
            }

            // 3. 内存大小与已用百分比
            if (mem) mem.innerText = res.data.memory || '-- MB';
            if (memPct) {
                memPct.innerText = res.data.mem_percent ? `已用 ${res.data.mem_percent}` : '已用 --%';
            }

            // 4. 运行时间
            if (uptime) uptime.innerText = res.data.uptime || '--';

            if (appSum) appSum.innerText = res.data.appSum || '0';
        }
    } catch (e) {
        console.error('获取状态失败:', e);
    }
}