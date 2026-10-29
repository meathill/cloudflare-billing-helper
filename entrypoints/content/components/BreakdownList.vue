<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue';
import type { BreakdownItem, CycleInfo } from '../../../lib/types';
import type { ProductFamily } from '../../../lib/products';
import { fetchBreakdown } from '../../../lib/api';
import { formatQty } from '../../../lib/format';

const props = defineProps<{
  accountId: string;
  family: ProductFamily;
  metric: string;
  unit: string;
  cycle: CycleInfo | null;
}>();

const items = ref<BreakdownItem[]>([]);
const loading = ref(false);
const error = ref<string | null>(null);

async function load(): Promise<void> {
  loading.value = true;
  error.value = null;
  try {
    const cycle = props.cycle;
    const start = cycle?.cycleStart ?? new Date(Date.now() - 14 * 86_400_000);
    const end = cycle?.cycleEnd ?? new Date();
    items.value = await fetchBreakdown(props.accountId, props.family, props.metric, start, end);
    if (items.value.length === 0) error.value = '__empty__';
  } catch (e) {
    error.value = e instanceof Error ? e.message : String(e);
    items.value = [];
  } finally {
    loading.value = false;
  }
}

onMounted(load);
watch(() => [props.family, props.metric, props.cycle], load);

const maxUsage = computed(() => Math.max(1, ...items.value.map((i) => i.usage)));
</script>

<template>
  <div class="breakdown">
    <div v-if="loading" class="state">加载中…</div>
    <div v-else-if="error === '__empty__'" class="state muted">没有可用数据</div>
    <div v-else-if="error" class="state err" :title="error">
      暂无法获取该维度拆分（字段待校准）
      <span class="err-detail">{{ error }}</span>
    </div>
    <div v-else class="list">
      <div v-for="item in items.slice(0, 15)" :key="item.id" class="item">
        <div class="item-head">
          <span class="item-name" :title="item.name">{{ item.name }}</span>
          <span v-if="item.note" class="item-note">{{ item.note }}</span>
          <span class="item-usage">{{ formatQty(item.usage, unit === 'GB-months' ? 'GB-months' : 'count') }}</span>
        </div>
        <div class="item-track">
          <div
            class="item-fill"
            :style="{ width: `${Math.max(1, (item.usage / maxUsage) * 100)}%` }"
          />
        </div>
      </div>
      <div v-if="items.length > 15" class="more">… 共 {{ items.length }} 项</div>
    </div>
  </div>
</template>

<style scoped>
.breakdown {
  font-size: 12px;
}
.state {
  padding: 8px 0;
  color: var(--cfbh-text-2);
}
.state.err {
  color: var(--cfbh-danger);
}
.err-detail {
  display: block;
  font-size: 10px;
  color: var(--cfbh-text-2);
  word-break: break-all;
  margin-top: 2px;
}
.muted {
  opacity: 0.7;
}
.list {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.item-head {
  display: flex;
  align-items: baseline;
  gap: 8px;
  margin-bottom: 3px;
}
.item-name {
  font-weight: 500;
  max-width: 320px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.item-note {
  color: var(--cfbh-text-2);
  font-size: 11px;
  flex: 1;
}
.item-usage {
  font-variant-numeric: tabular-nums;
}
.item-track {
  height: 4px;
  background: var(--cfbh-track);
  border-radius: 2px;
  overflow: hidden;
}
.item-fill {
  height: 100%;
  background: var(--cfbh-accent);
  border-radius: 2px;
}
.more {
  color: var(--cfbh-text-2);
  font-size: 11px;
}
</style>
