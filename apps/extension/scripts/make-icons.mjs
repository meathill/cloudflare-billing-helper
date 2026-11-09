/**
 * 生成扩展图标：把 assets/icon.svg 渲染为 16/32/48/96/128 PNG。
 * 传入参数时可额外渲染商店 logo：node scripts/make-icons.mjs 300 docs/store/logo-300x300.png
 * （路径相对 apps/extension，输出文件不放进 public/icon，避免打进扩展包。）
 */
import { chromium } from 'playwright';
import { readFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const svg = readFileSync(join(root, 'assets/icon.svg'), 'utf8');
const outDir = join(root, 'public/icon');
mkdirSync(outDir, { recursive: true });

const browser = await chromium.launch({ ...(process.env.CHROME_BIN ? { executablePath: process.env.CHROME_BIN } : {}), headless: true });
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

// 可选：渲染商店 logo（如 Edge Add-ons 要求的 300×300）
const [storeSize, storePath] = process.argv.slice(2);
if (storeSize && storePath) {
  const size = Number(storeSize);
  if (!Number.isInteger(size) || size < 128) throw new Error(`商店 logo 尺寸需为 ≥128 的整数，收到：${storeSize}`);
  const outPath = resolve(root, storePath);
  mkdirSync(dirname(outPath), { recursive: true });
  await page.setViewportSize({ width: size, height: size });
  await page.setContent(
    `<!doctype html><html><head><style>
      html,body{margin:0;padding:0;background:transparent;overflow:hidden}
      svg{display:block;width:${size}px;height:${size}px}
    </style></head><body>${svg}</body></html>`,
  );
  await page.locator('svg').screenshot({ path: outPath, omitBackground: true });
  console.log(`✓ ${storePath}`);
}

await browser.close();
