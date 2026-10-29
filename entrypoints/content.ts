/** 内容脚本：在账单页挂载 Vue 面板（Shadow DOM），监听 MAIN-world 捕获的接口数据。 */
import { defineContentScript } from '#imports';
import { createApp } from 'vue';
import App from './content/App.vue';

export interface CapturedPayload {
  url: string;
  data: unknown;
  at: number;
}

export default defineContentScript({
  matches: ['https://dash.cloudflare.com/*/billing/billable-usage*'],
  cssInjectionMode: 'ui',

  async main(ctx) {
    const accountId = getAccountId();
    const captures: CapturedPayload[] = [];

    window.addEventListener('message', (event) => {
      if (event.origin !== window.location.origin) return;
      if (event.source !== window) return;
      const msg = event.data as { source?: string; type?: string; url?: string; data?: unknown };
      if (msg?.source !== 'cfbh' || msg.type !== 'capture') return;
      captures.push({ url: msg.url ?? '', data: msg.data, at: Date.now() });
      if (captures.length > 10) captures.shift();
      // eslint-disable-next-line no-console
      console.info('[CF Billing Helper] 捕获接口数据:', msg.url, msg.data);
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

    await ui.mount();

    // dash 是 SPA：锚点卡片被重渲染时自动重新挂载
    const timer = setInterval(() => {
      if (!ui.shadowHost.isConnected) {
        try {
          Promise.resolve(ui.mount() as unknown).catch(() => {});
        } catch {
          // ignore
        }
      }
    }, 3000);
    ctx.onInvalidated(() => clearInterval(timer));
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
