import XCTest
import BillingCore
@testable import MacApp

@MainActor final class BillingVisualsTests: XCTestCase {
    func testOverviewLayoutUsesAvailableWidth() {
        XCTAssertFalse(usesWideOverview(contentWidth: 615))
        XCTAssertFalse(usesWideOverview(contentWidth: 699))
        XCTAssertTrue(usesWideOverview(contentWidth: 700))
        XCTAssertTrue(usesWideOverview(contentWidth: 815))
    }
    func testCycleProgressClampsBeforeAndAfterCycle() {
        let start = Date(timeIntervalSince1970: 0), cycle = Cycle(start: start, end: start.addingTimeInterval(10 * 86400))
        let before = cycleProgress(cycle: cycle, now: start.addingTimeInterval(-100))
        XCTAssertEqual(before.elapsed, 0); XCTAssertEqual(before.total, 10); XCTAssertEqual(before.fraction, 0)
        let inside = cycleProgress(cycle: cycle, now: start.addingTimeInterval(3.5 * 86400))
        XCTAssertEqual(inside.elapsed, 3); XCTAssertEqual(inside.fraction, 0.35, accuracy: 0.0001)
        let after = cycleProgress(cycle: cycle, now: cycle.end.addingTimeInterval(1))
        XCTAssertEqual(after.elapsed, 10); XCTAssertEqual(after.fraction, 1)
    }
    func testTrendSegmentsRespectExplicitGapsAndKeepNegativeAdjustments() {
        let start = Date(timeIntervalSince1970: 0), cycle = Cycle(start: start, end: start.addingTimeInterval(10 * 86400))
        let points = [UsageTrendPoint(at: start.addingTimeInterval(86400), cost: 4, startsSegment: true), UsageTrendPoint(at: start.addingTimeInterval(2 * 86400), cost: 5), UsageTrendPoint(at: start.addingTimeInterval(5 * 86400), cost: -2, startsSegment: true), UsageTrendPoint(at: start.addingTimeInterval(6 * 86400), cost: -1)]
        let segments = trendSegments(points, cycle: cycle)
        XCTAssertEqual(segments.map { $0.points.count }, [2, 2]); XCTAssertEqual(segments[1].points.first?.cost, -2)
    }
    func testObservedDomainUsesActualDatesAndDoesNotAddFutureDays() throws {
        let start = Date(timeIntervalSince1970: 0), cycle = Cycle(start: start, end: start.addingTimeInterval(30 * 86400))
        let first = UsageTrendPoint(at: start.addingTimeInterval(86400), cost: 1), last = UsageTrendPoint(at: start.addingTimeInterval(3 * 86400), cost: 3)
        let domain = try XCTUnwrap(observedTrendDomain(points: [first, last], cycle: cycle))
        XCTAssertEqual(domain.lowerBound, first.at); XCTAssertEqual(domain.upperBound, last.at)
        let one = try XCTUnwrap(observedTrendDomain(points: [first], cycle: cycle))
        XCTAssertLessThanOrEqual(one.upperBound, cycle.end); XCTAssertLessThan(one.lowerBound, one.upperBound)
    }
    func testUsageSharesRequireCompleteNonnegativeSameCurrencyDenominator() {
        let rows = [UsageDisplayRow(name: "A", currency: "USD", cost: 3, sourceLabel: ""), UsageDisplayRow(name: "B", currency: "USD", cost: 2, sourceLabel: "")]
        XCTAssertEqual(usageShareDenominator(rows: rows, reportedUsage: 5), 5)
        XCTAssertNil(usageShareDenominator(rows: rows, reportedUsage: 6)); XCTAssertNil(usageShareDenominator(rows: rows, reportedUsage: 0))
        XCTAssertNil(usageShareDenominator(rows: rows + [UsageDisplayRow(name: "Unknown", currency: "USD", cost: nil, sourceLabel: "")], reportedUsage: 5))
        XCTAssertNil(usageShareDenominator(rows: rows + [UsageDisplayRow(name: "Adjustment", currency: "USD", cost: -1, sourceLabel: "")], reportedUsage: 4))
    }
    func testZeroProductsCollapseButUnknownAndNegativeRemainVisible() {
        let rows = [UsageDisplayRow(name: "Zero", currency: "USD", cost: 0, sourceLabel: ""), UsageDisplayRow(name: "Unknown", currency: "USD", cost: nil, sourceLabel: ""), UsageDisplayRow(name: "Adjustment", currency: "USD", cost: -1, sourceLabel: "")]
        let partition = partitionProducts(rows)
        XCTAssertEqual(partition.zero.map(\.name), ["Zero"]); XCTAssertEqual(partition.visible.map(\.name), ["Unknown", "Adjustment"])
    }
    func testQuotaAlertsKeepZeroCostProductsVisibleAndOrderByUrgency() {
        let cycle = Cycle(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 30 * 86400))
        func quota(_ name: String, _ status: QuotaStatus, _ day: Double?) -> UsageQuota {
            UsageQuota(serviceName: name, currency: "USD", unit: "ops", used: 1, billable: 0, included: 2, includedSource: "catalog", asOf: cycle.start, dailyRate: 1, rateBasis: "cycle", projectedTotal: 30, exhaustionDate: day.map { cycle.start.addingTimeInterval($0 * 86400) }, status: status, projectedOverageCost: nil, points: [], isComplete: true)
        }
        let quotas = [quota("Late", .danger, 20), quota("Soon", .danger, 5), quota("Fine", .ok, nil), quota("Over", .exhausted, 9), quota("Close", .warn, nil)]
        let snapshot = BillingSnapshot(accountID: "a", cycles: [cycle], totals: [], checkedAt: cycle.start, isComplete: true, selectedCycle: cycle, usageQuotas: quotas)
        XCTAssertEqual(quotaAlerts(snapshot, cycle: cycle).map(\.serviceName), ["Over", "Soon", "Late"])
        XCTAssertTrue(quotaAlerts(snapshot, cycle: Cycle(start: cycle.start, end: cycle.end.addingTimeInterval(1))).isEmpty)
        let rows = ["Late", "Fine", "Close"].map { UsageDisplayRow(name: $0, currency: "USD", cost: 0, sourceLabel: "") }
        let partition = partitionProducts(rows) { row in usageQuota(for: row, in: snapshot).map { $0.status != .ok } ?? false }
        XCTAssertEqual(partition.visible.map(\.name), ["Late", "Close"]); XCTAssertEqual(partition.zero.map(\.name), ["Fine"])
    }
    func testOnlyCatalogEvidenceAssignsProductFamily() throws {
        let data = Data("[{\"key\":\"kv-storage\",\"name\":\"KV Storage\",\"family\":\"kv\",\"aliases\":[\"kv storage (gb\"]},{\"key\":\"workers-cpu-ms\",\"name\":\"Workers CPU ms\",\"family\":\"workers\"},{\"key\":\"r2-data-storage\",\"name\":\"R2 Data Storage\",\"family\":\"r2\"}]".utf8)
        let catalog = try ProductCatalog(data: data)
        XCTAssertEqual(productFamily("KV Storage", catalog: catalog), "kv")
        XCTAssertEqual(productFamily("KV something unknown", catalog: catalog), "other")
        XCTAssertEqual(shortProductName("Foo (EU)", catalog: catalog), "Foo (EU)")
        XCTAssertEqual(shortProductName("Foo (US)", catalog: catalog), "Foo (US)")
        XCTAssertEqual(productFamily("", catalog: catalog), "other")
        XCTAssertEqual(productFamily("Workers CPU ms (first 30M included)", catalog: catalog), "workers")
        XCTAssertEqual(shortProductName("Workers CPU ms (first 30M included)", catalog: catalog), tr("CPU time", "CPU 时间"))
        XCTAssertEqual(productFamily("R2 Data Storage (First 10GB)", catalog: catalog), "r2")
        XCTAssertEqual(productFamily("R2", catalog: catalog), "r2"); XCTAssertEqual(productFamily("Images", catalog: catalog), "images")
    }
}
