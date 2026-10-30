/** chrome.storage 封装：session 缓存 + local 快照。所有键带 cfbh: 前缀。 */
import { localDateISO } from './format';

const PREFIX = 'cfbh:';

export async function cacheGet<T>(key: string): Promise<T | null> {
  const full = `${PREFIX}cache:${key}`;
  try {
    const raw = await chrome.storage.session.get(full);
    const hit = raw[full] as { t: number; ttl?: number; data: T } | undefined;
    const ttl = hit?.ttl ?? 60 * 60_000;
    if (hit && Date.now() - hit.t < ttl) return hit.data;
  } catch {
    // storage 不可用时静默降级为无缓存
  }
  return null;
}

export async function cacheSet<T>(key: string, data: T, ttlMs: number): Promise<void> {
  const full = `${PREFIX}cache:${key}`;
  try {
    await chrome.storage.session.set({ [full]: { t: Date.now(), ttl: ttlMs, data } });
  } catch {
    // 忽略（如超过配额）
  }
}

/**
 * 每日快照：accountId → cycleStart → dayISO → productId → { u, c }。
 * - u：累计用量（cycle-to-date）
 * - c：累计费用（USD，cycle-to-date）
 * 历史版本直接存 number（当时只有用量），读取时按 u 兼容。
 */
const SNAP_KEY = (accountId: string) => `${PREFIX}snapshots:${accountId}`;

export interface SnapshotValue {
  u?: number;
  c?: number;
}

type SnapshotStore = Record<string, Record<string, Record<string, SnapshotValue>>>;

/**
 * 快照体积上限：超过后从最老账期开始裁剪。约 30 产品 × 2 维度 × 一年
 * ≈ 300–500KB，4MB 上限在 chrome.storage.local 默认 10MB 配额下留足余量。
 */
export const SNAP_MAX_BYTES = 4 * 1024 * 1024;

/**
 * 账期分组键：账期起始日本地零点 → UTC 日期。
 * 非零时区（UTC+8）会退一天，键与自然日不一致，所以写与读必须走这对函数。
 */
export function cycleKeyOf(cycleStart: Date): string {
  return cycleStart.toISOString().slice(0, 10);
}

/**
 * 反解账期真实起始日（cycleKeyOf 的逆运算）。
 * 候选日 D 需满足 D.toISOString().slice(0,10) === key，据此回代求解；
 * 无法确定时返回 null（调用方退回"丢弃首点"的保守行为）。
 */
export function resolveCycleStartDate(cycleKey: string): string | null {
  const base = new Date(`${cycleKey}T00:00:00`);
  if (Number.isNaN(base.getTime())) return null;
  for (let delta = -2; delta <= 2; delta++) {
    const d = new Date(base);
    d.setDate(d.getDate() + delta);
    if (d.toISOString().slice(0, 10) === cycleKey) return localDateISO(d);
  }
  return null;
}

/** 体积保护：序列化超过 maxBytes 时从最老账期开始删除，直到放下（或删空）。 */
export function pruneStore(store: SnapshotStore, maxBytes: number): SnapshotStore {
  let json = JSON.stringify(store);
  while (json.length > maxBytes) {
    const oldest = Object.keys(store).sort()[0];
    if (!oldest) break;
    delete store[oldest];
    json = JSON.stringify(store);
  }
  return store;
}

/**
 * 合并写入某天的快照，返回写入后的完整 store（便于调用方一次读盘、多处派生）。
 * 保留全部账期；仅在体积超过上限时裁剪最老的账期。
 */
export async function recordSnapshot(
  accountId: string,
  cycleStartISO: string,
  dayISO: string,
  values: Record<string, SnapshotValue>,
): Promise<SnapshotStore> {
  try {
    const key = SNAP_KEY(accountId);
    const raw = await chrome.storage.local.get(key);
    const store: SnapshotStore = (raw[key] as SnapshotStore | undefined) ?? {};
    const cycle = (store[cycleStartISO] ??= {});
    const day = (cycle[dayISO] ??= {});
    Object.assign(day, values);
    pruneStore(store, SNAP_MAX_BYTES);
    await chrome.storage.local.set({ [key]: store });
    return store;
  } catch {
    return {};
  }
}

/** 读取单维度的值；历史 number 值视为用量（u）。 */
function readValue(v: SnapshotValue | number | undefined, kind: 'u' | 'c'): number | undefined {
  if (v == null) return undefined;
  if (typeof v === 'number') return kind === 'u' ? v : undefined;
  const value = v[kind];
  return Number.isFinite(value) ? value : undefined;
}

/** 一次读盘取回整个快照 store，便于页面内多处派生（避免按产品重复读盘）。 */
export async function getSnapshotStore(accountId: string): Promise<SnapshotStore> {
  try {
    const raw = await chrome.storage.local.get(SNAP_KEY(accountId));
    return (raw[SNAP_KEY(accountId)] as SnapshotStore | undefined) ?? {};
  } catch {
    return {};
  }
}

/** 从 store 派生某产品某维度的单账期日序列（纯函数）。 */
export function seriesFromStore(
  store: SnapshotStore,
  cycleStartISO: string,
  productId: string,
  kind: 'u' | 'c' = 'u',
): { date: string; value: number }[] {
  const cycle = store[cycleStartISO];
  if (!cycle) return [];
  return Object.entries(cycle)
    .map(([date, values]) => ({ date, value: readValue(values[productId], kind) }))
    .filter((p): p is { date: string; value: number } => p.value != null)
    .sort((a, b) => a.date.localeCompare(b.date));
}

/** 从 store 派生某产品跨账期的日序列（按账期分组，纯函数）。 */
export function allSeriesFromStore(
  store: SnapshotStore,
  productId: string,
  kind: 'u' | 'c' = 'u',
): Record<string, { date: string; value: number }[]> {
  const out: Record<string, { date: string; value: number }[]> = {};
  for (const cycleStart of Object.keys(store).sort()) {
    const list = seriesFromStore(store, cycleStart, productId, kind);
    if (list.length > 0) out[cycleStart] = list;
  }
  return out;
}

export async function getSnapshotSeries(
  accountId: string,
  cycleStartISO: string,
  productId: string,
  kind: 'u' | 'c' = 'u',
): Promise<{ date: string; value: number }[]> {
  try {
    return seriesFromStore(await getSnapshotStore(accountId), cycleStartISO, productId, kind);
  } catch {
    return [];
  }
}

/**
 * 跨账期序列：productId 在所有账期的每日序列，按账期分组返回（cycleStart 升序）。
 * 分组的意义：累计值在账期切换时清零，差分必须按账期内进行，不能跨组相减。
 */
export async function getAllSnapshotSeries(
  accountId: string,
  productId: string,
  kind: 'u' | 'c' = 'u',
): Promise<Record<string, { date: string; value: number }[]>> {
  try {
    return allSeriesFromStore(await getSnapshotStore(accountId), productId, kind);
  } catch {
    return {};
  }
}
