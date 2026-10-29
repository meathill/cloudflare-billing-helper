<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue';
import type { PageData } from '../../lib/types';
import { specOf } from '../../lib/products';
import { parsePage } from '../../lib/parse/dom-parser';
import { recordSnapshot, getSnapshotSeries } from '../../lib/cache';
import { detectLang, makeT } from '../../lib/i18n';
import type { CapturedPayload } from '../content';
import QuotaTable from './components/QuotaTable.vue';
import type { DisplayRow } from './components/QuotaTable.vue';
import CostShareBars from './components/CostShareBars.vue';
import QuotaTrendChart from './components/QuotaTrendChart.vue';
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

let observer: MutationObserver | null = null;
let parseTimer: number | undefined;

function parseNow(): void {
  const parsed = parsePage(document);
  if (parsed) {
    pageData.value = parsed;
    waiting.value = false;
    void recordAndLoadSeries(parsed);
  } else if (!pageData.value) {
    waiting.value = true;
  }
}

function scheduleParse(): void {
  window.clearTimeout(parseTimer);
  parseTimer = window.setTimeout(parseNow, 600);
}

async function recordAndLoadSeries(parsed: PageData): Promise<void> {
  if (!props.accountId) return;
  const cycleStartISO = parsed.cycle?.cycleStart.toISOString().slice(0, 10) ?? '';
  if (!cycleStartISO) return;
  const todayISO = new Date().toISOString().slice(0, 10);
  const values: Record<string, number> = {};
  for (const row of parsed.products) {
    if (Number.isFinite(row.totalUsage)) values[row.id] = row.totalUsage;
  }
  if (Object.keys(values).length > 0) {
    await recordSnapshot(props.accountId, cycleStartISO, todayISO, values);
  }
  // 加载各产品快照序列（用于 gauge 趋势预测与趋势图）
  const next: Record<string, { date: string; value: number }[]> = {};
  for (const row of parsed.products) {
    next[row.id] = await getSnapshotSeries(props.accountId, cycleStartISO, row.id);
  }
  seriesByProduct.value = next;
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

const trendSeries = computed(() => {
  const rows = tableRef.value?.rows ?? [];
  return rows
    .filter((r) => r.row.included != null && r.row.included > 0 && (seriesByProduct.value[r.row.id]?.length ?? 0) >= 2)
    .map((r) => ({
      name: r.row.name,
      color: r.color,
      points: (seriesByProduct.value[r.row.id] ?? []).map((p) => ({
        date: p.date,
        pct: r.row.included ? p.value / r.row.included : 0,
      })),
    }));
});

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

const productCount = computed(() => pageData.value?.products.length ?? 0);
</script>

<template>
  <div class="cfbh-root">
    <div class="card">
      <div class="header">
        <div class="title">
          <span class="logo">⚡</span>
          <strong>{{ t('title') }}</strong>
          <span v-if="productCount > 0" class="count">{{ productCount }} 个产品</span>
        </div>
        <div class="actions">
          <button v-if="hasCaptures" class="btn" @click="copyDebug">
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

        <div v-if="trendSeries.length > 0" class="section">
          <div class="section-title">{{ t('quotaTrend') }}</div>
          <QuotaTrendChart :series="trendSeries" />
        </div>
      </template>

      <div class="footer">
        {{ t('localOnly') }}
        <span v-if="pageData && !pageData.cycle"> · {{ t('noCycle') }}</span>
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
.footer {
  margin-top: 14px;
  padding-top: 10px;
  border-top: 1px solid var(--cfbh-border);
  font-size: 11px;
  color: var(--cfbh-text-2);
}
</style>
