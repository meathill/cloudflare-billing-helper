/** 拆分查询统一入口：家族 + 指标 → 具体模块。 */
import type { BreakdownItem } from '../types';
import type { ProductFamily } from '../products';
import { d1Metric } from './d1';
import { doMetric } from './do';
import { kvMetric } from './kv';
import { r2Metric } from './r2';
import { workersMetric } from './workers';

export async function fetchBreakdown(
  accountId: string,
  family: ProductFamily,
  metric: string,
  cycleStart: Date,
  cycleEnd: Date,
): Promise<BreakdownItem[]> {
  switch (family) {
    case 'workers':
      return workersMetric(accountId, cycleStart, cycleEnd, metric);
    case 'kv':
      return kvMetric(accountId, cycleStart, cycleEnd, metric);
    case 'd1':
      return d1Metric(accountId, cycleStart, cycleEnd, metric);
    case 'r2':
      return r2Metric(accountId, cycleStart, cycleEnd, metric);
    case 'do':
      return doMetric(accountId, cycleStart, cycleEnd, metric);
    default:
      return [];
  }
}

export { getKvBreakdown } from './kv';
export type { KvBreakdown } from './kv';
