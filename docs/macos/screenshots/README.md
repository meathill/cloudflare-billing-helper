# Internal native-view screenshots

Build the isolated DesignPreview and export screenshots with sample data; the shipping app does not expose a Demo mode or screenshot export. The scripts use the separate DesignPreview bundle and reject a missing or mismatched bundle. A fresh export renders panel and settings views in English and Simplified Chinese, in light and dark appearance, at 1440 × 900 pixels. The retained panel and settings images are 1440 × 900. These are native-view renders, not interactive system-window screenshots.

```sh
bash apps/macos/scripts/build-design-preview.sh
bash apps/macos/scripts/export-previews.sh
```

For the five-page design set, use `bash apps/macos/scripts/export-design-previews.sh`; see [build instructions](../build.md) for preview launch and layout options. Do not use real credentials or billing data for screenshots.

## Mac App Store images

Run `bash apps/macos/scripts/export-store-assets.sh` to rebuild the isolated DesignPreview and export the four App Store pages (Overview, Accounts, Budget, About) in English and Simplified Chinese. It uses the removable local Sample fixture, light appearance, and the `--store-screenshot` path. Output files go to `docs/macos/store-assets/{en,zh}/` as 1440 × 900 PNGs without alpha. No live account, token, Keychain item, or Cloudflare request is used.
