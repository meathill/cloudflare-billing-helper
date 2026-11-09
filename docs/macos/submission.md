# Mac App Store submission

## Submitted November 5, 2026

- App: Billing Helper for Cloudflare (registered trademark attribution is included in the submitted listing).
- App Store Connect app ID: `6830777105`.
- Submitted at: November 5, 2026, 14:04 China Standard Time (UTC+08:00).
- Submission ID: `48339278-09c5-459c-a85a-4c725247479d`.
- Both submitted items were verified as **Waiting for Review** in App Store Connect.
- The account holder explicitly approved the final submission. Automatic release after approval remains selected.

[Open the submission in App Store Connect](https://appstoreconnect.apple.com/apps/6830777105/distribution/reviewsubmissions/details/48339278-09c5-459c-a85a-4c725247479d).

## Submitted items

1. macOS App 1.0.0, build 3.
2. Coffee Tip, a consumable with product ID `com.meathill.CloudflareBillingHelper.tip.coffee` and Apple ID `6830959441`.

The tip retains the previously selected US base price of $4.99, with automatic regional equivalents including CNY 38.00. It has English and Simplified Chinese metadata, review notes and an About-page screenshot. It does not unlock features.

## Build and validation

The old build 2 still contained the external support link. Build 3 was archived from the StoreKit implementation, signed and uploaded with Xcode's automatic signing. The universal archive and its dSYMs are retained locally at:

```text
apps/macos/build/CloudflareBillingHelper-StoreKit-Build3.xcarchive
```

The archive contains both `arm64` and `x86_64` slices. Its executable contains the intended StoreKit product ID and no old `buymeacoffee` link. The ambiguous SwiftUI/StoreKit `Transaction` references were qualified as `StoreKit.Transaction` to fix the release build.

Validation completed:

- BillingCore: 38 tests passed.
- macOS app: 44 tests passed.
- Universal Release archive and isolated Debug preview build succeeded.
- Xcode reported `Upload succeeded` and `EXPORT SUCCEEDED`.
- App Store Connect accepted the two-item submission and reported both items waiting for review.

The default Swift test build engine stalled in its SDK stat-cache step, so the app tests were run successfully with:

```sh
swift test --package-path apps/macos --scratch-path /tmp/cfbh-submit-tests --build-system native
```

No real-money or sandbox tip purchase was performed during this submission session. Compilation and submission acceptance do not establish purchase-flow behavior or guarantee App Review approval.

## Listing and review access

- English and Simplified Chinese names, descriptions and keywords were aligned with [the listing materials](store-listing.md).
- The account holder authorized the third-party Content Rights declaration; persistence was verified before submission.
- All eight screenshots were replaced with the RGB 1440x900 assets in `store-assets/build3/en/` and `store-assets/build3/zh/`. Earlier local files and App Store asset-library entries were preserved.
- All four review-contact fields were verified populated, without copying private details into the repository.
- App login is not required to explore the local Sample account. Live Cloudflare access still requires an eligible account and an authorized read-only token, as described in [the review notes](app-review-notes.md).

App Store Connect's App Information page initially kept its Save button disabled despite local edits. Reloading that page restored the current form. Successful save responses and the subsequent submission validation confirmed that the names and Content Rights declaration were persisted.
