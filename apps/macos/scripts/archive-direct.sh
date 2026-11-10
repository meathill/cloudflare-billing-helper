#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

build="${CFBH_DIRECT_BUILD:-6}"
output="${CFBH_DIRECT_OUTPUT:-$PWD/build/direct-$build}"
archive="$output/CloudflareBillingHelper.xcarchive"
if [ -e "$archive" ]; then
  echo "归档已存在，请设置新的 CFBH_DIRECT_OUTPUT，避免覆盖：$archive" >&2
  exit 1
fi
mkdir -p "$output"

# 仅官网包启用 BMC；默认 Xcode 配置仍为 App Store 的 StoreKit 渠道。
xcodebuild -project CloudflareBillingHelper.xcodeproj \
  -scheme CloudflareBillingHelper -configuration Release \
  -derivedDataPath "$output/DerivedData" -archivePath "$archive" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=FNXZ69UX8K \
  CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY='Apple Development' \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=DIRECT_DISTRIBUTION \
  CURRENT_PROJECT_VERSION="$build" ENABLE_HARDENED_RUNTIME=YES \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  DEBUG_INFORMATION_FORMAT=dwarf-with-dsym archive
