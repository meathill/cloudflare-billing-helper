#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Use the existing Development identity for the already registered app ID.
# Provisioning updates are enabled only to synchronize/create the matching profile.
# This does not enable device registration, upload, or export.
archive_path="${CFBH_DEVELOPMENT_ARCHIVE_PATH:-$PWD/build/CloudflareBillingHelper-Development.xcarchive}"
xcodebuild -project CloudflareBillingHelper.xcodeproj \
  -scheme CloudflareBillingHelper \
  -configuration Release \
  -derivedDataPath /tmp/cfbh-appstore-development-derived \
  -archivePath "$archive_path" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=FNXZ69UX8K \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY='Apple Development'  \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
  archive
