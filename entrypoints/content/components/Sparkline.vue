<script setup lang="ts">
import { computed } from 'vue';
import { detectAnomalies } from '../../../lib/trend';
import type { TrendPoint } from '../../../lib/trend';
import { formatQty } from '../../../lib/format';

/**
 * 单产品每日用量迷你折线（表格内嵌）：无坐标轴，只表达形状与异动。
 * 数据来自扩展自存的每日快照：累计类产品取差分后的每日用量，水位类（存储等）取每日水平。
 * 基线固定为 0，形状即趋势；悬停用原生 tooltip 给出最近一天的数值。
 */
const props = defineProps<{
  points: TrendPoint[];
  color: string;
  unit: string;
}>();

const W = 96;
const H = 26;
const PAD = 3;
/** 只画最近 N 个记录日，保证可读 */
const MAX_POINTS = 30;
/** 翻倍 / 腰斩才算异动，避免把正常波动标红 */
const ANOMALY_RATIO = 2;

const visible = computed(() => props.points.slice(-MAX_POINTS));

const yMax = computed(() => {
  const m = Math.max(0, ...visible.value.map((p) => p.value));
  return m > 0 ? m : 1;
});

function x(i: number): number {
  return PAD + (i / Math.max(1, visible.value.length - 1)) * (W - PAD * 2);
}

function y(v: number): number {
  return H - PAD - (Math.min(v, yMax.value) / yMax.value) * (H - PAD * 2);
}

const path = computed(() =>
  visible.value
    .map((p, i) => `${i === 0 ? 'M' : 'L'}${x(i).toFixed(1)},${y(p.value).toFixed(1)}`)
    .join(' '),
);

const marks = computed(() =>
  detectAnomalies(visible.value, { ratio: ANOMALY_RATIO })
    .map((a) => {
      const i = visible.value.findIndex((p) => p.date === a.date);
      return i >= 0 ? { key: a.date, cx: x(i), cy: y(a.value) } : null;
    })
    .filter((m): m is { key: string; cx: number; cy: number } => m != null),
);

const title = computed(() => {
  const pts = visible.value;
  if (pts.length === 0) return '';
  const last = pts[pts.length - 1]!;
  let text = `${last.date}：${formatQty(last.value, props.unit)}/天`;
  const list = detectAnomalies(pts, { ratio: ANOMALY_RATIO });
  const a = list[list.length - 1];
  if (a && a.date === last.date) {
    text += Number.isFinite(a.ratio)
      ? `（较近 7 次均值 ${a.ratio >= 1 ? '+' : ''}${Math.round((a.ratio - 1) * 100)}%）`
      : '（此前无数据）';
  }
  return text;
});
</script>

<template>
  <svg v-if="points.length >= 2" :viewBox="`0 0 ${W} ${H}`" class="spark" role="img">
    <title>{{ title }}</title>
    <path
      :d="path"
      fill="none"
      :stroke="color"
      stroke-width="1.5"
      stroke-linejoin="round"
      stroke-linecap="round"
    />
    <circle :cx="x(visible.length - 1)" :cy="y(visible[visible.length - 1]!.value)" r="1.8" :fill="color" />
    <circle v-for="m in marks" :key="m.key" :cx="m.cx" :cy="m.cy" r="2.1" fill="var(--cfbh-danger)" />
  </svg>
  <span v-else class="spark-empty">—</span>
</template>

<style scoped>
.spark {
  width: 100%;
  height: auto;
  display: block;
  overflow: visible;
}
.spark-empty {
  color: var(--cfbh-text-2);
  font-size: 12px;
}
</style>
