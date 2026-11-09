/** Keep the unpacked extension's historical path stable for its Chrome ID and storage. */
import { cp, mkdir, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const source = resolve(root, 'apps/extension/.output/chrome-mv3');
const destination = resolve(root, '.output/chrome-mv3');
await mkdir(resolve(root, '.output'), { recursive: true });
await rm(destination, { recursive: true, force: true });
await cp(source, destination, { recursive: true });
console.log('Copied production build to .output/chrome-mv3 (legacy unpacked extension path).');
