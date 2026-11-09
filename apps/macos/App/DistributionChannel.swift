import Foundation

enum DistributionChannel {
    #if DIRECT_DISTRIBUTION
    static let usesStoreKit = false
    static let supportURL = URL(string: "https://buymeacoffee.com/meathill")
    #else
    static let usesStoreKit = true
    static let supportURL: URL? = nil
    #endif
}
