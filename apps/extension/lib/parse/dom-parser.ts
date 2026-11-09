/**
 * 从可计费使用量页 DOM 解析产品行与账期。
 * 策略：不依赖 dash 的私有 class（会变），按表头文本定位列、按产品名匹配目录；
 * 兼容中英文界面（产品名在两种语言下都是英文）。
 */
import { matchProduct } from '../products';
import type { CycleInfo, PageData, ProductRow } from '../types';

/** 解析 "127.98M" / "171.57k" / "1.74 GB-months" / "$2.46" / "3,000" → 数值 + 单位。 */
export function parseQuantity(text: string): { value: number; unit?: string } | null {
  const t = text.replace(/\s+/g, ' ').trim();
  if (!t) return null;
  const m = /^[$]?\s*([\d,]+(?:\.\d+)?)\s*([kKmMbB])?(?:\s*([A-Za-z·*\-]+(?:-[A-Za-z]+)*))?/.exec(t);
  if (!m) return null;
  const numStr = m[1].replace(/,/g, '');
  let value = Number(numStr);
  if (!Number.isFinite(value)) return null;
  const suffix = m[2]?.toLowerCase();
  if (suffix === 'k') value *= 1e3;
  else if (suffix === 'm') value *= 1e6;
  else if (suffix === 'b') value *= 1e9;
  const unit = m[3];
  return { value, unit: unit || undefined };
}

/** 解析提示里的免费额度，如 "First 30M are included" → 30e6；"First 1GB is included" → 1。 */
export function parseIncludedHint(hint: string): { value: number; unit?: string } | null {
  const m = /First\s+([\d,.]+)\s*([kKmMbB])?\s*(GB[-mo]*|GB\*S|GB-s|million|billion)?/i.exec(hint);
  if (!m) return null;
  let value = Number(m[1].replace(/,/g, ''));
  if (!Number.isFinite(value)) return null;
  const suffix = m[2]?.toLowerCase();
  if (suffix === 'k') value *= 1e3;
  else if (suffix === 'm') value *= 1e6;
  else if (suffix === 'b') value *= 1e9;
  const word = m[3]?.toLowerCase();
  if (word === 'million') value *= 1e6;
  else if (word === 'billion') value *= 1e9;
  return { value, unit: m[3] ? m[3].replace(/\*/g, '-') : undefined };
}

const MONTHS: Record<string, number> = {
  jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5,
  jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11,
};

/** "Oct 17, 2026" / "Oct 17" → Date（无年份时用 givenYear）。 */
export function parseDashDate(text: string, givenYear?: number): Date | null {
  const m = /([A-Za-z]{3})\s+(\d{1,2})(?:,?\s+(\d{4}))?/.exec(text);
  if (!m) return null;
  const mon = MONTHS[m[1].toLowerCase()];
  if (mon == null) return null;
  const year = m[3] ? Number(m[3]) : givenYear ?? new Date().getFullYear();
  return new Date(year, mon, Number(m[2]));
}

/** 从整页文本解析账期：范围 + "已观察 31 个周期日中的 12 天" / "12 of 31 cycle days observed"。 */
export function parseCycle(docText: string): CycleInfo | null {
  // 中英文两种口径
  const zh = /(\d+)\s*个周期日中的\s*(\d+)\s*天/.exec(docText);
  const en = /(\d+)\s*of\s*(\d+)\s*cycle days?/i.exec(docText);
  let totalDays: number | null = null;
  let observedDays: number | null = null;
  if (zh) {
    totalDays = Number(zh[1]);
    observedDays = Number(zh[2]);
  } else if (en) {
    observedDays = Number(en[1]);
    totalDays = Number(en[2]);
  }
  if (totalDays == null || observedDays == null || !(totalDays > 0) || !(observedDays > 0)) return null;

  // 找 "MMM d - MMM d, yyyy" 范围，取包含今天或最近的一个作为账期
  const rangeRe = /([A-Za-z]{3})\s+(\d{1,2})\s*[-–]\s*([A-Za-z]{3})\s+(\d{1,2}),?\s+(\d{4})/g;
  const ranges: { start: Date; end: Date }[] = [];
  let m: RegExpExecArray | null;
  while ((m = rangeRe.exec(docText))) {
    const start = parseDashDate(`${m[1]} ${m[2]}, ${m[5]}`);
    const end = parseDashDate(`${m[3]} ${m[4]}, ${m[5]}`);
    if (start && end && end > start) ranges.push({ start, end });
  }
  if (ranges.length === 0) return null;
  // 账期范围 = 跨度最接近 totalDays 的那个
  let best = ranges[0];
  let bestDiff = Infinity;
  for (const r of ranges) {
    const span = Math.round((r.end.getTime() - r.start.getTime()) / 86_400_000) + 1;
    const diff = Math.abs(span - totalDays);
    if (diff < bestDiff) {
      best = r;
      bestDiff = diff;
    }
  }
  return { cycleStart: best.start, cycleEnd: best.end, totalDays, observedDays };
}

interface ColumnMap {
  product: number;
  total: number;
  billable: number;
  cost: number;
}

function detectColumns(cells: string[]): ColumnMap | null {
  const find = (re: RegExp) => cells.findIndex((c) => re.test(c));
  const product = find(/产品|product/i);
  const total = find(/总使用量|total usage|总用量/i);
  const billable = find(/可计费|billable/i);
  const cost = find(/使用成本|usage cost|成本|cost/i);
  if (product < 0 || total < 0) return null;
  return {
    product,
    total,
    billable: billable >= 0 ? billable : -1,
    cost: cost >= 0 ? cost : -1,
  };
}

export function findUsageTable(root: Document | Element): Element | null {
  const tables = Array.from(root.querySelectorAll('table'));
  for (const t of tables) {
    const headText = (t.querySelector('thead') ?? t).textContent ?? '';
    if (/总使用量|total usage/i.test(headText) && (/产品|product/i.test(headText))) return t;
  }
  // 兜底：div 表格（role=table）
  const roleTables = Array.from(root.querySelectorAll('[role="table"]'));
  for (const t of roleTables) {
    const text = t.textContent ?? '';
    if (/总使用量|total usage/i.test(text) && /产品|product/i.test(text)) return t;
  }
  return null;
}

function rowCells(row: Element): Element[] {
  return Array.from(row.querySelectorAll(':scope > td, :scope > th, [role="cell"], [role="gridcell"]'));
}

function extractProductCell(cell: Element): { name: string; hint?: string } {
  const text = (cell.textContent ?? '').replace(/\s+/g, ' ').trim();
  const hintMatch = /\(([^)]+)\)/.exec(text);
  const hint = hintMatch?.[1]?.trim();
  const name = (hintMatch ? text.slice(0, hintMatch.index) : text).trim();
  return { name, hint };
}

function extractCost(cell: Element): { cost: number; rate?: number } {
  const text = (cell.textContent ?? '').replace(/\s+/g, ' ').trim();
  const numbers = Array.from(text.matchAll(/\$\s*([\d,]+(?:\.\d+)?)/g)).map((m) => Number(m[1].replace(/,/g, '')));
  const cost = numbers.length > 0 ? numbers[0] : 0;
  const rateMatch = /\$\s*([\d.]+)\s*\/\s*([A-Za-z·*\-]+)/.exec(text);
  const rate = rateMatch ? Number(rateMatch[1]) : undefined;
  return { cost, rate: rate != null && Number.isFinite(rate) ? rate : undefined };
}

/** 解析整个页面；表格不存在或无产品行时返回 null。 */
export function parsePage(doc: Document): PageData | null {
  const table = findUsageTable(doc);
  if (!table) return null;
  const trRows = Array.from(table.querySelectorAll('tr, [role="row"]'));

  let cols: ColumnMap | null = null;
  const products: ProductRow[] = [];

  for (const tr of trRows) {
    const cells = rowCells(tr);
    if (cells.length < 2) continue;
    const cellTexts = cells.map((c) => (c.textContent ?? '').replace(/\s+/g, ' ').trim());
    if (!cols) {
      const detected = detectColumns(cellTexts);
      if (detected) {
        cols = detected;
        continue;
      }
    }
    if (!cols) continue;
    if (cols.product >= cellTexts.length) continue;
    const { name, hint } = extractProductCell(cells[cols.product]);
    if (!name) continue;

    const totalQ = parseQuantity(cellTexts[cols.total]);
    if (!totalQ) continue;

    let billable = totalQ.value;
    if (cols.billable >= 0 && cols.billable < cellTexts.length) {
      const b = parseQuantity(cellTexts[cols.billable]);
      if (b) billable = b.value;
    }
    let cost = 0;
    let rate: number | undefined;
    if (cols.cost >= 0 && cols.cost < cellTexts.length) {
      const parsed = extractCost(cells[cols.cost]);
      cost = parsed.cost;
      rate = parsed.rate;
    }

    const spec = matchProduct(name);
    let included: number | undefined;
    let includedFromHint = false;
    if (spec?.included != null) {
      included = spec.included;
    } else if (hint) {
      const h = parseIncludedHint(hint);
      if (h) {
        included = h.value;
        includedFromHint = true;
      }
    }

    products.push({
      id: spec?.key ?? `unknown:${name.toLowerCase()}`,
      name,
      hint,
      unit: spec?.unit ?? normalizeUnit(totalQ.unit),
      totalUsage: totalQ.value,
      billableUsage: billable,
      cost,
      effectiveRate: rate,
      included,
      includedFromHint,
    });
  }

  if (products.length === 0) return null;
  const cycle = parseCycle(doc.body?.textContent ?? '');
  return { cycle, products, parsedAt: Date.now() };
}

function normalizeUnit(unit: string | undefined): string {
  if (!unit) return 'count';
  const u = unit.toLowerCase();
  if (u.includes('gb-month') || u === 'gb-mo') return 'GB-months';
  if (u === 'gb-s' || u === 'gb-s') return 'GB-s';
  return u;
}
