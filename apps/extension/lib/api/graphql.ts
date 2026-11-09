/** dash 内部 GraphQL 客户端：content script 与 dash 同源，自动带登录 cookie。 */
import { cacheGet, cacheSet } from '../cache';

const GRAPHQL_URL = 'https://dash.cloudflare.com/api/v4/graphql';

export async function dashGraphql<T>(
  accountId: string,
  query: string,
  variables: Record<string, unknown> = {},
): Promise<T> {
  const res = await fetch(GRAPHQL_URL, {
    method: 'POST',
    credentials: 'include',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      query,
      variables: { accountTag: accountId, ...variables },
    }),
  });
  if (!res.ok) throw new Error(`GraphQL HTTP ${res.status}`);
  const json = (await res.json()) as { data?: T; errors?: { message: string }[] };
  if (json.errors && json.errors.length > 0) {
    throw new Error(json.errors.map((e) => e.message).join('; '));
  }
  if (!json.data) throw new Error('GraphQL 空响应');
  return json.data;
}

/** 依序尝试多个候选查询，返回第一个成功的结果；全部失败抛出聚合错误。 */
export async function tryQueries<T>(
  label: string,
  candidates: { label: string; run: () => Promise<T> }[],
): Promise<T> {
  const errors: string[] = [];
  for (const c of candidates) {
    try {
      return await c.run();
    } catch (e) {
      errors.push(`${c.label}: ${e instanceof Error ? e.message : String(e)}`);
    }
  }
  throw new Error(`[${label}] 所有候选查询失败 → ${errors.join(' | ')}`);
}

/** 日期 → YYYY-MM-DD（UTC，analytics 接口口径）。 */
export function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

/** 账期内的观察窗口 [from, to]：to 不超过昨天（analytics 只有历史数据）。 */
export function observationWindow(cycleStart: Date, cycleEnd: Date): { from: string; to: string } {
  const yesterday = new Date(Date.now() - 86_400_000);
  const to = cycleEnd > yesterday ? yesterday : cycleEnd;
  return { from: isoDate(cycleStart), to: isoDate(to) };
}

/** 带缓存执行拆分查询（TTL 默认 10 分钟）。 */
export async function cachedQuery<T>(key: string, loader: () => Promise<T>, ttlMs = 10 * 60_000): Promise<T> {
  const hit = await cacheGet<T>(key);
  if (hit) return hit;
  const data = await loader();
  await cacheSet(key, data, ttlMs);
  return data;
}
