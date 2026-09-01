/**
 * 微型组件化路由引擎
 */
class AppEngine {
    constructor(containerId) {
        this.container = document.getElementById(containerId);
        this.currentModule = null;
        this.routes = {};
    }

    // 注册路由
    register(key, modulePath) {
        this.routes[key] = modulePath;
        return this;
    }

    // 切换并加载模块
    async load(key, btnEl) {
        // 1. 触发旧模块的销毁生命周期（清除定时器、解绑事件等）
        if (this.currentModule && typeof this.currentModule.unmount === 'function') {
            this.currentModule.unmount();
        }

        // 2. 更新 Tab 菜单居中样式
        document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
        if (btnEl) btnEl.classList.add('active');

        // 3. 动态导入（Dynamic Import）JS 模块
        try {
            this.container.innerHTML = `<div class="flex justify-center items-center h-48 text-slate-400 text-sm">加载中...</div>`;

            const modulePath = this.routes[key];
            // 利用 ES6 import 动态加载
            const module = await import(modulePath);
            this.currentModule = module;

            // 4. 渲染 HTML 并执行挂载钩子
            this.container.innerHTML = module.render();
            if (typeof module.mount === 'function') {
                module.mount(this.container);
            }
        } catch (err) {
            console.error(err);
            this.container.innerHTML = `<div class="p-6 bg-red-50 text-red-600 rounded-xl text-center text-sm">页面模块加载失败: ${key}</div>`;
        }
        this.container.classList.remove('animate-fade-in');
        void this.container.offsetWidth;
        this.container.classList.add('animate-fade-in');
    }
}

// 挂载全局实例
window.app = new AppEngine('app-content');