/** 产品行排序：耗尽/将耗尽优先，其余按预计费用降序。 */
import type { Exhaustion, Projection } from './types';

export interface SortableRow {
  row: { cost: number };
  projection: Pick<Projection, 'exhaustion' | 'quotaPct' | 'projectedCost'>;
}

function rank(ex: Exhaustion): number {
  if (ex.status === 'exhausted') return 0;
  if (ex.status === 'danger' && ex.inThisCycle) return 1;
  return 2;
}

/** 已耗尽（超额比例高的在前）→ 本周期将耗尽（耗尽日早的在前）→ 其他（预计费用高的在前）。 */
export function compareRows(a: SortableRow, b: SortableRow): number {
  const ra = rank(a.projection.exhaustion);
  const rb = rank(b.projection.exhaustion);
  if (ra !== rb) return ra - rb;

  if (ra === 0) {
    return (b.projection.quotaPct ?? 0) - (a.projection.quotaPct ?? 0);
  }
  if (ra === 1) {
    const da = a.projection.exhaustion.date?.getTime() ?? Number.POSITIVE_INFINITY;
    const db = b.projection.exhaustion.date?.getTime() ?? Number.POSITIVE_INFINITY;
    return da - db;
  }
  const ca = a.projection.projectedCost ?? a.row.cost;
  const cb = b.projection.projectedCost ?? b.row.cost;
  return cb - ca || b.row.cost - a.row.cost;
}
