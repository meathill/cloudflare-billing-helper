/** 极简 i18n：跟随页面语言（zh/en），默认中文。 */

type Lang = 'zh' | 'en';

const DICT = {
  title: { zh: '账单用量助手', en: 'Billing Usage Helper' },
  quotaWarning: { zh: '以下产品将在本账期内耗尽免费额度', en: 'These products will exhaust their free quota this cycle' },
  exhausted: { zh: '已耗尽', en: 'exhausted' },
  willExhaust: { zh: '预计耗尽', en: 'Will exhaust' },
  notExhaust: { zh: '本周期内不会耗尽', en: 'Will not exhaust this cycle' },
  unknownQuota: { zh: '未知免费额度', en: 'Unknown free quota' },
  product: { zh: '产品', en: 'Product' },
  quota: { zh: '免费额度', en: 'Free quota' },
  remaining: { zh: '剩余', en: 'Remaining' },
  dailyAvg: { zh: '日均', en: 'Daily avg' },
  projected: { zh: '预计本周期', en: 'Projected' },
  projectedCost: { zh: '预计费用', en: 'Projected cost' },
  exhaustion: { zh: '耗尽预期', en: 'Exhaustion' },
  costShare: { zh: '费用构成', en: 'Cost breakdown' },
  tabCost: { zh: '每日费用', en: 'Daily cost' },
  tabQuota: { zh: '额度消耗', en: 'Quota usage' },
  rangeCycle: { zh: '本账期', en: 'This cycle' },
  rangeAll: { zh: '全部历史', en: 'All history' },
  totalCost: { zh: '总费用', en: 'Total' },
  costAnomaly: { zh: '费用异动', en: 'Cost anomalies' },
  costTrendEmpty: {
    zh: '打开账单页几天后，这里会显示每日费用曲线',
    en: 'The daily cost chart appears after a few days of visits',
  },
  trendEmpty: { zh: '扩展运行几天后这里会显示每日额度消耗曲线', en: 'Trend appears after the extension runs for a few days' },
  breakdown: { zh: '按应用拆分', en: 'Per-app breakdown' },
  breakdownLoading: { zh: '加载中…', en: 'Loading…' },
  breakdownEmpty: { zh: '没有可用数据', en: 'No data available' },
  breakdownUnsupported: { zh: '暂无法获取该维度拆分', en: 'Breakdown not available for this metric' },
  waiting: { zh: '正在等待页面数据…', en: 'Waiting for page data…' },
  refresh: { zh: '刷新', en: 'Refresh' },
  copyDebug: { zh: '复制接口调试数据', en: 'Copy API debug data' },
  copied: { zh: '已复制', en: 'Copied' },
  estimated: { zh: '估算', en: 'estimate' },
  localOnly: { zh: '所有数据仅在本地处理，不会发送到第三方', en: 'All data is processed locally' },
  advice: { zh: '建议', en: 'Tip' },
  noCycle: { zh: '未解析到账期，预估基于已观察数据', en: 'Cycle not parsed; estimates use observed data' },
} as const;

export type I18nKey = keyof typeof DICT;

export function detectLang(): Lang {
  const htmlLang = document.documentElement.lang ?? '';
  if (/^en/i.test(htmlLang)) return 'en';
  const text = document.body?.textContent ?? '';
  if (/总使用量|可计费/.test(text)) return 'zh';
  if (/Total [Uu]sage|Billable/.test(text)) return 'en';
  return 'zh';
}

export function makeT(lang: Lang) {
  return (key: I18nKey): string => DICT[key][lang];
}
