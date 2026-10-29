/**
 * 生成 Chrome Web Store 宣传图：小图 440×280、横幅 1400×560。
 * 用法：node scripts/make-promo.mjs
 */
import { chromium } from 'playwright';
import { readFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const outDir = join(root, 'docs/store');
mkdirSync(outDir, { recursive: true });

const icon = readFileSync(join(root, 'public/icon/128.png')).toString('base64');
const panel = readFileSync(join(root, 'docs/screenshots/panel.png')).toString('base64');

const BASE_CSS = `
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", sans-serif;
    background: #1b1d21;
    overflow: hidden;
  }
  .glow {
    position: absolute; inset: 0;
    background:
      radial-gradient(120% 100% at 85% 15%, rgba(246,130,31,.55), transparent 60%),
      radial-gradient(90% 120% at 10% 100%, rgba(246,130,31,.22), transparent 60%);
  }
  .tag { color: #f6a04d; font-size: 13px; letter-spacing: .12em; text-transform: uppercase; }
`;

function htmlSmall() {
  return `<!doctype html><html><head><style>${BASE_CSS}
    body { width: 440px; height: 280px; color: #fff; }
    .wrap { position: relative; width: 100%; height: 100%; display: flex; flex-direction: column;
            align-items: center; justify-content: center; gap: 14px; text-align: center; }
    img.icon { width: 84px; height: 84px; border-radius: 20px; box-shadow: 0 16px 40px rgba(0,0,0,.45); }
    h1 { font-size: 27px; font-weight: 700; letter-spacing: -.01em; }
    p { font-size: 13.5px; color: #c9cdd3; line-height: 1.6; }
    .chips { display: flex; gap: 8px; }
    .chip { font-size: 11px; color: #ffd9b3; border: 1px solid rgba(246,130,31,.45);
            background: rgba(246,130,31,.12); border-radius: 999px; padding: 4px 10px; }
  </style></head><body>
    <div class="glow"></div>
    <div class="wrap">
      <img class="icon" src="data:image/png;base64,${icon}" alt="">
      <h1>Cloudflare Billing Helper</h1>
      <p>Free-quota headroom · exhaustion forecast · per-app cost</p>
      <div class="chips"><span class="chip">Workers</span><span class="chip">KV</span><span class="chip">D1</span><span class="chip">R2</span><span class="chip">Durable Objects</span></div>
    </div>
  </body></html>`;
}

function htmlMarquee() {
  return `<!doctype html><html><head><style>${BASE_CSS}
    body { width: 1400px; height: 560px; color: #fff; }
    .wrap { position: relative; width: 100%; height: 100%; display: flex; align-items: center; }
    .left { width: 46%; padding: 0 0 0 72px; }
    .brand { display: flex; align-items: center; gap: 16px; margin-bottom: 26px; }
    .brand img { width: 64px; height: 64px; border-radius: 16px; box-shadow: 0 14px 36px rgba(0,0,0,.45); }
    .brand span { font-size: 13px; color: #ffd9b3; letter-spacing: .14em; text-transform: uppercase; }
    h1 { font-size: 50px; font-weight: 700; line-height: 1.14; letter-spacing: -.02em; margin-bottom: 20px; }
    h1 em { font-style: normal; color: #f6a04d; }
    p.sub { font-size: 17px; color: #c9cdd3; line-height: 1.65; margin-bottom: 28px; }
    ul { list-style: none; display: flex; flex-direction: column; gap: 12px; }
    li { font-size: 15px; color: #e7e9ec; display: flex; gap: 10px; align-items: baseline; }
    li b { color: #f6a04d; font-weight: 600; }
    .shot {
      position: absolute; right: -60px; top: 68px; width: 760px;
      border-radius: 16px; border: 1px solid rgba(255,255,255,.14);
      box-shadow: 0 30px 80px rgba(0,0,0,.55); opacity: .97;
    }
  </style></head><body>
    <div class="glow"></div>
    <div class="wrap">
      <div class="left">
        <div class="brand">
          <img src="data:image/png;base64,${icon}" alt="">
          <span>Chrome extension</span>
        </div>
        <h1>Cloudflare <em>Billing Helper</em></h1>
        <p class="sub">Free-quota headroom, projected exhaustion dates, and per-app cost breakdown — right on the Billable Usage page.</p>
        <ul>
          <li><b>›</b> Quota progress for all 29 billing lines</li>
          <li><b>›</b> Exhaustion alerts with dates</li>
          <li><b>›</b> Per-Worker / KV / D1 / R2 / DO breakdown</li>
        </ul>
      </div>
      <img class="shot" src="data:image/png;base64,${panel}" alt="">
    </div>
  </body></html>`;
}

const execPath =
  process.env.CHROME_BIN ??
  `${process.env.HOME}/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing`;

const browser = await chromium.launch({ executablePath: execPath, headless: true });
const page = await browser.newPage();

await page.setViewportSize({ width: 440, height: 280 });
await page.setContent(htmlSmall());
await page.screenshot({ path: join(outDir, 'promo-440x280.png') });
console.log('✓ docs/store/promo-440x280.png');

await page.setViewportSize({ width: 1400, height: 560 });
await page.setContent(htmlMarquee());
await page.screenshot({ path: join(outDir, 'marquee-1400x560.png') });
console.log('✓ docs/store/marquee-1400x560.png');

await browser.close();
