/** 构建前自动调升 patch 版本（让 Chrome 扩展卡片能区分新旧版本）。 */
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const file = join(root, 'package.json');
const pkg = JSON.parse(readFileSync(file, 'utf8'));

const parts = String(pkg.version).split('.').map((n) => Number(n) || 0);
while (parts.length < 3) parts.push(0);
const [major, minor, patch] = parts;
pkg.version = `${major}.${minor}.${patch + 1}`;

writeFileSync(file, `${JSON.stringify(pkg, null, 2)}\n`);
console.log(`[build] 版本号 → ${pkg.version}`);
