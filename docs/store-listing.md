# Chrome Web Store Listing（v0.1.5）

> 本文件是提交 Chrome Web Store 时可直接复制粘贴的完整文案与表单答案。
> 图形资源见 `docs/store/` 与 `docs/screenshots/`，安装包见 `.output/cloudflare-billing-helper-*.zip`。

## 一、基本信息

| 字段 | 值 |
| --- | --- |
| Item name（≤45 字符） | `Cloudflare Billing Helper` |
| Category | Developer Tools |
| Language（默认） | English |
| 本地化语言 | 中文（简体） |
| Visibility | Public |
| Pricing | Free |
| Website | https://meathill.com/cloudflare-billing-helper |
| Support URL | https://github.com/meathill/cloudflare-billing-helper/issues |
| Privacy policy URL | https://meathill.com/cloudflare-billing-helper#privacy |
| Mature content | No |

## 二、简短描述（≤132 字符）

**English（默认）**

> Track free-tier quota, forecast exhaustion dates and cost, and break spend down by Worker, KV, D1, R2 and Durable Objects.

**中文（简体）**

> 追踪 Cloudflare 免费额度余量，预测耗尽日期与本周期费用，按 Worker / KV / D1 / R2 / DO 拆分用量。

## 三、详细描述（≤16,000 字符）

> 商店详情页不渲染 Markdown，以下为纯文本排版，直接粘贴即可。

### English

```
Cloudflare Billing Helper turns the dashboard's Billable Usage page into a quota cockpit.

See free-tier headroom, when each product will run out, how much it will cost, and which Worker or namespace is driving the number — without creating an API token.

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
Cost composition bars and a quota-consumption trend chart built from daily snapshots stored on your device.

HOW IT WORKS

The extension runs only on dash.cloudflare.com pages under /billing. It reads the same data the dashboard already displays and calls the dashboard's own endpoints using your existing browser session. No API token is required, and everything is computed locally in your browser.

REQUIREMENTS

• A Cloudflare account with the Workers Paid plan and access to Billing → Billable Usage.
• The panel appears below the spend summary and follows the billing-period switcher.

PRIVACY

• No telemetry, no analytics, no third-party scripts.
• Nothing is uploaded: cached query results and daily usage snapshots stay in chrome.storage on your device.
• The only network requests are to dash.cloudflare.com.

NOTES

• GB-month figures are estimates based on average daily storage.
• Some per-app breakdowns rely on dashboard endpoints that may change over time; the built-in "self-check" reports any unavailable dataset.

LINKS

Website: https://meathill.com/cloudflare-billing-helper
Source: https://github.com/meathill/cloudflare-billing-helper
```

### 中文（简体）

```
把 Cloudflare 账单的「可计费使用量」页面变成一张配额驾驶舱。

在页面上直接看到：每个产品还剩多少免费额度、什么时候会耗尽、本周期预计花多少钱，以及花费到底来自哪个 Worker / namespace——无需创建 API Token。

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
费用构成条形图，以及基于每日本地快照的额度消耗趋势图。

工作原理

扩展只在 dash.cloudflare.com 的 /billing 页面运行。它读取账单页面已展示的数据，并复用你当前的浏览器登录态调用 Dashboard 自身接口，不需要 API Token，所有计算都在浏览器本地完成。

使用条件

• 使用 Workers Paid 套餐、可访问「账单 → 可计费使用量」的 Cloudflare 账户。
• 面板会出现在「支出摘要」下方，并随账期切换自动刷新。

隐私

• 无遥测、无统计、无第三方脚本。
• 不上传任何数据：查询缓存与每日用量快照保存在本机 chrome.storage 中。
• 仅访问 dash.cloudflare.com。

说明

• GB-months 为按日均存储量估算的数值。
• 部分按应用拆分依赖 Dashboard 内部接口，接口字段可能变化；面板内置「接口自检」会报告不可用的数据集。

链接

主页：https://meathill.com/cloudflare-billing-helper
源码：https://github.com/meathill/cloudflare-billing-helper
```

## 四、隐私与权限表单（Privacy practices）

### Single purpose（单一用途）

```
Add free-quota tracking, exhaustion forecasting, cost projection and per-application usage attribution to the Cloudflare Billable Usage page.
```

### Permission justification

**`storage`**

```
Stores cached breakdown query results (10 minutes) and daily usage snapshots (up to 3 billing periods) locally in chrome.storage. This powers the trend chart and makes repeated lookups instant. No data leaves the browser.
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

## 五、图形资源

| 用途 | 文件 | 尺寸 |
| --- | --- | --- |
| 商店图标（必填） | `public/icon/128.png` | 128×128 |
| 截图（至少 1 张，最多 5 张） | `docs/screenshots/store-1280x800.png` | 1280×800 |
| 小宣传图（可选） | `docs/store/promo-440x280.png` | 440×280 |
| 横幅宣传图（可选） | `docs/store/marquee-1400x560.png` | 1400×560 |

如需更多截图，可参考 `docs/screenshots/panel.png`（2x 面板特写）另行裁切。

## 六、提交步骤

1. Chrome Web Store Developer Dashboard → New item → 上传 `.output/cloudflare-billing-helper-0.1.5-chrome.zip`；
2. Store listing：粘贴上文名称 / 简介 / 详细描述（英文为默认，中文在「Add language」里添加）；
3. 上传图标、截图与宣传图；填写 Website / Support / Privacy policy URL；
4. Privacy practices：按第四节填写单一用途、权限说明、远程代码「No」、数据「Does not collect」；
5. Distribution：Public / Free / All regions；
6. 提交审核（新账号首次提交通常需要 1–3 个工作日）。
