# AGENTS.md

## Layout
- `apps/extension`: WXT + Vue browser extension (content panel on the Cloudflare billing page).
- `apps/macos`: SwiftUI menu bar app; billing logic lives in the `Packages/BillingCore` Swift package.
- `packages/billing-spec/catalog.json`: shared product catalog (free allowances, units, kinds, catalog prices) used by both apps.

## Verification
- Extension tests: `pnpm test:extension`; type check: `pnpm compile`.
- macOS tests: `pnpm test:macos` (BillingCore package tests + app tests via `swift test`).
- macOS Xcode build: `pnpm build:macos`. New Swift files under `apps/macos/App` must also be added to `CloudflareBillingHelper.xcodeproj`; files in `Packages/BillingCore` are picked up automatically.
- `pnpm build:extension` bumps the extension patch version; avoid running it just to verify.

## Free-quota projections
- Extension: `lib/math.ts` projects cumulative products from the recent daily growth between local snapshots (`recentDailyRate`, 7-day window), falling back to the cycle average.
- macOS: `UsageQuotaBuilder` (BillingCore) uses `ConsumedQuantity` / `CumulatedPricingQuantity` from `/billable-usage`, with the same 7-day recent rate.
