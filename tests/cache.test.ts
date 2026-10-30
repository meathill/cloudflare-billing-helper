import { beforeEach, describe, expect, it } from 'vitest';
import {
  allSeriesFromStore,
  cycleKeyOf,
  getAllSnapshotSeries,
  getSnapshotSeries,
  pruneStore,
  recordSnapshot,
  resolveCycleStartDate,
  seriesFromStore,
  SNAP_MAX_BYTES,
} from '../lib/cache';
import type { SnapshotValue } from '../lib/cache';

/** 内存版 chrome.storage.local（vitest 环境无 chrome 全局） */
const mem = new Map<string, unknown>();
(globalThis as { chrome?: unknown }).chrome = {
  storage: {
    local: {
      get: async (key: string) => (mem.has(key) ? { [key]: mem.get(key) } : {}),
      set: async (obj: Record<string, unknown>) => {
        for (const [k, v] of Object.entries(obj)) mem.set(k, v);
      },
    },
  },
};

const ACCOUNT = 'abc123';
const CYCLE = '2026-10-17';

beforeEach(() => mem.clear());

describe('recordSnapshot / getSnapshotSeries', () => {
  it('记录 u/c 双维度并可分别读取', async () => {
    await recordSnapshot(ACCOUNT, CYCLE, '2026-10-18', {
      workers: { u: 100, c: 0.5 },
      r2: { u: 3.2, c: 0 },
    });
    expect(await getSnapshotSeries(ACCOUNT, CYCLE, 'workers', 'u')).toEqual([
      { date: '2026-10-18', value: 100 },
    ]);
    expect(await getSnapshotSeries(ACCOUNT, CYCLE, 'workers', 'c')).toEqual([
      { date: '2026-10-18', value: 0.5 },
    ]);
    // 同日重写合并而非覆盖整天
    await recordSnapshot(ACCOUNT, CYCLE, '2026-10-18', { kv: { u: 7, c: 0.01 } });
    expect(await getSnapshotSeries(ACCOUNT, CYCLE, 'workers', 'u')).toEqual([
      { date: '2026-10-18', value: 100 },
    ]);
    expect(await getSnapshotSeries(ACCOUNT, CYCLE, 'kv', 'c')).toEqual([
      { date: '2026-10-18', value: 0.01 },
    ]);
  });

  it('兼容历史 number 快照：视为用量，费用维度读不到', async () => {
    const key = `cfbh:snapshots:${ACCOUNT}`;
    mem.set(key, { [CYCLE]: { '2026-10-18': { legacy: 42 } } });
    expect(await getSnapshotSeries(ACCOUNT, CYCLE, 'legacy', 'u')).toEqual([
      { date: '2026-10-18', value: 42 },
    ]);
    expect(await getSnapshotSeries(ACCOUNT, CYCLE, 'legacy', 'c')).toEqual([]);
  });

  it('新对象与旧 number 可在同一天共存', async () => {
    const key = `cfbh:snapshots:${ACCOUNT}`;
    mem.set(key, { [CYCLE]: { '2026-10-18': { legacy: 42 } } });
    await recordSnapshot(ACCOUNT, CYCLE, '2026-10-18', { fresh: { u: 1, c: 0.2 } });
    expect(await getSnapshotSeries(ACCOUNT, CYCLE, 'legacy', 'u')).toEqual([
      { date: '2026-10-18', value: 42 },
    ]);
    expect(await getSnapshotSeries(ACCOUNT, CYCLE, 'fresh', 'u')).toEqual([
      { date: '2026-10-18', value: 1 },
    ]);
  });

  it('查询不存在的账期/产品返回空', async () => {
    await recordSnapshot(ACCOUNT, CYCLE, '2026-10-18', { a: { u: 1 } });
    expect(await getSnapshotSeries(ACCOUNT, '1999-01-01', 'a')).toEqual([]);
    expect(await getSnapshotSeries(ACCOUNT, CYCLE, 'nope')).toEqual([]);
  });
});

describe('getAllSnapshotSeries', () => {
  it('按账期分组返回，组内按日期升序', async () => {
    await recordSnapshot(ACCOUNT, CYCLE, '2026-10-18', { a: { u: 1, c: 0.1 } });
    await recordSnapshot(ACCOUNT, CYCLE, '2026-10-19', { a: { u: 3, c: 0.3 } });
    await recordSnapshot(ACCOUNT, '2026-11-17', '2026-11-18', { a: { u: 10, c: 1 } });
    const all = await getAllSnapshotSeries(ACCOUNT, 'a', 'c');
    expect(Object.keys(all)).toEqual([CYCLE, '2026-11-17']);
    expect(all[CYCLE]).toEqual([
      { date: '2026-10-18', value: 0.1 },
      { date: '2026-10-19', value: 0.3 },
    ]);
    expect(all['2026-11-17']).toEqual([{ date: '2026-11-18', value: 1 }]);
  });
});

describe('账期键', () => {
  it('cycleKeyOf 与 resolveCycleStartDate 互逆（任意时区都成立）', () => {
    const start = new Date(2026, 9, 17); // 本地 10 月 17 日零点
    const key = cycleKeyOf(start);
    expect(resolveCycleStartDate(key)).toBe('2026-10-17');
  });

  it('非零时区下键与自然日可能差一天，但仍能反解回真实起始日', () => {
    const start = new Date(2026, 10, 16);
    const key = cycleKeyOf(start);
    expect(resolveCycleStartDate(key)).toBe('2026-11-16');
  });

  it('非法键返回 null', () => {
    expect(resolveCycleStartDate('not-a-date')).toBeNull();
  });
});

describe('pruneStore', () => {
  it('超过上限时从最老账期开始裁剪', () => {
    const store: Record<string, Record<string, Record<string, SnapshotValue>>> = {
      '2026-08-01': { '2026-08-02': { a: { u: 1 } } },
      '2026-09-01': { '2026-09-02': { a: { u: 2 } } },
      '2026-10-01': { '2026-10-02': { a: { u: 3 } } },
    };
    const full = JSON.stringify(store).length;
    const pruned = pruneStore({ ...store }, full - 10);
    expect(Object.keys(pruned)).toEqual(['2026-09-01', '2026-10-01']);
  });
  it('未超限原样返回', () => {
    const store = { '2026-10-01': { '2026-10-02': { a: { u: 1 } } } };
    expect(pruneStore(store, SNAP_MAX_BYTES)).toBe(store);
  });
});

describe('store 派生函数', () => {
  const store = {
    '2026-10-16': {
      '2026-10-18': { a: { u: 10, c: 0.1 }, b: { u: 1 } },
      '2026-10-17': { a: { u: 5, c: 0.05 } },
    },
    '2026-09-16': {
      '2026-09-18': { a: { u: 3, c: 0.03 } },
    },
  };

  it('seriesFromStore：按日期升序取指定维度', () => {
    expect(seriesFromStore(store, '2026-10-16', 'a', 'u')).toEqual([
      { date: '2026-10-17', value: 5 },
      { date: '2026-10-18', value: 10 },
    ]);
    expect(seriesFromStore(store, '2026-10-16', 'a', 'c')).toEqual([
      { date: '2026-10-17', value: 0.05 },
      { date: '2026-10-18', value: 0.1 },
    ]);
  });

  it('seriesFromStore：缺维度或缺账期返回空', () => {
    expect(seriesFromStore(store, '2026-10-16', 'b', 'c')).toEqual([]);
    expect(seriesFromStore(store, '1999-01-01', 'a', 'u')).toEqual([]);
  });

  it('allSeriesFromStore：按账期分组', () => {
    const all = allSeriesFromStore(store, 'a', 'c');
    expect(Object.keys(all)).toEqual(['2026-09-16', '2026-10-16']);
    expect(all['2026-09-16']).toEqual([{ date: '2026-09-18', value: 0.03 }]);
  });

  it('recordSnapshot 返回写入后的完整 store（一次读盘多处派生）', async () => {
    await recordSnapshot(ACCOUNT, CYCLE, '2026-10-18', { a: { u: 1, c: 0.2 } });
    const returned = await recordSnapshot(ACCOUNT, CYCLE, '2026-10-19', { a: { u: 2, c: 0.4 } });
    expect(seriesFromStore(returned, CYCLE, 'a', 'c')).toEqual([
      { date: '2026-10-18', value: 0.2 },
      { date: '2026-10-19', value: 0.4 },
    ]);
    expect(returned[CYCLE]?.['2026-10-19']?.a).toEqual({ u: 2, c: 0.4 });
  });
});
