// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "BillingCore", platforms: [.macOS(.v13)], products: [.library(name: "BillingCore", targets: ["BillingCore"])], targets: [.target(name: "BillingCore"), .testTarget(name: "BillingCoreTests", dependencies: ["BillingCore"])])
