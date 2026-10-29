# Cloudflare Billing Helper

浏览器扩展：增强 Cloudflare Dashboard 的「可计费使用量」页
（`dash.cloudflare.com/{accountId}/billing/billable-usage`），解决官方页面看不到免费额度余量、无法预估耗尽时间、看不出钱花在哪个应用上的问题。

## 功能

1. **免费额度可视化** — 每个计费行显示「已用 / 免费额度 / 剩余」进度条与状态色（绿 <70%、琥珀 70–100%、红超量/将耗尽）。
2. **耗尽预警** — 面板顶部列出会在本账期内耗尽免费额度的产品，并给出预计耗尽日期：
   - 请求类产品（CPU、操作数、请求数…）按日均线性外推；
   - 存储类产品（KV/R2/DO 的 GB-months）按每日存储序列做趋势回归；
   - 扩展每天自存一份快照，运行几天后即使接口没有历史也能预测趋势（趋势图同步生成）。
3. **逐产品预估** — 日均用量、按日均外推的本周期预计用量、预计超额费用（有效费率优先用「成本 ÷ 可计费量」反推）。
4. **按应用拆分** — 点击产品行展开，通过 dashboard 内部 GraphQL/REST（复用登录 cookie，无需 API token）拆到具体应用：
   - Workers：每个 Worker 的 CPU 时间与请求
   - KV：每个 namespace 的 GB-months、key 数、读/写/删/列操作
   - D1：每个数据库的文件大小、行读写
   - R2：每个 bucket 的 GB-months、Class A/B 操作
   - Durable Objects：请求、存储（字段名未见完整公开文档，采用候选查询依次尝试，失败时该行降级提示，不影响其他行）
5. **费用构成** — 横向条形图显示各产品费用占比；**额度消耗趋势** — 多折线图（来自每日快照）。

隐私：所有数据仅在本地处理（`chrome.storage`），扩展只访问 `dash.cloudflare.com` 自身，不请求任何第三方服务。

## 开发

```bash
pnpm install
pnpm dev          # 开发模式（热更新），按提示加载 .output/chrome-mv3
pnpm build        # 生产构建 → .output/chrome-mv3（自动调升 patch 版本号）
pnpm build:only   # 只构建，不改版本号
pnpm zip          # 打包 zip
pnpm test         # vitest 单测（预估算法、DOM 解析）
pnpm compile      # vue-tsc 类型检查
```

手动加载：`chrome://extensions` → 开发者模式 → 「加载已解压的扩展程序」→ 选择 `.output/chrome-mv3`，然后打开账单页。
**升级后**：在 `chrome://extensions` 点扩展卡片上的刷新按钮，再到账单页**整页刷新**（扩展重载不会自动重注入已打开的标签页）。
面板标题栏显示当前扩展版本号，控制台 `[CFBH] content script vX.Y.Z 已注入` 可确认运行版本。

## 实机调试

```bash
node scripts/repro.mjs    # 用真实 Chromium 加载扩展，跑 playground 页四个场景
                          # （整页直载 / 其他账单页不挂载 / SPA 切入挂载 / 切离卸载）
```

`playground/index.html` 模拟账单页结构，content script 额外匹配了 `http://localhost:8199/*` 便于本地调试。
面板不显示时，先看账单页 DevTools Console 里有没有 `[CFBH]` 日志：没有任何日志说明脚本未注入
（检查 chrome://extensions 是否有报错、是否隐身窗口、URL 是否为 `/{accountId}/billing/billable-usage`）。

## 结构

```
entrypoints/
  injected.content.ts   # MAIN-world：钩住页面 fetch/XHR，捕获账单接口 JSON（调试/后续增强）
  content.ts            # ISOLATED：Shadow DOM 挂载 Vue 面板，SPA 自动重挂载
  content/App.vue       # 面板根组件（预警条、额度表、图表）
  content/components/   # QuotaTable / QuotaBar / BreakdownList / CostShareBars / QuotaTrendChart
lib/
  products.ts           # 29 个计费行目录：免费额度、单位、颜色、产品族、拆分能力
  math.ts               # 日均/外推/耗尽日期/回归（纯函数）
  parse/dom-parser.ts   # 页面表格解析（中英文界面兼容，不依赖私有 class）
  api/                  # dash GraphQL 客户端 + workers/kv/d1/r2/do 拆分模块
  cache.ts              # session 缓存（10 分钟）+ 每日快照（local，保留 3 个账期）
tests/                  # vitest
```

## 实现说明与已知限制

- 数据以页面 DOM 解析为准（对页面改版有兜底），MAIN-world 拦截的接口 JSON 目前仅用于调试：面板右上角「复制接口调试数据」可导出捕获内容，用于后续增强与 GraphQL 字段校准。
- KV/R2/DO/Workers 拆分的 GraphQL 数据集字段名（如 `r2StorageAdaptiveGroups`、`durableObjectsStorageAdaptiveGroups`）未全部见于公开文档，代码按官方文档/常见命名编写并做候选尝试；某维度失败时仅该维度降级，扩展右上角按钮导出调试数据即可修正。
- GB-months 为账期内日均字节的估算口径，与 Cloudflare 计费基本一致，UI 标注「估算」。
- 图标暂未内置（开发版显示默认拼图图标）。
