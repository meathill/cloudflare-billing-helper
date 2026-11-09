/** Generate deterministic demo screenshots from the dedicated capture build. */
import { chromium } from 'playwright';
import { createServer } from 'node:http';
import { readFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const extPath = join(root, '.output/capture/chrome-mv3');
const outDir = join(root, '../../docs/screenshots');
mkdirSync(outDir, { recursive: true });
const fixture = readFileSync(join(root, 'playground/index.html'), 'utf8');
const server = createServer((req, res) => {
  res.setHeader('content-type', 'text/html; charset=utf-8');
  res.end(req.url?.includes('lang=en') ? fixture.replace('<html lang="zh-CN">', '<html lang="en">') : fixture);
});
let context;
try {
  await new Promise((resolve, reject) => server.once('error', reject).listen(8199, '127.0.0.1', resolve));
  context = await chromium.launchPersistentContext('', {
    ...(process.env.CHROME_BIN ? { executablePath: process.env.CHROME_BIN } : { channel: 'chromium' }),
    headless: true, viewport: { width: 1600, height: 1100 }, deviceScaleFactor: 2,
    args: [`--disable-extensions-except=${extPath}`, `--load-extension=${extPath}`, '--no-first-run'],
  });
  const page = await context.newPage();
  await page.clock.install({ time: new Date('2026-10-28T12:00:00Z') });
  for (const lang of ['zh', 'en']) {
    await page.goto(`http://localhost:8199/billing/billable-usage?lang=${lang}`);
    const host = page.locator('cf-billing-helper');
    await host.waitFor({ timeout: 10000 });
    await host.getByText(lang === 'zh' ? '免费额度' : 'Free quota', { exact: true }).first().waitFor();
    await host.locator('details').first().locator('summary').click();
    await host.getByText('production-api').waitFor();
    await host.screenshot({ path: join(outDir, `panel-${lang}.png`) });
    if (lang === 'zh') {
      await host.screenshot({ path: join(outDir, 'panel.png') });

    }
    console.log(`✓ ${lang} panel`);
  }
  await context.close();
  context = await chromium.launchPersistentContext('', {
    ...(process.env.CHROME_BIN ? { executablePath: process.env.CHROME_BIN } : { channel: 'chromium' }),
    headless: true, viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1,
    args: [`--disable-extensions-except=${extPath}`, `--load-extension=${extPath}`, '--no-first-run'],
  });
  const storePage = await context.newPage();
  await storePage.clock.install({ time: new Date('2026-10-28T12:00:00Z') });
  for (const lang of ['zh', 'en']) {
    await storePage.goto(`http://localhost:8199/billing/billable-usage?lang=${lang}`);
    const storeHost = storePage.locator('cf-billing-helper');
    await storeHost.getByText(lang === 'zh' ? '免费额度' : 'Free quota', { exact: true }).first().waitFor();
    await storeHost.locator('details').first().locator('summary').click();
    await storeHost.getByText('production-api').waitFor();
    await storePage.evaluate(() => {
      document.querySelectorAll('header, aside, main section > .card').forEach(element => {
        element.style.display = 'none';
      });
      document.querySelector('main').style.display = 'block';
      document.querySelector('main section').style.width = '1232px';
      const root = document.querySelector('cf-billing-helper').shadowRoot.querySelector('.cfbh-root');
      root.style.width = '1232px';
      root.style.margin = '0';
      const bounds = root.getBoundingClientRect();
      const scale = Math.min(1, 1232 / bounds.width, 752 / bounds.height);
      root.style.position = 'fixed';
      root.style.top = '24px';
      root.style.left = `${(1280 - bounds.width * scale) / 2}px`;
      root.style.transformOrigin = 'top left';
      root.style.transform = `scale(${scale})`;
    });
    await storePage.screenshot({ path: join(outDir, `store-1280x800-${lang}.png`) });
    if (lang === 'zh') await storePage.screenshot({ path: join(outDir, 'store-1280x800.png') });
  }

} finally {
  await context?.close();
  if (server.listening) await new Promise((resolve) => server.close(resolve));
}
