/** KV 族拆分：namespace 列表、每 namespace 存储量与操作量。 */
import type { BreakdownItem } from '../types';
import { cachedQuery, dashGraphql, observationWindow } from './graphql';

interface Namespace {
  id: string;
  title: string;
}

const DASH_ORIGIN = 'https://dash.cloudflare.com';

/** 列出账号下全部 KV namespace（REST，同源带 cookie）。 */
export async function listKvNamespaces(accountId: string): Promise<Namespace[]> {
  const result: Namespace[] = [];
  for (let page = 1; page <= 20; page++) {
    const res = await fetch(
      `${DASH_ORIGIN}/api/v4/accounts/${accountId}/storage/kv/namespaces?page=${page}&per_page=100`,
      { credentials: 'include' },
    );
    if (!res.ok) throw new Error(`KV namespaces HTTP ${res.status}`);
    const json = (await res.json()) as { result: Namespace[] | null };
    const list = json.result ?? [];
    result.push(...list);
    if (list.length < 100) break;
  }
  return result;
}

const STORAGE_QUERY = /* GraphQL */ `
  query CfbhKvStorage($accountTag: string!, $from: Date!, $to: Date!, $namespaceId: string) {
    viewer {
      accounts(filter: { accountTag: $accountTag }) {
        storage: kvStorageAdaptiveGroups(
          filter: { date_geq: $from, date_leq: $to, namespaceId: $namespaceId }
          limit: 10000
        ) {
          dimensions {
            date
          }
          max {
            byteCount
            keyCount
          }
        }
      }
    }
  }
`;

const OPS_QUERY = /* GraphQL */ `
  query CfbhKvOps($accountTag: string!, $from: Date!, $to: Date!, $namespaceId: string) {
    viewer {
      accounts(filter: { accountTag: $accountTag }) {
        ops: kvOperationsAdaptiveGroups(
          filter: { date_geq: $from, date_leq: $to, namespaceId: $namespaceId }
          limit: 10000
        ) {
          dimensions {
            actionType
          }
          sum {
            requests
          }
        }
      }
    }
  }
`;

interface StorageResponse {
  viewer: { accounts: { storage: { dimensions: { date: string }; max: { byteCount: number; keyCount: number } }[] }[] };
}

interface OpsResponse {
  viewer: { accounts: { ops: { dimensions: { actionType: string }; sum: { requests: number } }[] }[] };
}

/** 并发映射（保持顺序）。 */
async function mapLimit<T, R>(items: T[], limit: number, fn: (item: T, index: number) => Promise<R>): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let next = 0;
  async function worker() {
    while (next < items.length) {
      const i = next++;
      results[i] = await fn(items[i], i);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return results;
}

function bytesToGbMonths(dailyBytes: number[]): number {
  if (dailyBytes.length === 0) return 0;
  const avg = dailyBytes.reduce((a, b) => a + b, 0) / dailyBytes.length;
  return avg / 1e9;
}

export interface KvBreakdown {
  namespaces: { id: string; title: string; gbMonths: number; currentGb: number; keyCount: number; ops: Record<string, number> }[];
}

/** 每 namespace 的 GB-months（日均字节估算）+ 各类操作量。任一 namespace 查询失败时该项降级为 0。 */
export async function getKvBreakdown(
  accountId: string,
  cycleStart: Date,
  cycleEnd: Date,
): Promise<KvBreakdown> {
  const { from, to } = observationWindow(cycleStart, cycleEnd);
  const key = `kv:${accountId}:${from}:${to}`;
  return cachedQuery(key, async () => {
    const namespaces = await listKvNamespaces(accountId);
    const detailed = await mapLimit(namespaces, 3, async (ns) => {
      const [storage, ops] = await Promise.all([
        dashGraphql<StorageResponse>(accountId, STORAGE_QUERY, { from, to, namespaceId: ns.id })
          .then((d) => d.viewer.accounts[0]?.storage ?? [])
          .catch(() => []),
        dashGraphql<OpsResponse>(accountId, OPS_QUERY, { from, to, namespaceId: ns.id })
          .then((d) => d.viewer.accounts[0]?.ops ?? [])
          .catch(() => []),
      ]);
      const last = storage.length > 0 ? storage[storage.length - 1] : null;
      const opsMap: Record<string, number> = {};
      for (const o of ops) {
        const action = (o.dimensions.actionType ?? 'unknown').toLowerCase();
        opsMap[action] = (opsMap[action] ?? 0) + (o.sum.requests ?? 0);
      }
      return {
        id: ns.id,
        title: ns.title,
        gbMonths: bytesToGbMonths(storage.map((s) => s.max.byteCount ?? 0)),
        currentGb: last ? (last.max.byteCount ?? 0) / 1e9 : 0,
        keyCount: last?.max.keyCount ?? 0,
        ops: opsMap,
      };
    });
    return { namespaces: detailed.sort((a, b) => b.gbMonths - a.gbMonths) };
  });
}

const ACTION_ALIASES: Record<string, string[]> = {
  read: ['read', 'reads', 'get'],
  write: ['write', 'writes', 'put'],
  delete: ['delete', 'deletes'],
  list: ['list', 'lists'],
};

/** 按指标取拆分列表：storage / read / write / delete / list。 */
export async function kvMetric(
  accountId: string,
  cycleStart: Date,
  cycleEnd: Date,
  metric: string,
): Promise<BreakdownItem[]> {
  const b = await getKvBreakdown(accountId, cycleStart, cycleEnd);
  if (metric === 'storage') {
    return b.namespaces.map((n) => ({
      id: n.id,
      name: n.title,
      usage: n.gbMonths,
      note: `当前 ${n.currentGb.toFixed(2)} GB · ${n.keyCount} keys`,
    }));
  }
  const aliases = ACTION_ALIASES[metric] ?? [metric];
  return b.namespaces
    .map((n) => {
      const total = aliases.reduce((sum, a) => sum + (n.ops[a] ?? 0), 0);
      return { id: n.id, name: n.title, usage: total, note: metricLabel(metric) };
    })
    .filter((i) => i.usage > 0)
    .sort((a, b2) => b2.usage - a.usage);
}

function metricLabel(metric: string): string {
  switch (metric) {
    case 'read': return '读操作';
    case 'write': return '写操作';
    case 'delete': return '删除操作';
    case 'list': return '列操作';
    default: return metric;
  }
}
