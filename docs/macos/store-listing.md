# Mac App Store listing materials

Listing metadata for the macOS app. Version 1.0.0 (3) and its optional Coffee Tip were submitted on November 5, 2026 and are waiting for review. See the [submission record](submission.md). No credentials or real account data belong in this document.

## English (U.S.)

**Name (30/30 characters):** Billing Helper for Cloudflare®  
**Subtitle (24/30 characters):** Billing in your menu bar  
**Keywords (65/100 UTF-8 bytes):** `usage,cost,forecast,budget,monitor,serverless,subscription,trends`

**Description:**

Keep an eye on Cloudflare account billing from your Mac. Billing Helper for Cloudflare® brings costs, billing periods and estimates into a native menu bar app.

• See current fixed subscription costs and usage charges, alongside an estimated end-of-cycle total.
• See each product's cost share and cumulative cost line for the current cycle.
• Switch between accounts and billing cycles, check when data was last retrieved, and review the reason when billing information is incomplete.
• Track free-quota usage for each product, with the projected run-out date and overage based on recent daily usage.
• Set optional budget alerts for each account and currency, and optional alerts before a free quota runs out.

Try the app first with its built-in, removable Sample account, which uses local simulated data. Connect real accounts using a read-only Cloudflare API token. The token is stored in macOS Keychain; billing data is requested directly from Cloudflare and cached on your Mac. You control the token's account and zone scope.

Estimates are not invoices and exclude taxes and credits. Data availability and update timing depend on Cloudflare and your token permissions. Usage-based billing data is available for eligible pay-as-you-go accounts; Enterprise contracts are not supported.

Cloudflare® is a trademark and/or registered trademark of Cloudflare, Inc. in the United States and other jurisdictions. Billing Helper for Cloudflare® is independent and is not affiliated with, sponsored by or endorsed by Cloudflare.

## 简体中文

**名称（30/30 字符）：** Billing Helper for Cloudflare®  
**副标题（7/30 字符）：** 账单费用与趋势  
**关键词（90/100 UTF-8 字节）：** `账单管理,用量统计,费用分析,预算提醒,费用趋势,订阅管理,估算预测`

**描述：**

在 Mac 上随时了解 Cloudflare® 账户账单。Billing Helper for Cloudflare® 将费用、账期和估算带到原生菜单栏应用中。

• 查看当前固定订阅费用、已产生的按量费用，以及账期结束时的预计总费用。
• 查看各产品的费用占比和本账期累计费用走势。
• 切换账户和账期，查看上次检查时间，并在账单数据不完整时了解原因。
• 查看各产品的免费额度用量，按近期每日用量预估用完日期和超额费用。
• 按账户和币种设置可选的预算提醒，并可在免费额度用完前收到提醒。

可先用内置且可移除的示例账户体验，示例数据保存在本机。使用只读 Cloudflare API 令牌连接真实账户。令牌保存在 macOS 钥匙串，账单数据直接从 Cloudflare 获取并缓存在本机；账户与域名的授权范围由你控制。

估算不等于账单，且不含税费和抵扣。数据可用性和更新时间取决于 Cloudflare 及令牌权限。按量计费数据适用于符合条件的按量付费账户，不支持 Enterprise 合同账户。

Cloudflare® 是 Cloudflare, Inc. 在美国及其他国家和地区的商标和/或注册商标。Billing Helper for Cloudflare® 是独立应用，与 Cloudflare 无关联，也未获其赞助或背书。

## What's New in 1.1.0

**English:**

• Free-quota tracking: each product now shows how much of its free allowance is used, the daily usage over the last 7 days, the projected run-out date and the estimated overage.
• Free-quota alerts: an overview banner and menu bar indicator, plus optional notifications before a quota runs out and when it is used up.
• Products that may incur charges stay visible even before they do.
• A more compact Overview: the current cost sits next to the account and cycle pickers, and each product row shows a single bar.
• Clearer messages when Cloudflare cannot be reached or a Keychain token is missing; pasting a token again restores existing accounts.

**简体中文：**

• 免费额度追踪：每个产品显示免费额度已用比例、近 7 天日均用量、预计用完日期和预计超额费用。
• 免费额度预警：概览页提醒与菜单栏标记，并可选择在额度即将用完和已用完时收到通知。
• 可能产生费用的产品即使尚未产生费用也会保持显示。
• 概览页更紧凑：当前费用与账户、账期选择并排，每个产品只显示一条进度条。
• 连不上 Cloudflare 或钥匙串缺少令牌时提示更明确；重新粘贴令牌即可恢复已有账户。

## Shared fields and submission status

- **Support URL:** https://meathill.com/about — entered in App Store Connect and verified publicly accessible.
- **Privacy:** the bilingual privacy policy URL is set for English and Simplified Chinese. The “No Data Collected” App Privacy response was published after the account holder confirmed that requests are not retained beyond servicing.
- **Price and availability:** Free in all 175 App Store territories, with automatic release after approval. The optional StoreKit tip does not unlock features.
- **Build:** 1.0.0 (3), the universal Sample-account build with StoreKit support and matching dSYMs, was uploaded and submitted. Builds 1 and 2 are older archives and are not selected.
- **Category and rating:** Productivity and 4+ are set in App Store Connect. The account holder confirmed and authorized the declaration that the app accesses third-party content with the necessary rights or lawful permission; it was saved before submission.
- **Review contact:** all four contact fields were verified populated before submission; private contact details are not recorded here.
- **Review access:** the universal 1.0.0 build contains a built-in removable Sample account for local review without app login. Real Cloudflare API access still requires an eligible account and read-only token. The [review notes](app-review-notes.md) accurately describe this limitation; do not copy personal credentials or billing data into App Store Connect. Whether the Sample is sufficient for review is determined by Apple.
- **About / voluntary support:** the optional consumable `com.meathill.CloudflareBillingHelper.tip.coffee` was submitted with the app. English and Simplified Chinese names, descriptions, review notes and a review screenshot are configured. Its existing US base price is $4.99, with automatic regional equivalents, including CNY 38.00 in mainland China.
- **Screenshots:** all eight Overview, Accounts, Budget and About screenshots were replaced with the 1440×900 RGB PNGs in `store-assets/build3/`, with the account holder's approval. Billing screenshots use isolated Sample data, and About shows the new name and StoreKit support wording. Earlier local screenshots and the old App Store asset-library entries were retained. For 1.1.0 (6), regenerated screenshots with the compact Overview and the Sample account's free-quota row are in `store-assets/build6/`.
- **Cloudflare trademark:** the English and Simplified Chinese App Store titles were saved as “Billing Helper for Cloudflare®,” following Cloudflare’s [Trademark Guidelines](https://www.cloudflare.com/trademark/) example of a referential “for Cloudflare” name. A trademark attribution and non-endorsement statement are included in the listing and About page. The Content Rights declaration is separate from, and does not claim, Cloudflare endorsement.

References: [Apple app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/), [version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information), [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/), [review guidelines](https://developer.apple.com/app-store/review/guidelines/).
