#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
xcodebuild -project CloudflareBillingHelper.xcodeproj -scheme CloudflareBillingHelper -configuration Release -archivePath "$PWD/build/CloudflareBillingHelper.xcarchive" ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO archive
