# Review and privacy notes

The app is a menu bar utility. Open its menu bar icon to access the main window and Settings. A built-in, removable Sample account is intended for local exploration without app login. It uses simulated data; reviewing the real Cloudflare connection still requires an authorized read-only token and eligible account. See the [draft review notes](app-review-notes.md), and verify the final build before submission.

For a real account, use the link on the Accounts page to create a read-only Cloudflare API token. Confirm Account > Billing > Read, Account > Account Settings > Read, and Zone > Zone > Read; the template initially includes all accounts and zones, and its resource scope can be narrowed. Paste the token directly into the app's secure field, find accounts and select those to add. Billing access is checked separately after import; advanced manual account ID and token entry is also available. The token is stored in macOS Keychain. Requests go directly to Cloudflare's official API; no third party receives credentials or billing data. Account metadata and billing snapshots are stored locally. Budget notifications are optional. The billable usage endpoint supports eligible pay-as-you-go accounts, not Enterprise contracts. Cloudflare's [official MCP notes](https://github.com/cloudflare/mcp/blob/main/AGENTS.md#refused-api-calls) explain that OAuth cannot access billing endpoints.

The About page identifies the product and its author, Meathill, an independent full-stack developer. Its voluntary support link opens an external browser; support does not unlock features, and the app does not collect payment information. Before App Store submission, verify the applicable regional rules and review treatment for the external support link against Apple’s [App Review Guidelines, sections 3.1.1 and 3.2.1](https://developer.apple.com/app-store/review/guidelines/#business); approval has not been established.

The release needs an Apple Developer team, a unique bundle identifier, signing, App Store Connect privacy disclosures and review of permission wording against current Cloudflare API token controls before submission. This repository does not upload or submit the app.

# 审核与隐私说明

应用位于菜单栏，可通过菜单栏图标打开主窗口和设置。内置的可移除示例账户用于无需登录地体验本机模拟数据；审核真实 Cloudflare 连接仍需要有权访问的只读令牌及适用账户。详见[审核备注草稿](app-review-notes.md)，提交前应核对最终构建。

真实账户可通过账户页的链接创建 Cloudflare 只读 API 令牌，确认 Account > Billing > Read、Account > Account Settings > Read 和 Zone > Zone > Read 三项权限。模板默认包含所有账户和域名，可按需缩小资源范围。将 Token 直接粘贴到本机应用的安全输入框，读取账户并勾选添加；应用随后单独检查账单权限。高级设置仍可手动输入账户 ID 和令牌。令牌保存在 macOS 钥匙串，应用直接访问 Cloudflare 官方 API，不向第三方发送令牌或账单数据；账户元数据与账单快照保存在本机，预算通知可选。可计费用量接口仅支持符合条件的按量付费账户，不支持 Enterprise 合同账户。[Cloudflare 官方 MCP 说明](https://github.com/cloudflare/mcp/blob/main/AGENTS.md#refused-api-calls)指出 OAuth 无法访问账单接口。

关于页介绍产品及作者肉山（Meathill），一位独立全栈开发者。自愿支持链接会打开外部浏览器，不解锁应用功能，应用也不收集支付信息。提交 App Store 前需参照 [Apple 审核指南 3.1.1 和 3.2.1](https://developer.apple.com/app-store/review/guidelines/#business)，确认外部支持链接在发行地区的适用规则及审核处理；目前未获得审核批准。

正式提交前仍需配置 Apple Developer 团队、唯一 Bundle ID、签名及 App Store Connect 隐私信息，并根据 Cloudflare 当前令牌权限选项核对操作说明。本仓库不自动上传或提交应用。
