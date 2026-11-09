import { describe, expect, it } from 'vitest';
import { projectCumulative, projectGauge, recentDailyRate, regression, projectRow } from '../lib/math';
import type { CycleInfo, ProductRow } from '../lib/types';

function cycle(): CycleInfo {
  return {
    cycleStart: new Date(2026, 9, 17),
    cycleEnd: new Date(2026, 10, 16),
    totalDays: 31,
    observedDays: 12,
  };
}

function row(overrides: Partial<ProductRow>): ProductRow {
  return {
    id: 'test',
    name: 'Test',
    unit: 'count',
    totalUsage: 0,
    billableUsage: 0,
    cost: 0,
    includedFromHint: false,
    ...overrides,
  };
}

describe('projectCumulative', () => {
  it('按日均外推预计用量与费用（Workers CPU 案例）', () => {
    // 127.98M 总用量、97.99M 可计费、$1.96 → 12 天观察
    const r = row({
      totalUsage: 127.98e6,
      billableUsage: 97.99e6,
      cost: 1.96,
      included: 30e6,
    });
    const p = projectCumulative(r, cycle());
    expect(p.dailyAvg).toBeCloseTo(127.98e6 / 12, 0);
    expect(p.projectedTotal).toBeCloseTo((127.98e6 / 12) * 31, 0);
    expect(p.projectedBillable).toBeCloseTo((127.98e6 / 12) * 31 - 30e6, 0);
    // 有效费率 = 1.96 / 97.99M ≈ $0.02 / M
    expect(p.rateUsed).toBeCloseTo(1.96 / 97.99e6, 12);
    expect(p.projectedCost).toBeCloseTo(((127.98e6 / 12) * 31 - 30e6) * (1.96 / 97.99e6), 3);
  });

  it('累计将超出额度的产品标记 danger 并给出耗尽日期', () => {
    // 12 天用 24M → 日均 2M，included 30M → 周期第 15 天（11月1日）耗尽
    const r = row({ totalUsage: 24e6, included: 30e6 });
    const p = projectCumulative(r, cycle());
    expect(p.exhaustion.status).toBe('danger');
    expect(p.exhaustion.inThisCycle).toBe(true);
    expect(p.exhaustion.date).toEqual(new Date(2026, 10, 1));
  });

  it('用量低于日均消耗节奏时不会在本周期耗尽', () => {
    // 日均 0.5M，included 30M → 60 天后耗尽，超出 31 天周期
    const r = row({ totalUsage: 6e6, included: 30e6 });
    const p = projectCumulative(r, cycle());
    expect(p.exhaustion.inThisCycle).toBe(false);
    expect(p.exhaustion.status).toBe('ok');
    expect(p.exhaustion.date).toBeDefined();
  });

  it('已耗尽 → exhausted；无额度信息 → unknown', () => {
    const r1 = row({ totalUsage: 50e6, included: 30e6 });
    expect(projectCumulative(r1, cycle()).exhaustion.status).toBe('exhausted');
    const r2 = row({ totalUsage: 5 });
    expect(projectCumulative(r2, cycle()).exhaustion.status).toBe('unknown');
  });

  it('零用量不给出耗尽日期', () => {
    const p = projectCumulative(row({ totalUsage: 0, included: 30e6 }), cycle());
    expect(p.exhaustion.status).toBe('ok');
    expect(p.exhaustion.date).toBeUndefined();
  });

  it('近期增量加速时按近期速率预警（账期均值会漏报）', () => {
    // 12 天累计 0.6M：前 9 天几乎不动，最近 3 天每天 +0.15M
    const series = [
      { date: '2026-10-20', value: 0.1e6 },
      { date: '2026-10-25', value: 0.15e6 },
      { date: '2026-10-28', value: 0.6e6 },
    ];
    const r = row({ totalUsage: 0.6e6, included: 1e6 });
    const byCycle = projectCumulative(r, cycle());
    expect(byCycle.exhaustion.inThisCycle).toBe(true);
    const p = projectCumulative(r, cycle(), null, series);
    expect(p.rateBasis).toBe('recent');
    expect(p.dailyAvg).toBeCloseTo(0.45e6 / 3, 0);
    // 剩余 0.4M ÷ 0.15M/天 ≈ 2.67 天 → 第 14.67 天，比账期均值（第 20 天）更早
    expect(p.exhaustion.date!.getTime()).toBeLessThan(byCycle.exhaustion.date!.getTime());
    expect(p.exhaustion.basis).toBe('recent');
    expect(p.projectedTotal).toBeCloseTo(0.6e6 + 0.15e6 * 19, 0);
  });

  it('用量过七成但本周期不会耗尽时标记 warn', () => {
    const series = [
      { date: '2026-10-27', value: 7.4e6 },
      { date: '2026-10-28', value: 7.5e6 },
    ];
    const p = projectCumulative(row({ totalUsage: 7.5e6, included: 10e6 }), cycle(), null, series);
    expect(p.exhaustion.inThisCycle).toBe(false);
    expect(p.exhaustion.status).toBe('warn');
  });
});

describe('recentDailyRate', () => {
  it('取窗口内最早点到最新点的平均日增量', () => {
    const series = [
      { date: '2026-10-01', value: 0 },
      { date: '2026-10-20', value: 100 },
      { date: '2026-10-24', value: 140 },
      { date: '2026-10-27', value: 200 },
    ];
    expect(recentDailyRate(series)).toBeCloseTo(100 / 7);
  });

  it('窗口内没有更早的点时退到上一个快照', () => {
    expect(recentDailyRate([
      { date: '2026-10-01', value: 0 },
      { date: '2026-10-21', value: 200 },
    ])).toBeCloseTo(10);
  });

  it('单点或累计回落返回 null', () => {
    expect(recentDailyRate([{ date: '2026-10-21', value: 200 }])).toBeNull();
    expect(recentDailyRate([
      { date: '2026-10-20', value: 300 },
      { date: '2026-10-21', value: 200 },
    ])).toBeNull();
  });
});

describe('projectGauge', () => {
  it('无序列时按当前水位估算，不预测耗尽', () => {
    const r = row({ unit: 'GB-months', totalUsage: 1.74, included: 1 });
    const p = projectGauge(r, cycle());
    expect(p.projectedTotal).toBe(1.74);
    expect(p.quotaPct).toBeCloseTo(1.74);
    expect(p.exhaustion.status).toBe('exhausted'); // 当前水位已超过 1GB
  });

  it('有上升序列时按回归预测耗尽日期', () => {
    // 每天 +0.1GB：0.5 → 0.6 → 0.7 → 0.8，included 1.0 → 5 天后（约 2 天后达到）
    const series = [
      { date: '2026-10-24', value: 0.5 },
      { date: '2026-10-25', value: 0.6 },
      { date: '2026-10-26', value: 0.7 },
      { date: '2026-10-27', value: 0.8 },
    ];
    const r = row({ unit: 'GB-months', totalUsage: 0.8, included: 1 });
    const p = projectGauge(r, cycle(), series);
    expect(p.exhaustion.basis).toBe('trend');
    expect(p.exhaustion.inThisCycle).toBe(true);
    expect(p.exhaustion.date).toBeInstanceOf(Date);
  });

  it('下降或平稳序列不预测耗尽', () => {
    const series = [
      { date: '2026-10-24', value: 0.8 },
      { date: '2026-10-25', value: 0.75 },
      { date: '2026-10-26', value: 0.7 },
    ];
    const r = row({ unit: 'GB-months', totalUsage: 0.7, included: 1 });
    const p = projectGauge(r, cycle(), series);
    expect(p.exhaustion.inThisCycle).toBe(false);
  });
});

describe('regression', () => {
  it('拟合线性序列', () => {
    const fit = regression([1, 2, 3, 4].map((v) => ({ x: v, y: v * 2 + 1 })));
    expect(fit).not.toBeNull();
    expect(fit!.slope).toBeCloseTo(2);
    expect(fit!.intercept).toBeCloseTo(1);
  });

  it('点数不足或 x 相同返回 null', () => {
    expect(regression([{ x: 1, y: 1 }])).toBeNull();
    expect(regression([
      { x: 1, y: 1 },
      { x: 1, y: 2 },
    ])).toBeNull();
  });
});

describe('projectRow dispatch', () => {
  it('GB-months 单位自动走 gauge', () => {
    const r = row({ unit: 'GB-months', totalUsage: 0.5, included: 1 });
    expect(projectRow(r, null, cycle()).projectedTotal).toBe(0.5);
  });
});
