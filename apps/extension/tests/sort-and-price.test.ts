import { describe, expect, it } from 'vitest';
import { compareRows } from '../lib/sort';
import { deriveRate, projectCumulative } from '../lib/math';
import { PRODUCTS } from '../lib/products';
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

describe('compareRows 排序', () => {
  const mk = (
    name: string,
    status: 'exhausted' | 'danger' | 'ok',
    opts: { quotaPct?: number; date?: Date; cost?: number; rowCost?: number } = {},
  ) => ({
    name,
    row: { cost: opts.rowCost ?? 0 },
    projection: {
      exhaustion: {
        status,
        inThisCycle: status !== 'ok',
        date: opts.date,
        basis: 'linear' as const,
      },
      quotaPct: opts.quotaPct,
      projectedCost: opts.cost,
    },
  });

  it('已耗尽 → 将耗尽（按日期）→ 其他（按预计费用）', () => {
    const rows = [
      mk('cost-high-ok', 'ok', { cost: 99 }),
      mk('danger-late', 'danger', { date: new Date(2026, 10, 10) }),
      mk('exhausted-small', 'exhausted', { quotaPct: 1.1 }),
      mk('danger-early', 'danger', { date: new Date(2026, 10, 1) }),
      mk('exhausted-big', 'exhausted', { quotaPct: 4 }),
    ];
    const sorted = [...rows].sort(compareRows).map((r) => r.name);
    expect(sorted).toEqual([
      'exhausted-big',
      'exhausted-small',
      'danger-early',
      'danger-late',
      'cost-high-ok',
    ]);
  });

  it('其他组内按预计费用降序，其次按当前费用', () => {
    const rows = [
      mk('a', 'ok', { cost: 1, rowCost: 0 }),
      mk('b', 'ok', { cost: 5, rowCost: 0 }),
      mk('c', 'ok', { cost: 2, rowCost: 3 }),
    ];
    expect([...rows].sort(compareRows).map((r) => r.name)).toEqual(['b', 'c', 'a']);
  });
});

describe('deriveRate 目录价兜底', () => {
  it('页面有费用 → 用页面反推', () => {
    const r = row({ billableUsage: 100, cost: 2 });
    expect(deriveRate(r, PRODUCTS.find((p) => p.key === 'workers-cpu-ms'))).toEqual({
      rate: 0.02,
      source: 'page',
    });
  });

  it('本周期无费用 → 回落到目录价并标记 catalog', () => {
    const spec = PRODUCTS.find((p) => p.key === 'kv-list-operations')!;
    const { rate, source } = deriveRate(row({}), spec);
    expect(source).toBe('catalog');
    expect(rate).toBeCloseTo(5 / 1e6, 12);
  });

  it('目录价内生：KV List 预计超额 20 万次 ≈ $1', () => {
    const spec = PRODUCTS.find((p) => p.key === 'kv-list-operations')!;
    // 12 天 462.76k → 日均 38.56k → 31 天约 1.195M，超出 1M 约 195k 次
    const r = row({ id: spec.key, unit: spec.unit, totalUsage: 462.76e3, included: 1e6 });
    const p = projectCumulative(r, cycle(), spec);
    expect(p.rateSource).toBe('catalog');
    expect(p.projectedCost).toBeCloseTo((p.projectedTotal - 1e6) * (5 / 1e6), 6);
    expect(p.projectedCost).toBeGreaterThan(0.9);
    expect(p.projectedCost).toBeLessThan(1.1);
  });

  it('页面无费用且目录也没有价格 → undefined', () => {
    const spec = PRODUCTS.find((p) => p.key === 'observability-logs')!;
    expect(deriveRate(row({}), spec)).toEqual({});
  });
});
