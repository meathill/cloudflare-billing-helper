import { describe, expect, it } from 'vitest';
import { parseIncludedHint, parsePage, parseQuantity, parseCycle, parseDashDate } from '../lib/parse/dom-parser';

describe('parseQuantity', () => {
  it.each([
    ['127.98M', 127.98e6],
    ['171.57k', 171.57e3],
    ['38.07k', 38.07e3],
    ['1.74 GB-months', 1.74],
    ['0.16 GB-months', 0.16],
    ['3,000', 3000],
    ['0', 0],
    ['$2.46', 2.46],
    ['25B', 25e9],
  ])('%s → %d', (input, expected) => {
    expect(parseQuantity(input)?.value).toBe(expected);
  });

  it('捕获单位', () => {
    expect(parseQuantity('1.74 GB-months')?.unit).toBe('GB-months');
    expect(parseQuantity('127.98M')?.unit).toBeUndefined();
  });
});

describe('parseIncludedHint', () => {
  it.each([
    ['First 30M are included', 30e6],
    ['First 1M is included', 1e6],
    ['First 10M is included', 10e6],
    ['First 3,000 emails included', 3000],
    ['6000 minutes included per month', null],
  ])('%s', (hint, expected) => {
    expect(parseIncludedHint(hint)?.value ?? null).toBe(expected);
  });

  it('GB 提示', () => {
    expect(parseIncludedHint('GB, First 1GB is included')?.value).toBe(1);
    expect(parseIncludedHint('first 5GB included')?.value).toBe(5);
  });
});

describe('parseDashDate', () => {
  it('带年份', () => {
    expect(parseDashDate('Oct 17, 2026')).toEqual(new Date(2026, 9, 17));
  });
  it('不带年份补齐', () => {
    expect(parseDashDate('Nov 16', 2026)).toEqual(new Date(2026, 10, 16));
  });
});

describe('parseCycle', () => {
  it('中文文案', () => {
    const text = '预计周期费用 $6.35 Oct 17 - Nov 16, 2026 · 已观察 31 个周期日中的 12 天';
    const c = parseCycle(text);
    expect(c).not.toBeNull();
    expect(c!.cycleStart).toEqual(new Date(2026, 9, 17));
    expect(c!.cycleEnd).toEqual(new Date(2026, 10, 16));
    expect(c!.totalDays).toBe(31);
    expect(c!.observedDays).toBe(12);
  });

  it('英文文案', () => {
    const text = 'Projected cycle spend $6.35 Oct 17 - Nov 16, 2026 · 12 of 31 cycle days observed';
    const c = parseCycle(text);
    expect(c!.totalDays).toBe(31);
    expect(c!.observedDays).toBe(12);
  });
});

const FIXTURE_HTML = `
<html><body>
<div class="summary">支出摘要
  <div>总费用 $2.46 已观察使用量 Oct 17 - Oct 28, 2026</div>
  <div>预计周期费用 $6.35 Oct 17 - Nov 16, 2026 · 已观察 31 个周期日中的 12 天</div>
</div>
<table>
  <thead>
    <tr><th>产品</th><th>总使用量</th><th>可计费使用量</th><th>使用成本</th></tr>
  </thead>
  <tbody>
    <tr>
      <td><span class="dot"></span><div>Workers CPU ms</div><div>(First 30M are included)</div></td>
      <td>127.98M</td><td>97.99M</td>
      <td><div>$1.96</div><div>有效费率 $0.00 / unit</div></td>
    </tr>
    <tr>
      <td><span class="dot"></span><div>KV Storage</div><div>(GB, First 1GB is included)</div></td>
      <td>1.74 GB-months</td><td>1 GB-months</td>
      <td><div>$0.50</div><div>有效费率 $0.50 / GB-months</div></td>
    </tr>
    <tr>
      <td><span class="dot"></span><div>Worker Build Minutes</div><div>(6000 minutes included per month)</div></td>
      <td>471</td><td>0</td>
      <td><div>$0.00</div><div>本账单周期无使用费用</div></td>
    </tr>
    <tr>
      <td><span class="dot"></span><div>KV List Operations</div><div>(First 1M is included)</div></td>
      <td>462.76k</td><td>0</td>
      <td><div>$0.00</div><div>本账单周期无使用费用</div></td>
    </tr>
    <tr>
      <td><span class="dot"></span><div>神秘产品 X</div><div>(First 100 is included)</div></td>
      <td>42</td><td>0</td>
      <td><div>$0.00</div><div>本账单周期无使用费用</div></td>
    </tr>
  </tbody>
</table>
</body></html>`;

function doc(): Document {
  return new DOMParser().parseFromString(FIXTURE_HTML, 'text/html');
}

describe('parsePage', () => {
  const page = () => parsePage(doc())!;

  it('解析出全部产品行', () => {
    const p = page();
    expect(p.products).toHaveLength(5);
  });

  it('Workers CPU ms：目录免费额度 + 反推费率', () => {
    const w = page().products[0];
    expect(w.id).toBe('workers-cpu-ms');
    expect(w.included).toBe(30e6);
    expect(w.totalUsage).toBe(127.98e6);
    expect(w.billableUsage).toBe(97.99e6);
    expect(w.cost).toBe(1.96);
    // $0.00 / unit 解析为 0 → deriveRate 阶段用 cost/billable 反推
    expect(w.effectiveRate).toBe(0);
  });

  it('KV Storage：单位为 GB-months、可计费 1', () => {
    const kv = page().products[1];
    expect(kv.id).toBe('kv-storage');
    expect(kv.unit).toBe('GB-months');
    expect(kv.totalUsage).toBe(1.74);
    expect(kv.billableUsage).toBe(1);
    expect(kv.included).toBe(1);
  });

  it('未知产品走 hint 兜底并标记 unknown', () => {
    const mystery = page().products.find((p) => p.id.startsWith('unknown:'))!;
    expect(mystery.name).toBe('神秘产品 X');
    expect(mystery.included).toBe(100);
    expect(mystery.includedFromHint).toBe(true);
  });

  it('解析账期', () => {
    const c = page().cycle;
    expect(c).not.toBeNull();
    expect(c!.totalDays).toBe(31);
    expect(c!.observedDays).toBe(12);
    expect(c!.cycleStart).toEqual(new Date(2026, 9, 17));
  });

  it('无表格时返回 null', () => {
    const empty = new DOMParser().parseFromString('<html><body><div>hi</div></body></html>', 'text/html');
    expect(parsePage(empty)).toBeNull();
  });
});
