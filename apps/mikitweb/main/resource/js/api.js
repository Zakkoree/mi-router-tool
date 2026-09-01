/**
 * 统一 Toast 轻提示通知
 * @param {string} message - 提示消息内容
 * @param {'error'|'success'|'info'} type - 提示类型
 */
function showToast(message, type = 'error') {
    if (type === 'error') {
        console.error(`[API Log]: ${message}`);
    } else {
        console.log(`[API Log]: ${message}`);
    }

    let toastContainer = document.getElementById('toast-container');
    if (!toastContainer) {
        toastContainer = document.createElement('div');
        toastContainer.id = 'toast-container';
        toastContainer.className = 'fixed top-5 right-5 z-50 flex flex-col gap-2 pointer-events-none';
        document.body.appendChild(toastContainer);
    }

    let styleClass = 'bg-slate-900 text-white shadow-slate-900/20';
    let icon = 'ℹ️';

    if (type === 'error') {
        styleClass = 'bg-red-500 text-white shadow-red-500/20';
        icon = '⚠️';
    } else if (type === 'success') {
        styleClass = 'bg-emerald-600 text-white shadow-emerald-600/20';
        icon = '✅';
    }

    const toast = document.createElement('div');
    toast.className = `pointer-events-auto flex items-center gap-2.5 px-4 py-3 rounded-xl text-xs sm:text-sm font-semibold shadow-lg transition-all duration-300 transform translate-x-10 opacity-0 ${styleClass}`;
    toast.innerHTML = `<span>${icon}</span><span>${message}</span>`;

    toastContainer.appendChild(toast);
    requestAnimationFrame(() => {
        toast.classList.remove('translate-x-10', 'opacity-0');
    });

    setTimeout(() => {
        toast.classList.add('translate-x-10', 'opacity-0');
        toast.addEventListener('transitionend', () => toast.remove());
    }, 3500);
}

/**
 * 统一后端 API 请求基础函数
 * @param {string} path - 接口路径，如 '/app/toggle'
 * @param {object} options - fetch 配置项
 * @param {boolean} options.showError - 是否在失败后自动展示 Toast 提示（默认 true）
 * @param {number} options.timeout - 单次请求超时熔断时间毫秒（默认 8000ms）
 */
async function requestApi(path, options = {}) {
    const {
        showError = true,
        timeout = 8000,
        ...fetchOptions
    } = options;

    const normalizedPath = path.startsWith('/') ? path : `/${path}`;
    const url = `/api${normalizedPath}`;

    // 挂载超时控制器
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeout);

    try {
        const res = await fetch(url, {
            ...fetchOptions,
            signal: controller.signal,
            headers: {
                'Content-Type': 'application/json',
                ...(fetchOptions.headers || {})
            }
        });

        clearTimeout(timeoutId);

        // 拦截 HTTP 状态码异常
        if (!res.ok) {
            throw new Error(`HTTP 异常 ${res.status} (${res.statusText || 'Server Error'})`);
        }

        const data = await res.json();

        // 拦截业务 logic 错误 (code !== 0)
        if (data && typeof data.code !== 'undefined' && data.code !== 0) {
            throw new Error(data.msg || data.message || `业务错误 (code: ${data.code})`);
        }

        return data;

    } catch (err) {
        clearTimeout(timeoutId);

        let errMsg = err.message;
        if (err.name === 'AbortError') {
            errMsg = '请求超时，请检查服务响应状态';
        } else if (err.name === 'TypeError') {
            errMsg = '网络连接失败，请检查网关状态';
        }

        if (showError) {
            showToast(errMsg, 'error');
            return null;
        }

        throw new Error(errMsg);
    }
}

// 挂载到全局 window
window.requestApi = requestApi;
window.showToast = showToast;