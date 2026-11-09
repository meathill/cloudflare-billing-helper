import { describe, expect, it } from 'vitest';
import fixture from '../../../packages/billing-spec/fixtures/billing.json';
import { summarizeBilling } from '../lib/billing-summary';

describe('shared billing fixtures', () => {
  for (const test of fixture.cases) it(test.name, () => {
    const actual = summarizeBilling(test);
    expect(actual.incomplete).toBe(test.expected.incomplete);
    expect(actual.totals.map(row => row.currency)).toEqual(test.expected.totals.map(row => row.currency));
    for (const [index, expected] of test.expected.totals.entries()) {
      expect(actual.totals[index].fixedCost).toBeCloseTo(Number(expected.fixedCost), 8);
      expect(actual.totals[index].usageCost).toBeCloseTo(Number(expected.usageCost), 8);
      if ('forecastCost' in expected) {
        if (expected.forecastCost === null) expect(actual.totals[index].forecastCost).toBeNull();
        else expect(actual.totals[index].forecastCost).toBeCloseTo(Number(expected.forecastCost), 8);
      }
    }
  });
});

it.each(['', 'Infinity', '1e999'])('marks invalid amount %s incomplete', (price) => {
  const cycle = { start: '2024-02-01T00:00:00Z', end: '2024-03-01T00:00:00Z' };
  const result = summarizeBilling({ cycle, subscriptions: [{ id: 'invalid', currency: 'USD', price, periodStart: cycle.start, periodEnd: cycle.end }], usage: [] });
  expect(result.incomplete).toBe(true);
  expect(result.totals.every(row => Number.isFinite(row.fixedCost))).toBe(true);
});
