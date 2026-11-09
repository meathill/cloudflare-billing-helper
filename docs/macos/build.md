# Build and archive

Requires Xcode and the macOS SDK. `apps/macos/scripts/build.sh` builds a debug app. `apps/macos/scripts/archive.sh` creates an unsigned universal archive in `apps/macos/build/CloudflareBillingHelper.xcarchive`. Signing and App Store submission are separate release steps. Use `open path/to/CloudflareBillingHelper.app --args --show-settings` to open Settings on launch.

## Connect an account

On the Accounts page, open the read-only API token creation link. In Cloudflare, confirm the prefilled Account > Billing > Read, Account > Account Settings > Read, and Zone > Zone > Read permissions and create the token. The link initially includes all accounts and zones; narrow the resource scope as appropriate. Paste the token directly into the app's secure field, find accounts, then select and add them. The app checks billing access separately after import. Advanced manual account ID and token entry remains available.

Cloudflare's [official MCP repository](https://github.com/cloudflare/mcp/blob/main/AGENTS.md#refused-api-calls) notes that its OAuth authorization cannot access billing endpoints; this app uses a read-only API token instead. Keep the token local and paste it only into the app.

The Overview page shows the current account, a Refresh billing action, and reasons when billing data is incomplete. Waiting and loading are shown as neutral states. Metered totals and product subtotals use the latest cumulative cost for each complete dimension; raw daily records remain available.

## Isolated design preview

The internal DesignPreview is not a feature of the shipping app. It has a separate bundle identifier and uses sample data, separate defaults and an in-memory token store. It does not read or alter the real app's accounts or credentials. Build it and launch its window with:

```bash
bash apps/macos/scripts/build-design-preview.sh
open /tmp/cfbh-design-preview/Build/Products/Debug/CloudflareBillingHelper.app
```

Export the five pages in English and Chinese, light and dark (20 images) with:

```bash
bash apps/macos/scripts/export-design-previews.sh
# Optional first argument: destination directory
```

The default destination is `docs/macos/design/previews/`. To export a minimum-size layout with long sample names:

```bash
/tmp/cfbh-design-preview/Build/Products/Debug/CloudflareBillingHelper.app/Contents/MacOS/CloudflareBillingHelper \
  --export-previews docs/macos/design/previews \
  --preview-language en --preview-appearance light --preview-view settings \
  --preview-page accounts --preview-long-names --preview-minimum
```

To regenerate the English and Simplified Chinese App Store screenshots with the isolated removable Sample account, run:

```bash
bash apps/macos/scripts/export-store-assets.sh
```

This writes the four 1440 × 900 product screenshots per language to `docs/macos/store-assets/` without using live Cloudflare credentials or requests.

These images are rendered from native views with sample data. The visual direction and generation prompt are in `docs/macos/design/`.

## 官网直装发行

官网渠道使用 `DIRECT_DISTRIBUTION` 编译条件，关于页链接到 BMC，不包含 StoreKit 打赏实现。默认 Xcode 构建仍使用 StoreKit，已提交的 App Store 1.0.0（3）不受影响。不要从 App Store 归档重新签名生成官网包。

```bash
# 构建通用归档，默认构建号为 5，启用 Hardened Runtime
pnpm archive:macos:direct
# 使用 Xcode 账号与 Developer ID 云端签名，上传 Apple 公证
xcodebuild -exportArchive \
  -archivePath "$PWD/apps/macos/build/direct-5/CloudflareBillingHelper.xcarchive" \
  -exportOptionsPlist "$PWD/apps/macos/ExportOptions-Direct.plist" \
  -exportPath "$PWD/apps/macos/build/direct-5/upload" \
  -allowProvisioningUpdates
# 公证处理完成后，导出已附加票据的应用
xcodebuild -exportNotarizedApp \
  -archivePath "$PWD/apps/macos/build/direct-5/CloudflareBillingHelper.xcarchive" \
  -exportPath "$PWD/apps/macos/build/direct-5/notarized"
# 校验签名、票据与 Gatekeeper，再生成含 Applications 快捷方式的 DMG
pnpm package:macos:direct
```

如需新构建，使用 `CFBH_DIRECT_BUILD` 设置新构建号，归档和打包命令使用同一个值。脚本拒绝覆盖既有归档或 DMG，且拒绝打包未完成 Developer ID 签名、公证的应用。DMG 内的应用已签名、公证；DMG 容器本身不单独签名。

本次文件位于 `apps/macos/build/direct-5/releases/`，发布到 R2 `blog`：

- Mac：`downloads/cloudflare-billing-helper/macos/1.0.0-5/billing-helper-for-cloudflare-1.0.0-5-universal.dmg`
- 扩展：`downloads/cloudflare-billing-helper/extension/0.2.0/cloudflare-billing-helper-0.2.0-chrome.zip`
- 两个文件均附带同路径 `.sha256`，公开域名为 `https://i.meathill.com`。

R2 使用版本化对象与 `public, max-age=31536000, immutable`，不覆盖旧文件。更新官网 `src/lib/billing-helper-release.ts` 前，必须先验证新文件可下载、回读哈希与本地一致；网站位于相邻的 `blog-2026` 仓库。

渠道回归：

```bash
swift test --package-path apps/macos --build-system native
swift test --package-path apps/macos --build-system native -Xswiftc -DDIRECT_DISTRIBUTION
```
