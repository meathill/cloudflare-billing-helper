<script setup lang="ts">
import { computed } from 'vue';
import type { CycleInfo, PageData, ProductRow, Projection } from '../../../lib/types';
import { specOf } from '../../../lib/products';
import { projectRow } from '../../../lib/math';
import { formatQty, formatMoney } from '../../../lib/format';
import { makeT } from '../../../lib/i18n';
import QuotaBar from './QuotaBar.vue';

export interface DisplayRow {
  row: ProductRow;
  projection: Projection;
  color: string;
  family: string;
  expandable: boolean;
  /** 耗尽后的迁移建议（来自目录） */
  advice?: string;
}

const props = defineProps<{
  pageData: PageData;
  lang: 'zh' | 'en';
  series: Record<string, { date: string; value: number }[]>;
}>();

const emit = defineEmits<{ (e: 'expanded', rowId: string): void }>();

const t = computed(() => makeT(props.lang));

const rows = computed<DisplayRow[]>(() => {
  const cycle = props.pageData.cycle;
  return props.pageData.products
    .map((row) => {
      const spec = specOf(row);
      const series = props.series[row.id] ?? [];
      const projection = projectRow(row, spec, cycle, series);
      return {
        row,
        projection,
        color: spec?.color ?? '#888',
        family: spec?.family ?? 'other',
        expandable: spec?.breakdown != null,
        advice: spec?.advice,
      };
    })
    .sort((a, b) => {
      const ca = a.projection.projectedCost ?? a.row.cost;
      const cb = b.projection.projectedCost ?? b.row.cost;
      return cb - ca || b.row.cost - a.row.cost;
    });
});

defineExpose({ rows });

function fmtQty(value: number, unit: string): string {
  return formatQty(value, unit);
}

function fmtMoney(value: number | undefined): string {
  return value != null ? formatMoney(value) : '—';
}

function remainingText(r: DisplayRow): string {
  if (r.row.included == null) return '—';
  const remaining = r.row.included - r.row.totalUsage;
  return remaining <= 0 ? t.value('exhausted') : fmtQty(remaining, r.row.unit);
}

function exhaustionText(r: DisplayRow): string {
  const ex = r.projection.exhaustion;
  if (ex.status === 'exhausted') return t.value('exhausted');
  if (ex.status === 'danger' && ex.date) {
    const d = `${ex.date.getMonth() + 1}/${ex.date.getDate()}`;
    return props.lang === 'zh' ? `${d} 耗尽` : `exhausts ${d}`;
  }
  if (ex.status === 'unknown') return t.value('unknownQuota');
  return t.value('notExhaust');
}

function statusClass(r: DisplayRow): string {
  switch (r.projection.exhaustion.status) {
    case 'exhausted':
    case 'danger':
      return 'danger';
    case 'warn':
      return 'warn';
    default:
      return 'ok';
  }
}
</script>

<template>
  <div class="quota-table">
    <div class="head row">
      <div class="col-name">{{ t('product') }}</div>
      <div class="col-quota">{{ t('quota') }}</div>
      <div class="col-remaining">{{ t('remaining') }}</div>
      <div class="col-avg">{{ t('dailyAvg') }}</div>
      <div class="col-projected">{{ t('projected') }}</div>
      <div class="col-cost">{{ t('projectedCost') }}</div>
      <div class="col-exhaust">{{ t('exhaustion') }}</div>
    </div>
    <details
      v-for="r in rows"
      :key="r.row.id"
      class="row-wrap"
      @toggle="(e: Event) => (e.target as HTMLDetailsElement).open && emit('expanded', r.row.id)"
    >
      <summary class="row">
        <div class="col-name">
          <span class="dot" :style="{ background: r.color }" />
          <div class="name-block">
            <div class="name">{{ r.row.name }}</div>
            <div v-if="r.row.hint" class="hint">{{ r.row.hint }}</div>
          </div>
        </div>
        <div class="col-quota">
          <QuotaBar :pct="r.projection.quotaPct" :color="r.color" />
          <div class="quota-text">
            {{ fmtQty(r.row.totalUsage, r.row.unit) }}
            <template v-if="r.row.included != null"> / {{ fmtQty(r.row.included, r.row.unit) }}</template>
          </div>
        </div>
        <div class="col-remaining" :class="statusClass(r)">{{ remainingText(r) }}</div>
        <div class="col-avg">{{ r.projection.dailyAvg > 0 ? fmtQty(r.projection.dailyAvg, r.row.unit) + '/天' : '—' }}</div>
        <div class="col-projected">{{ fmtQty(r.projection.projectedTotal, r.row.unit) }}</div>
        <div class="col-cost" :class="{ danger: (r.projection.projectedCost ?? 0) > 0 }">
          {{ fmtMoney(r.projection.projectedCost) }}
        </div>
        <div class="col-exhaust" :class="statusClass(r)">{{ exhaustionText(r) }}</div>
      </summary>
      <div class="detail">
        <div v-if="r.projection.exhaustion.status === 'danger' && r.advice" class="advice">
          💡 {{ r.advice }}
        </div>
        <slot name="detail" :row="r" />
      </div>
    </details>
  </div>
</template>

<style scoped>
.quota-table {
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.head.row,
summary.row {
  display: grid;
  grid-template-columns: minmax(180px, 1.6fr) minmax(170px, 1.4fr) 80px 90px 110px 84px 92px;
  gap: 10px;
  align-items: center;
}
.head.row {
  font-size: 11px;
  color: var(--cfbh-text-2);
  padding: 4px 8px;
  text-transform: uppercase;
  letter-spacing: 0.02em;
}
.row-wrap {
  border-radius: 8px;
  border: 1px solid transparent;
}
.row-wrap[open] {
  border-color: var(--cfbh-border);
  background: var(--cfbh-bg-2);
}
summary.row {
  cursor: pointer;
  padding: 8px;
  border-radius: 8px;
  list-style: none;
}
summary.row::-webkit-details-marker {
  display: none;
}
summary.row:hover {
  background: var(--cfbh-bg-2);
}
.col-name {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}
.dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  flex-shrink: 0;
}
.name-block {
  min-width: 0;
}
.name {
  font-size: 13px;
  font-weight: 500;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.hint {
  font-size: 11px;
  color: var(--cfbh-text-2);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.col-quota {
  display: flex;
  flex-direction: column;
  gap: 3px;
}
.quota-text {
  font-size: 11px;
  color: var(--cfbh-text-2);
  font-variant-numeric: tabular-nums;
}
.col-remaining,
.col-avg,
.col-projected,
.col-cost,
.col-exhaust {
  font-size: 12px;
  font-variant-numeric: tabular-nums;
  color: var(--cfbh-text);
}
.danger {
  color: var(--cfbh-danger);
  font-weight: 500;
}
.warn {
  color: var(--cfbh-warn);
}
.ok {
  color: var(--cfbh-ok);
}
.detail {
  padding: 4px 12px 12px 30px;
}
.advice {
  font-size: 12px;
  color: var(--cfbh-text-2);
  background: var(--cfbh-bg-2);
  border: 1px dashed var(--cfbh-border);
  border-radius: 6px;
  padding: 6px 10px;
  margin-bottom: 6px;
}
@media (max-width: 1100px) {
  .head.row,
  summary.row {
    grid-template-columns: minmax(150px, 1.6fr) minmax(140px, 1.4fr) 70px 80px 100px 76px 88px;
  }
}
</style>
