<script setup lang="ts">
import { computed } from 'vue';
import { formatPct } from '../../../lib/format';

const props = defineProps<{
  pct: number | undefined;
  color: string;
}>();

const clamped = computed(() => {
  if (props.pct == null || !Number.isFinite(props.pct)) return 0;
  return Math.min(100, Math.max(0, props.pct * 100));
});

const over = computed(() => props.pct != null && props.pct > 1);

const statusColor = computed(() => {
  if (over.value) return 'var(--cfbh-danger)';
  if (props.pct != null && props.pct >= 0.7) return 'var(--cfbh-warn)';
  return props.color || 'var(--cfbh-ok)';
});
</script>

<template>
  <div class="bar-wrap" :title="over ? '已超出免费额度' : undefined">
    <div class="bar-track">
      <div
        class="bar-fill"
        :style="{ width: `${clamped}%`, background: statusColor }"
      />
      <div
        v-if="over"
        class="bar-overflow"
        :style="{ left: '100%' }"
      />
    </div>
    <span class="bar-label" :style="{ color: over ? 'var(--cfbh-danger)' : undefined }">
      {{ formatPct(props.pct) }}
    </span>
  </div>
</template>

<style scoped>
.bar-wrap {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 140px;
}
.bar-track {
  position: relative;
  flex: 1;
  height: 6px;
  border-radius: 3px;
  background: var(--cfbh-track);
  overflow: hidden;
}
.bar-fill {
  height: 100%;
  border-radius: 3px;
  transition: width 0.3s ease;
}
.bar-overflow {
  position: absolute;
  top: 0;
  width: 2px;
  height: 100%;
  background: var(--cfbh-danger);
}
.bar-label {
  font-size: 11px;
  font-variant-numeric: tabular-nums;
  min-width: 34px;
  text-align: right;
  color: var(--cfbh-text-2);
}
</style>
