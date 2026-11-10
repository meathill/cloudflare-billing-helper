# macOS design

A calm, native billing utility for quick checks during the workday. Follow system light and dark appearance, preserve keyboard and VoiceOver access, and keep account data and refresh state legible. The main window uses a sidebar and a structured main area for Overview, Accounts, Budget alerts, Settings and About; the menu bar panel stays compact. The concept in `../../docs/macos/design/sidebar-accounts-concept-v1.png` is a visual direction, not a source of real account data.

## Visual identity

- Reuse the project's orange lightning and quota-bar mark from `BrandMark.imageset`. It is the app's mark, not the official Cloudflare cloud logo. Label it “Billing Helper” and “for Cloudflare”; Chinese may use “Cloudflare 费用助手” as the subtitle.
- The brand accent is `#F6821F`, used sparingly for the mark, selected navigation and primary actions. Use dark ink on orange fills; use the appearance-aware `accentText` role for orange text.
- Dark: background `#202225`, sidebar `#292B2E`, section `#2B2D31`, separator `#414347`, text `#F3F1EB`, secondary `#A2A5AA`. Light: warm background `#F6F1E9`, sidebar `#EFE9DF`, section `#FAF7F1`, separator `#D5CCC0`, text `#34312D`, secondary `#68625C`. Avoid pure black or white and full-window gradients.
- System fonts: page titles 26–30 pt, section headings 16–17 pt, body 13 pt. Spacing follows 8 / 12 / 16 / 24 / 32 pt; section corners are 12 pt with a 1 pt border.
- Use one semantic section surface for related content, never nested cards. Status uses words as well as color; ordinary waiting and loading are neutral, with warning and error colors reserved for actionable states. Preserve cached billing data and show its freshness when a refresh fails.

`BrandStyle.swift` owns shared appearance roles, mark, header, section, status pill and secondary text styling. Test both appearances and localizations with isolated DesignPreview sample data; never use real credentials or billing values in screenshots.

## Billing visualizations

- Keep the billing cycle and source cutoff next to the current cost. The separate period progress bar indicates elapsed time in the billing cycle, not spending or quota. Distinguish current fixed and metered components, unavailable or incomplete data, and the estimated cycle forecast in words.
- A cost-share bar represents a product's share of an explicitly identified same-currency total. Show the amount and percentage with the bar; do not imply it is free-quota usage. If the denominator is zero or incomplete, or currencies differ, show an unavailable state instead of a misleading percentage.
- The Overview keeps billing controls and the current cost summary in one top row, followed directly by product details; there is no separate trend or alert section. Each product row may show a compact cumulative cost line labeled by its dates; leave unknown or incomplete intervals as gaps rather than filling them with zero.
- Each product row shows a single bar. With a known free allowance it is a free-quota bar comparing consumed quantity (Cloudflare `ConsumedQuantity`) with the allowance, inferred from the billed quantity once Cloudflare prices usage, otherwise from the shared catalog; the cost share then appears as text. Without an allowance the row shows the cost-share bar. Color quota bars by status and always state the status in words; label exhaustion dates and overage as estimates from recent daily usage. Keep zero-cost products visible while their quota needs attention or may incur charges.
- Keep product rows spacious and ordered by cost, with exact values and accessible text in addition to color and graphics. Use the existing light/dark semantic palette and the same section hierarchy; avoid nested cards.
