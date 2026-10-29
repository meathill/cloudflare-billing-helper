/**
 * 生成扩展图标：把 assets/icon.svg 渲染为 16/32/48/96/128 PNG。
 * 用法：node scripts/make-icons.mjs
 */
import { chromium } from 'playwright';
import { readFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const svg = readFileSync(join(root, 'assets/icon.svg'), 'utf8');
const outDir = join(root, 'public/icon');
mkdirSync(outDir, { recursive: true });

const execPath =
  process.env.CHROME_BIN ??
  `${process.env.HOME}/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing`;

const browser = await chromium.launch({ executablePath: execPath, headless: true });
const page = await browser.newPage();

for (const size of [16, 32, 48, 96, 128]) {
  await page.setViewportSize({ width: size, height: size });
  await page.setContent(
    `<!doctype html><html><head><style>
      html,body{margin:0;padding:0;background:transparent;overflow:hidden}
      svg{display:block;width:${size}px;height:${size}px}
    </style></head><body>${svg}</body></html>`,
  );
  await page.locator('svg').screenshot({ path: join(outDir, `${size}.png`), omitBackground: true });
  console.log(`✓ public/icon/${size}.png`);
}

await browser.close();
