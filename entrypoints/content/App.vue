<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue';
import type { PageData } from '../../lib/types';
import { specOf } from '../../lib/products';
import { parsePage } from '../../lib/parse/dom-parser';
import { recordSnapshot, getSnapshotStore, seriesFromStore, allSeriesFromStore, cycleKeyOf, resolveCycleStartDate } from '../../lib/cache';
import type { SnapshotValue } from '../../lib/cache';
import { toDailySeries, sumSeries, mergeSegments, detectAnomaliesBySegment } from '../../lib/trend';
import type { TrendPoint, Anomaly } from '../../lib/trend';
import { localDateISO, formatMoney } from '../../lib/format';
import { detectLang, makeT } from '../../lib/i18n';
import { runSelfCheck } from '../../lib/api/selfcheck';
import type { SelfCheckItem } from '../../lib/api/selfcheck';
import type { CapturedPayload } from '../content';
import QuotaTable from './components/QuotaTable.vue';
import type { DisplayRow } from './components/QuotaTable.vue';
import CostShareBars from './components/CostShareBars.vue';
import TrendChart from './components/TrendChart.vue';
import type { TrendSeries, TrendAnomaly } from './components/TrendChart.vue';
import BreakdownList from './components/BreakdownList.vue';

const props = defineProps<{
  accountId: string;
  getCaptures?: () => CapturedPayload[];
}>();

const pageData = ref<PageData | null>(null);
const waiting = ref(true);
const lang = ref<'zh' | 'en'>('zh');
const t = computed(() => makeT(lang.value));

const expanded = ref<Record<string, boolean>>({});
const tableRef = ref<InstanceType<typeof QuotaTable> | null>(null);
const cycleKey = computed(() => pageData.value?.cycle?.cycleStart.toISOString() ?? '');

const seriesByProduct = ref<Record<string, { date: string; value: number }[]>>({});

// 每日费用曲线：tab 与范围（本账期 / 全部历史）
const trendTab = ref<'cost' | 'quota'>('cost');
const costRange = ref<'cycle' | 'all'>('cycle');
const allCostByProduct = ref<Record<string, Record<string, { date: string; value: number }[]>>>({});
/** 快照里存在的账期（升序） */
const snapshotCycles = ref<string[]>([]);

let observer: MutationObserver | null = null;
let parseTimer: number | undefined;
let lastLogKey = '';

function parseNow(): void {
  const parsed = parsePage(document);
  if (parsed) {
    const logKey = `${parsed.products.length}:${parsed.cycle?.cycleStart.toISOString() ?? 'nocycle'}`;
    if (logKey !== lastLogKey) {
      lastLogKey = logKey;
      // eslint-disable-next-line no-console
      console.info(
        `[CFBH] 解析成功：${parsed.products.length} 个产品行，账期 ${parsed.cycle ? '已识别' : '未识别'}`,
      );
    }
    pageData.value = parsed;
    waiting.value = false;
    void recordAndLoadSeries(parsed);
  } else if (!pageData.value) {
    // eslint-disable-next-line no-console
    console.info('[CFBH] 尚未解析到产品表格，继续等待页面渲染…');
    waiting.value = true;
  }
}

function scheduleParse(): void {
  window.clearTimeout(parseTimer);
  parseTimer = window.setTimeout(parseNow, 600);
}

async function recordAndLoadSeries(parsed: PageData): Promise<void> {
  if (!props.accountId) return;
  const cycleStart = parsed.cycle?.cycleStart;
  const cycleKey = cycleStart ? cycleKeyOf(cycleStart) : '';
  if (!cycleKey) return;
  const todayISO = localDateISO();
  const values: Record<string, SnapshotValue> = {};
  for (const row of parsed.products) {
    if (Number.isFinite(row.totalUsage)) {
      values[row.id] = { u: row.totalUsage, c: Number.isFinite(row.cost) ? row.cost : 0 };
    }
  }
  // 一次读盘写入，同时拿回最新快照供下面派生（避免按产品重复读盘）
  const store =
    Object.keys(values).length > 0
      ? await recordSnapshot(props.accountId, cycleKey, todayISO, values)
      : await getSnapshotStore(props.accountId);
  // 各产品序列：用量给 gauge 趋势预测与额度图，费用给每日费用曲线与异动检测
  const nextUsage: Record<string, { date: string; value: number }[]> = {};
  const nextAllCost: Record<string, Record<string, { date: string; value: number }[]>> = {};
  for (const row of parsed.products) {
    nextUsage[row.id] = seriesFromStore(store, cycleKey, row.id, 'u');
    nextAllCost[row.id] = allSeriesFromStore(store, row.id, 'c');
  }
  seriesByProduct.value = nextUsage;
  allCostByProduct.value = nextAllCost;
  snapshotCycles.value = Object.keys(store).sort();
}

onMounted(() => {
  lang.value = detectLang();
  parseNow();
  observer = new MutationObserver(scheduleParse);
  observer.observe(document.body, { childList: true, subtree: true });
});

onUnmounted(() => {
  observer?.disconnect();
  window.clearTimeout(parseTimer);
});

function refresh(): void {
  parseNow();
}

const warnings = computed<DisplayRow[]>(() => {
  if (!pageData.value) return [];
  const rows = tableRef.value?.rows ?? [];
  return rows
    .filter((r) => r.projection.exhaustion.inThisCycle)
    .sort((a, b) => {
      const da = a.projection.exhaustion.date?.getTime() ?? Infinity;
      const db = b.projection.exhaustion.date?.getTime() ?? Infinity;
      return da - db;
    });
});

const costItems = computed(() => {
  const rows = tableRef.value?.rows ?? [];
  return rows
    .filter((r) => r.row.cost > 0)
    .map((r) => ({ name: r.row.name, cost: r.row.cost, color: r.color }));
});

const trendSeries = computed<TrendSeries[]>(() => {
  const rows = tableRef.value?.rows ?? [];
  return rows
    .filter((r) => r.row.included != null && r.row.included > 0 && (seriesByProduct.value[r.row.id]?.length ?? 0) >= 2)
    .map((r) => ({
      name: r.row.name,
      color: r.color,
      points: (seriesByProduct.value[r.row.id] ?? []).map((p) => ({
        date: p.date,
        value: r.row.included ? p.value / r.row.included : 0,
      })),
    }));
});

/** 当前账期键（页面上解析到的账期） */
const currentCycleKey = computed(() => {
  const c = pageData.value?.cycle?.cycleStart;
  return c ? cycleKeyOf(c) : '';
});

/** 账期起始日：当前账期用页面解析值（最准），历史账期按分组键反解 */
function cycleStartOf(cycleKey: string): string | undefined {
  if (cycleKey === currentCycleKey.value) {
    const c = pageData.value?.cycle?.cycleStart;
    if (c) return localDateISO(c);
  }
  return resolveCycleStartDate(cycleKey) ?? undefined;
}

/**
 * 各产品在各账期的每日费用。
 * 累计值在账期切换时清零，所以差分只在账期内进行；账期首个快照按
 * 「周期开始到当天」的天数摊成日均（而不是丢弃）。
 */
const dailyCostByCycle = computed<Record<string, Record<string, TrendPoint[]>>>(() => {
  const out: Record<string, Record<string, TrendPoint[]>> = {};
  for (const row of pageData.value?.products ?? []) {
    const byCycle: Record<string, TrendPoint[]> = {};
    const all = allCostByProduct.value[row.id] ?? {};
    for (const cycleKey of Object.keys(all).sort()) {
      const points = toDailySeries(all[cycleKey] ?? [], 'cumulative', cycleStartOf(cycleKey));
      byCycle[cycleKey] = points.map((p) => ({ ...p, seg: cycleKey }));
    }
    out[row.id] = byCycle;
  }
  return out;
});

/** 当前范围下的每日费用（跨账期用 seg 标记，画图时断开，不把两段连成一条线） */
const dailyCostByProduct = computed<Record<string, TrendPoint[]>>(() => {
  const out: Record<string, TrendPoint[]> = {};
  const cycles =
    costRange.value === 'cycle'
      ? snapshotCycles.value.filter((k) => k === currentCycleKey.value)
      : snapshotCycles.value;
  for (const row of pageData.value?.products ?? []) {
    const byCycle = dailyCostByCycle.value[row.id] ?? {};
    out[row.id] = mergeSegments(
      cycles.filter((k) => byCycle[k]).map((k) => ({ seg: k, points: byCycle[k]! })),
    );
  }
  return out;
});

const totalCostDaily = computed(() => sumSeries(Object.values(dailyCostByProduct.value)));

/** 费用曲线：总费用（橙）+ 当前费用 Top5 产品分线（至少 2 个点才画得成线） */
const costChartSeries = computed<TrendSeries[]>(() => {
  const rows = tableRef.value?.rows ?? [];
  const top = [...rows]
    .filter((r) => (dailyCostByProduct.value[r.row.id]?.length ?? 0) >= 2)
    .sort((a, b) => b.row.cost - a.row.cost)
    .slice(0, 5)
    .map((r) => ({ name: r.row.name, color: r.color, points: dailyCostByProduct.value[r.row.id] ?? [] }));
  const total = totalCostDaily.value;
  if (total.length < 2) return top;
  return [{ name: t.value('totalCost'), color: 'var(--cfbh-accent)', points: total }, ...top];
});

const costChartReady = computed(() => costChartSeries.value.some((s) => s.points.length >= 2));

/** 曲线上的异动红点（基准按账期独立计算，不跨账期混算） */
const costAnomalyMarks = computed<TrendAnomaly[]>(() => {
  const out: TrendAnomaly[] = [];
  costChartSeries.value.forEach((s, index) => {
    for (const a of detectAnomaliesBySegment(s.points, { minValue: 0.5 })) {
      out.push({ seriesIndex: index, date: a.date, ratio: a.ratio });
    }
  });
  return out;
});

interface CostAnomalyChip {
  name: string;
  color: string;
  anomaly: Anomaly;
}

function deviation(a: Anomaly): number {
  return Number.isFinite(a.ratio) ? Math.abs(a.ratio - 1) : 99;
}

/** 顶部异动提示：只提示最新一天有异动的系列（历史异动在曲线上有红点），按波动幅度取前 3 */
const costAnomalyChips = computed<CostAnomalyChip[]>(() => {
  const out: CostAnomalyChip[] = [];
  for (const s of costChartSeries.value) {
    const list = detectAnomaliesBySegment(s.points, { minValue: 0.5 });
    const last = list[list.length - 1];
    if (last && s.points[s.points.length - 1]?.date === last.date) {
      out.push({ name: s.name, color: s.color, anomaly: last });
    }
  }
  return out.sort((a, b) => deviation(b.anomaly) - deviation(a.anomaly)).slice(0, 3);
});

function anomalyText(chip: CostAnomalyChip): string {
  const a = chip.anomaly;
  const money = formatMoney(a.value);
  if (!Number.isFinite(a.ratio)) {
    return lang.value === 'zh' ? `${chip.name}：${money}/天（此前无费用）` : `${chip.name}: ${money}/day (was $0)`;
  }
  const pct = Math.round((a.ratio - 1) * 100);
  const dir = pct > 0 ? `+${pct}%` : `${pct}%`;
  return lang.value === 'zh'
    ? `${chip.name}：${money}/天，较近 7 次均值 ${dir}`
    : `${chip.name}: ${money}/day, ${dir} vs recent avg`;
}

const moneyFormat = (v: number): string => formatMoney(v);
const pctFormat = (v: number): string => `${Math.round(v * 100)}%`;

function onExpanded(rowId: string): void {
  expanded.value[rowId] = true;
}

function specOfRow(rowId: string) {
  const row = pageData.value?.products.find((p) => p.id === rowId);
  return row ? specOf(row) : null;
}

const copied = ref(false);
async function copyDebug(): Promise<void> {
  const captures = props.getCaptures?.() ?? [];
  try {
    await navigator.clipboard.writeText(JSON.stringify(captures, null, 2));
    copied.value = true;
    setTimeout(() => (copied.value = false), 2000);
  } catch {
    // 剪贴板不可用时忽略
  }
}

const hasCaptures = computed(() => (props.getCaptures?.() ?? []).length > 0);

/** 抓包调试按钮只在开发构建出现（生产包不保留调试入口） */
const isDev = import.meta.env.DEV;

const productCount = computed(() => pageData.value?.products.length ?? 0);

const version = (() => {
  try {
    return chrome.runtime.getManifest().version;
  } catch {
    return '';
  }
})();

// 接口自检
const checkItems = ref<SelfCheckItem[]>([]);
const checking = ref(false);
async function runCheck(): Promise<void> {
  if (!props.accountId || checking.value) return;
  checking.value = true;
  try {
    checkItems.value = await runSelfCheck(props.accountId, pageData.value?.cycle ?? null);
    // eslint-disable-next-line no-console
    console.info('[CFBH] 接口自检结果', checkItems.value);
  } catch (e) {
    checkItems.value = [{ name: '接口自检', ok: false, detail: e instanceof Error ? e.message : String(e) }];
  } finally {
    checking.value = false;
  }
}
</script>

<template>
  <div class="cfbh-root">
    <div class="card">
      <div class="header">
        <div class="title">
          <span class="logo">⚡</span>
          <strong>{{ t('title') }}</strong>
          <span v-if="productCount > 0" class="count">{{ productCount }} 个产品</span>
          <span class="count version">v{{ version }}</span>
        </div>
        <div class="actions">
          <button v-if="isDev && hasCaptures" class="btn" @click="copyDebug">
            {{ copied ? t('copied') : t('copyDebug') }}
          </button>
          <button class="btn" @click="refresh">{{ t('refresh') }}</button>
        </div>
      </div>

      <div v-if="waiting" class="waiting">{{ t('waiting') }}</div>

      <template v-else-if="pageData">
        <div v-if="warnings.length > 0" class="warning-banner">
          <div class="warning-title">⚠️ {{ t('quotaWarning') }}：</div>
          <div class="warning-list">
            <span v-for="w in warnings" :key="w.row.id" class="warning-chip" :style="{ borderColor: w.color }">
              <strong>{{ w.row.name }}</strong>
              <em v-if="w.projection.exhaustion.date">
                {{ lang === 'zh' ? '预计' : '~' }}
                {{ w.projection.exhaustion.date.getMonth() + 1 }}/{{ w.projection.exhaustion.date.getDate() }}
              </em>
              <em v-else>{{ t('exhausted') }}</em>
            </span>
          </div>
        </div>

        <QuotaTable ref="tableRef" :page-data="pageData" :lang="lang" :series="seriesByProduct" @expanded="onExpanded">
          <template #detail="{ row }">
            <BreakdownList
              v-if="expanded[row.row.id] && specOfRow(row.row.id)?.breakdown"
              :account-id="props.accountId"
              :family="specOfRow(row.row.id)!.breakdown!.family"
              :metric="specOfRow(row.row.id)!.breakdown!.metric"
              :unit="row.row.unit"
              :cycle="pageData.cycle"
            />
          </template>
        </QuotaTable>

        <div v-if="costItems.length > 1" class="section">
          <div class="section-title">{{ t('costShare') }}</div>
          <CostShareBars :items="costItems" />
        </div>

        <div v-if="costChartReady || trendSeries.length > 0" class="section">
          <div class="trend-head">
            <div class="seg">
              <button class="seg-btn" :class="{ active: trendTab === 'cost' }" @click="trendTab = 'cost'">
                {{ t('tabCost') }}
              </button>
              <button class="seg-btn" :class="{ active: trendTab === 'quota' }" @click="trendTab = 'quota'">
                {{ t('tabQuota') }}
              </button>
            </div>
            <div v-if="trendTab === 'cost' && costChartReady" class="seg">
              <button class="seg-btn" :class="{ active: costRange === 'cycle' }" @click="costRange = 'cycle'">
                {{ t('rangeCycle') }}
              </button>
              <button class="seg-btn" :class="{ active: costRange === 'all' }" @click="costRange = 'all'">
                {{ t('rangeAll') }}
              </button>
            </div>
          </div>
          <template v-if="trendTab === 'cost'">
            <div v-if="costAnomalyChips.length > 0" class="anomaly-banner">
              <span class="anomaly-title">⚡ {{ t('costAnomaly') }}</span>
              <span
                v-for="chip in costAnomalyChips"
                :key="chip.name"
                class="anomaly-chip"
                :style="{ borderColor: chip.color }"
              >
                {{ anomalyText(chip) }}
              </span>
            </div>
            <TrendChart
              v-if="costChartReady"
              :series="costChartSeries"
              :y-format="moneyFormat"
              :anomalies="costAnomalyMarks"
            />
            <div v-else class="chart-empty">{{ t('costTrendEmpty') }}</div>
          </template>
          <template v-else>
            <TrendChart v-if="trendSeries.length > 0" :series="trendSeries" :y-format="pctFormat" />
            <div v-else class="chart-empty">{{ t('trendEmpty') }}</div>
          </template>
        </div>

        <div v-if="checkItems.length > 0" class="section">
          <div class="section-title">接口自检</div>
          <div
            v-for="item in checkItems"
            :key="item.name"
            class="check-item"
            :class="item.ok ? 'check-ok' : 'check-err'"
          >
            <span class="check-name">{{ item.ok ? '✓' : '✗' }} {{ item.name }}</span>
            <span class="check-detail">{{ item.detail }}</span>
          </div>
        </div>
      </template>

      <div class="footer">
        {{ t('localOnly') }}
        <span v-if="pageData && !pageData.cycle"> · {{ t('noCycle') }}</span>
        <button class="link-btn" :disabled="checking" @click="runCheck">
          {{ checking ? '自检中…' : '接口自检' }}
        </button>
      </div>
    </div>
  </div>
</template>

<style>
.cfbh-root {
  --cfbh-bg: #ffffff;
  --cfbh-bg-2: #f7f8fa;
  --cfbh-border: #e4e7ec;
  --cfbh-text: #1f2429;
  --cfbh-text-2: #6b7280;
  --cfbh-track: #eceef1;
  --cfbh-accent: #f6821f;
  --cfbh-ok: #16a34a;
  --cfbh-warn: #d97706;
  --cfbh-danger: #dc2626;

  margin: 12px 0;
  color: var(--cfbh-text);
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial,
    'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei', sans-serif;
  font-size: 13px;
  line-height: 1.5;
}
.cfbh-root .card {
  background: var(--cfbh-bg);
  border: 1px solid var(--cfbh-border);
  border-radius: 10px;
  padding: 16px;
  box-shadow: 0 1px 2px rgb(0 0 0 / 4%);
}
@media (prefers-color-scheme: dark) {
  .cfbh-root {
    --cfbh-bg: #1b1c1f;
    --cfbh-bg-2: #242629;
    --cfbh-border: #33363b;
    --cfbh-text: #e8eaed;
    --cfbh-text-2: #9aa0a6;
    --cfbh-track: #2d3034;
  }
  .cfbh-root .card {
    box-shadow: none;
  }
}
</style>

<style scoped>
.header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 12px;
}
.title {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 14px;
}
.logo {
  font-size: 15px;
}
.count {
  color: var(--cfbh-text-2);
  font-size: 12px;
  font-weight: 400;
}
.version {
  font-size: 11px;
  opacity: 0.7;
}
.actions {
  display: flex;
  gap: 8px;
}
.btn {
  border: 1px solid var(--cfbh-border);
  background: var(--cfbh-bg);
  color: var(--cfbh-text);
  border-radius: 6px;
  font-size: 12px;
  padding: 4px 10px;
  cursor: pointer;
}
.btn:hover {
  background: var(--cfbh-bg-2);
}
.waiting {
  color: var(--cfbh-text-2);
  padding: 20px 0;
  text-align: center;
  font-size: 12px;
}
.warning-banner {
  background: color-mix(in srgb, var(--cfbh-danger) 7%, transparent);
  border: 1px solid color-mix(in srgb, var(--cfbh-danger) 35%, transparent);
  border-radius: 8px;
  padding: 10px 12px;
  margin-bottom: 12px;
}
.warning-title {
  font-size: 12px;
  font-weight: 600;
  color: var(--cfbh-danger);
  margin-bottom: 6px;
}
.warning-list {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.warning-chip {
  display: inline-flex;
  gap: 6px;
  align-items: baseline;
  border: 1px solid var(--cfbh-border);
  border-radius: 6px;
  padding: 3px 8px;
  font-size: 12px;
  background: var(--cfbh-bg);
}
.warning-chip em {
  font-style: normal;
  color: var(--cfbh-danger);
  font-variant-numeric: tabular-nums;
}
.section {
  margin-top: 16px;
  border-top: 1px solid var(--cfbh-border);
  padding-top: 12px;
}
.section-title {
  font-size: 12px;
  font-weight: 600;
  color: var(--cfbh-text-2);
  margin-bottom: 8px;
  text-transform: uppercase;
  letter-spacing: 0.03em;
}
.trend-head {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
  margin-bottom: 8px;
}
.seg {
  display: inline-flex;
  border: 1px solid var(--cfbh-border);
  border-radius: 6px;
  overflow: hidden;
}
.seg-btn {
  border: none;
  background: var(--cfbh-bg);
  color: var(--cfbh-text-2);
  font-size: 11px;
  padding: 3px 10px;
  cursor: pointer;
}
.seg-btn + .seg-btn {
  border-left: 1px solid var(--cfbh-border);
}
.seg-btn.active {
  background: var(--cfbh-bg-2);
  color: var(--cfbh-text);
  font-weight: 600;
}
.anomaly-banner {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  margin-bottom: 10px;
  font-size: 12px;
}
.anomaly-title {
  color: var(--cfbh-warn);
  font-weight: 600;
}
.anomaly-chip {
  border: 1px solid var(--cfbh-border);
  border-radius: 6px;
  padding: 2px 8px;
  background: color-mix(in srgb, var(--cfbh-warn) 7%, transparent);
  font-variant-numeric: tabular-nums;
}
.chart-empty {
  color: var(--cfbh-text-2);
  font-size: 12px;
  padding: 14px 0;
  text-align: center;
}
.check-item {
  display: flex;
  gap: 10px;
  padding: 4px 0;
  font-size: 12px;
  border-bottom: 1px dashed var(--cfbh-border);
}
.check-name {
  white-space: nowrap;
  min-width: 150px;
}
.check-detail {
  color: var(--cfbh-text-2);
  word-break: break-all;
  font-size: 11px;
}
.check-ok .check-name {
  color: var(--cfbh-ok);
}
.check-err .check-name {
  color: var(--cfbh-danger);
}
.check-err .check-detail {
  color: var(--cfbh-danger);
}
.link-btn {
  border: none;
  background: none;
  padding: 0;
  margin-left: 10px;
  color: var(--cfbh-text-2);
  font-size: 11px;
  text-decoration: underline;
  cursor: pointer;
}
.link-btn:hover {
  color: var(--cfbh-text);
}
.footer {
  margin-top: 14px;
  padding-top: 10px;
  border-top: 1px solid var(--cfbh-border);
  font-size: 11px;
  color: var(--cfbh-text-2);
}
</style>
