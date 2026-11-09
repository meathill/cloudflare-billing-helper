#!/bin/sh
set -eu
cd "$(dirname "$0")/../../.."
bash apps/macos/scripts/build-design-preview.sh
app=/tmp/cfbh-design-preview/Build/Products/Debug/CloudflareBillingHelper.app/Contents/MacOS/CloudflareBillingHelper
bundle=/tmp/cfbh-design-preview/Build/Products/Debug/CloudflareBillingHelper.app
if [ ! -x "$app" ] || [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist" 2>/dev/null || true)" != "com.meathill.CloudflareBillingHelper.DesignPreview" ]; then
  echo "Build the isolated DesignPreview first: bash apps/macos/scripts/build-design-preview.sh" >&2
  exit 1
fi
for language in en zh; do
  destination="$PWD/docs/macos/store-assets/$language"
  mkdir -p "$destination"
  for page in overview accounts budget about; do
    "$app" --export-previews "$destination" \
      --preview-language "$language" \
      --preview-appearance light \
      --preview-view settings \
      --preview-page "$page" \
      --store-screenshot
  done
done
