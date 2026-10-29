<script setup lang="ts">
import { computed } from 'vue';

/**
 * 额度消耗趋势：每产品「已用/免费额度」百分比随日期的折线（来自扩展自存的每日快照）。
 * SVG 手绘：X = 快照日序号，Y = 0 至最大百分比。
 */
const props = defineProps<{
  series: { name: string; color: string; points: { date: string; pct: number }[] }[];
}>();

const W = 560;
const H = 140;
const PAD_L = 30;
const PAD_B = 18;
const PAD_T = 6;

const maxLen = computed(() => Math.max(0, ...props.series.map((s) => s.points.length)));
const yMax = computed(() => {
  const all = props.series.flatMap((s) => s.points.map((p) => p.pct));
  const m = Math.max(0.1, ...all);
  return Math.ceil(m * 1.1 * 10) / 10;
});

function x(i: number): number {
  const n = Math.max(1, maxLen.value - 1);
  return PAD_L + (i / n) * (W - PAD_L - 6);
}

function y(pct: number): number {
  const usable = H - PAD_B - PAD_T;
  return PAD_T + usable - (Math.min(pct, yMax.value) / yMax.value) * usable;
}

function pathOf(points: { pct: number }[]): string {
  return points.map((p, i) => `${i === 0 ? 'M' : 'L'}${x(i).toFixed(1)},${y(p.pct).toFixed(1)}`).join(' ');
}

const yTicks = computed(() => {
  const ticks: { v: number; y: number }[] = [];
  const step = yMax.value <= 1 ? 0.25 : yMax.value / 4;
  for (let v = 0; v <= yMax.value + 1e-9; v += step) {
    ticks.push({ v, y: y(v) });
  }
  return ticks;
});

const labels = computed(() => {
  const s = props.series.find((s2) => s2.points.length > 0);
  if (!s) return [];
  return s.points.map((p, i) => ({ i, label: p.date.slice(5), x: x(i) }));
});
</script>

<template>
  <svg :viewBox="`0 0 ${W} ${H}`" class="trend">
    <g v-for="tick in yTicks" :key="tick.v">
      <line
        :x1="PAD_L"
        :y1="tick.y"
        :x2="W - 6"
        :y2="tick.y"
        stroke="var(--cfbh-track)"
        stroke-width="1"
      />
      <text :x="PAD_L - 4" :y="tick.y + 3" text-anchor="end" class="tick-label">
        {{ Math.round(tick.v * 100) }}%
      </text>
    </g>
    <g>
      <path
        v-for="(s, idx) in series"
        :key="idx"
        :d="pathOf(s.points)"
        fill="none"
        :stroke="s.color"
        stroke-width="1.8"
        stroke-linejoin="round"
        stroke-linecap="round"
      />
    </g>
    <g v-for="l in labels" :key="l.i">
      <text v-if="l.i % Math.ceil(maxLen / 8) === 0 || l.i === maxLen - 1" :x="l.x" :y="H - 4" text-anchor="middle" class="tick-label">
        {{ l.label }}
      </text>
    </g>
  </svg>
  <div class="legend">
    <span v-for="(s, idx) in series" :key="idx" class="legend-item">
      <span class="dot" :style="{ background: s.color }" />{{ s.name }}
    </span>
  </div>
</template>

<style scoped>
.trend {
  width: 100%;
  height: auto;
}
.tick-label {
  font-size: 9px;
  fill: var(--cfbh-text-2);
}
.legend {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  font-size: 11px;
  color: var(--cfbh-text-2);
  margin-top: 4px;
}
.legend-item {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  max-width: 200px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  flex-shrink: 0;
}
</style>
