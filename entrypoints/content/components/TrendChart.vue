<script setup lang="ts">
import { computed, ref } from 'vue';
import type { TrendPoint } from '../../../lib/trend';

/**
 * 通用趋势折线图（SVG 手绘，无图表库依赖）：
 * - 多系列折线，X 轴为所有系列日期的并集（按日期定位，开关图例不会让曲线横跳）
 * - 按 seg（账期）分段绘制：跨账期不连线，避免把两段曲线连成一条误导的斜线
 * - hover 显示竖线 + 浮动框（日期 + 各系列当日值）
 * - 异动点红点标记（由父组件计算传入）
 * - 图例可点击开关系列
 */
export interface TrendSeries {
  name: string;
  color: string;
  points: TrendPoint[];
}

export interface TrendAnomaly {
  /** 对应 props.series 的下标 */
  seriesIndex: number;
  date: string;
  /** value / baseline，Infinity 表示从 0 突增 */
  ratio: number;
}

const props = defineProps<{
  series: TrendSeries[];
  /** Y 轴与浮框的数值格式化（$、% 等由调用方决定） */
  yFormat: (v: number) => string;
  anomalies?: TrendAnomaly[];
}>();

const W = 560;
const H = 150;
const PAD_L = 46;
const PAD_B = 18;
const PAD_T = 8;

const hidden = ref<Set<string>>(new Set());

const visibleSeries = computed(() => props.series.filter((s) => !hidden.value.has(s.name)));

/** 所有系列日期的并集（含被隐藏的系列，保证开关图例时 X 坐标稳定） */
const dates = computed(() => {
  const set = new Set<string>();
  for (const s of props.series) for (const p of s.points) set.add(p.date);
  return [...set].sort();
});

function xOf(date: string): number {
  const i = dates.value.indexOf(date);
  if (i < 0) return PAD_L;
  return PAD_L + (i / Math.max(1, dates.value.length - 1)) * (W - PAD_L - 8);
}

const yMax = computed(() => {
  const all = visibleSeries.value.flatMap((s) => s.points.map((p) => p.value));
  const m = Math.max(0, ...all);
  return m > 0 ? m * 1.1 : 1;
});

function y(v: number): number {
  const usable = H - PAD_B - PAD_T;
  return PAD_T + usable - (Math.min(v, yMax.value) / yMax.value) * usable;
}

/** 按 seg 分段（连续同组为一段），跨段各自成一条路径 */
function segmentsOf(points: TrendPoint[]): TrendPoint[][] {
  const segs: TrendPoint[][] = [];
  for (const p of points) {
    const last = segs[segs.length - 1];
    if (!last || (last[0]?.seg ?? undefined) !== (p.seg ?? undefined)) {
      segs.push([p]);
    } else {
      last.push(p);
    }
  }
  return segs;
}

const visibleSegments = computed(() =>
  visibleSeries.value.map((s) => ({ name: s.name, color: s.color, segs: segmentsOf(s.points) })),
);

function pathOf(points: TrendPoint[]): string {
  return points.map((p, i) => `${i === 0 ? 'M' : 'L'}${xOf(p.date).toFixed(1)},${y(p.value).toFixed(1)}`).join(' ');
}

const yTicks = computed(() => {
  const ticks: { v: number; y: number }[] = [];
  for (let k = 0; k <= 4; k++) {
    const v = (yMax.value * k) / 4;
    ticks.push({ v, y: y(v) });
  }
  return ticks;
});

const xLabels = computed(() => {
  const step = Math.max(1, Math.ceil(dates.value.length / 8));
  return dates.value
    .map((d, i) => ({ i, label: d.slice(5), x: xOf(d) }))
    .filter((l) => l.i % step === 0 || l.i === dates.value.length - 1);
});

// hover：竖线 + 浮框
const hover = ref<{ date: string; px: number } | null>(null);

function onMove(e: MouseEvent): void {
  const svg = e.currentTarget as SVGElement;
  const rect = svg.getBoundingClientRect();
  if (rect.width === 0 || dates.value.length === 0) return;
  const vx = ((e.clientX - rect.left) / rect.width) * W;
  let best = 0;
  let bestDist = Infinity;
  for (let i = 0; i < dates.value.length; i++) {
    const d = Math.abs(xOf(dates.value[i]!) - vx);
    if (d < bestDist) {
      bestDist = d;
      best = i;
    }
  }
  const date = dates.value[best]!;
  hover.value = { date, px: xOf(date) };
}

const hoverRows = computed(() => {
  if (!hover.value) return [];
  return visibleSeries.value
    .map((s) => {
      const p = s.points.find((p2) => p2.date === hover.value!.date);
      return p ? { name: s.name, color: s.color, value: p.value } : null;
    })
    .filter((r): r is { name: string; color: string; value: number } => r != null);
});

/** 浮框水平位置（clamp 避免溢出图表） */
const tipLeft = computed(() => {
  const px = Math.min(Math.max(hover.value?.px ?? 0, 70), W - 70);
  return `${(px / W) * 100}%`;
});

// 异动点标记
const marks = computed(() => {
  if (!props.anomalies) return [];
  return props.anomalies.flatMap((a) => {
    const s = props.series[a.seriesIndex];
    if (!s || hidden.value.has(s.name)) return [];
    const p = s.points.find((p2) => p2.date === a.date);
    if (!p) return [];
    return {
      cx: xOf(a.date),
      cy: y(p.value),
      color: s.color,
      name: s.name,
      date: a.date,
      ratio: a.ratio,
    };
  });
});

function toggle(name: string): void {
  const next = new Set(hidden.value);
  if (next.has(name)) next.delete(name);
  else next.add(name);
  hidden.value = next;
}

function markTitle(m: { name: string; date: string; ratio: number }): string {
  if (!Number.isFinite(m.ratio)) return `${m.name} ${m.date}：从 0 突增`;
  const pct = Math.round((m.ratio - 1) * 100);
  return `${m.name} ${m.date}：${pct > 0 ? '+' : ''}${pct}%`;
}
</script>

<template>
  <div class="trend-wrap">
    <svg :viewBox="`0 0 ${W} ${H}`" class="trend" @mousemove="onMove" @mouseleave="hover = null">
      <g v-for="tick in yTicks" :key="tick.v">
        <line :x1="PAD_L" :y1="tick.y" :x2="W - 8" :y2="tick.y" stroke="var(--cfbh-track)" stroke-width="1" />
        <text :x="PAD_L - 5" :y="tick.y + 3" text-anchor="end" class="tick-label">
          {{ yFormat(tick.v) }}
        </text>
      </g>
      <line
        v-if="hover"
        :x1="hover.px"
        :y1="PAD_T"
        :x2="hover.px"
        :y2="H - PAD_B"
        stroke="var(--cfbh-text-2)"
        stroke-width="1"
        stroke-dasharray="3 3"
      />
      <g>
        <template v-for="s in visibleSegments" :key="s.name">
          <path
            v-for="(g, gi) in s.segs"
            :key="`${s.name}-${gi}`"
            :d="pathOf(g)"
            fill="none"
            :stroke="s.color"
            stroke-width="1.8"
            stroke-linejoin="round"
            stroke-linecap="round"
          />
          <!-- 单点分段画不出线，补一个圆点 -->
          <circle
            v-for="(g, gi) in s.segs.filter((x) => x.length === 1)"
            :key="`${s.name}-dot-${gi}`"
            :cx="xOf(g[0]!.date)"
            :cy="y(g[0]!.value)"
            r="2.5"
            :fill="s.color"
          />
        </template>
      </g>
      <g v-for="m in marks" :key="`${m.name}-${m.date}`">
        <circle :cx="m.cx" :cy="m.cy" r="3.5" fill="var(--cfbh-danger)" stroke="var(--cfbh-bg)" stroke-width="1">
          <title>{{ markTitle(m) }}</title>
        </circle>
      </g>
      <g v-for="l in xLabels" :key="l.i">
        <text :x="l.x" :y="H - 4" text-anchor="middle" class="tick-label">{{ l.label }}</text>
      </g>
    </svg>
    <div v-if="hover && hoverRows.length > 0" class="tip" :style="{ left: tipLeft }">
      <div class="tip-date">{{ hover.date }}</div>
      <div v-for="r in hoverRows" :key="r.name" class="tip-row">
        <span class="dot" :style="{ background: r.color }" />
        <span class="tip-name">{{ r.name }}</span>
        <span class="tip-val">{{ yFormat(r.value) }}</span>
      </div>
    </div>
    <div v-if="series.length > 1" class="legend">
      <button
        v-for="s in series"
        :key="s.name"
        class="legend-item"
        :class="{ off: hidden.has(s.name) }"
        type="button"
        @click="toggle(s.name)"
      >
        <span class="dot" :style="{ background: s.color }" />{{ s.name }}
      </button>
    </div>
  </div>
</template>

<style scoped>
.trend-wrap {
  position: relative;
}
.trend {
  width: 100%;
  height: auto;
  display: block;
}
.tick-label {
  font-size: 9px;
  fill: var(--cfbh-text-2);
}
.tip {
  position: absolute;
  top: 0;
  transform: translateX(-50%);
  background: var(--cfbh-bg);
  border: 1px solid var(--cfbh-border);
  border-radius: 6px;
  box-shadow: 0 2px 8px rgb(0 0 0 / 12%);
  padding: 5px 8px;
  font-size: 11px;
  pointer-events: none;
  white-space: nowrap;
  z-index: 2;
}
.tip-date {
  color: var(--cfbh-text-2);
  margin-bottom: 2px;
}
.tip-row {
  display: flex;
  align-items: center;
  gap: 5px;
  line-height: 1.6;
}
.tip-name {
  max-width: 170px;
  overflow: hidden;
  text-overflow: ellipsis;
}
.tip-val {
  margin-left: auto;
  font-variant-numeric: tabular-nums;
  font-weight: 600;
}
.legend {
  display: flex;
  flex-wrap: wrap;
  gap: 4px 10px;
  font-size: 11px;
  color: var(--cfbh-text-2);
  margin-top: 4px;
}
.legend-item {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  max-width: 200px;
  border: none;
  background: none;
  padding: 0;
  font: inherit;
  color: inherit;
  cursor: pointer;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.legend-item.off {
  opacity: 0.4;
  text-decoration: line-through;
}
.dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  flex-shrink: 0;
}
</style>
