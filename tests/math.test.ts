import { describe, expect, it } from 'vitest';
import { projectCumulative, projectGauge, regression, projectRow } from '../lib/math';
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
