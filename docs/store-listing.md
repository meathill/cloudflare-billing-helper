# Chrome Web Store Listing（v0.2.0）

> 本文件是提交 Chrome Web Store 时可直接复制粘贴的完整文案与表单答案。
> 图形资源见 `docs/store/` 与 `docs/screenshots/`，安装包见 `.output/cloudflare-billing-helper-0.2.0-chrome.zip`。
> 本次更新的说明见第四节；Chrome Web Store 后台没有独立的 release notes 字段（商店页只显示 "Updated on <日期>" 与版本号），更新说明需贴在描述开头，文案已同步合并进第三节。

## 〇、两套多语言机制（重要）

| 机制 | 位置 | 作用 |
| --- | --- | --- |
| **Manifest `_locales`** | `public/_locales/{en,zh_CN}/messages.json`，manifest 用 `__MSG_extName__` / `__MSG_extDescription__`，`default_locale: en` | 决定 **Chrome 扩展管理页 / 工具栏提示** 里显示的名称与描述，随浏览器界面语言自动切换 |
| **商店 Listing 语言** | Chrome Web Store Developer Dashboard → Store listing → Add language | 决定 **商店页面** 上的名称、简介、详细描述、截图，需在后台手动添加中文（简体）并分别填写 |

两者互不影响：只配 manifest，商店页面仍只有默认语言；只加商店语言，浏览器 UI 里的名称仍是默认语言。本次已同时准备。

## 一、基本信息

| 字段 | 值 |
| --- | --- |
| Item name（≤45 字符） | `Cloudflare Billing Helper`（中文列表名称：`Cloudflare 账单用量助手`） |
| Category | Developer Tools |
| 语言（默认） | English |
| 本地化语言 | 中文（简体）——需在 Dashboard「Add language」中手工添加 |
| Visibility | Public |
| Pricing | Free |
| Website | https://meathill.com/cloudflare-billing-helper |
| Support URL | https://github.com/meathill/cloudflare-billing-helper/issues |
| Privacy policy URL | https://meathill.com/cloudflare-billing-helper#privacy |
| Mature content | No |

## 二、简短描述（≤132 字符）

**English（默认）**

> Track free-tier quota, forecast cost and exhaustion dates, break spend down by app, and spot daily cost spikes.

**中文（简体）**

> 追踪 Cloudflare 免费额度余量，预测耗尽日期与本周期费用，按应用拆分用量，并标记每日费用异动。

## 三、详细描述（≤16,000 字符）

> 商店详情页不渲染 Markdown，以下为纯文本排版，直接粘贴即可。

### English

```
Cloudflare Billing Helper turns the dashboard's Billable Usage page into a quota cockpit.

See free-tier headroom, when each product will run out, how much it will cost, and which Worker or namespace is driving the number — without creating an API token.

WHAT'S NEW IN 0.2.0

• A trend line in every product row — each row now carries a compact daily-usage sparkline, built from snapshots the extension stores on your device. Hover it to see the latest day's value.
• Sharp moves are flagged — a day that doubles or halves is marked with a red dot right on the line.
• Correct across billing periods — counters reset at each new billing period, and the trend line is computed inside a period only.

WHAT YOU GET

• Free-quota progress for every billing line
All 29 billing products get a usage bar against their included quota, with remaining amounts and clear green / amber / red states.

• Exhaustion alerts with projected dates
Products that will run out this billing cycle are listed at the top with an estimated date, so you can plan a migration (for example KV → R2) before overage charges begin. Request-based products are projected from the daily average; storage products are projected from their daily storage trend.

• Per-product cost forecasts
Daily average, projected usage for the cycle and projected overage cost. When a product has not been billed yet, the estimate uses official list pricing and is marked with "≈".

• Per-app breakdown
Expand a product row to attribute usage to individual Workers, KV namespaces, D1 databases, R2 buckets and Durable Objects, sorted by consumption with share bars.

• A trend line for every product
Each row carries a compact daily-usage sparkline built from snapshots stored on your device, so a product that suddenly doubles or halves is visible at a glance; those days are marked with a red dot. A cost composition bar shows where the money goes.

HOW IT WORKS

The extension runs only on dash.cloudflare.com pages under /billing. It reads the same data the dashboard already displays and calls the dashboard's own endpoints using your existing browser session. No API token is required, and everything is computed locally in your browser.

REQUIREMENTS

• A Cloudflare account with the Workers Paid plan and access to Billing → Billable Usage.
• The panel appears below the spend summary and follows the billing-period switcher.

PRIVACY

• No telemetry, no analytics, no third-party scripts.
• Nothing is uploaded: cached query results and daily usage and cost snapshots stay in chrome.storage on your device.
• The only network requests are to dash.cloudflare.com.

NOTES

• GB-month figures are estimates based on average daily storage.
• Some per-app breakdowns rely on dashboard endpoints that may change over time; the built-in "self-check" reports any unavailable dataset.
• The trend charts need at least two days of snapshots; the extension records one whenever you open the Billable Usage page.

LINKS

Website: https://meathill.com/cloudflare-billing-helper
Source: https://github.com/meathill/cloudflare-billing-helper
```

### 中文（简体）

```
把 Cloudflare 账单的「可计费使用量」页面变成一张配额驾驶舱。

在页面上直接看到：每个产品还剩多少免费额度、什么时候会耗尽、本周期预计花多少钱，以及花费到底来自哪个 Worker / namespace——无需创建 API Token。

0.2.0 更新内容

• 每个产品行内嵌一条每日用量趋势线——基于扩展每天自存的快照，鼠标悬停可看最近一天的具体数值。
• 暴涨暴跌会被标出来——某天用量翻倍或腰斩，趋势线上直接标红点。
• 跨账期也对——累计值在换账期时清零，趋势线只在账期内计算。

你会得到

• 每个产品的免费额度进度
29 个计费产品逐一显示免费额度使用进度条、剩余量，以及绿 / 黄 / 红三色状态。

• 耗尽预警与预计日期
会在本账期内耗尽的产品置顶显示，并给出预计耗尽日期，方便你在开始超额扣费前安排迁移（例如 KV → R2）。请求类产品按日均线性外推，存储类产品按每日存储趋势回归。

• 逐产品费用预估
显示日均用量、本周期预计用量与预计超额费用。尚未产生费用的产品使用官方目录价估算，并标注「≈」。

• 按应用拆分
展开产品行即可把用量拆到具体的 Worker、KV namespace、D1 数据库、R2 bucket 与 Durable Object，按消耗降序排列并给占比条。

• 每个产品都有趋势线
每行内嵌一条每日用量迷你折线（基于扩展每天自存的本机快照），哪个产品突然翻倍或腰斩一眼就能看到，这些天会标上红点；费用构成条形图则显示钱花在了哪里。

工作原理

扩展只在 dash.cloudflare.com 的 /billing 页面运行。它读取账单页面已展示的数据，并复用你当前的浏览器登录态调用 Dashboard 自身接口，不需要 API Token，所有计算都在浏览器本地完成。

使用条件

• 使用 Workers Paid 套餐、可访问「账单 → 可计费使用量」的 Cloudflare 账户。
• 面板会出现在「支出摘要」下方，并随账期切换自动刷新。

隐私

• 无遥测、无统计、无第三方脚本。
• 不上传任何数据：查询缓存与每日用量、费用快照保存在本机 chrome.storage 中。
• 仅访问 dash.cloudflare.com。

说明

• GB-months 为按日均存储量估算的数值。
• 部分按应用拆分依赖 Dashboard 内部接口，接口字段可能变化；面板内置「接口自检」会报告不可用的数据集。
• 趋势曲线需要至少两天的快照记录，扩展在你每次打开「可计费使用量」时记录一次。

链接

主页：https://meathill.com/cloudflare-billing-helper
源码：https://github.com/meathill/cloudflare-billing-helper
```

## 四、更新说明（Updates / What's new）

> **Chrome Web Store 后台没有独立的 release notes 输入框**：商店页只显示 "Updated on <日期>" 与版本号。
> 因此更新说明的落地位置是**详细描述的开头**（下方文案已合并进第三节描述），本节保留一份可独立复制粘贴的版本，
> 以后每次发新版，在这里追加一段并把同样的内容补到描述开头即可。

### v0.2.0 更新说明（English）

```
WHAT'S NEW IN 0.2.0

• A trend line in every product row
Each row now carries a compact daily-usage sparkline, built from snapshots the extension records on your device. Hover it to see the latest day's value, so you can tell at a glance whether a product is climbing steadily or suddenly jumping.

• Sharp moves are flagged
A day whose usage doubles or halves is marked with a red dot right on the line, so a surprise overage no longer slips by.

• Correct across billing periods
Counters reset at every new billing period, and the trend line is computed inside a period only — daily values and sharp-move detection are never mixed across periods.
```

### v0.2.0 更新说明（中文（简体））

```
0.2.0 更新内容

• 每个产品都有行内趋势线
每个产品行内嵌一条每日用量迷你折线，数据来自扩展在你本机记录的每日快照；鼠标悬停可看最近一天的具体数值，是稳定爬升还是突然跳涨一眼就能分辨。

• 暴涨暴跌会被标出来
某天用量翻倍或腰斩，趋势线上直接标红点，意外超额不再被忽略。

• 跨账期也对
累计值在换账期时清零，趋势线只在账期内计算，每日值与异动判断不会跨账期混算。
```

### 版本记录

| 版本 | 说明 |
| --- | --- |
| 0.2.0 | 首次公开发布：免费额度追踪、耗尽预警、逐产品预估、按应用拆分、行内每日用量趋势线 |

> 0.1.x 为发布前的内部迭代版本，未公开发布；对外版本记录自 0.2.0 起。

## 五、隐私与权限表单（Privacy practices）

### Single purpose（单一用途）

```
Add free-quota tracking, exhaustion forecasting, cost projection and per-application usage attribution to the Cloudflare Billable Usage page.
```

### Permission justification

**`storage`**

```
Stores cached breakdown query results (10 minutes) and daily usage and cost snapshots locally in chrome.storage. The snapshots are kept for all billing periods and are pruned only if they exceed a 4MB size cap. This powers the per-product daily trend lines and makes repeated lookups instant. No data leaves the browser.
```

**Host permission `https://dash.cloudflare.com/*`**

```
The content script injects the panel only on Cloudflare dashboard pages under /billing. It reads the billable-usage table the page already renders and calls the dashboard's own GraphQL/REST endpoints using the user's existing session. No other sites are accessed and no external servers are contacted.
```

### Remote code

```
No. All code is bundled in the extension package; nothing is loaded or evaluated remotely.
```

### Data usage（数据收集声明）

选择 **「Does not collect user data」**。理由：

- 账单与用量数据仅在浏览器内计算与展示，本地缓存不构成收集；
- 无任何对外网络请求（仅访问 dash.cloudflare.com 自身接口）；
- 无遥测、无账号系统、无广告。

> 若审核人员追问“读取账单是否属于金融信息收集”，按其口径补充说明：扩展未将任何数据传出设备，数据仅在本地渲染，符合「不收集」定义。

## 六、图形资源

| 用途 | 文件 | 尺寸 |
| --- | --- | --- |
| 商店图标（必填） | `public/icon/128.png` | 128×128 |
| 截图（至少 1 张，最多 5 张） | `docs/screenshots/store-1280x800.png` | 1280×800 |
| 小宣传图（可选） | `docs/store/promo-440x280.png` | 440×280 |
| 横幅宣传图（可选） | `docs/store/marquee-1400x560.png` | 1400×560 |

如需更多截图，可参考 `docs/screenshots/panel.png`（2x 面板特写）另行裁切。

## 七、提交步骤

1. Chrome Web Store Developer Dashboard → New item → 上传 `.output/cloudflare-billing-helper-0.2.0-chrome.zip`；
2. Store listing（English）：粘贴上文英文名称 / 简介 / 详细描述，**描述开头先贴第四节英文更新说明**；
3. Store listing → **Add language → 中文（简体）**：粘贴中文名称 / 简介 / 详细描述（描述开头贴第四节中文更新说明；截图与图片可与默认语言共用）；
4. 上传图标、截图与宣传图；填写 Website / Support / Privacy policy URL；
5. Privacy practices：按第五节填写单一用途、权限说明、远程代码「No」、数据「Does not collect」；
6. Distribution：Public / Free / All regions；
7. 提交审核（新账号首次提交通常需要 1–3 个工作日）；审核通过后再点 Publish 发布。

> 发下一版时：先 `pnpm build`（自动 +1 patch）→ `pnpm zip` → 在第四节追加新版本说明并同步到描述开头 → 上传新 zip 提交审核。
