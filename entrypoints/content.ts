/** 内容脚本：在账单页挂载 Vue 面板（Shadow DOM），监听 MAIN-world 捕获的接口数据。
 * dash 是 SPA：匹配整个 billing 区，监听 URL 变化，仅在实际进入
 * 可计费使用量页时挂载面板，离开时卸载。 */
import { defineContentScript } from '#imports';
import { createApp } from 'vue';
import App from './content/App.vue';

export interface CapturedPayload {
  url: string;
  data: unknown;
  at: number;
}

const TARGET_RE = /\/billing\/billable-usage(\/|$|\?)/;

export default defineContentScript({
  matches: [
    'https://dash.cloudflare.com/*/billing*',
    'http://localhost:8199/*',
  ],
  cssInjectionMode: 'ui',

  async main(ctx) {
    try {
      // eslint-disable-next-line no-console
      console.info('[CFBH] content script 已注入', window.location.href);
      const accountId = getAccountId();
      const captures: CapturedPayload[] = [];

      window.addEventListener('message', (event) => {
        if (event.origin !== window.location.origin) return;
        if (event.source !== window) return;
        const msg = event.data as { source?: string; type?: string; url?: string; data?: unknown };
        if (msg?.source !== 'cfbh') return;
        if (msg.type === 'urlchange') {
          sync();
          return;
        }
        if (msg.type === 'capture') {
          captures.push({ url: msg.url ?? '', data: msg.data, at: Date.now() });
          if (captures.length > 10) captures.shift();
          // eslint-disable-next-line no-console
          console.info('[CFBH] 捕获接口数据:', msg.url, msg.data);
        }
      });

      const ui = await createShadowRootUi(ctx, {
        name: 'cf-billing-helper',
        position: 'inline',
        anchor: findAnchor,
        append: 'after',
        onMount: (container) => {
          const app = createApp(App, {
            accountId,
            getCaptures: () => [...captures],
          });
          app.mount(container);
          return app;
        },
        onRemove: (app) => app?.unmount(),
      });

      const isTarget = (): boolean => TARGET_RE.test(window.location.pathname);

      const sync = (): void => {
        try {
          if (ctx.isInvalid) return;
          if (isTarget() && !ui.shadowHost.isConnected) {
            ui.mount();
            // eslint-disable-next-line no-console
            console.info('[CFBH] 面板已挂载');
          } else if (!isTarget() && ui.shadowHost.isConnected) {
            ui.remove();
            // eslint-disable-next-line no-console
            console.info('[CFBH] 离开账单页，面板已卸载');
          }
        } catch (e) {
          // eslint-disable-next-line no-console
          console.error('[CFBH] 同步挂载状态失败：', e);
        }
      };

      sync();
      // 兜底：MAIN 脚本未注入（旧浏览器）或 dash 重渲染移除宿主元素
      const timer = setInterval(sync, 1500);
      ctx.onInvalidated(() => clearInterval(timer));
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error('[CFBH] 初始化失败，请把此错误反馈给开发者：', e);
    }
  },
});

function getAccountId(): string {
  const seg = window.location.pathname.split('/').filter(Boolean);
  return seg[0] ?? '';
}

/**
 * 定位面板锚点：优先放在「支出摘要」卡片之后；找不到就放在主内容区顶部。
 * 返回 null 时 WXT 会把 UI 加到 body 末尾，这里始终给出兜底。
 */
function findAnchor(): Element {
  const summaryHeading = Array.from(document.querySelectorAll('h1,h2,h3,h4,span,div')).find((el) => {
    const t = (el.textContent ?? '').trim();
    return (t === '支出摘要' || /^Spend [Ss]ummary$/.test(t)) && el.children.length === 0;
  });
  if (summaryHeading) {
    let card: Element | null = summaryHeading;
    for (let i = 0; i < 8 && card; i++) {
      card = card.parentElement;
      if (card && card !== document.body) {
        const r = card.getBoundingClientRect();
        // 支出摘要是一张整宽卡片
        if (r.width > 600) break;
      }
    }
    if (card) return card;
  }
  return document.querySelector('main') ?? document.body;
}
