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

• Daily cost curve — every time you open this page the extension records a snapshot of your usage and cost and turns them into a daily cost curve (total plus your top products). Days that spike or drop sharply are marked with a red dot and called out at the top of the panel.
• Quota-consumption curve for every product, with hover values and a legend you can switch products off in.
• Curves restart at every new billing period, so daily values and spike detection are never mixed across periods.

WHAT YOU GET

• Free-quota progress for every billing line
All 29 billing products get a usage bar against their included quota, with remaining amounts and clear green / amber / red states.

• Exhaustion alerts with projected dates
Products that will run out this billing cycle are listed at the top with an estimated date, so you can plan a migration (for example KV → R2) before overage charges begin. Request-based products are projected from the daily average; storage products are projected from their daily storage trend.

• Per-product cost forecasts
Daily average, projected usage for the cycle and projected overage cost. When a product has not been billed yet, the estimate uses official list pricing and is marked with "≈".

• Per-app breakdown
Expand a product row to attribute usage to individual Workers, KV namespaces, D1 databases, R2 buckets and Durable Objects, sorted by consumption with share bars.

• Charts that answer "am I on track?"
Cost composition bars, a daily cost curve (total plus your top products) and a quota-consumption curve, both built from snapshots the extension stores on your device. Days that spike or drop sharply are marked with a red dot and called out at the top of the panel.

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

• 每日费用曲线——每次打开本页都会记录一条用量与费用快照，换算成每日费用曲线（总费用与费用最高的产品各一条），某天费用暴涨暴跌会标出红点并在面板顶部提示。
• 每个产品的额度消耗曲线，支持悬停查看当天数值、图例点击开关。
• 换账期时曲线重新起算，每日值与异动判断不会跨账期混算。

你会得到

• 每个产品的免费额度进度
29 个计费产品逐一显示免费额度使用进度条、剩余量，以及绿 / 黄 / 红三色状态。

• 耗尽预警与预计日期
会在本账期内耗尽的产品置顶显示，并给出预计耗尽日期，方便你在开始超额扣费前安排迁移（例如 KV → R2）。请求类产品按日均线性外推，存储类产品按每日存储趋势回归。

• 逐产品费用预估
显示日均用量、本周期预计用量与预计超额费用。尚未产生费用的产品使用官方目录价估算，并标注「≈」。

• 按应用拆分
展开产品行即可把用量拆到具体的 Worker、KV namespace、D1 数据库、R2 bucket 与 Durable Object，按消耗降序排列并给占比条。

• 一眼看清趋势
费用构成条形图、每日费用曲线（总费用与费用最高的产品各一条）与额度消耗曲线，均基于扩展每天自存的本机快照。某天费用突然涨上去或掉下来时，曲线上会标出红点，面板顶部也会直接提示。

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

• Daily cost curve
Every time you open the Billable Usage page, the extension records a snapshot of your usage and cost, then turns them into a daily cost curve — the total plus your top-spending products. Any day that jumps or drops sharply is marked with a red dot and called out at the top of the panel, so a surprise overage no longer slips by.

• Quota-consumption curve
The quota chart now shows how each product's free-tier usage moves over time. Hover for the exact value of any day, and click the legend to switch individual products on and off.

• Correct across billing periods
Curves restart at every new billing period: daily values are computed inside a period only, the first day of a period is averaged from the period start, and periods are never mixed when judging whether a day was unusual.
```

### v0.2.0 更新说明（中文（简体））

```
0.2.0 更新内容

• 每日费用曲线
每次打开「可计费使用量」时，扩展都会记录一条用量与费用快照，并换算成每日费用曲线：总费用一条，费用最高的产品各一条。某天费用突然涨上去或掉下来时，曲线上会标出红点，面板顶部也会直接提示，意外超额不再被忽略。

• 额度消耗曲线
额度曲线会显示每个产品的免费额度消耗过程，鼠标悬停可看当天数值，图例可点开或关掉某条线。

• 跨账期也算得对
换账期时曲线重新起算：每日值只在账期内计算，新账期第一天按周期开始摊算，不同账期之间不会混在一起比较。
```

### 版本记录

| 版本 | 说明 |
| --- | --- |
| 0.2.0 | 首次公开发布：免费额度追踪、耗尽预警、逐产品预估、按应用拆分、每日费用与额度曲线、暴涨暴跌提示 |

> 0.1.x 为发布前的内部迭代版本，未公开发布；对外版本记录自 0.2.0 起。

## 五、隐私与权限表单（Privacy practices）

### Single purpose（单一用途）

```
Add free-quota tracking, exhaustion forecasting, cost projection and per-application usage attribution to the Cloudflare Billable Usage page.
```

### Permission justification

**`storage`**

```
Stores cached breakdown query results (10 minutes) and daily usage and cost snapshots locally in chrome.storage. The snapshots are kept for all billing periods and are pruned only if they exceed a 4MB size cap. This powers the daily cost and quota trend charts and makes repeated lookups instant. No data leaves the browser.
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
