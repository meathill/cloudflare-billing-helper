import XCTest
@testable import MacApp

final class DistributionChannelTests: XCTestCase {
    func testSupportDestinationMatchesBuildChannel() {
        #if DIRECT_DISTRIBUTION
        XCTAssertFalse(DistributionChannel.usesStoreKit)
        XCTAssertEqual(DistributionChannel.supportURL?.absoluteString, "https://buymeacoffee.com/meathill")
        #else
        XCTAssertTrue(DistributionChannel.usesStoreKit)
        XCTAssertNil(DistributionChannel.supportURL)
        #endif
    }
}
