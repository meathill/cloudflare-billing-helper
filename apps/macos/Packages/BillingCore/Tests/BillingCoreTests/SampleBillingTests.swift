import XCTest
@testable import BillingCore
final class SampleBillingTests: XCTestCase {
    func testLegacyAccountsAndExplicitSource() throws {
        let decoder = JSONDecoder()
        let old = try decoder.decode(AccountProfile.self, from: Data(#"{"id":"abc","name":"existing"}"#.utf8))
        XCTAssertEqual(old.source, .cloudflare)
        let sample = try decoder.decode(AccountProfile.self, from: JSONEncoder().encode(SampleBilling.account))
        XCTAssertEqual(sample.source, .sample); XCTAssertEqual(sample.id, "local-sample-account")
        XCTAssertThrowsError(try decoder.decode(AccountProfile.self, from: Data(#"{"id":"local-sample-account","name":"x","source":null}"#.utf8)))
        XCTAssertThrowsError(try decoder.decode(AccountProfile.self, from: Data(#"{"id":"local-sample-account","name":"x","source":"unknown"}"#.utf8)))
    }
    func testCurrentMonthSyntheticDataAgrees() throws {
        let parser = ISO8601DateFormatter()
        let now = try XCTUnwrap(parser.date(from: "2028-02-16T12:34:00Z"))
        let snapshot = SampleBilling.snapshot(now: now)
        XCTAssertEqual(snapshot.accountID, SampleBilling.account.id)
        XCTAssertEqual(snapshot.selectedCycle?.start, parser.date(from: "2028-02-01T00:00:00Z"))
        XCTAssertEqual(snapshot.selectedCycle?.end, parser.date(from: "2028-03-01T00:00:00Z"))
        XCTAssertEqual(snapshot.sourceAsOf, parser.date(from: "2028-02-16T00:00:00Z"))
        XCTAssertEqual(snapshot.totals.first?.usageCost, Decimal(string: "1.65"))
        XCTAssertEqual(snapshot.totals.first?.total, Decimal(string: "6.65"))
        XCTAssertEqual(snapshot.totals.first?.forecastCost, Decimal(string: "8.19"))
        XCTAssertEqual(snapshot.usageProductTotals?.compactMap(\.cost).reduce(0, +), snapshot.totals.first?.usageCost)
        XCTAssertEqual(snapshot.usageTotalTrends?.first?.points.last?.cost, snapshot.totals.first?.usageCost)
        XCTAssertTrue(snapshot.usageTrends!.allSatisfy { trend in trend.points.last?.cost == snapshot.usageProductTotals?.first(where: { $0.serviceName == trend.serviceName })?.cost })
        XCTAssertTrue(snapshot.usage.allSatisfy { $0.period.end <= now })
    }
    func testFirstDayDoesNotInventObservations() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-01T00:00:00Z"))
        let snapshot = SampleBilling.snapshot(now: now)
        XCTAssertTrue(snapshot.usage.isEmpty)
        XCTAssertEqual(snapshot.totals.first?.usageCost, 0)
        XCTAssertNil(snapshot.sourceAsOf); XCTAssertNil(snapshot.totals.first?.forecastCost)
        XCTAssertTrue(snapshot.usageTrends!.isEmpty); XCTAssertTrue(snapshot.usageTotalTrends!.isEmpty)
    }
}
