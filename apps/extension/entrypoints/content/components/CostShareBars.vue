<script setup lang="ts">
import { computed } from 'vue';
import { formatMoney } from '../../../lib/format';

const props = defineProps<{
  items: { name: string; cost: number; color: string }[];
}>();

const total = computed(() => props.items.reduce((s, i) => s + i.cost, 0));
const max = computed(() => Math.max(0.0001, ...props.items.map((i) => i.cost)));
const sorted = computed(() => [...props.items].sort((a, b) => b.cost - a.cost));
</script>

<template>
  <div class="cost-share">
    <div v-for="item in sorted" :key="item.name" class="item">
      <span class="dot" :style="{ background: item.color }" />
      <span class="name" :title="item.name">{{ item.name }}</span>
      <div class="track">
        <div class="fill" :style="{ width: `${(item.cost / max) * 100}%`, background: item.color }" />
      </div>
      <span class="cost">{{ formatMoney(item.cost) }}</span>
      <span class="pct">{{ total > 0 ? `${Math.round((item.cost / total) * 100)}%` : '—' }}</span>
    </div>
  </div>
</template>

<style scoped>
.cost-share {
  display: flex;
  flex-direction: column;
  gap: 6px;
  font-size: 12px;
}
.item {
  display: grid;
  grid-template-columns: 10px minmax(140px, 1.2fr) 2fr 64px 40px;
  gap: 8px;
  align-items: center;
}
.dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
}
.name {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.track {
  height: 8px;
  background: var(--cfbh-track);
  border-radius: 4px;
  overflow: hidden;
}
.fill {
  height: 100%;
  border-radius: 4px;
}
.cost {
  font-variant-numeric: tabular-nums;
  text-align: right;
}
.pct {
  color: var(--cfbh-text-2);
  font-variant-numeric: tabular-nums;
  text-align: right;
}
</style>
