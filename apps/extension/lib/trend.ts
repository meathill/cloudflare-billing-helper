/**
 * 趋势计算纯函数：把快照里的累计序列换算成「每日值」曲线，并做暴涨暴跌检测。
 * 页面上的用量/费用都是本账期累计值（cycle-to-date），直接画只会单调上升；
 * 只有差分成每日值，突增突降才看得出来。
 *
 * 跨账期规则：累计值在账期切换时清零，所以
 * 1) 每日值必须在账期内独立差分，不能拿上个账期的末值去减；
 * 2) 账期首个快照按「周期开始到当天」的天数摊成日均（不是丢弃）；
 * 3) 异动基准不跨账期（拿上个账期的水平比这期的今天没有意义）。
 */
import type { UsageKind } from './products';

export interface TrendPoint {
  /** ISO 日期（YYYY-MM-DD） */
  date: string;
  value: number;
  /** 所属账期分组；跨账期画图时用于断开曲线 */
  seg?: string;
}

/** 两个 ISO 日期间隔的天数（≥1）。按 UTC 解析避免时区/夏令时干扰。 */
export function dayGap(a: string, b: string): number {
  const ta = Date.parse(`${a}T00:00:00Z`);
  const tb = Date.parse(`${b}T00:00:00Z`);
  if (!Number.isFinite(ta) || !Number.isFinite(tb)) return 1;
  return Math.max(1, Math.round((tb - ta) / 86_400_000));
}

/** 含首尾的天数（from 与 from 同为 1 天）。账期首日摊日均时用它。 */
export function daysInclusive(from: string, to: string): number {
  const a = Date.parse(`${from}T00:00:00Z`);
  const b = Date.parse(`${to}T00:00:00Z`);
  if (!Number.isFinite(a) || !Number.isFinite(b)) return 1;
  return Math.max(1, Math.round((b - a) / 86_400_000) + 1);
}

/**
 * 累计序列 → 每日值。
 * - cumulative：相邻两点差分 ÷ 相隔天数（没打开页面的天摊为日均）；
 *   累计回落（Cloudflare 修正历史数据）时按 0 计，避免负值毛刺。
 *   账期首个快照没有前值：给定 cycleStartDate（账期起始日）时按
 *   「周期开始到当天的天数」摊成日均；没有则丢弃该点。
 * - gauge：存储水位等即时值，原样返回（仅排序）。
 */
export function toDailySeries(
  points: TrendPoint[],
  kind: UsageKind,
  cycleStartDate?: string,
): TrendPoint[] {
  const sorted = [...points].sort((a, b) => a.date.localeCompare(b.date));
  if (kind === 'gauge') return sorted.map((p) => ({ ...p }));
  const out: TrendPoint[] = [];
  for (let i = 0; i < sorted.length; i++) {
    const cur = sorted[i]!;
    if (i === 0) {
      // 账期首个快照：累计值从周期开始算起，摊成日均
      if (!cycleStartDate) continue;
      const days = daysInclusive(cycleStartDate, cur.date);
      out.push({ date: cur.date, value: Math.max(0, cur.value) / days, seg: cur.seg });
      continue;
    }
    const prev = sorted[i - 1]!;
    const diff = cur.value - prev.value;
    // 累计回落（Cloudflare 修正历史数据）跳过该点：钳成 0 会在曲线上造出假的暴跌
    if (diff < 0) continue;
    out.push({ date: cur.date, value: diff / dayGap(prev.date, cur.date), seg: cur.seg });
  }
  return out;
}

/** 多条每日序列按日期对齐求和（各产品日费用 → 总日费用）。分组标记沿用首次出现该日期的序列。 */
export function sumSeries(list: TrendPoint[][]): TrendPoint[] {
  const acc = new Map<string, { value: number; seg?: string }>();
  for (const series of list) {
    for (const p of series) {
      const cur = acc.get(p.date);
      if (cur) cur.value += p.value;
      else acc.set(p.date, { value: p.value, seg: p.seg });
    }
  }
  return [...acc.entries()]
    .map(([date, v]) => ({ date, value: v.value, seg: v.seg }))
    .sort((a, b) => a.date.localeCompare(b.date));
}

/** 把多组（每组一个账期）的序列按日期拼成一条带分组标记的序列。 */
export function mergeSegments(groups: { seg: string; points: TrendPoint[] }[]): TrendPoint[] {
  const out: TrendPoint[] = [];
  for (const g of groups) {
    for (const p of g.points) out.push({ ...p, seg: g.seg });
  }
  return out.sort((a, b) => a.date.localeCompare(b.date));
}

export interface Anomaly {
  date: string;
  value: number;
  /** 基准：此前 window 个点的均值；0 表示此前无费用 */
  baseline: number;
  /** value / baseline；baseline 为 0 时为 Infinity */
  ratio: number;
}

export interface AnomalyOptions {
  /** 基准窗口：取此前 N 个记录点（默认 7） */
  window?: number;
  /** 波动阈值：≥ratio 倍视为暴涨、≤1/ratio 视为暴跌（默认 1.5，即 ±50%） */
  ratio?: number;
  /** 绝对值门槛：暴涨需 value 达到、暴跌需 baseline 达到，滤掉小额噪音（USD） */
  minValue?: number;
}

/**
 * 检测每日序列中的暴涨/暴跌点：每个点与其此前 window 个点的均值比较。
 * 注意：最新一个点可能是"今天还没过完"的半截数据，暴跌告警对它不成立
 * （只影响涨幅的漏报，不影响曲线），因此最后一个点只报涨不报跌。
 */
export function detectAnomalies(points: TrendPoint[], opts: AnomalyOptions = {}): Anomaly[] {
  const { window = 7, ratio = 1.5, minValue = 0 } = opts;
  const out: Anomaly[] = [];
  for (let i = 0; i < points.length; i++) {
    const hist = points.slice(Math.max(0, i - window), i);
    if (hist.length < 3) continue;
    const cur = points[i]!;
    const baseline = hist.reduce((s, p) => s + p.value, 0) / hist.length;
    if (baseline <= 0) {
      if (cur.value > 0 && cur.value >= minValue) {
        out.push({ date: cur.date, value: cur.value, baseline, ratio: Infinity });
      }
      continue;
    }
    const r = cur.value / baseline;
    const spike = cur.value >= minValue && r >= ratio;
    const drop = i < points.length - 1 && baseline >= minValue && r <= 1 / ratio;
    if (spike || drop) out.push({ date: cur.date, value: cur.value, baseline, ratio: r });
  }
  return out;
}

/**
 * 按分组（账期）分别做异动检测：基准只在同一账期内取，
 * 避免用上个账期的水平去衡量这账期的第一天。
 */
export function detectAnomaliesBySegment(
  points: TrendPoint[],
  opts: AnomalyOptions = {},
): (Anomaly & { seg?: string })[] {
  const out: (Anomaly & { seg?: string })[] = [];
  let group: TrendPoint[] = [];
  let seg: string | undefined;
  const flush = (): void => {
    for (const a of detectAnomalies(group, opts)) out.push({ ...a, seg });
    group = [];
  };
  for (const p of points) {
    if (group.length > 0 && p.seg !== seg) flush();
    seg = p.seg;
    group.push(p);
  }
  if (group.length > 0) flush();
  return out;
}
