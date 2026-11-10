#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

output="${CFBH_DIRECT_OUTPUT:-$PWD/build/direct-${CFBH_DIRECT_BUILD:-6}}"
app="${1:-$output/notarized/CloudflareBillingHelper.app}"
binary="$app/Contents/MacOS/CloudflareBillingHelper"
codesign --verify --deep --strict "$app"
if ! codesign -dv --verbose=2 "$app" 2>&1 | grep -q 'Authority=Developer ID Application:'; then
  echo "需要 Developer ID Application 签名，不能打包开发版或 App Store 版。" >&2
  exit 1
fi
xcrun stapler validate "$app"
spctl --assess --type execute "$app"
xcrun lipo -verify_arch arm64 "$binary"
xcrun lipo -verify_arch x86_64 "$binary"
if ! strings "$binary" | grep -qF 'https://buymeacoffee.com/meathill'; then
  echo "不是 BMC 官网渠道构建，拒绝打包。" >&2
  exit 1
fi

version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Contents/Info.plist")
filename="billing-helper-for-cloudflare-$version-$build-universal.dmg"
releases="$output/releases"
image="$releases/$filename"
if [ -e "$image" ]; then
  echo "安装包已存在，不覆盖：$image" >&2
  exit 1
fi
mkdir -p "$releases"
staging=$(mktemp -d "${TMPDIR:-/tmp/}cfbh-direct-dmg.XXXXXX")
ditto "$app" "$staging/CloudflareBillingHelper.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname 'Billing Helper for Cloudflare' \
  -srcfolder "$staging" -format UDZO "$image"
hdiutil verify "$image"
(cd "$releases" && shasum -a 256 "$filename" > "$filename.sha256")
printf '\n%s\n' "$image"
