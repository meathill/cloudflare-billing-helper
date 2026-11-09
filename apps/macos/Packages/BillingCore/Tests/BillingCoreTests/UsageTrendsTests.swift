import Foundation
import XCTest
@testable import BillingCore
final class UsageTrendsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 0)
    private func observation(_ name: String, _ currency: String = "USD", _ from: Int, _ to: Int, _ cumulative: Decimal?) -> UsageTrendObservation {
        UsageTrendObservation(serviceName: name, currency: currency, period: Cycle(start: start.addingTimeInterval(Double(from) * 86400), end: start.addingTimeInterval(Double(to) * 86400)), cumulative: cumulative)
    }
    private func observation(_ name: String, _ from: Int, _ to: Int, _ cumulative: Decimal?) -> UsageTrendObservation { observation(name, "USD", from, to, cumulative) }
    private func product(_ name: String, _ cost: Decimal, source: String = "cumulative") -> UsageProductTotal { product(name, "USD", cost, source: source) }
    private func product(_ name: String, _ currency: String = "USD", _ cost: Decimal, source: String = "cumulative") -> UsageProductTotal { UsageProductTotal(serviceName: name, currency: currency, cost: cost, source: source, isComplete: true) }
    private var cycle: Cycle { Cycle(start: start, end: start.addingTimeInterval(10 * 86400)) }
    func testSynchronizedDimensionsCurrenciesAndNegativeAdjustment() {
        let dimensions = [
            [observation("KV", 0, 1, 2), observation("KV", 1, 2, 1)],
            [observation("KV", 0, 1, 4), observation("KV", 1, 2, 5)],
            [observation("Other", 0, 1, 1), observation("Other", 1, 2, 2)],
            [observation("EU", "EUR", 0, 1, 3), observation("EU", "EUR", 1, 2, 4)]
        ]
        let result = UsageTrendBuilder.build(cycle: cycle, now: cycle.end, dimensions: dimensions, products: [product("KV", 6), product("Other", 2), product("EU", "EUR", 4)], totals: [CurrencyTotals(currency: "USD", fixedCost: 0, usageCost: 8, forecastCost: nil), CurrencyTotals(currency: "EUR", fixedCost: 0, usageCost: 4, forecastCost: nil)], usageComplete: true)
        let kv = result.products.first { $0.serviceName == "KV" }!
        XCTAssertEqual(kv.points.map(\.cost), [6, 6])
        XCTAssertEqual(kv.points.map(\.startsSegment), [true, false])
        XCTAssertTrue(kv.isComplete)
        XCTAssertEqual(result.totals.first { $0.currency == "USD" }?.points.map(\.cost), [7, 8])
        XCTAssertEqual(result.totals.first { $0.currency == "EUR" }?.points.map(\.cost), [3, 4])
    }
    func testMissingDimensionNeverZeroFilledAndGapSegments() {
        let dimensions = [
            [observation("KV", 0, 1, 1), observation("KV", 1, 2, 2), observation("KV", 2, 3, 3)],
            [observation("KV", 0, 1, 10), observation("KV", 2, 3, 30)]
        ]
        let result = UsageTrendBuilder.build(cycle: cycle, now: cycle.end, dimensions: dimensions, products: [product("KV", 33)], totals: [CurrencyTotals(currency: "USD", fixedCost: 0, usageCost: 33, forecastCost: nil)], usageComplete: true)
        XCTAssertEqual(result.products.first?.points.map(\.cost), [11, 33])
        XCTAssertEqual(result.products.first?.points.map(\.startsSegment), [true, true])
        XCTAssertFalse(result.products.first!.isComplete)
        XCTAssertEqual(result.totals.first?.points.map(\.startsSegment), [true, true])
        XCTAssertFalse(result.totals.first!.isComplete)
    }
    func testMissingCumulativeFallbackNoTrendAndUnknownService() {
        let dimensions = [[observation("", 0, 1, 1), observation("", 1, 2, nil)], [observation("Other", 0, 1, 4)]]
        let result = UsageTrendBuilder.build(cycle: cycle, now: cycle.end, dimensions: dimensions, products: [product("", 3, source: "period-sum"), product("Other", 4)], totals: [CurrencyTotals(currency: "USD", fixedCost: 0, usageCost: 7, forecastCost: nil)], usageComplete: true)
        XCTAssertEqual(result.products.map(\.serviceName), ["Other"])
        XCTAssertTrue(result.totals.isEmpty)
    }
    func testAmbiguousDuplicateAndSourceCutoff() {
        let dimensions = [[observation("X", 0, 1, 1), observation("X", 0, 1, 2), observation("X", 1, 2, 4), observation("X", 2, 3, 8)]]
        let result = UsageTrendBuilder.build(cycle: cycle, now: start.addingTimeInterval(2 * 86400), dimensions: dimensions, products: [product("X", 4)], totals: [CurrencyTotals(currency: "USD", fixedCost: 0, usageCost: 4, forecastCost: nil)], usageComplete: false)
        XCTAssertEqual(result.products.first?.points.map(\.cost), [4])
        XCTAssertFalse(result.products.first!.isComplete)
        XCTAssertTrue(result.products.first!.points[0].startsSegment)
    }
    func testOldSnapshotWithoutTrendFieldsDecodes() throws {
        let original = BillingSnapshot(accountID: "account", cycles: [], totals: [], checkedAt: start, isComplete: false)
        let data = try JSONEncoder().encode(original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "usageTrends"); json.removeValue(forKey: "usageTotalTrends")
        let decoded = try JSONDecoder().decode(BillingSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.usageTrends); XCTAssertNil(decoded.usageTotalTrends)
    }
}
extension UsageTrendsTests {
    func testDuplicateWithMissingCumulativeAndOverlapExcludeAmbiguousPoints() {
        let dimensions = [[observation("X", 0, 1, 1), observation("X", 0, 1, nil), observation("X", 1, 2, 4), observation("X", 1, 3, 7), observation("X", 3, 4, 8)]]
        let result = UsageTrendBuilder.build(cycle: cycle, now: cycle.end, dimensions: dimensions, products: [product("X", 8)], totals: [CurrencyTotals(currency: "USD", fixedCost: 0, usageCost: 8, forecastCost: nil)], usageComplete: false)
        XCTAssertEqual(result.products.first?.points.map(\.cost), [8])
        XCTAssertFalse(result.products.first!.isComplete)
    }
}
extension UsageTrendsTests {
    func testNegativeTotalsAreNotClampedAndFutureIsNotShown() {
        let dimensions = [[observation("Refund", 0, 1, 2), observation("Refund", 1, 2, -1), observation("Refund", 2, 3, 10)]]
        let result = UsageTrendBuilder.build(cycle: cycle, now: start.addingTimeInterval(2 * 86400), dimensions: dimensions, products: [product("Refund", -1)], totals: [CurrencyTotals(currency: "USD", fixedCost: 0, usageCost: -1, forecastCost: nil)], usageComplete: true)
        XCTAssertEqual(result.products.first?.points.map(\.cost), [2, -1])
        XCTAssertEqual(result.totals.first?.points.map(\.cost), [2, -1])
        XCTAssertFalse(result.products.first!.isComplete)
    }
}
