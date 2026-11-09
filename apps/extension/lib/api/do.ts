/**
 * Durable Objects 族拆分：请求、计算时长、存储与行读写。
 * DO 的 GraphQL 数据集字段名未见完整公开文档，这里按候选查询依序尝试，全部失败时上层降级。
 */
import type { BreakdownItem } from '../types';
import { cachedQuery, dashGraphql, observationWindow, tryQueries } from './graphql';

const REQUESTS_CANDIDATES = [
  /* GraphQL */ `
    query CfbhDoReq($accountTag: string!, $from: Date!, $to: Date!) {
      viewer {
        accounts(filter: { accountTag: $accountTag }) {
          groups: durableObjectsRequestsAdaptiveGroups(filter: { date_geq: $from, date_leq: $to }, limit: 10000) {
            dimensions { scriptName }
            sum { requests }
          }
        }
      }
    }
  `,
];

const STORAGE_CANDIDATES = [
  /* GraphQL */ `
    query CfbhDoStorage($accountTag: string!, $from: Date!, $to: Date!) {
      viewer {
        accounts(filter: { accountTag: $accountTag }) {
          groups: durableObjectsStorageAdaptiveGroups(filter: { date_geq: $from, date_leq: $to }, limit: 10000) {
            dimensions { namespaceId }
            max { storageBytes }
          }
        }
      }
    }
  `,
];

interface GroupsResponse<T> {
  viewer: { accounts: { groups: T[] }[] };
}

export interface DoBreakdown {
  requests: { name: string; requests: number }[];
  storage: { name: string; gb: number }[];
}

export async function getDoBreakdown(
  accountId: string,
  cycleStart: Date,
  cycleEnd: Date,
): Promise<DoBreakdown> {
  const { from, to } = observationWindow(cycleStart, cycleEnd);
  return cachedQuery(`do:${accountId}:${from}:${to}`, async () => {
    const [requests, storage] = await Promise.all([
      tryQueries<{ name: string; requests: number }[]>('DO requests', REQUESTS_CANDIDATES.map((q) => ({
        label: 'requests',
        run: async () => {
          const data = await dashGraphql<GroupsResponse<{ dimensions: { scriptName: string }; sum: { requests: number } }>>(
            accountId, q, { from, to },
          );
          return (data.viewer.accounts[0]?.groups ?? [])
            .map((g) => ({ name: g.dimensions.scriptName, requests: g.sum.requests ?? 0 }))
            .sort((a, b) => b.requests - a.requests);
        },
      }))).catch(() => [] as { name: string; requests: number }[]),
      tryQueries<{ name: string; gb: number }[]>('DO storage', STORAGE_CANDIDATES.map((q) => ({
        label: 'storage',
        run: async () => {
          const data = await dashGraphql<GroupsResponse<{ dimensions: { namespaceId: string }; max: { storageBytes: number } }>>(
            accountId, q, { from, to },
          );
          return (data.viewer.accounts[0]?.groups ?? [])
            .map((g) => ({ name: g.dimensions.namespaceId, gb: (g.max.storageBytes ?? 0) / 1e9 }))
            .sort((a, b) => b.gb - a.gb);
        },
      }))).catch(() => [] as { name: string; gb: number }[]),
    ]);
    return { requests, storage };
  });
}

export async function doMetric(
  accountId: string,
  cycleStart: Date,
  cycleEnd: Date,
  metric: string,
): Promise<BreakdownItem[]> {
  const b = await getDoBreakdown(accountId, cycleStart, cycleEnd);
  if (metric === 'requests') {
    return b.requests.map((r) => ({ id: r.name, name: r.name, usage: r.requests }));
  }
  if (metric === 'sqlStorage' || metric === 'storage') {
    return b.storage.map((s) => ({ id: s.name, name: s.name, usage: s.gb, note: '按当前水位估算' }));
  }
  // duration / rowsRead / rowsWritten 暂无可靠数据集，返回空由上层提示
  return [];
}
