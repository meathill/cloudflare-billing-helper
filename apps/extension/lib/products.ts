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

import catalog from '../../../packages/billing-spec/catalog.json';

export const PRODUCTS: ProductSpec[] = catalog as ProductSpec[];

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
