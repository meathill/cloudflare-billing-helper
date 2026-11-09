#!/bin/sh
set -eu
cd "$(dirname "$0")/../../.."
app="/tmp/cfbh-design-preview/Build/Products/Debug/CloudflareBillingHelper.app/Contents/MacOS/CloudflareBillingHelper"
bundle="/tmp/cfbh-design-preview/Build/Products/Debug/CloudflareBillingHelper.app"
if [ ! -x "$app" ] || [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist" 2>/dev/null || true)" != "com.meathill.CloudflareBillingHelper.DesignPreview" ]; then
  echo "Build the isolated DesignPreview first: bash apps/macos/scripts/build-design-preview.sh" >&2
  exit 1
fi
destination="${1:-$PWD/docs/macos/screenshots}"
for language in en zh; do
  for appearance in light dark; do
    for view in panel settings; do
      if [ "$view" = settings ]; then
        "$app" --export-previews "$destination" --preview-language "$language" --preview-appearance "$appearance" --preview-view settings --preview-page settings
      else
        "$app" --export-previews "$destination" --preview-language "$language" --preview-appearance "$appearance" --preview-view panel
      fi
    done
  done
done
