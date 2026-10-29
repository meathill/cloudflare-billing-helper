/** Workers 族拆分：每个 Worker 的 CPU 时间与请求数。 */
import { cachedQuery, dashGraphql, observationWindow } from './graphql';
import type { BreakdownItem } from '../types';

const QUERY = /* GraphQL */ `
  query CfbhWorkers($accountTag: string!, $from: Date!, $to: Date!) {
    viewer {
      accounts(filter: { accountTag: $accountTag }) {
        invocations: workersInvocationsAdaptiveGroups(
          filter: { date_geq: $from, date_leq: $to }
          limit: 10000
        ) {
          dimensions {
            scriptName
          }
          sum {
            cpuTime
            requests
          }
        }
      }
    }
  }
`;

interface InvocationsResponse {
  viewer: {
    accounts: {
      invocations: {
        dimensions: { scriptName: string };
        sum: { cpuTime: number; requests: number };
      }[];
    }[];
  };
}

export interface WorkersBreakdown {
  byScript: { name: string; cpuTimeMs: number; requests: number }[];
}

/** 返回按 CPU 降序的每个 Worker 用量。cpuTime GraphQL 单位是微秒，换算为 ms。 */
export async function getWorkersBreakdown(
  accountId: string,
  cycleStart: Date,
  cycleEnd: Date,
): Promise<WorkersBreakdown> {
  const { from, to } = observationWindow(cycleStart, cycleEnd);
  return cachedQuery(`workers:${accountId}:${from}:${to}`, async () => {
    const data = await dashGraphql<InvocationsResponse>(accountId, QUERY, { from, to });
    const groups = data.viewer.accounts[0]?.invocations ?? [];
    const byScript = groups
      .map((g) => ({
        name: g.dimensions.scriptName,
        cpuTimeMs: (g.sum.cpuTime ?? 0) / 1000,
        requests: g.sum.requests ?? 0,
      }))
      .sort((a, b) => b.cpuTimeMs - a.cpuTimeMs);
    return { byScript };
  });
}

/** 按指标取拆分列表。 */
export async function workersMetric(
  accountId: string,
  cycleStart: Date,
  cycleEnd: Date,
  metric: string,
): Promise<BreakdownItem[]> {
  const b = await getWorkersBreakdown(accountId, cycleStart, cycleEnd);
  const items: BreakdownItem[] = b.byScript.map((s) => ({
    id: s.name,
    name: s.name,
    usage: metric === 'requests' ? s.requests : s.cpuTimeMs,
    note: metric === 'requests' ? `${s.cpuTimeMs.toFixed(0)} ms CPU` : `${s.requests} 请求`,
  }));
  return items.sort((a, b2) => b2.usage - a.usage);
}
