/** 数量与文案格式化。 */

/** 本地时区的 ISO 日期（YYYY-MM-DD）。toISOString 是 UTC，凌晨 0–8 点会错位一天。 */
export function localDateISO(d: Date = new Date()): string {
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${d.getFullYear()}-${m}-${day}`;
}

export function compactNumber(n: number): string {
  if (!Number.isFinite(n)) return '—';
  const abs = Math.abs(n);
  if (abs === 0) return '0';
  if (abs < 0.01) return n.toExponential(1);
  if (abs < 1) return trimZeros(n.toFixed(2));
  if (abs < 1000) return trimNum(n);
  if (abs < 1e6) return `${trimZeros((n / 1e3).toFixed(1))}k`;
  if (abs < 1e9) return `${trimZeros((n / 1e6).toFixed(2))}M`;
  return `${trimZeros((n / 1e9).toFixed(2))}B`;
}

function trimNum(n: number): string {
  return Number.isInteger(n) ? String(n) : trimZeros(n.toFixed(1));
}

function trimZeros(s: string): string {
  return s.replace(/\.0+$/, '').replace(/(\.\d*?)0+$/, '$1');
}

/** 按单位格式化用量。 */
export function formatQty(value: number, unit: string): string {
  switch (unit) {
    case 'GB-months':
      return `${trimZeros(value.toFixed(2))} GB-mo`;
    case 'GB-s':
      return `${compactNumber(value)} GB·s`;
    case 'ms':
      return `${compactNumber(value)} ms`;
    case 'minutes':
      return `${compactNumber(value)} min`;
    case 'browsers':
      return `${trimZeros(value.toFixed(1))} 并发`;
    case 'hours':
      return `${compactNumber(value)} h`;
    case 'dimension-months':
      return `${compactNumber(value)} dim-mo`;
    default:
      return compactNumber(value);
  }
}

export function formatMoney(n: number): string {
  const abs = Math.abs(n);
  if (abs === 0) return '$0.00';
  if (abs < 0.01) return `$${n.toFixed(4)}`;
  return `$${n.toFixed(2)}`;
}

export function formatPct(p: number | undefined): string {
  if (p == null || !Number.isFinite(p)) return '—';
  const v = p * 100;
  if (v >= 100) return `${trimZeros(v.toFixed(0))}%`;
  if (v < 1) return `<1%`;
  return `${trimZeros(v.toFixed(0))}%`;
}

export function formatDate(d: Date | undefined, lang: 'zh' | 'en'): string {
  if (!d) return '—';
  if (lang === 'zh') return `${d.getMonth() + 1}月${d.getDate()}日`;
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}
