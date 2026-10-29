/** R2 族拆分：每 bucket 存储量与 Class A/B 操作量。 */
import type { BreakdownItem } from '../types';
import { cachedQuery, dashGraphql, observationWindow } from './graphql';

const STORAGE_QUERY = /* GraphQL */ `
  query CfbhR2Storage($accountTag: string!, $from: Date!, $to: Date!) {
    viewer {
      accounts(filter: { accountTag: $accountTag }) {
        storage: r2StorageAdaptiveGroups(
          filter: { date_geq: $from, date_leq: $to }
          limit: 10000
        ) {
          dimensions {
            bucketName
          }
          max {
            payloadSize
            metadataSize
            objectCount
          }
        }
      }
    }
  }
`;

const OPS_QUERY = /* GraphQL */ `
  query CfbhR2Ops($accountTag: string!, $from: Date!, $to: Date!) {
    viewer {
      accounts(filter: { accountTag: $accountTag }) {
        ops: r2OperationsAdaptiveGroups(
          filter: { date_geq: $from, date_leq: $to }
          limit: 10000
        ) {
          dimensions {
            bucketName
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
  viewer: {
    accounts: {
      storage: {
        dimensions: { bucketName: string };
        max: { payloadSize: number; metadataSize: number; objectCount: number };
      }[];
    }[];
  };
}

interface OpsResponse {
  viewer: {
    accounts: {
      ops: { dimensions: { bucketName: string; actionType: string }; sum: { requests: number } }[];
    }[];
  };
}

export interface R2Breakdown {
  buckets: { name: string; gbMonths: number; objects: number; classA: number; classB: number }[];
}

/**
 * 每 bucket：GB-months ≈ 账期内日均 (payload+metadata) 字节 / 1e9；
 * Class A/B 操作按 actionType 前缀归类（write/put/list 等为 A，read/get 为 B，字段名待实测校准）。
 */
export async function getR2Breakdown(
  accountId: string,
  cycleStart: Date,
  cycleEnd: Date,
): Promise<R2Breakdown> {
  const { from, to } = observationWindow(cycleStart, cycleEnd);
  return cachedQuery(`r2:${accountId}:${from}:${to}`, async () => {
    const [storage, ops] = await Promise.all([
      dashGraphql<StorageResponse>(accountId, STORAGE_QUERY, { from, to })
        .then((d) => d.viewer.accounts[0]?.storage ?? [])
        .catch(() => []),
      dashGraphql<OpsResponse>(accountId, OPS_QUERY, { from, to })
        .then((d) => d.viewer.accounts[0]?.ops ?? [])
        .catch(() => []),
    ]);

    const byBucket = new Map<string, { totalBytes: number; days: number; objects: number }>();
    for (const s of storage) {
      const name = s.dimensions.bucketName;
      const entry = byBucket.get(name) ?? { totalBytes: 0, days: 0, objects: 0 };
      entry.totalBytes += (s.max.payloadSize ?? 0) + (s.max.metadataSize ?? 0);
      entry.days += 1;
      entry.objects = Math.max(entry.objects, s.max.objectCount ?? 0);
      byBucket.set(name, entry);
    }

    const classAActions = new Set(['write', 'put', 'list', 'create', 'copy', 'delete', 'lifecycle']);
    const result = [...byBucket.entries()].map(([name, e]) => ({
      name,
      gbMonths: e.days > 0 ? e.totalBytes / e.days / 1e9 : 0,
      objects: e.objects,
      classA: 0,
      classB: 0,
    }));
    const byName = new Map(result.map((r) => [r.name, r]));
    for (const o of ops) {
      const bucket = byName.get(o.dimensions.bucketName);
      if (!bucket) continue;
      const action = (o.dimensions.actionType ?? '').toLowerCase();
      const isA = [...classAActions].some((a) => action.includes(a));
      if (isA) bucket.classA += o.sum.requests ?? 0;
      else bucket.classB += o.sum.requests ?? 0;
    }
    return { buckets: result.sort((a, b) => b.gbMonths - a.gbMonths) };
  });
}

export async function r2Metric(
  accountId: string,
  cycleStart: Date,
  cycleEnd: Date,
  metric: string,
): Promise<BreakdownItem[]> {
  const b = await getR2Breakdown(accountId, cycleStart, cycleEnd);
  return b.buckets
    .map((bk) => {
      if (metric === 'storage') {
        return { id: bk.name, name: bk.name, usage: bk.gbMonths, note: `${bk.objects} objects` };
      }
      if (metric === 'classA') {
        return { id: bk.name, name: bk.name, usage: bk.classA, note: 'Class A（写/列）' };
      }
      return { id: bk.name, name: bk.name, usage: bk.classB, note: 'Class B（读）' };
    })
    .filter((i) => i.usage > 0)
    .sort((a, b2) => b2.usage - a.usage);
}
