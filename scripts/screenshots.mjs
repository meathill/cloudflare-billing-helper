/**
 * 生成文档/落地页用截图：加载扩展打开 playground，截取面板元素（2x）。
 * 用法：pnpm build:only && node scripts/screenshots.mjs
 */
import { chromium } from 'playwright';
import { createServer } from 'node:http';
import { readFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const extPath = join(root, '.output/chrome-mv3');
const outDir = join(root, 'docs/screenshots');
mkdirSync(outDir, { recursive: true });

const FIXTURE = readFileSync(join(root, 'playground/index.html'), 'utf8');
const server = createServer((req, res) => {
  res.setHeader('content-type', 'text/html; charset=utf-8');
  res.end(FIXTURE);
});
await new Promise((r) => server.listen(8199, '127.0.0.1', r));

const execPath =
  process.env.CHROME_BIN ??
  `${process.env.HOME}/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing`;

const context = await chromium.launchPersistentContext('', {
  executablePath: extPath ? execPath : execPath,
  headless: true,
  viewport: { width: 1480, height: 1100 },
  deviceScaleFactor: 2,
  args: [`--disable-extensions-except=${extPath}`, `--load-extension=${extPath}`, '--no-first-run'],
});

const page = await context.newPage();
await page.goto('http://localhost:8199/billing/billable-usage');
await page.waitForSelector('cf-billing-helper', { timeout: 10_000 });
// 等面板内数据渲染完成
await page.waitForFunction(
  () => document.querySelector('cf-billing-helper')?.shadowRoot?.textContent?.includes('免费额度'),
  { timeout: 10_000 },
);

const host = page.locator('cf-billing-helper');
await host.screenshot({ path: join(outDir, 'panel.png') });
console.log('✓ docs/screenshots/panel.png');

// Chrome Web Store 列表图：1280×800（含页面上下文）
await page.setViewportSize({ width: 1280, height: 800 });
await page.evaluate(() => {
  const host = document.querySelector('cf-billing-helper');
  host?.scrollIntoView({ block: 'center' });
});
await page.waitForTimeout(300);
await page.screenshot({ path: join(outDir, 'store-1280x800.png') });
console.log('✓ docs/screenshots/store-1280x800.png');

await context.close();
server.close();
