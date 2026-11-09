/** Shared billing summary; intervals are half-open and currencies stay separate. */
type Interval = { periodStart: string; periodEnd: string; currency: string; id: string };
type Subscription = Interval & { price: string | null };
type Usage = Interval & { cost: string | null };
export function summarizeBilling(input: { cycle: { start: string; end: string }; subscriptions: Subscription[]; usage: Usage[]; sourceAsOf?: string | null }) {
  const start = Date.parse(input.cycle.start), end = Date.parse(input.cycle.end);
  if (!(end > start)) throw new Error('Invalid billing cycle');
  const totals = new Map<string, { currency: string; fixedCost: number; usageCost: number }>();
  const total = (currency: string) => {
    if (!totals.has(currency)) totals.set(currency, { currency, fixedCost: 0, usageCost: 0 });
    return totals.get(currency)!;
  };
  const incompleteCurrencies = new Set<string>();
  const amount = (value: string | null): number | null => {
    if (typeof value !== 'string' || !value.trim()) return null;
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  };
  const seenSubscriptions = new Map<string, string | null>();
  for (const item of input.subscriptions) {
    const key = JSON.stringify([item.id, item.currency, item.periodStart, item.periodEnd]);
    if (seenSubscriptions.has(key)) {
      if (amount(seenSubscriptions.get(key) ?? null) !== amount(item.price)) incompleteCurrencies.add(item.currency);
      continue;
    }
    seenSubscriptions.set(key, item.price);
    const from = Date.parse(item.periodStart), to = Date.parse(item.periodEnd);
    if (!(to > from)) throw new Error('Invalid subscription period');
    const overlap = Math.max(0, Math.min(end, to) - Math.max(start, from));
    if (overlap) {
      total(item.currency);
      const value = amount(item.price);
      if (value === null) incompleteCurrencies.add(item.currency);
      else total(item.currency).fixedCost += value * overlap / (to - from);
    }
  }
  const seenUsage = new Map<string, Usage>();
  for (const item of input.usage) {
    const key = JSON.stringify([item.currency, item.id]);
    const previous = seenUsage.get(key);
    if (previous) {
      if (previous.periodStart !== item.periodStart || previous.periodEnd !== item.periodEnd || amount(previous.cost) !== amount(item.cost)) incompleteCurrencies.add(item.currency);
      continue;
    }
    seenUsage.set(key, item);
    const from = Date.parse(item.periodStart), to = Date.parse(item.periodEnd);
    if (!(to > from)) throw new Error('Invalid usage period');
    if (to <= start || from >= end) continue;
    total(item.currency);
    if (from < start || to > end) { incompleteCurrencies.add(item.currency); continue; }
    const value = amount(item.cost);
    if (value === null) incompleteCurrencies.add(item.currency);
    else total(item.currency).usageCost += value;
  }
  const elapsed = input.sourceAsOf ? Math.max(0, Math.min(end - start, Date.parse(input.sourceAsOf) - start)) : 0;
  return { totals: [...totals.values()].sort((a, b) => a.currency.localeCompare(b.currency)).map(row => ({
    ...row, forecastCost: !incompleteCurrencies.has(row.currency) && elapsed > 0 ? row.fixedCost + row.usageCost * (end - start) / elapsed : null,
  })), incomplete: incompleteCurrencies.size > 0 };
}
