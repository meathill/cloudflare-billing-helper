#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# 开发签名后，钥匙串按团队和 bundle ID 授权。未登记的 Mac 需要 -allowProvisioningDeviceRegistration。
xcodebuild -project CloudflareBillingHelper.xcodeproj -scheme CloudflareBillingHelper -configuration Debug -derivedDataPath build/DerivedData \
  DEVELOPMENT_TEAM=FNXZ69UX8K CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY='Apple Development' \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
