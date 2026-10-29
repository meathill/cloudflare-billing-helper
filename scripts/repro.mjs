/**
 * 扩展实机复现脚本：加载 .output/chrome-mv3，打开本地 playground 页，
 * 验证三个场景：① 整页直载挂载 ② 其他账单页不挂载 ③ SPA 路由切入挂载。
 * 用法：pnpm build && node scripts/repro.mjs （SHOT=1 保存截图）
 */
import { chromium } from 'playwright';
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, dirname } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const extPath = join(root, '.output/chrome-mv3');
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
  executablePath: execPath,
  headless: process.env.HEADLESS === '1' ? true : false,
  args: [`--disable-extensions-except=${extPath}`, `--load-extension=${extPath}`, '--no-first-run'],
});

const logs = [];
const page = await context.newPage();
page.on('console', (m) => logs.push(`[console.${m.type()}] ${m.text()}`));
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));
page.on('requestfailed', (r) => {
  if (r.url().includes('chrome-extension')) logs.push(`[requestfailed] ${r.url()} ${r.failure()?.errorText}`);
});

const hostState = () =>
  page.evaluate(() => {
    const host = document.querySelector('cf-billing-helper');
    const shadowText = host?.shadowRoot?.textContent ?? '';
    return {
      mounted: !!host && host.isConnected,
      hasWaiting: shadowText.includes('正在等待'),
      hasQuotaTable: shadowText.includes('免费额度'),
    };
  });

// 场景 ①：整页直载可计费使用量页
await page.goto('http://localhost:8199/billing/billable-usage');
await page.waitForTimeout(3000);
const direct = await hostState();
console.log('① 整页直载 billable-usage:', JSON.stringify(direct));

// 场景 ②：整页直载其他账单页（不应挂载）
await page.goto('http://localhost:8199/billing/subscription');
await page.waitForTimeout(2000);
const other = await hostState();
console.log('② 整页直载其他账单页:', JSON.stringify(other));

// 场景 ③：SPA 路由切入 billable-usage（应挂载）
await page.evaluate(() => history.pushState({}, '', '/billing/billable-usage'));
await page.waitForTimeout(1500);
const spa = await hostState();
console.log('③ SPA 路由切入:', JSON.stringify(spa));

// 场景 ④：SPA 路由离开（应卸载）
await page.evaluate(() => history.pushState({}, '', '/billing/subscription'));
await page.waitForTimeout(1500);
const left = await hostState();
console.log('④ SPA 路由离开:', JSON.stringify(left));

// 服务 worker 是否正常
let swInfo = 'unknown';
try {
  swInfo = `service worker: ${context.serviceWorkers().length} 个`;
} catch (e) {
  swInfo = `service worker 检查失败: ${e.message}`;
}
console.log(swInfo);

if (process.env.SHOT) {
  await page.evaluate(() => history.pushState({}, '', '/billing/billable-usage'));
  await page.waitForTimeout(2000);
  await page.setViewportSize({ width: 1440, height: 1500 });
  await page.screenshot({ path: join(root, '.output/panel-screenshot.png') });
  console.log('=== 截图已保存 ===');
}

console.log('=== 页面 console 日志 ===');
console.log(logs.join('\n') || '(无日志)');

await context.close();
server.close();

const pass = direct.hasQuotaTable && !other.mounted && spa.hasQuotaTable && !left.mounted;
console.log(pass ? '\n✅ 全部场景通过' : '\n❌ 有场景未通过');
process.exit(pass ? 0 : 1);
