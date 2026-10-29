/** 内容脚本：在账单页挂载 Vue 面板（Shadow DOM），监听 MAIN-world 捕获的接口数据。
 * dash 是 SPA 且内容异步渲染、React 重渲染会移除外插节点，因此：
 * 1) 等产品表格出现后才挂载（锚点必然存在，不会落到页面底部）
 * 2) 锚点 = 包含「支出摘要」的卡片；找不到则用表格所在卡片
 * 3) MutationObserver 在节点被移除后立即原位重挂（80ms 节流），另有 1.5s 轮询兜底
 * 4) 路由变化（由 MAIN-world 脚本转发）动态挂载/卸载 */
import { defineContentScript } from '#imports';
import { createApp } from 'vue';
import { findUsageTable } from '../lib/parse/dom-parser';
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
      console.info(
        `[CFBH] content script v${chrome.runtime.getManifest().version} 已注入`,
        window.location.href,
      );
      const accountId = getAccountId();
      const captures: CapturedPayload[] = [];

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

      window.addEventListener('message', (event) => {
        if (event.origin !== window.location.origin) return;
        if (event.source !== window) return;
        const msg = event.data as { source?: string; type?: string; url?: string; data?: unknown };
        if (msg?.source !== 'cfbh') return;
        if (msg.type === 'urlchange') {
          scheduleSync();
          return;
        }
        if (msg.type === 'capture') {
          captures.push({ url: msg.url ?? '', data: msg.data, at: Date.now() });
          if (captures.length > 10) captures.shift();
          // eslint-disable-next-line no-console
          console.info('[CFBH] 捕获接口数据:', msg.url, msg.data);
        }
      });

      const isTarget = (): boolean => TARGET_RE.test(window.location.pathname);

      const sync = (): void => {
        try {
          if (ctx.isInvalid) return;
          if (!isTarget()) {
            if (ui.shadowHost.isConnected) {
              ui.remove();
              // eslint-disable-next-line no-console
              console.info('[CFBH] 离开账单页，面板已卸载');
            }
            return;
          }
          if (ui.shadowHost.isConnected) return;
          // 页面数据未就绪（表格还没渲染）：先不挂载，避免锚点退化到 body 末尾
          if (!findUsageTable(document)) {
            return;
          }
          // 清理可能残留的旧 App 实例（节点被页面上次渲染移除时不会走 onRemove）
          try {
            ui.remove();
          } catch {
            // ignore
          }
          ui.mount();
          // eslint-disable-next-line no-console
          console.info('[CFBH] 面板已挂载');
        } catch (e) {
          // eslint-disable-next-line no-console
          console.error('[CFBH] 同步挂载状态失败：', e);
        }
      };

      let syncTimer: number | undefined;
      const scheduleSync = (): void => {
        window.clearTimeout(syncTimer);
        syncTimer = window.setTimeout(sync, 80);
      };

      // dash 的 React 重渲染可能移除宿主节点：观察到移除立即重挂
      const observer = new MutationObserver(scheduleSync);
      observer.observe(document.body, { childList: true, subtree: true });

      sync();
      const timer = setInterval(sync, 1500);
      ctx.onInvalidated(() => {
        observer.disconnect();
        clearInterval(timer);
        window.clearTimeout(syncTimer);
      });
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
 * 定位面板锚点（面板会插到锚点之后）：
 * 1) 包含「支出摘要」的整宽卡片（同时含费用文本，避免误匹配侧边栏/标题）
 * 2) 产品表格所在的卡片
 * 3) 产品表格本身
 * 只有找到以上任一元素才返回，绝不再退化到 body。
 */
function findAnchor(): Element | null {
  // 1) 支出摘要卡片
  const all = Array.from(document.querySelectorAll('div, section, article'));
  for (const el of all) {
    const text = el.textContent ?? '';
    if (!(text.includes('支出摘要') || /Spend [Ss]ummary/.test(text))) continue;
    if (!/总费用|预计周期费用|Total spend|Projected/i.test(text)) continue;
    let cur: Element | null = el;
    for (let i = 0; i < 6 && cur; i++) {
      const r = cur.getBoundingClientRect();
      // 整宽卡片：有一定宽度和高度，但不是一个巨大的容器
      if (r.width > 600 && r.height > 80 && r.height < 800) return cur;
      cur = cur.parentElement;
    }
  }
  // 2) / 3) 产品表格
  const table = findUsageTable(document);
  if (table) {
    let cur: Element | null = table;
    for (let i = 0; i < 6 && cur && cur !== document.body; i++) {
      const r = cur.getBoundingClientRect();
      if (r.width > 600 && r.height > 120) return cur;
      cur = cur.parentElement;
    }
    return table;
  }
  return null;
}
