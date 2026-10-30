import { describe, expect, it } from 'vitest';
import {
  dayGap,
  detectAnomalies,
  detectAnomaliesBySegment,
  mergeSegments,
  sumSeries,
  toDailySeries,
} from '../lib/trend';
import type { TrendPoint } from '../lib/trend';

function pts(list: [string, number][]): TrendPoint[] {
  return list.map(([date, value]) => ({ date, value }));
}

describe('dayGap', () => {
  it('同月相邻', () => {
    expect(dayGap('2026-10-01', '2026-10-02')).toBe(1);
  });
  it('跨月', () => {
    expect(dayGap('2026-10-30', '2026-11-02')).toBe(3);
  });
  it('非法日期回退 1', () => {
    expect(dayGap('bad', '2026-10-02')).toBe(1);
  });
});

describe('toDailySeries', () => {
  it('cumulative：差分摊日均，首点丢弃', () => {
    const out = toDailySeries(pts([['2026-10-17', 100], ['2026-10-18', 150], ['2026-10-19', 220]]), 'cumulative');
    expect(out).toEqual([
      { date: '2026-10-18', value: 50 },
      { date: '2026-10-19', value: 70 },
    ]);
  });
  it('缺失天摊为日均（周五→周一差分除以 3）', () => {
    const out = toDailySeries(pts([['2026-10-23', 100], ['2026-10-26', 250]]), 'cumulative');
    expect(out).toEqual([{ date: '2026-10-26', value: 50 }]);
  });
  it('累计回落按 0 计，不产生负值', () => {
    const out = toDailySeries(pts([['2026-10-17', 100], ['2026-10-18', 90]]), 'cumulative');
    expect(out).toEqual([{ date: '2026-10-18', value: 0 }]);
  });
  it('单点/空序列安全', () => {
    expect(toDailySeries(pts([['2026-10-17', 5]]), 'cumulative')).toEqual([]);
    expect(toDailySeries([], 'cumulative')).toEqual([]);
  });
  it('gauge：水位值原样透传', () => {
    const out = toDailySeries(pts([['2026-10-18', 3.2], ['2026-10-17', 2.8]]), 'gauge');
    expect(out).toEqual([
      { date: '2026-10-17', value: 2.8 },
      { date: '2026-10-18', value: 3.2 },
    ]);
  });
});

describe('toDailySeries 跨账期', () => {
  it('给定账期起始日：首点按「周期开始到当天」的天数摊日均，不再丢弃', () => {
    // 账期 10-17 开始；首个快照在 10-19（累计 3 天用量 3.0 → 日均 1.0）
    const out = toDailySeries(
      pts([['2026-10-19', 3], ['2026-10-20', 4]]),
      'cumulative',
      '2026-10-17',
    );
    expect(out).toEqual([
      { date: '2026-10-19', value: 1 },
      { date: '2026-10-20', value: 1 },
    ]);
  });
  it('首点就是账期第一天时按 1 天算', () => {
    const out = toDailySeries(pts([['2026-10-17', 0.25], ['2026-10-18', 0.5]]), 'cumulative', '2026-10-17');
    expect(out).toEqual([
      { date: '2026-10-17', value: 0.25 },
      { date: '2026-10-18', value: 0.25 },
    ]);
  });
  it('不给账期起始日：首点无法计算则丢弃（保守行为）', () => {
    const out = toDailySeries(pts([['2026-10-17', 0.25], ['2026-10-18', 0.5]]), 'cumulative');
    expect(out).toEqual([{ date: '2026-10-18', value: 0.25 }]);
  });
});

describe('mergeSegments', () => {
  it('按日期拼接各账期并打上 seg 标记', () => {
    const out = mergeSegments([
      { seg: '2026-09-16', points: pts([['2026-09-18', 0.1]]) },
      { seg: '2026-10-16', points: pts([['2026-10-17', 0.2], ['2026-10-18', 0.3]]) },
    ]);
    expect(out).toEqual([
      { date: '2026-09-18', value: 0.1, seg: '2026-09-16' },
      { date: '2026-10-17', value: 0.2, seg: '2026-10-16' },
      { date: '2026-10-18', value: 0.3, seg: '2026-10-16' },
    ]);
  });
});

describe('sumSeries', () => {
  it('保留分组标记（用于跨账期断线）', () => {
    const out = sumSeries([
      [{ date: '2026-10-17', value: 1, seg: 'c1' }],
      [{ date: '2026-10-17', value: 2, seg: 'c1' }],
    ]);
    expect(out).toEqual([{ date: '2026-10-17', value: 3, seg: 'c1' }]);
  });
});

describe('sumSeries', () => {
  it('按日期对齐求和，产出并集日期', () => {
    const out = sumSeries([
      pts([['2026-10-18', 1], ['2026-10-19', 2]]),
      pts([['2026-10-19', 3], ['2026-10-20', 4]]),
    ]);
    expect(out).toEqual([
      { date: '2026-10-18', value: 1 },
      { date: '2026-10-19', value: 5 },
      { date: '2026-10-20', value: 4 },
    ]);
  });
  it('空输入', () => {
    expect(sumSeries([])).toEqual([]);
  });
});

describe('detectAnomalies', () => {
  it('暴涨：超过阈值报异动', () => {
    const base = pts([['2026-10-01', 1], ['2026-10-02', 1], ['2026-10-03', 1]]);
    const out = detectAnomalies([...base, { date: '2026-10-04', value: 3 }], { minValue: 0.5 });
    expect(out).toHaveLength(1);
    expect(out[0]!.date).toBe('2026-10-04');
    expect(out[0]!.ratio).toBeCloseTo(3);
  });
  it('暴跌：中段点报异动，最后一个点只报涨不报跌（半截数据）', () => {
    const series = pts([['2026-10-01', 2], ['2026-10-02', 2], ['2026-10-03', 2], ['2026-10-04', 0.5]]);
    // 作为末点的 0.5 不报（可能是当天只过了半天）
    expect(detectAnomalies(series, { minValue: 0.5 })).toHaveLength(0);
    // 同样幅度落在中段则报
    const withTail = [...series, { date: '2026-10-05', value: 2 }];
    const out = detectAnomalies(withTail, { minValue: 0.5 });
    expect(out.map((a) => a.date)).toEqual(['2026-10-04']);
  });
  it('小额噪音被 minValue 过滤', () => {
    const series = pts([['2026-10-01', 0.01], ['2026-10-02', 0.01], ['2026-10-03', 0.01], ['2026-10-04', 0.05]]);
    expect(detectAnomalies(series, { minValue: 0.5 })).toHaveLength(0);
  });
  it('从 0 突增（baseline=0）报 Infinity 倍率', () => {
    const series = pts([['2026-10-01', 0], ['2026-10-02', 0], ['2026-10-03', 0], ['2026-10-04', 2]]);
    const out = detectAnomalies(series, { minValue: 0.5 });
    expect(out).toHaveLength(1);
    expect(out[0]!.ratio).toBe(Infinity);
  });
  it('历史不足 3 点不检测', () => {
    const series = pts([['2026-10-01', 1], ['2026-10-02', 99]]);
    expect(detectAnomalies(series)).toHaveLength(0);
  });
});

describe('detectAnomaliesBySegment', () => {
  it('基准不跨账期：新账期的低值不与上个账期的高值比较', () => {
    // 上个账期每日 5，新账期每日 0.5 —— 不应报暴跌（那是新账期的正常水平）
    const series: TrendPoint[] = [
      { date: '2026-09-18', value: 5, seg: 'c1' },
      { date: '2026-09-19', value: 5, seg: 'c1' },
      { date: '2026-09-20', value: 5, seg: 'c1' },
      { date: '2026-09-21', value: 5, seg: 'c1' },
      { date: '2026-10-17', value: 0.5, seg: 'c2' },
      { date: '2026-10-18', value: 0.5, seg: 'c2' },
      { date: '2026-10-19', value: 0.5, seg: 'c2' },
    ];
    const out = detectAnomaliesBySegment(series, { minValue: 0.5 });
    expect(out.map((a) => a.date)).not.toContain('2026-10-17');
    // 不分组时同一个序列会误报（上个账期的 5 把新账期首日拉成暴跌）
    expect(detectAnomalies(series, { minValue: 0.5 }).map((a) => a.date)).toContain('2026-10-17');
  });

  it('账期内仍能正常报异动，并带上 seg', () => {
    const series: TrendPoint[] = [
      { date: '2026-10-17', value: 1, seg: 'c2' },
      { date: '2026-10-18', value: 1, seg: 'c2' },
      { date: '2026-10-19', value: 1, seg: 'c2' },
      { date: '2026-10-20', value: 3, seg: 'c2' },
    ];
    const out = detectAnomaliesBySegment(series, { minValue: 0.5 });
    expect(out).toHaveLength(1);
    expect(out[0]!.date).toBe('2026-10-20');
    expect(out[0]!.seg).toBe('c2');
  });
});
