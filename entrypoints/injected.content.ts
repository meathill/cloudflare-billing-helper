/**
 * MAIN-world 注入脚本：钩住页面的 fetch/XHR，把账单相关 JSON 响应回传给扩展。
 * 用于获取页面自身接口的结构化数据（按日明细、免费额度字段等），DOM 解析的补充。
 */
import { defineContentScript } from '#imports';

export default defineContentScript({
  matches: [
    'https://dash.cloudflare.com/*/billing/billable-usage*',
    // 本地 playground 只在开发构建注入，生产包不带 localhost（保持上架包干净）
    ...(import.meta.env.DEV ? ['http://localhost:8199/*'] : []),
  ],
  world: 'MAIN',
  registration: 'manifest',
  main() {
    // 抓包（fetch/XHR 拦截）只用于本地调试接口字段，生产构建不注入这段逻辑。
    // SPA 路由转发是功能必需，始终保留：dash 路由器在 MAIN world 调 pushState，
    // 隔离世界 hook 不到，必须在这里监听并转发给 content script。
    if (import.meta.env.DEV) {
      const CAPTURE_RE = /(billable[_-]?usage|billing\/usage|billable-usage)/i;

      function send(url: string, data: unknown): void {
        try {
          window.postMessage(
            { source: 'cfbh', type: 'capture', url, data },
            window.location.origin,
          );
        } catch {
          // 忽略序列化失败
        }
      }

      async function captureIfRelevant(url: string, res: Response): Promise<void> {
        try {
          if (!CAPTURE_RE.test(url)) return;
          const ct = res.headers.get('content-type') ?? '';
          if (!ct.includes('json')) return;
          const data = await res.clone().json();
          send(url, data);
        } catch {
          // ignore
        }
      }

      const originalFetch = window.fetch;
      window.fetch = async function cfbhFetch(input: RequestInfo | URL, init?: RequestInit) {
        const res = await originalFetch.call(window, input, init);
        try {
          const url =
            typeof input === 'string' ? input : input instanceof Request ? input.url : input.toString();
          void captureIfRelevant(url, res);
        } catch {
          // ignore
        }
        return res;
      } as typeof fetch;

      const xhrOpen = XMLHttpRequest.prototype.open;
      const xhrSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function (
        this: XMLHttpRequest & { __cfbhUrl?: string },
        ...args: unknown[]
      ) {
        this.__cfbhUrl = String(args[1] ?? '');
        // @ts-expect-error 透传原始参数
        return xhrOpen.apply(this, args);
      };
      XMLHttpRequest.prototype.send = function (this: XMLHttpRequest, ...args: unknown[]) {
        this.addEventListener('load', () => {
          try {
            const url = (this as XMLHttpRequest & { __cfbhUrl?: string }).__cfbhUrl ?? '';
            if (!CAPTURE_RE.test(url)) return;
            const ct = this.getResponseHeader('content-type') ?? '';
            if (
              ct.includes('json') &&
              this.responseType !== 'arraybuffer' &&
              this.responseType !== 'blob'
            ) {
              send(url, JSON.parse(this.responseText));
            }
          } catch {
            // ignore
          }
        });
        // @ts-expect-error 透传原始参数
        return xhrSend.apply(this, args);
      };
    }

    const dispatchUrlChange = (): void => {
      try {
        window.postMessage({ source: 'cfbh', type: 'urlchange' }, window.location.origin);
      } catch {
        // ignore
      }
    };
    for (const type of ['pushState', 'replaceState'] as const) {
      const original = history[type].bind(history);
      history[type] = function (this: History, ...args: Parameters<History['pushState']>) {
        const result = original(...args);
        dispatchUrlChange();
        return result;
      } as History['pushState'];
    }
    window.addEventListener('popstate', dispatchUrlChange);
  },
});
