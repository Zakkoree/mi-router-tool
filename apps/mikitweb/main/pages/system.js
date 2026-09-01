/**
 * 未开发页面组件
 */
export function render() {
    return `
    <div class="space-y-6 animate-fade-in">
        <div class="min-h-[480px] bg-white rounded-3xl border border-slate-200/80 shadow-sm p-8 flex flex-col items-center justify-center text-center">
            
            <!-- 视觉插图与图标 -->
            <div class="relative mb-6">
                <!-- 背景发光底衬 -->
                <div class="absolute inset-0 bg-blue-100/60 rounded-full blur-xl transform scale-125"></div>
                <!-- 图标容器 -->
                <div class="relative w-20 h-20 bg-gradient-to-tr from-blue-500 to-indigo-600 rounded-2xl flex items-center justify-center text-white shadow-lg shadow-blue-500/30">
                    <svg class="w-10 h-10 animate-bounce" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M11 4a2 2 0 114 0v1a1 1 0 001 1h3a1 1 0 011 1v3a1 1 0 01-1 1h-1a2 2 0 100 4h1a1 1 0 011 1v3a1 1 0 01-1 1h-3a1 1 0 01-1-1v-1a2 2 0 10-4 0v1a1 1 0 01-1 1H7a1 1 0 01-1-1v-3a1 1 0 00-1-1H4a2 2 0 110-4h1a1 1 0 001-1V7a1 1 0 011-1h3a1 1 0 001-1V4z" />
                    </svg>
                </div>
            </div>

            <!-- 状态标签 -->
            <div class="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-slate-100 border border-slate-200/60 text-slate-500 text-xs font-semibold mb-3">
                <span class="w-2 h-2 rounded-full bg-amber-400 animate-ping"></span>
                功能构建中
            </div>

            <!-- 主标题与描述 -->
            <h2 class="text-xl sm:text-2xl font-black text-slate-800 tracking-tight mb-2">
                该功能未完成，更多功能使用 shell 脚本
            </h2>

            <!-- 操作按钮 -->
            <div class="flex items-center gap-3">
                <button onclick="navTo('home')" class="px-5 py-2.5 rounded-xl bg-slate-900 hover:bg-slate-800 text-white font-medium text-sm transition-all duration-200 shadow-md shadow-slate-900/10 flex items-center gap-2">
                    <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1h3a1 1 0 001-1V10M9 21h6" />
                    </svg>
                    返回控制台首页
                </button>
            </div>

        </div>
    </div>
    `;
}

export function mount(container) {
    // 可选：页面挂载后的初始化逻辑
}

export function unmount() {
    // 可选：页面卸载时的清理逻辑
}