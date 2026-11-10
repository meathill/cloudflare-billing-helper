import Foundation
import XCTest
@testable import BillingCore

final class UsageQuotaTests: XCTestCase {
    private let parser = ISO8601DateFormatter()
    private let catalog = try! ProductCatalog(data: Data(#"""
    [
      {"key":"kv-list-operations","name":"KV List Operations","family":"kv","unit":"ops","included":1000000,"kind":"cumulative","unitPrice":0.000005},
      {"key":"kv-storage","name":"KV Storage","family":"kv","unit":"GB-months","included":1,"kind":"gauge","unitPrice":0.5}
    ]
    """#.utf8))
    private var february: Cycle { Cycle(start: parser.date(from: "2026-02-01T00:00:00Z")!, end: parser.date(from: "2026-03-01T00:00:00Z")!) }
    private func day(_ index: Int, _ consumed: Double?, service: String = "KV List Operations", dimension: String = "a", billable: Double? = 0, cost: Decimal = 0) -> UsageQuantityObservation {
        let start = february.start.addingTimeInterval(Double(index) * 86400)
        return UsageQuantityObservation(dimension: dimension, serviceName: service, currency: "USD", period: Cycle(start: start, end: start.addingTimeInterval(86400)), consumed: consumed, cumulativeBillable: billable, cost: cost)
    }

    func testRecentAccelerationDrivesExhaustionDateAndOverage() throws {
        let rows = (0..<14).map { day($0, $0 < 10 ? 20_000 : 120_000) }
        let now = february.start.addingTimeInterval(14 * 86400 + 3600)
        let quota = try XCTUnwrap(UsageQuotaBuilder.build(cycle: february, now: now, observations: rows, catalog: catalog).first)
        XCTAssertEqual(quota.used, 680_000)
        XCTAssertEqual(quota.included, 1_000_000)
        XCTAssertEqual(quota.includedSource, "catalog")
        XCTAssertEqual(quota.rateBasis, "recent")
        // Last 7 days: 3 × 20k + 4 × 120k
        let rate = 540_000.0 / 7
        XCTAssertEqual(quota.dailyRate, rate, accuracy: 0.001)
        XCTAssertEqual(quota.status, .danger)
        let expected = february.start.addingTimeInterval(14 * 86400 + 320_000 / rate * 86400)
        XCTAssertEqual(quota.exhaustionDate!.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(quota.projectedTotal, 680_000 + rate * 14, accuracy: 0.001)
        XCTAssertEqual(NSDecimalNumber(decimal: quota.projectedOverageCost!).doubleValue, (680_000 + rate * 14 - 1_000_000) * 0.000005, accuracy: 0.0001)
        XCTAssertEqual(quota.points.count, 14)
        XCTAssertEqual(quota.points.last?.perDay, 120_000)
        XCTAssertTrue(quota.needsAttention)
        XCTAssertTrue(quota.isComplete)
    }

    func testBillableQuantityOverridesCatalogAllowanceAndRecordsCrossingDate() throws {
        // Cloudflare bills a started million: $5 for 500k billable lists. The projection must still use $5 per million.
        let rows = (0..<5).map { index in day(index, 300_000, billable: index == 4 ? 500_000 : 0, cost: index == 4 ? 5 : 0) }
        let quota = try XCTUnwrap(UsageQuotaBuilder.build(cycle: february, now: february.end, observations: rows, catalog: catalog).first)
        XCTAssertEqual(quota.billable, 500_000)
        XCTAssertEqual(quota.included, 1_000_000)
        XCTAssertEqual(quota.includedSource, "api")
        XCTAssertEqual(quota.status, .exhausted)
        XCTAssertEqual(quota.exhaustionDate, february.start.addingTimeInterval(4 * 86400))
        XCTAssertEqual(NSDecimalNumber(decimal: quota.projectedOverageCost!).doubleValue, (quota.projectedTotal - 1_000_000) * 0.000005, accuracy: 0.0001)
    }

    func testDimensionsAreSummedAndShortCyclesUseCycleAverage() throws {
        let rows = (0..<3).flatMap { [day($0, 100_000, dimension: "a"), day($0, 50_000, dimension: "b")] }
        let quota = try XCTUnwrap(UsageQuotaBuilder.build(cycle: february, now: february.start.addingTimeInterval(3 * 86400), observations: rows, catalog: catalog).first)
        XCTAssertEqual(quota.used, 450_000)
        XCTAssertEqual(quota.rateBasis, "cycle")
        XCTAssertEqual(quota.dailyRate, 150_000, accuracy: 0.001)
        XCTAssertEqual(quota.points.map(\.perDay), [150_000, 150_000, 150_000])
        XCTAssertEqual(quota.status, .danger)
    }

    func testWarnAboveSeventyPercentAndSkipsGaugeOrUnknownProducts() throws {
        let rows = (0..<14).map { day($0, $0 == 0 ? 740_000 : 1_000) } + [day(0, 5, service: "KV Storage"), day(0, 5, service: "Unknown")]
        let quotas = UsageQuotaBuilder.build(cycle: february, now: february.start.addingTimeInterval(14 * 86400), observations: rows, catalog: catalog)
        XCTAssertEqual(quotas.map(\.serviceName), ["KV List Operations"])
        XCTAssertEqual(quotas.first?.status, .warn)
        XCTAssertNil(quotas.first?.exhaustionDate)
    }

    func testMissingQuantityMarksIncompleteAndFutureRowsIgnored() throws {
        let rows = [day(0, 10), day(1, nil), day(20, 99)]
        let quota = try XCTUnwrap(UsageQuotaBuilder.build(cycle: february, now: february.start.addingTimeInterval(2 * 86400), observations: rows, catalog: catalog).first)
        XCTAssertEqual(quota.used, 10)
        XCTAssertFalse(quota.isComplete)
        XCTAssertEqual(quota.asOf, february.start.addingTimeInterval(2 * 86400))
    }

    func testSnapshotCarriesQuotasFromBillableUsageQuantities() async throws {
        let rows = (0..<3).map { index -> String in
            let start = "2026-02-0\(index + 1)T00:00:00Z", end = "2026-02-0\(index + 2)T00:00:00Z"
            let consumed = index == 1 ? #""200000""# : "200000"
            return #"{"BillingPeriodStart":"2026-02-01T00:00:00Z","BillingCurrency":"USD","ContractedCost":0,"CumulatedContractedCost":0,"ConsumedQuantity":\#(consumed),"CumulatedPricingQuantity":null,"PricingQuantity":{"unexpected":true},"ChargePeriodStart":"\#(start)","ChargePeriodEnd":"\#(end)","ServiceName":"KV List Operations"}"#
        }
        let transport = QuotaTransport { path in
            if path.hasSuffix("/info") { return #"{"success":true,"result":{"covered":true,"subscriptions":[{"id":"s","billing_cycle_anchor_timestamp":"2026-02-01T00:00:00Z","start_timestamp":"2026-01-01T00:00:00Z"}]}}"# }
            if path.hasSuffix("/billable-usage") { return #"{"success":true,"result":[\#(rows.joined(separator: ","))]}"# }
            return #"{"success":true,"result":[],"result_info":{"page":1,"total_pages":1}}"#
        }
        let snapshot = try await BillingService(transport: transport, catalog: catalog).fetchSnapshot(account: AccountProfile(id: "a", name: "A"), token: "x", now: parser.date(from: "2026-02-04T06:00:00Z")!)
        let quota = try XCTUnwrap(snapshot.usageQuotas?.first)
        XCTAssertEqual(quota.used, 600_000)
        XCTAssertEqual(quota.status, .danger)
        XCTAssertEqual(quota.exhaustionDate, parser.date(from: "2026-02-06T00:00:00Z"))
        let decoded = try JSONDecoder().decode(BillingSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.usageQuotas, snapshot.usageQuotas)
    }

    func testRealServiceNamesWithAllowanceNotesMatchCatalog() throws {
        let base = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("packages/billing-spec/catalog.json")
        let shared = try ProductCatalog(contentsOf: base)
        let names = [
            "KV List Operations (First 1M is included)": "kv-list-operations",
            "Workers CPU ms (first 30M are included)": "workers-cpu-ms",
            "Durable Objects Compute Duration (GB*S, First 400,000 GB*S is included)": "do-compute-duration",
            "KV Storage (GB, First GB is included)": "kv-storage",
            "D1 - Storage GB-mo (first 5GB included)": "d1-storage",
            "Regular Twitch Neurons (RTN)": "regular-twitch-neurons",
            "Worker Build Minutes (6000 minutes included per month)": "worker-build-minutes"
        ]
        for (name, key) in names { XCTAssertEqual(shared.product(for: name)?.key, key, name) }
        XCTAssertNil(shared.product(for: "Something Else (First 1M is included)"))
        let rows = (0..<3).map { day($0, 400_000, service: "KV List Operations (First 1M is included)") }
        XCTAssertEqual(UsageQuotaBuilder.build(cycle: february, now: february.end, observations: rows, catalog: shared).first?.status, .exhausted)
    }

    func testOldSnapshotWithoutQuotasDecodes() throws {
        let data = try JSONEncoder().encode(BillingSnapshot(accountID: "a", cycles: [], totals: [], checkedAt: Date(), isComplete: true))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "usageQuotas")
        XCTAssertNil(try JSONDecoder().decode(BillingSnapshot.self, from: JSONSerialization.data(withJSONObject: json)).usageQuotas)
    }
}

private final class QuotaTransport: BillingTransport {
    let body: (String) -> String
    init(_ body: @escaping (String) -> String) { self.body = body }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (Data(body(request.url!.path).utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!)
    }
}
