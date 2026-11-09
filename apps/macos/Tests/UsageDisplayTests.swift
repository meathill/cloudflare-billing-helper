import XCTest
import BillingCore
@testable import MacApp

@MainActor final class UsageDisplayTests: XCTestCase {
    func testProductAmountUsesNormalizedTotalNotSumOfDailyRows() throws {
        let cycle = Cycle(start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 200))
        let raw = [UsageCharge(id: "one", currency: "USD", cost: 9, period: cycle, serviceName: "KV")]
        let total = UsageProductTotal(serviceName: "KV", currency: "USD", cost: 3, source: "cumulative", isComplete: true)
        let snapshot = BillingSnapshot(accountID: "a", cycles: [cycle], totals: [], checkedAt: Date(), isComplete: true, usage: raw, selectedCycle: cycle, usageProductTotals: [total])
        let row = try XCTUnwrap(usageDisplayRows(snapshot: snapshot, cycle: cycle)?.first)
        XCTAssertEqual(row.cost, 3); XCTAssertEqual(row.sourceLabel, tr("Cloudflare accumulated cost", "Cloudflare 累计费用"))
    }
    func testOldCacheAndDifferentCycleDoNotProduceMisleadingSubtotal() {
        let cycle = Cycle(start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 200))
        let old = BillingSnapshot(accountID: "a", cycles: [cycle], totals: [], checkedAt: Date(), isComplete: true, usage: [UsageCharge(id: "one", currency: "USD", cost: 9, period: cycle, serviceName: "KV")], selectedCycle: cycle)
        XCTAssertNil(usageDisplayRows(snapshot: old, cycle: cycle))
        let total = UsageProductTotal(serviceName: "KV", currency: "USD", cost: 3, source: "cumulative", isComplete: true)
        let current = BillingSnapshot(accountID: "a", cycles: [cycle], totals: [], checkedAt: Date(), isComplete: true, selectedCycle: cycle, usageProductTotals: [total])
        XCTAssertNil(usageDisplayRows(snapshot: current, cycle: Cycle(start: cycle.start, end: cycle.end.addingTimeInterval(1))))
    }
    func testIncompleteAndUnrecognizedSourcesNeverDisplayAnAmount() throws {
        let cycle = Cycle(start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 200))
        let totals = [UsageProductTotal(serviceName: "Partial", currency: "USD", cost: 0, source: "period-sum", isComplete: false), UsageProductTotal(serviceName: "Unknown", currency: "USD", cost: 3, source: "unknown", isComplete: true), UsageProductTotal(serviceName: "Mixed", currency: "USD", cost: 4, source: "mixed", isComplete: true)]
        let snapshot = BillingSnapshot(accountID: "a", cycles: [cycle], totals: [], checkedAt: Date(), isComplete: false, selectedCycle: cycle, usageProductTotals: totals)
        let rows = try XCTUnwrap(usageDisplayRows(snapshot: snapshot, cycle: cycle))
        XCTAssertNil(rows[0].cost); XCTAssertNil(rows[1].cost); XCTAssertEqual(rows[2].cost, 4); XCTAssertEqual(rows[2].sourceLabel, tr("Mixed cost sources", "混合费用来源"))
    }
}
