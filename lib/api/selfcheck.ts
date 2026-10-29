/** 接口自检：逐项探测拆分查询在当前账号/登录态下是否可用，输出可直接反馈的结果。 */
import type { CycleInfo } from '../types';
import { dashGraphql, observationWindow } from './graphql';
import { listKvNamespaces } from './kv';
import { listD1Databases } from './d1';

export interface SelfCheckItem {
  name: string;
  ok: boolean;
  detail: string;
}

const WORKERS_PROBE = /* GraphQL */ `
  query CfbhProbeWorkers($accountTag: string!, $from: Date!, $to: Date!) {
    viewer {
      accounts(filter: { accountTag: $accountTag }) {
        g: workersInvocationsAdaptiveGroups(filter: { date_geq: $from, date_leq: $to }, limit: 1) {
          dimensions { scriptName }
          sum { cpuTime requests }
        }
      }
    }
  }
`;

const KV_STORAGE_PROBE = /* GraphQL */ `
  query CfbhProbeKvStorage($accountTag: string!, $from: Date!, $to: Date!) {
    viewer {
      accounts(filter: { accountTag: $accountTag }) {
        g: kvStorageAdaptiveGroups(filter: { date_geq: $from, date_leq: $to }, limit: 1) {
          dimensions { date }
          max { byteCount keyCount }
        }
      }
    }
  }
`;

const KV_OPS_PROBE = /* GraphQL */ `
  query CfbhProbeKvOps($accountTag: string!, $from: Date!, $to: Date!) {
    viewer {
      accounts(filter: { accountTag: $accountTag }) {
        g: kvOperationsAdaptiveGroups(filter: { date_geq: $from, date_leq: $to }, limit: 1) {
          dimensions { actionType }
          sum { requests }
        }
      }
    }
  }
`;

const D1_ROWS_PROBE = /* GraphQL */ `
  query CfbhProbeD1($accountTag: string!, $from: Date!, $to: Date!) {
    viewer {
      accounts(filter: { accountTag: $accountTag }) {
        g: d1AnalyticsAdaptiveGroups(filter: { date_geq: $from, date_leq: $to }, limit: 1) {
          dimensions { databaseId }
          sum { readRows writtenRows }
        }
      }
    }
  }
`;

const R2_STORAGE_PROBE = /* GraphQL */ `
  query CfbhProbeR2($accountTag: string!, $from: Date!, $to: Date!) {
    viewer {
      accounts(filter: { accountTag: $accountTag }) {
        g: r2StorageAdaptiveGroups(filter: { date_geq: $from, date_leq: $to }, limit: 1) {
          dimensions { bucketName }
          max { payloadSize metadataSize objectCount }
        }
      }
    }
  }
`;

const R2_OPS_PROBE = /* GraphQL */ `
  query CfbhProbeR2Ops($accountTag: string!, $from: Date!, $to: Date!) {
    viewer {
      accounts(filter: { accountTag: $accountTag }) {
        g: r2OperationsAdaptiveGroups(filter: { date_geq: $from, date_leq: $to }, limit: 1) {
          dimensions { bucketName }
          sum { requests }
        }
      }
    }
  }
`;

const DO_REQUESTS_PROBE = /* GraphQL */ `
  query CfbhProbeDoReq($accountTag: string!, $from: Date!, $to: Date!) {
    viewer {
      accounts(filter: { accountTag: $accountTag }) {
        g: durableObjectsRequestsAdaptiveGroups(filter: { date_geq: $from, date_leq: $to }, limit: 1) {
          dimensions { scriptName }
          sum { requests }
        }
      }
    }
  }
`;

const DO_STORAGE_PROBE = /* GraphQL */ `
  query CfbhProbeDoStorage($accountTag: string!, $from: Date!, $to: Date!) {
    viewer {
      accounts(filter: { accountTag: $accountTag }) {
        g: durableObjectsStorageAdaptiveGroups(filter: { date_geq: $from, date_leq: $to }, limit: 1) {
          dimensions { namespaceId }
          max { storageBytes }
        }
      }
    }
  }
`;

interface AccountsProbe<T> {
  viewer: { accounts: { g?: T[] }[] };
}

export async function runSelfCheck(accountId: string, cycle: CycleInfo | null): Promise<SelfCheckItem[]> {
  const start = cycle?.cycleStart ?? new Date(Date.now() - 7 * 86_400_000);
  const end = cycle?.cycleEnd ?? new Date();
  const { from, to } = observationWindow(start, end);
  const items: SelfCheckItem[] = [];

  const probe = async (name: string, fn: () => Promise<string>): Promise<void> => {
    const t0 = Date.now();
    try {
      const detail = await fn();
      items.push({ name, ok: true, detail: `${detail} · ${Date.now() - t0}ms` });
    } catch (e) {
      items.push({ name, ok: false, detail: e instanceof Error ? e.message : String(e) });
    }
  };

  const gqlProbe = async (query: string): Promise<string> => {
    const data = await dashGraphql<AccountsProbe<unknown>>(accountId, query, { from, to });
    const n = data.viewer.accounts[0]?.g?.length ?? 0;
    return n > 0 ? `返回 ${n} 组` : '接口可用（暂无数据）';
  };

  await probe('GraphQL 登录态', async () => {
    const data = await dashGraphql<{ viewer: { accounts: unknown[] } }>(
      accountId,
      /* GraphQL */ `query CfbhProbeAuth($accountTag: string!) {
        viewer { accounts(filter: { accountTag: $accountTag }) { __typename } }
      }`,
      {},
    );
    return data.viewer.accounts.length > 0 ? '可访问该账号' : '接口正常但账号不可见';
  });

  await probe('Workers 调用数据集', () => gqlProbe(WORKERS_PROBE));
  await probe('KV namespaces (REST)', async () => `${(await listKvNamespaces(accountId)).length} 个 namespace`);
  await probe('KV 存储数据集', () => gqlProbe(KV_STORAGE_PROBE));
  await probe('KV 操作数据集', () => gqlProbe(KV_OPS_PROBE));
  await probe('D1 数据库 (REST)', async () => `${(await listD1Databases(accountId)).length} 个数据库`);
  await probe('D1 行读写数据集', () => gqlProbe(D1_ROWS_PROBE));
  await probe('R2 存储数据集', () => gqlProbe(R2_STORAGE_PROBE));
  await probe('R2 操作数据集', () => gqlProbe(R2_OPS_PROBE));
  await probe('DO 请求数据集', () => gqlProbe(DO_REQUESTS_PROBE));
  await probe('DO 存储数据集', () => gqlProbe(DO_STORAGE_PROBE));

  return items;
}
