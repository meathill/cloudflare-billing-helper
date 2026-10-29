/** 页面数据与投影的公共类型。 */

export interface CycleInfo {
  /** 账期开始日（如 10-17） */
  cycleStart: Date;
  /** 账期结束日（含，如 11-16） */
  cycleEnd: Date;
  /** 周期总天数（31） */
  totalDays: number;
  /** 已观察天数（12） */
  observedDays: number;
}

/** 一行计费产品数据（解析自页面或接口）。 */
export interface ProductRow {
  /** 目录 key；未知产品为 `unknown:<名称>` */
  id: string;
  /** 页面上显示的产品名 */
  name: string;
  /** 页面上的括号提示，如 "(First 30M are included)" */
  hint?: string;
  /** 用量单位（count/ms/GB-months/…），未知产品从用量文本推断 */
  unit: string;
  /** 总使用量 */
  totalUsage: number;
  /** 可计费使用量 */
  billableUsage: number;
  /** 使用成本（USD） */
  cost: number;
  /** 页面标注的有效费率（$/单位），可能缺失 */
  effectiveRate?: number;
  /** 免费额度（与用量同单位） */
  included?: number;
  /** 免费额度是否来自页面提示（而非内置目录） */
  includedFromHint: boolean;
}

export interface PageData {
  cycle: CycleInfo | null;
  products: ProductRow[];
  /** 解析时间 */
  parsedAt: number;
}

export type QuotaStatus = 'ok' | 'warn' | 'danger' | 'exhausted' | 'unknown';

export interface Exhaustion {
  status: QuotaStatus;
  /** 预计（首次）达到免费额度的日期；已耗尽时为实际达到日 */
  date?: Date;
  /** 是否会在本账期内耗尽 */
  inThisCycle: boolean;
  /** 预计耗尽说明（如“按当前增长趋势”） */
  basis: 'linear' | 'trend' | 'already' | 'none';
}

export interface Projection {
  /** 日均用量（与用量同单位/天） */
  dailyAvg: number;
  /** 预计本周期总用量 */
  projectedTotal: number;
  /** 预计本周期可计费（超出免费额度的部分） */
  projectedBillable: number;
  /** 预计本周期费用（USD） */
  projectedCost?: number;
  /** 已用免费额度百分比（0-1+） */
  quotaPct?: number;
  /** 免费额度剩余 */
  remainingQuota?: number;
  /** 预计费用所用的有效费率 */
  rateUsed?: number;
  exhaustion: Exhaustion;
}

export interface BreakdownItem {
  /** 应用标识（worker 名 / namespace id / bucket 名 / db uuid） */
  id: string;
  /** 显示名 */
  name: string;
  /** 用量（按请求的 metric 单位） */
  usage: number;
  /** 附加信息（如 key 数、区域） */
  note?: string;
}
