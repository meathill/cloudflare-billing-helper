#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
xcodebuild -project CloudflareBillingHelper.xcodeproj -scheme CloudflareBillingHelper -configuration Debug -derivedDataPath /tmp/cfbh-design-preview PRODUCT_BUNDLE_IDENTIFIER=com.meathill.CloudflareBillingHelper.DesignPreview CODE_SIGNING_ALLOWED=NO build
