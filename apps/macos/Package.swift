// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MacApp", platforms: [.macOS(.v13)], dependencies: [.package(path: "Packages/BillingCore")], targets: [
    .executableTarget(name: "MacApp", dependencies: [.product(name: "BillingCore", package: "BillingCore")], path: "App", exclude: ["Info.plist", "CloudflareBillingHelper.entitlements", "Assets.xcassets", "PrivacyInfo.xcprivacy"]),
    .testTarget(name: "MacAppTests", dependencies: ["MacApp", .product(name: "BillingCore", package: "BillingCore")], path: "Tests")
])
