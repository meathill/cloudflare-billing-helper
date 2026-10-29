/**
 * Cloudflare Workers Paid 计费行目录（来源：可计费使用量页产品列表，29 行）。
 * included 为免费额度（与本行用量同单位）；kind 决定预估算法：
 * - cumulative：周期内累计（请求数、CPU、操作数……），按日均线性外推
 * - gauge：周期内平均水位（GB-months、并发数……），需按存储序列趋势外推
 */
import type { ProductRow } from './types';

export type ProductFamily = 'workers' | 'kv' | 'd1' | 'r2' | 'do' | 'other';
export type UsageKind = 'cumulative' | 'gauge';

export interface ProductSpec {
  key: string;
  /** 页面英文基准名 */
  name: string;
  /** 额外匹配别名（小写归一化后包含匹配） */
  aliases?: string[];
  unit: string;
  included?: number;
  kind: UsageKind;
  family: ProductFamily;
  /** 图表颜色（对应页面圆点色系） */
  color: string;
  /** 本行支持按应用拆分：家族 + 指标 */
  breakdown?: { family: ProductFamily; metric: string };
  /** 耗尽后的迁移建议 */
  advice?: string;
  /**
   * 官方目录单价（USD / 单位）。仅在页面反推不出有效费率时兜底
   * （典型：本周期尚未产生费用、页面无“有效费率”文案）。
   */
  unitPrice?: number;
}

export const PRODUCTS: ProductSpec[] = [
  {
    key: 'workers-cpu-ms',
    name: 'Workers CPU ms',
    unit: 'ms',
    included: 30_000_000,
    kind: 'cumulative',
    family: 'workers',
    color: '#2f7d3b',
    breakdown: { family: 'workers', metric: 'cpuTime' },
  },
  {
    key: 'kv-storage',
    name: 'KV Storage',
    aliases: ['kv storage (gb'],
    unit: 'GB-months',
    included: 1,
    kind: 'gauge',
    family: 'kv',
    color: '#9333ea',
    breakdown: { family: 'kv', metric: 'storage' },
    advice: '存储型负载可考虑迁移到 R2（免 Class A/B 的 get/put 更便宜，10GB 免费额度）',
  },
  {
    key: 'worker-build-minutes',
    name: 'Worker Build Minutes',
    unit: 'minutes',
    included: 6000,
    kind: 'cumulative',
    family: 'workers',
    color: '#22a06b',
  },
  {
    key: 'email-service-sent',
    name: 'Email Service - Emails Sent',
    unit: 'emails',
    included: 3000,
    kind: 'cumulative',
    family: 'other',
    color: '#5fd4b0',
  },
  {
    key: 'kv-delete-operations',
    name: 'KV Delete Operations',
    unit: 'ops',
    included: 1_000_000,
    kind: 'cumulative',
    family: 'kv',
    color: '#17b8a6',
    breakdown: { family: 'kv', metric: 'delete' },
  },
  {
    key: 'kv-list-operations',
    name: 'KV List Operations',
    unit: 'ops',
    included: 1_000_000,
    kind: 'cumulative',
    family: 'kv',
    color: '#c026d3',
    breakdown: { family: 'kv', metric: 'list' },
  },
  {
    key: 'do-compute-requests',
    name: 'Durable Objects Compute Requests',
    unit: 'requests',
    included: 1_000_000,
    kind: 'cumulative',
    family: 'do',
    color: '#6b21a8',
    breakdown: { family: 'do', metric: 'requests' },
  },
  {
    key: 'd1-storage',
    name: 'D1 - Storage GB-mo',
    aliases: ['d1 - storage'],
    unit: 'GB-months',
    included: 5,
    kind: 'gauge',
    family: 'd1',
    color: '#84cc16',
    breakdown: { family: 'd1', metric: 'storage' },
  },
  {
    key: 'do-sql-storage',
    name: 'Durable Objects SQL Storage',
    unit: 'GB-months',
    included: 5,
    kind: 'gauge',
    family: 'do',
    color: '#f472b6',
    breakdown: { family: 'do', metric: 'sqlStorage' },
  },
  {
    key: 'queues-standard-operations',
    name: 'Queues - Standard operations',
    unit: 'ops',
    included: 1_000_000,
    kind: 'cumulative',
    family: 'other',
    color: '#e5484d',
  },
  {
    key: 'do-storage-rows-read',
    name: 'Durable Objects Storage Rows Read',
    unit: 'rows',
    included: 25_000_000_000,
    kind: 'cumulative',
    family: 'do',
    color: '#4271ae',
    breakdown: { family: 'do', metric: 'rowsRead' },
  },
  {
    key: 'kv-write-operations',
    name: 'KV Write Operations',
    unit: 'ops',
    included: 1_000_000,
    kind: 'cumulative',
    family: 'kv',
    color: '#e05d38',
    breakdown: { family: 'kv', metric: 'write' },
  },
  {
    key: 'images-transformed',
    name: 'Images Transformed',
    unit: 'images',
    included: 5000,
    kind: 'cumulative',
    family: 'other',
    color: '#3b82f6',
  },
  {
    key: 'kv-read-operations',
    name: 'KV Read Operations',
    unit: 'ops',
    included: 10_000_000,
    kind: 'cumulative',
    family: 'kv',
    color: '#5c8d29',
    breakdown: { family: 'kv', metric: 'read' },
  },
  {
    key: 'd1-rows-written',
    name: 'D1 - Rows Written',
    unit: 'rows',
    included: 50_000_000,
    kind: 'cumulative',
    family: 'd1',
    color: '#ef4444',
    breakdown: { family: 'd1', metric: 'rowsWritten' },
  },
  {
    key: 'd1-rows-read',
    name: 'D1 - Rows Read',
    unit: 'rows',
    included: 25_000_000_000,
    kind: 'cumulative',
    family: 'd1',
    color: '#06b6d4',
    breakdown: { family: 'd1', metric: 'rowsRead' },
  },
  {
    key: 'observability-logs',
    name: 'Observability - Logs',
    unit: 'events',
    included: 20_000_000,
    kind: 'cumulative',
    family: 'other',
    color: '#3d5af1',
  },
  {
    key: 'r2-class-b-operations',
    name: 'R2 Storage Class B Operations',
    unit: 'ops',
    included: 10_000_000,
    kind: 'cumulative',
    family: 'r2',
    color: '#a08a00',
    breakdown: { family: 'r2', metric: 'classB' },
  },
  {
    key: 'do-storage-rows-written',
    name: 'Durable Objects Storage Rows Written',
    unit: 'rows',
    included: 50_000_000,
    kind: 'cumulative',
    family: 'do',
    color: '#eab308',
    breakdown: { family: 'do', metric: 'rowsWritten' },
  },
  {
    key: 'do-compute-duration',
    name: 'Durable Objects Compute Duration',
    unit: 'GB-s',
    included: 400_000,
    kind: 'cumulative',
    family: 'do',
    color: '#e8d44d',
    breakdown: { family: 'do', metric: 'duration' },
  },
  {
    key: 'r2-class-a-operations',
    name: 'R2 Storage Class A Operations',
    unit: 'ops',
    included: 1_000_000,
    kind: 'cumulative',
    family: 'r2',
    color: '#2fa84f',
    breakdown: { family: 'r2', metric: 'classA' },
  },
  {
    key: 'workers-standard-requests',
    name: 'Workers Standard Requests',
    unit: 'requests',
    included: 10_000_000,
    kind: 'cumulative',
    family: 'workers',
    color: '#c05656',
    breakdown: { family: 'workers', metric: 'requests' },
  },
  {
    key: 'r2-data-storage',
    name: 'R2 Data Storage',
    unit: 'GB-months',
    included: 10,
    kind: 'gauge',
    family: 'r2',
    color: '#4f46e5',
    breakdown: { family: 'r2', metric: 'storage' },
  },
  {
    key: 'browser-run-concurrent',
    name: 'Browser Run - Average Concurrent Browsers',
    unit: 'browsers',
    included: 10,
    kind: 'gauge',
    family: 'other',
    color: '#a78bfa',
  },
  {
    key: 'browser-run-hours',
    name: 'Browser Run - Browser Hours',
    unit: 'hours',
    included: 10,
    kind: 'cumulative',
    family: 'other',
    color: '#f97316',
  },
  {
    key: 'vectorize-stored-dimensions',
    name: 'Vectorize - Stored Dimensions',
    unit: 'dimension-months',
    included: 10_000_000,
    kind: 'gauge',
    family: 'other',
    color: '#6b7f1f',
  },
  {
    key: 'vectorize-queried-dimensions',
    name: 'Vectorize - Queried Dimensions',
    unit: 'dimensions',
    included: 50_000_000,
    kind: 'cumulative',
    family: 'other',
    color: '#ec4899',
  },
  {
    key: 'regular-twitch-neurons',
    name: 'Regular Twitch Neurons',
    aliases: ['regular twitch neurons (rtn)'],
    unit: 'count',
    kind: 'cumulative',
    family: 'other',
    color: '#14b8a6',
  },
  {
    key: 'dynamic-workers',
    name: 'Dynamic Workers',
    unit: 'workers',
    included: 1000,
    kind: 'gauge',
    family: 'other',
    color: '#1e3a5f',
  },
];

/** Workers Paid 官方目录价（USD / 单位，Cloudflare 公开定价）。 */
const UNIT_PRICES: Record<string, number> = {
  'workers-cpu-ms': 0.02 / 1e6, // $0.02 / 百万 ms
  'workers-standard-requests': 0.3 / 1e6, // $0.30 / 百万请求
  'worker-build-minutes': 0.005, // $0.005 / 分钟
  'kv-storage': 0.5, // $0.50 / GB-month
  'kv-read-operations': 0.5 / 1e6, // $0.50 / 百万次
  'kv-write-operations': 5 / 1e6, // $5.00 / 百万次
  'kv-delete-operations': 5 / 1e6,
  'kv-list-operations': 5 / 1e6,
  'd1-storage': 0.75, // $0.75 / GB-month
  'd1-rows-read': 0.001 / 1e6, // $0.001 / 百万行
  'd1-rows-written': 1 / 1e6, // $1.00 / 百万行
  'r2-data-storage': 0.015, // $0.015 / GB-month
  'r2-class-a-operations': 4.5 / 1e6, // $4.50 / 百万次
  'r2-class-b-operations': 0.36 / 1e6, // $0.36 / 百万次
  'do-compute-requests': 0.15 / 1e6, // $0.15 / 百万请求
  'do-compute-duration': 12.5 / 1e6, // $12.50 / 百万 GB-s
  'do-sql-storage': 0.2, // $0.20 / GB-month
  'do-storage-rows-read': 0.001 / 1e6,
  'do-storage-rows-written': 1 / 1e6,
  'queues-standard-operations': 0.4 / 1e6, // $0.40 / 百万次
  'email-service-sent': 0.35 / 1e3, // $0.35 / 千封
  'images-transformed': 0.5 / 1e3, // $0.50 / 千次
};

for (const spec of PRODUCTS) {
  const price = UNIT_PRICES[spec.key];
  if (price != null) spec.unitPrice = price;
}

/** 名称归一化：小写、去括号内容、去非字母数字。 */
export function normalizeName(name: string): string {  return name
    .toLowerCase()
    .replace(/\([^)]*\)/g, '')
    .replace(/[^a-z0-9]+/g, '');
}

const _byNormalized = new Map<string, ProductSpec>();
for (const p of PRODUCTS) {
  _byNormalized.set(normalizeName(p.name), p);
  for (const a of p.aliases ?? []) _byNormalized.set(normalizeName(a), p);
}

/** 根据页面产品名匹配目录；匹配不到返回 null。 */
export function matchProduct(name: string): ProductSpec | null {
  const norm = normalizeName(name);
  if (!norm) return null;
  const exact = _byNormalized.get(norm);
  if (exact) return exact;
  // 页面名可能带单位前后缀（如 "D1 - Storage GB-mo"），做包含匹配，取最长命中
  let best: ProductSpec | null = null;
  let bestLen = 0;
  for (const [key, spec] of _byNormalized) {
    if (key.length > bestLen && (norm.includes(key) || key.includes(norm))) {
      best = spec;
      bestLen = key.length;
    }
  }
  return best;
}

export function specOf(row: ProductRow): ProductSpec | null {
  return row.id.startsWith('unknown:') ? null : PRODUCTS.find((p) => p.key === row.id) ?? null;
}

export const FAMILY_LABEL: Record<ProductFamily, { zh: string; en: string }> = {
  workers: { zh: 'Workers', en: 'Workers' },
  kv: { zh: 'KV 存储', en: 'KV Storage' },
  d1: { zh: 'D1 数据库', en: 'D1 Databases' },
  r2: { zh: 'R2 对象存储', en: 'R2 Buckets' },
  do: { zh: 'Durable Objects', en: 'Durable Objects' },
  other: { zh: '其他', en: 'Other' },
};
