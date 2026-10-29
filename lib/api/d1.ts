/** D1 族拆分：每个数据库的文件大小 + 行读写量。 */
import type { BreakdownItem } from '../types';
import { cachedQuery, dashGraphql, observationWindow } from './graphql';

const DASH_ORIGIN = 'https://dash.cloudflare.com';

interface Database {
  uuid: string;
  name: string;
  file_size?: number;
  num_tables?: number;
  created_at?: string;
}

export async function listD1Databases(accountId: string): Promise<Database[]> {
  const result: Database[] = [];
  for (let page = 1; page <= 20; page++) {
    const res = await fetch(
      `${DASH_ORIGIN}/api/v4/accounts/${accountId}/d1/database?page=${page}&per_page=100`,
      { credentials: 'include' },
    );
    if (!res.ok) throw new Error(`D1 databases HTTP ${res.status}`);
    const json = (await res.json()) as { result: Database[] | null };
    const list = json.result ?? [];
    result.push(...list);
    if (list.length < 100) break;
  }
  return result;
}

const ROWS_QUERY = /* GraphQL */ `
  query CfbhD1Rows($accountTag: string!, $from: Date!, $to: Date!) {
    viewer {
      accounts(filter: { accountTag: $accountTag }) {
        rows: d1AnalyticsAdaptiveGroups(
          filter: { date_geq: $from, date_leq: $to }
          limit: 10000
        ) {
          dimensions {
            databaseId
          }
          sum {
            readRows
            writtenRows
          }
        }
      }
    }
  }
`;

interface RowsResponse {
  viewer: {
    accounts: {
      rows: { dimensions: { databaseId: string }; sum: { readRows: number; writtenRows: number } }[];
    }[];
  };
}

export interface D1Breakdown {
  databases: { id: string; name: string; gb: number; tables: number; rowsRead: number; rowsWritten: number }[];
}

export async function getD1Breakdown(
  accountId: string,
  cycleStart: Date,
  cycleEnd: Date,
): Promise<D1Breakdown> {
  const { from, to } = observationWindow(cycleStart, cycleEnd);
  return cachedQuery(`d1:${accountId}:${from}:${to}`, async () => {
    const databases = await listD1Databases(accountId);
    let rowsByDb = new Map<string, { readRows: number; writtenRows: number }>();
    try {
      const data = await dashGraphql<RowsResponse>(accountId, ROWS_QUERY, { from, to });
      rowsByDb = new Map(
        (data.viewer.accounts[0]?.rows ?? []).map((r) => [
          r.dimensions.databaseId,
          { readRows: r.sum.readRows ?? 0, writtenRows: r.sum.writtenRows ?? 0 },
        ]),
      );
    } catch {
      // 行读写数据集不可用时降级为 0
    }
    return {
      databases: databases
        .map((db) => ({
          id: db.uuid,
          name: db.name,
          gb: (db.file_size ?? 0) / 1e9,
          tables: db.num_tables ?? 0,
          rowsRead: rowsByDb.get(db.uuid)?.readRows ?? 0,
          rowsWritten: rowsByDb.get(db.uuid)?.writtenRows ?? 0,
        }))
        .sort((a, b) => b.gb - a.gb),
    };
  });
}

export async function d1Metric(
  accountId: string,
  cycleStart: Date,
  cycleEnd: Date,
  metric: string,
): Promise<BreakdownItem[]> {
  const b = await getD1Breakdown(accountId, cycleStart, cycleEnd);
  return b.databases
    .map((db) => {
      if (metric === 'storage') {
        return { id: db.id, name: db.name, usage: db.gb, note: `${db.tables} 张表` };
      }
      if (metric === 'rowsRead') {
        return { id: db.id, name: db.name, usage: db.rowsRead, note: `${db.gb.toFixed(2)} GB` };
      }
      return { id: db.id, name: db.name, usage: db.rowsWritten, note: `${db.gb.toFixed(2)} GB` };
    })
    .filter((i) => i.usage > 0)
    .sort((a, b2) => b2.usage - a.usage);
}
