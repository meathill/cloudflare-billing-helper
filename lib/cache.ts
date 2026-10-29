/** chrome.storage 封装：session 缓存 + local 快照。所有键带 cfbh: 前缀。 */

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

/** 每日快照：accountId → cycleStart → dayISO → productId → usage。 */
const SNAP_KEY = (accountId: string) => `${PREFIX}snapshots:${accountId}`;

type SnapshotStore = Record<string, Record<string, Record<string, number>>>;

export async function recordSnapshot(
  accountId: string,
  cycleStartISO: string,
  dayISO: string,
  values: Record<string, number>,
): Promise<void> {
  try {
    const raw = await chrome.storage.local.get(SNAP_KEY(accountId));
    const store: SnapshotStore = (raw[SNAP_KEY(accountId)] as SnapshotStore | undefined) ?? {};
    const cycle = (store[cycleStartISO] ??= {});
    const day = (cycle[dayISO] ??= {});
    Object.assign(day, values);
    // 只保留最近 3 个账期
    const keys = Object.keys(store).sort();
    while (keys.length > 3) {
      const oldest = keys.shift();
      if (oldest) delete store[oldest];
    }
    await chrome.storage.local.set({ [SNAP_KEY(accountId)]: store });
  } catch {
    // ignore
  }
}

export async function getSnapshotSeries(
  accountId: string,
  cycleStartISO: string,
  productId: string,
): Promise<{ date: string; value: number }[]> {
  try {
    const raw = await chrome.storage.local.get(SNAP_KEY(accountId));
    const store: SnapshotStore = (raw[SNAP_KEY(accountId)] as SnapshotStore | undefined) ?? {};
    const cycle = store[cycleStartISO];
    if (!cycle) return [];
    return Object.entries(cycle)
      .map(([date, values]) => ({ date, value: values[productId] }))
      .filter((p) => p.value != null)
      .sort((a, b) => a.date.localeCompare(b.date));
  } catch {
    return [];
  }
}
