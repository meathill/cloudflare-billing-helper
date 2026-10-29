/**
 * 预估计算（纯函数）。
 * - cumulative 类：按日均线性外推；耗尽日 = 周期开始 + included/日均
 * - gauge 类（存储/并发）：单点水位无法判趋势，需传入按日序列做最小二乘回归
 */
import type { CycleInfo, Exhaustion, ProductRow, Projection, QuotaStatus } from './types';
import type { ProductSpec } from './products';

/** 最小二乘回归，返回斜率与截距。点数 < 2 或 x 全相同返回 null。 */
export function regression(points: { x: number; y: number; }[]): { slope: number; intercept: number; } | null {
  const n = points.length;
  if (n < 2) return null;
  const xs = points.map((p) => p.x);
  const ys = points.map((p) => p.y);
  const allSameX = xs.every((x) => x === xs[0]);
  if (allSameX) return null;
  const mx = xs.reduce((a, b) => a + b, 0) / n;
  const my = ys.reduce((a, b) => a + b, 0) / n;
  let num = 0;
  let den = 0;
  for (let i = 0; i < n; i++) {
    num += (xs[i] - mx) * (ys[i] - my);
    den += (xs[i] - mx) ** 2;
  }
  if (den === 0) return null;
  const slope = num / den;
  return { slope, intercept: my - slope * mx };
}

const DAY_MS = 86_400_000;

function statusFor(quotaPct: number | undefined, exhaustion: Exhaustion): QuotaStatus {
  if (exhaustion.status === 'exhausted') return 'exhausted';
  if (exhaustion.status === 'danger') return 'danger';
  if (quotaPct != null && quotaPct >= 0.7) return 'warn';
  return 'ok';
}

/** cumulative 类产品投影。 */
export function projectCumulative(row: ProductRow, cycle: CycleInfo | null): Projection {
  const observedDays = cycle?.observedDays ?? 0;
  const totalDays = cycle?.totalDays ?? 0;
  const dailyAvg = observedDays > 0 ? row.totalUsage / observedDays : 0;
  const projectedTotal = dailyAvg * totalDays;
  const included = row.included;
  const quotaPct = included != null && included > 0 ? row.totalUsage / included : undefined;
  const remainingQuota = included != null ? Math.max(0, included - row.totalUsage) : undefined;

  let exhaustion: Exhaustion;
  if (included == null) {
    exhaustion = { status: 'unknown', inThisCycle: false, basis: 'none' };
  } else if (row.totalUsage >= included) {
    exhaustion = { status: 'exhausted', inThisCycle: true, basis: 'already' };
  } else if (dailyAvg <= 0) {
    exhaustion = { status: 'ok', inThisCycle: false, basis: 'none' };
  } else {
    const daysToIncluded = included / dailyAvg;
    const date = cycle
      ? new Date(cycle.cycleStart.getTime() + daysToIncluded * DAY_MS)
      : undefined;
    const inThisCycle = totalDays > 0 && daysToIncluded <= totalDays;
    exhaustion = {
      status: inThisCycle ? 'danger' : 'ok',
      date,
      inThisCycle,
      basis: 'linear',
    };
  }

  const rate = deriveRate(row);
  const projectedBillable = included != null ? Math.max(0, projectedTotal - included) : Math.max(0, projectedTotal);
  const projectedCost = rate != null ? projectedBillable * rate : undefined;

  return {
    dailyAvg,
    projectedTotal,
    projectedBillable,
    projectedCost,
    quotaPct,
    remainingQuota,
    rateUsed: rate,
    exhaustion,
  };
}

export function deriveRate(row: ProductRow): number | undefined {
  if (row.effectiveRate != null && row.effectiveRate > 0) return row.effectiveRate;
  if (row.billableUsage > 0 && row.cost > 0) return row.cost / row.billableUsage;
  return undefined;
}

/**
 * gauge 类（存储/并发）投影。
 * @param series 按日水位序列（value 与用量同单位），按日期升序
 */
export function projectGauge(
  row: ProductRow,
  cycle: CycleInfo | null,
  series: { date: string; value: number; }[] = [],
): Projection {
  const quotaPct = row.included != null && row.included > 0 ? row.totalUsage / row.included : undefined;
  const remainingQuota = row.included != null ? Math.max(0, row.included - row.totalUsage) : undefined;
  // 无序列时按当前水位持平估算
  const dailyAvg = series.length >= 2 ? gaugeDailyDelta(series) : 0;
  const projectedTotal = row.totalUsage;

  let exhaustion: Exhaustion;
  const current = series.length > 0 ? series[series.length - 1].value : row.totalUsage;
  if (row.included == null) {
    exhaustion = { status: 'unknown', inThisCycle: false, basis: 'none' };
  } else if (current >= row.included) {
    exhaustion = { status: 'exhausted', inThisCycle: true, basis: 'already' };
  } else if (series.length >= 2) {
    const fit = regression(series.map((p, i) => ({ x: i, y: p.value })));
    if (fit && fit.slope > 0) {
      const daysToIncluded = (row.included - current) / fit.slope;
      const date = new Date(Date.now() + daysToIncluded * DAY_MS);
      const inThisCycle = cycle ? date.getTime() <= cycle.cycleEnd.getTime() + DAY_MS : daysToIncluded <= 30;
      exhaustion = {
        status: inThisCycle ? 'danger' : 'ok',
        date,
        inThisCycle,
        basis: 'trend',
      };
    } else {
      exhaustion = { status: 'ok', inThisCycle: false, basis: 'none' };
    }
  } else {
    exhaustion = { status: 'ok', inThisCycle: false, basis: 'none' };
  }

  const rate = deriveRate(row);
  // gauge 的“可计费”即超出部分的水位；无序列按当前水位估算
  const projectedBillable = row.included != null ? Math.max(0, projectedTotal - row.included) : projectedTotal;
  const projectedCost = rate != null ? projectedBillable * rate : undefined;

  return {
    dailyAvg,
    projectedTotal,
    projectedBillable,
    projectedCost,
    quotaPct,
    remainingQuota,
    rateUsed: rate,
    exhaustion,
  };
}

/** gauge 序列的平均日增量（正负均可）。 */
function gaugeDailyDelta(series: { value: number; }[]): number {
  const n = series.length;
  if (n < 2) return 0;
  return (series[n - 1].value - series[0].value) / (n - 1);
}

/** 对一行产品做投影（自动区分 cumulative / gauge）。 */
export function projectRow(
  row: ProductRow,
  spec: ProductSpec | null,
  cycle: CycleInfo | null,
  series: { date: string; value: number; }[] = [],
): Projection {
  const kind = spec?.kind ?? (row.unit === 'GB-months' ? 'gauge' : 'cumulative');
  return kind === 'gauge' ? projectGauge(row, cycle, series) : projectCumulative(row, cycle);
}

/** 生成某行的时间序列（优先扩展自留存档）。由调用方传入快照数据。 */
export function pctOfQuota(row: ProductRow): number | undefined {
  return row.included && row.included > 0 ? row.totalUsage / row.included : undefined;
}
