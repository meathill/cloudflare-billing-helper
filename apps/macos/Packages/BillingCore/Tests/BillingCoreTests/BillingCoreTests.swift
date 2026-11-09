import XCTest
@testable import BillingCore
final class BillingCoreTests: XCTestCase {
    func testAnnualProrationAndForecast() {
        let start = Date(timeIntervalSince1970: 0)
        let month = Cycle(start: start, end: start.addingTimeInterval(30 * 86400))
        let annual = FixedSubscription(id: "a", currency: "USD", price: 120, period: Cycle(start: start, end: start.addingTimeInterval(360 * 86400)))
        let charge = UsageCharge(id: "u", currency: "USD", cost: 5, period: Cycle(start: start, end: start.addingTimeInterval(15 * 86400)))
        let total = BillingCalculator.calculate(cycle: month, subscriptions: [annual, annual], usage: [charge, charge], now: charge.period.end).first!
        XCTAssertEqual(total.fixedCost!, 10, accuracy: Decimal(string: "0.000001")!)
        XCTAssertEqual(total.usageCost, 5)
        XCTAssertEqual(total.forecastCost!, 20, accuracy: Decimal(string: "0.000001")!)
    }
    func testMissingAndCurrency() {
        let cycle = Cycle(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 100))
        let subs = [FixedSubscription(id: "a", currency: "USD", price: nil, period: cycle), FixedSubscription(id: "b", currency: "EUR", price: 2, period: cycle)]
        let totals = BillingCalculator.calculate(cycle: cycle, subscriptions: subs, usage: [], now: cycle.end)
        XCTAssertEqual(totals.count, 2)
        XCTAssertNil(totals.first { $0.currency == "USD" }!.total)
        XCTAssertEqual(totals.first { $0.currency == "EUR" }!.total, 2)
    }
    func testStaleAndBudget() {
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(Freshness.isStale(checkedAt: start, now: start.addingTimeInterval(21600)))
        let events = BudgetEvaluator.evaluate(actual: 80, forecast: 100, budget: 100, currency: "USD", cycle: Cycle(start: start, end: start.addingTimeInterval(100)))
        XCTAssertEqual(events.map(\.threshold), ["80", "forecast"])
    }
}

private final class MockTransport: BillingTransport {
    var requests: [URLRequest] = []
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let path = request.url!.path
        let json: String
        if path.hasSuffix("/billable-usage/info") { json = #"{"success":true,"result":{"covered":true,"subscriptions":[{"id":"s","billing_cycle_anchor_timestamp":"2026-01-01T00:00:00Z","start_timestamp":"2026-01-01T00:00:00Z"}]}}"# }
        else if path.hasSuffix("/billable-usage") { json = #"{"success":true,"result":[]}"# }
        else if path.hasSuffix("/subscriptions") { json = #"{"success":true,"result":[]}"# }
        else { json = #"{"success":true,"result":[]}"# }
        return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
extension BillingCoreTests {
    func testRequestDateAndMissingPagination() async throws {
        let transport = MockTransport()
        let now = ISO8601DateFormatter().date(from: "2026-02-15T10:00:00Z")!
        let snapshot = try await BillingService(transport: transport).fetchSnapshot(account: AccountProfile(id: "abc", name: "test"), token: "test", now: now)
        let request = transport.requests.first { $0.url!.path.hasSuffix("/billable-usage") }!
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "from" }?.value, "2026-02-01")
        XCTAssertEqual(query.first { $0.name == "to" }?.value, "2026-02-15")
        XCTAssertFalse(snapshot.isComplete)
        XCTAssertTrue(snapshot.issues.contains("Zone pagination unavailable"))
    }
}

private struct FixtureFile: Decodable { let cases: [FixtureCase] }
private struct FixtureCase: Decodable {
    struct Period: Decodable { let start: String; let end: String }
    struct Item: Decodable { let id: String; let currency: String; let price: String?; let cost: String?; let periodStart: String; let periodEnd: String }
    struct Expected: Decodable { struct Total: Decodable { let currency: String; let fixedCost: String; let usageCost: String; let forecastCost: String? }; let totals: [Total]; let incomplete: Bool }
    let name: String; let cycle: Period; let subscriptions: [Item]; let usage: [Item]; let expected: Expected; let sourceAsOf: String?
}
extension BillingCoreTests {
    func testSharedFixturesAndCatalog() throws {
        let base = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("packages/billing-spec")
        let catalog = try ProductCatalog(contentsOf: base.appendingPathComponent("catalog.json"))
        XCTAssertEqual(catalog.product(for: "Workers CPU ms")?.family, "workers")
        let fixture = try JSONDecoder().decode(FixtureFile.self, from: Data(contentsOf: base.appendingPathComponent("fixtures/billing.json")))
        let parser = ISO8601DateFormatter()
        for item in fixture.cases {
            let cycle = Cycle(start: parser.date(from: item.cycle.start)!, end: parser.date(from: item.cycle.end)!)
            let fixed = item.subscriptions.map { FixedSubscription(id: $0.id, currency: $0.currency, price: $0.price.flatMap { Decimal(string: $0) }, period: Cycle(start: parser.date(from: $0.periodStart)!, end: parser.date(from: $0.periodEnd)!)) }
            let usage = item.usage.map { UsageCharge(id: $0.id, currency: $0.currency, cost: $0.cost.flatMap { Decimal(string: $0) }, period: Cycle(start: parser.date(from: $0.periodStart)!, end: parser.date(from: $0.periodEnd)!)) }
            let totals = BillingCalculator.calculate(cycle: cycle, subscriptions: fixed, usage: usage, now: item.sourceAsOf.flatMap(parser.date(from:)) ?? cycle.start)
            XCTAssertEqual(totals.count, item.expected.totals.count, item.name)
            XCTAssertEqual(totals.contains { !$0.isComplete }, item.expected.incomplete, item.name)
            for (actual, expected) in zip(totals, item.expected.totals) {
                XCTAssertEqual(actual.currency, expected.currency, item.name)
                XCTAssertEqual(actual.fixedCost!, Decimal(string: expected.fixedCost)!, accuracy: Decimal(string: "0.00000001")!, item.name)
                XCTAssertEqual(actual.usageCost!, Decimal(string: expected.usageCost)!, accuracy: Decimal(string: "0.00000001")!, item.name)
                if let forecast = expected.forecastCost { XCTAssertEqual(actual.forecastCost!, Decimal(string: forecast)!, accuracy: Decimal(string: "0.00000001")!, item.name) }
                else if item.sourceAsOf != nil { XCTAssertNil(actual.forecastCost, item.name) }
            }
        }
    }
}

private final class ScriptTransport: BillingTransport {
    var calls: [String] = []
    var handler: (URLRequest, Int) -> (Int, String, [String: String])
    init(_ handler: @escaping (URLRequest, Int) -> (Int, String, [String: String])) { self.handler = handler }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        calls.append(request.url!.absoluteString)
        let (status, body, headers) = handler(request, calls.count)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }
}
extension BillingCoreTests {
    func testPermissionsAndRetry() async throws {
        for (status, expected) in [(401, "invalidToken"), (403, "insufficientPermissions")] {
            let mock = ScriptTransport { _, _ in (status, "{}", [:]) }
            do { _ = try await BillingService(transport: mock).fetchSnapshot(account: AccountProfile(id: "a", name: "A"), token: "x"); XCTFail("expected error") }
            catch { XCTAssertEqual(String(describing: error), expected) }
        }
        let mock = ScriptTransport { _, n in n == 1 ? (429, "{}", ["Retry-After": "0"]) : (401, "{}", [:]) }
        do { _ = try await BillingService(transport: mock).fetchSnapshot(account: AccountProfile(id: "a", name: "A"), token: "x"); XCTFail("expected error") }
        catch { XCTAssertEqual(String(describing: error), "invalidToken") }
        XCTAssertEqual(mock.calls.count, 2)
    }
    func testPaginationAndPartialSubscriptions() async throws {
        let mock = ScriptTransport { request, _ in
            let path = request.url!.path
            if path.hasSuffix("/info") { return (200, #"{"success":true,"result":{"covered":true,"subscriptions":[{"id":"s","billing_cycle_anchor_timestamp":"2026-01-01T00:00:00Z","start_timestamp":"2026-01-01T00:00:00Z"}]}}"#, [:]) }
            if path.hasSuffix("/billable-usage") { return (200, #"{"success":true,"result":[{"BillingPeriodStart":"2026-02-01T00:00:00Z","BillingCurrency":"USD","ContractedCost":3,"ChargePeriodStart":"2026-02-01T00:00:00Z","ChargePeriodEnd":"2026-02-02T00:00:00Z","ServiceName":"Test"}]}"#, [:]) }
            if path.hasSuffix("/subscriptions") { return (403, "{}", [:]) }
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "page" }!.value!
            return (200, "{\"success\":true,\"result\":[],\"result_info\":{\"page\":\(page),\"total_pages\":2}}", [:])
        }
        let now = ISO8601DateFormatter().date(from: "2026-02-15T00:00:00Z")!
        let snapshot = try await BillingService(transport: mock).fetchSnapshot(account: AccountProfile(id: "a", name: "A"), token: "x", now: now)
        XCTAssertEqual(snapshot.totals.first?.usageCost, 3)
        XCTAssertEqual(snapshot.usageProductTotals?.first?.isComplete, true)
        XCTAssertFalse(snapshot.isComplete)
        XCTAssertNil(snapshot.totals.first?.total)
        XCTAssertEqual(snapshot.sourceAsOf, ISO8601DateFormatter().date(from: "2026-02-02T00:00:00Z"))
        XCTAssertEqual(mock.calls.filter { $0.contains("/zones?") }.count, 2)
    }
    func testCacheAccountIsolation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SnapshotCache(directory: directory)
        let snapshot = BillingSnapshot(accountID: "a", cycles: [], totals: [], checkedAt: Date(), isComplete: false)
        try cache.save(snapshot)
        XCTAssertEqual(try cache.load(accountID: "a")?.accountID, "a")
        XCTAssertNil(try cache.load(accountID: "b"))
        try cache.delete(accountID: "a")
        XCTAssertNil(try cache.load(accountID: "a"))
    }
}
extension BillingCoreTests {
    func testPerServiceForecastAndSelectedCycle() async throws {
        let mock = ScriptTransport { request, _ in
            let path = request.url!.path
            if path.hasSuffix("/info") { return (200, #"{"success":true,"result":{"covered":true,"subscriptions":[{"id":"s","billing_cycle_anchor_timestamp":"2026-02-01T00:00:00Z","start_timestamp":"2026-01-01T00:00:00Z"}]}}"#, [:]) }
            if path.hasSuffix("/billable-usage") { return (200, #"{"success":true,"result":[{"BillingPeriodStart":"2026-02-01T00:00:00Z","BillingCurrency":"USD","ContractedCost":2,"ChargePeriodStart":"2026-02-01T00:00:00Z","ChargePeriodEnd":"2026-02-03T00:00:00Z","ServiceName":"A"},{"BillingPeriodStart":"2026-02-01T00:00:00Z","BillingCurrency":"USD","ContractedCost":3,"ChargePeriodStart":"2026-02-01T00:00:00Z","ChargePeriodEnd":"2026-02-04T00:00:00Z","ServiceName":"B"}]}"#, [:]) }
            if path.hasSuffix("/subscriptions") { return (200, #"{"success":true,"result":[{"id":"f","currency":"USD","price":28,"current_period_start":"2026-02-01T00:00:00Z","current_period_end":"2026-03-01T00:00:00Z","state":"Paid"}]}"#, [:]) }
            return (200, #"{"success":true,"result":[],"result_info":{"page":1,"total_pages":1}}"#, [:])
        }
        let parser = ISO8601DateFormatter()
        let now = parser.date(from: "2026-02-15T00:00:00Z")!
        let snapshot = try await BillingService(transport: mock).fetchSnapshot(account: AccountProfile(id: "a", name: "A"), token: "x", now: now)
        XCTAssertTrue(snapshot.isComplete)
        XCTAssertEqual(snapshot.sourceAsOf, parser.date(from: "2026-02-03T00:00:00Z"))
        XCTAssertEqual(snapshot.selectedCycle?.start, parser.date(from: "2026-02-01T00:00:00Z"))
        XCTAssertEqual(snapshot.totals.first!.total, 33)
        XCTAssertEqual(snapshot.totals.first!.forecastCost!, 84, accuracy: Decimal(string: "0.00000001")!)
        XCTAssertTrue(snapshot.forecastIsEstimate)
    }
}
extension BillingCoreTests {
    func testSubscriptionStatesAndAmbiguousUsage() async throws {
        let mock = ScriptTransport { request, _ in
            let path = request.url!.path
            if path.hasSuffix("/info") { return (200, #"{"success":true,"result":{"covered":true,"subscriptions":[{"id":"s","billing_cycle_anchor_timestamp":"2026-02-01T00:00:00Z","start_timestamp":"2026-01-01T00:00:00Z"}]}}"#, [:]) }
            if path.hasSuffix("/billable-usage") { return (200, #"{"success":true,"result":[{"BillingPeriodStart":"2026-02-01T00:00:00Z","BillingCurrency":"USD","ContractedCost":3,"ChargePeriodStart":"2026-02-01T00:00:00Z","ChargePeriodEnd":"2026-02-02T00:00:00Z","ServiceName":"A"},{"BillingPeriodStart":"2026-02-01T00:00:00Z","BillingCurrency":"USD","ContractedCost":3,"ChargePeriodStart":"2026-02-01T00:00:00Z","ChargePeriodEnd":"2026-02-02T00:00:00Z","ServiceName":"A"}]}"#, [:]) }
            if path.hasSuffix("/subscriptions") { return (200, #"{"success":true,"result":[{"id":"paid","currency":"USD","price":10,"current_period_start":"2026-02-01T00:00:00Z","current_period_end":"2026-03-01T00:00:00Z","state":"Paid"},{"id":"expired","currency":"USD","price":99,"current_period_start":"2026-02-01T00:00:00Z","current_period_end":"2026-03-01T00:00:00Z","state":"Expired"}]}"#, [:]) }
            return (200, #"{"success":true,"result":[],"result_info":{"page":1,"total_pages":1}}"#, [:])
        }
        let snapshot = try await BillingService(transport: mock).fetchSnapshot(account: AccountProfile(id: "a", name: "A"), token: "x", now: ISO8601DateFormatter().date(from: "2026-02-15T00:00:00Z")!)
        XCTAssertFalse(snapshot.isComplete)
        XCTAssertEqual(snapshot.totals.first?.fixedCost, 10)
        XCTAssertEqual(snapshot.totals.first?.usageCost, 3)
        XCTAssertTrue(snapshot.issues.contains { $0.contains("Ambiguous duplicate") })
        XCTAssertNil(snapshot.totals.first?.forecastCost)
    }
}
extension BillingCoreTests {
    func testDifferentMonthlyAnchorsEstimateBothPeriods() async throws {
        let mock = ScriptTransport { request, _ in
            let path = request.url!.path
            if path.hasSuffix("/info") { return (200, #"{"success":true,"result":{"covered":true,"subscriptions":[{"id":"ref","billing_cycle_anchor_timestamp":"2026-01-17T00:00:00Z","start_timestamp":"2026-01-17T00:00:00Z"}]}}"#, [:]) }
            if path.hasSuffix("/billable-usage") { return (200, #"{"success":true,"result":[]}"#, [:]) }
            if path.hasSuffix("/subscriptions") { return (200, #"{"success":true,"result":[{"id":"domain","currency":"USD","price":30,"frequency":"monthly","initial_period_start":"2026-01-01T00:00:00Z","current_period_start":"2026-11-01T00:00:00Z","current_period_end":"2026-12-01T00:00:00Z","state":"Paid"}]}"#, [:]) }
            return (200, #"{"success":true,"result":[],"result_info":{"page":1,"total_pages":1}}"#, [:])
        }
        let parser = ISO8601DateFormatter()
        let snapshot = try await BillingService(transport: mock).fetchSnapshot(account: AccountProfile(id: "a", name: "A"), token: "x", now: parser.date(from: "2026-11-04T00:00:00Z")!)
        XCTAssertTrue(snapshot.isComplete)
        XCTAssertTrue(snapshot.fixedCostIsEstimate)
        XCTAssertNotNil(snapshot.fixedEstimateNote)
        XCTAssertEqual(snapshot.subscriptions.count, 1)
        XCTAssertEqual(snapshot.subscriptions.first?.period.start, parser.date(from: "2026-11-01T00:00:00Z"))
        XCTAssertEqual(snapshot.totals.first!.fixedCost!, Decimal(30) * Decimal(15.0 / 31) + 16, accuracy: Decimal(string: "0.00000001")!)
    }
    func testMonthEndAndLatestDefault() async throws {
        let mock = ScriptTransport { request, _ in
            let path = request.url!.path
            if path.hasSuffix("/info") { return (200, #"{"success":true,"result":{"covered":true,"subscriptions":[{"id":"x","billing_cycle_anchor_timestamp":"2026-01-31T00:00:00Z","start_timestamp":"2026-01-01T00:00:00Z"},{"id":"y","billing_cycle_anchor_timestamp":"2026-01-15T00:00:00Z","start_timestamp":"2026-01-01T00:00:00Z"}]}}"#, [:]) }
            if path.hasSuffix("/billable-usage") || path.hasSuffix("/subscriptions") { return (200, #"{"success":true,"result":[]}"#, [:]) }
            return (200, #"{"success":true,"result":[],"result_info":{"page":1,"total_pages":1}}"#, [:])
        }
        let parser = ISO8601DateFormatter()
        let snapshot = try await BillingService(transport: mock).fetchSnapshot(account: AccountProfile(id: "a", name: "A"), token: "x", now: parser.date(from: "2026-03-20T00:00:00Z")!)
        XCTAssertTrue(snapshot.cycles.contains(Cycle(start: parser.date(from: "2026-02-28T00:00:00Z")!, end: parser.date(from: "2026-03-31T00:00:00Z")!)))
        XCTAssertEqual(snapshot.selectedCycle?.start, parser.date(from: "2026-03-15T00:00:00Z"))
        let april = try await BillingService(transport: mock).fetchSnapshot(account: AccountProfile(id: "a", name: "A"), token: "x", now: parser.date(from: "2026-04-20T00:00:00Z")!)
        XCTAssertTrue(april.cycles.contains(Cycle(start: parser.date(from: "2026-03-31T00:00:00Z")!, end: parser.date(from: "2026-04-30T00:00:00Z")!)))
    }
}
extension BillingCoreTests {
    func testUnknownFrequencyDoesNotInventPriorCost() async throws {
        let mock = ScriptTransport { request, _ in
            let path = request.url!.path
            if path.hasSuffix("/info") { return (200, #"{"success":true,"result":{"covered":true,"subscriptions":[{"id":"ref","billing_cycle_anchor_timestamp":"2026-01-17T00:00:00Z","start_timestamp":"2026-01-17T00:00:00Z"}]}}"#, [:]) }
            if path.hasSuffix("/billable-usage") { return (200, #"{"success":true,"result":[]}"#, [:]) }
            if path.hasSuffix("/subscriptions") { return (200, #"{"success":true,"result":[{"id":"domain","currency":"USD","price":30,"initial_period_start":"2026-01-01T00:00:00Z","current_period_start":"2026-11-01T00:00:00Z","current_period_end":"2026-12-01T00:00:00Z","state":"Paid"}]}"#, [:]) }
            return (200, #"{"success":true,"result":[],"result_info":{"page":1,"total_pages":1}}"#, [:])
        }
        let now = ISO8601DateFormatter().date(from: "2026-11-04T00:00:00Z")!
        let snapshot = try await BillingService(transport: mock).fetchSnapshot(account: AccountProfile(id: "a", name: "A"), token: "x", now: now)
        XCTAssertFalse(snapshot.isComplete)
        XCTAssertEqual(snapshot.totals.first!.fixedCost!, 16, accuracy: Decimal(string: "0.00000001")!)
        XCTAssertNil(snapshot.totals.first?.total)
        XCTAssertFalse(snapshot.fixedCostIsEstimate)
    }
    func testCancelledSubscriptionEndClipsCost() async throws {
        let mock = ScriptTransport { request, _ in
            let path = request.url!.path
            if path.hasSuffix("/info") { return (200, #"{"success":true,"result":{"covered":true,"subscriptions":[{"id":"ref","billing_cycle_anchor_timestamp":"2026-01-17T00:00:00Z","start_timestamp":"2026-01-17T00:00:00Z"},{"id":"domain","billing_cycle_anchor_timestamp":"2026-01-01T00:00:00Z","start_timestamp":"2026-11-01T00:00:00Z","end_timestamp":"2026-11-10T00:00:00Z"}]}}"#, [:]) }
            if path.hasSuffix("/billable-usage") { return (200, #"{"success":true,"result":[]}"#, [:]) }
            if path.hasSuffix("/subscriptions") { return (200, #"{"success":true,"result":[{"id":"domain","currency":"USD","price":30,"frequency":"monthly","current_period_start":"2026-11-01T00:00:00Z","current_period_end":"2026-12-01T00:00:00Z","state":"Cancelled"}]}"#, [:]) }
            return (200, #"{"success":true,"result":[],"result_info":{"page":1,"total_pages":1}}"#, [:])
        }
        let parser = ISO8601DateFormatter()
        let snapshot = try await BillingService(transport: mock).fetchSnapshot(account: AccountProfile(id: "a", name: "A"), token: "x", now: parser.date(from: "2026-11-04T00:00:00Z")!)
        XCTAssertEqual(snapshot.totals.first!.fixedCost!, 9, accuracy: Decimal(string: "0.00000001")!)
        XCTAssertFalse(snapshot.fixedCostIsEstimate)
    }
}
extension BillingCoreTests {
    func testEndedHistoricalSubscriptionsDoNotPolluteCurrentCycle() async throws {
        let mock = ScriptTransport { request, _ in
            let path = request.url!.path
            if path.hasSuffix("/info") { return (200, #"{"success":true,"result":{"covered":true,"subscriptions":[{"id":"ref","billing_cycle_anchor_timestamp":"2026-01-01T00:00:00Z","start_timestamp":"2026-01-01T00:00:00Z"}]}}"#, [:]) }
            if path.hasSuffix("/billable-usage") { return (200, #"{"success":true,"result":[]}"#, [:]) }
            if path.hasSuffix("/subscriptions") { return (200, #"{"success":true,"result":[{"id":"current","currency":"USD","price":10,"current_period_start":"2026-11-01T00:00:00Z","current_period_end":"2026-12-01T00:00:00Z","state":"Paid"},{"id":"old","current_period_end":"2025-11-01T00:00:00Z","state":"Expired"},{"id":"old2","current_period_end":"2026-11-01T00:00:00Z","state":"Cancelled"}]}"#, [:]) }
            return (200, #"{"success":true,"result":[],"result_info":{"page":1,"total_pages":1}}"#, [:])
        }
        let snapshot = try await BillingService(transport: mock).fetchSnapshot(account: AccountProfile(id: "a", name: "A"), token: "x", now: ISO8601DateFormatter().date(from: "2026-11-04T00:00:00Z")!)
        XCTAssertTrue(snapshot.isComplete)
        XCTAssertEqual(snapshot.totals.first?.total, 10)
        XCTAssertEqual(snapshot.subscriptions.count, 1)
    }
}
extension BillingCoreTests {
    func testPrivateSafeSubscriptionDiagnostics() async throws {
        let mock = ScriptTransport { request, _ in
            let path = request.url!.path
            if path.hasSuffix("/info") { return (200, #"{"success":true,"result":{"covered":true,"subscriptions":[{"id":"s","billing_cycle_anchor_timestamp":"2026-02-01T00:00:00Z","start_timestamp":"2026-01-01T00:00:00Z"}]}}"#, [:]) }
            if path.hasSuffix("/billable-usage") { return (200, #"{"success":true,"result":[]}"#, [:]) }
            if path.hasSuffix("/subscriptions") { return (200, #"{"success":true,"result":[{"id":"private-id","state":"Paid","price":0,"rate_plan":{"id":"free"}}]}"#, [:]) }
            if path.hasSuffix("/zones") { return (200, #"{"success":true,"result":[{"id":"z1","name":"sensitive-domain"},{"id":"z2","name":"secret-zone"},{"id":"z3","name":"private-zone"}],"result_info":{"page":1,"total_pages":1}}"#, [:]) }
            if path.contains("z1") { return (403, #"{"success":false,"errors":[{"code":9109,"message":"private financial response"}]}"#, [:]) }
            if path.contains("z2") { return (404, #"{"success":false,"errors":[{"code":1002}]}"#, [:]) }
            return (200, #"{"success":true,"result":{"price":"invalid"}}"#, [:])
        }
        let snapshot = try await BillingService(transport: mock).fetchSnapshot(account: AccountProfile(id: "a", name: "A"), token: "secret-token", now: ISO8601DateFormatter().date(from: "2026-02-15T00:00:00Z")!)
        let issues = snapshot.issues.joined(separator: "\n")
        XCTAssertTrue(issues.contains("zone subscription unavailable: HTTP 403, codes=9109"))
        XCTAssertTrue(issues.contains("zone subscription unavailable: HTTP 404, codes=1002"))
        XCTAssertTrue(issues.contains("decoding path=result.price"))
        XCTAssertTrue(issues.contains("plan=free; price=zero"))
        XCTAssertTrue(issues.contains("currency,current_period_start,current_period_end"))
        for secret in ["sensitive-domain", "secret-zone", "private-zone", "private-id", "secret-token", "private financial response"] { XCTAssertFalse(issues.contains(secret)) }
        XCTAssertFalse(snapshot.isComplete)
    }
}
extension BillingCoreTests {
    func testUsageDiagnosticComparesCumulativeWithoutSavingCosts() async throws {
        let mock = ScriptTransport { request, _ in
            let path = request.url!.path
            if path.hasSuffix("/info") { return (200, #"{"success":true,"result":{"covered":true,"subscriptions":[{"id":"s","billing_cycle_anchor_timestamp":"2026-02-01T00:00:00Z","start_timestamp":"2026-01-01T00:00:00Z"}]}}"#, [:]) }
            if path.hasSuffix("/billable-usage") { return (200, #"{"success":true,"result":[{"BillingPeriodStart":"2026-02-01T00:00:00Z","BillingCurrency":"USD","ContractedCost":0,"CumulatedContractedCost":7,"ChargePeriodStart":"2026-02-01T00:00:00Z","ChargePeriodEnd":"2026-02-02T00:00:00Z","ServiceName":"KV Storage"},{"BillingPeriodStart":"2026-02-01T00:00:00Z","BillingCurrency":"USD","ContractedCost":0,"CumulatedContractedCost":9,"ChargePeriodStart":"2026-02-02T00:00:00Z","ChargePeriodEnd":"2026-02-03T00:00:00Z","ServiceName":"KV Storage"}]}"#, [:]) }
            if path.hasSuffix("/subscriptions") { return (200, #"{"success":true,"result":[]}"#, [:]) }
            return (200, #"{"success":true,"result":[],"result_info":{"page":1,"total_pages":1}}"#, [:])
        }
        let snapshot = try await BillingService(transport: mock).fetchSnapshot(account: AccountProfile(id: "a", name: "A"), token: "token", now: ISO8601DateFormatter().date(from: "2026-02-15T00:00:00Z")!)
        let diagnostic = try XCTUnwrap(snapshot.usageDiagnostics?.first)
        XCTAssertTrue(diagnostic.allCumulativePresent)
        XCTAssertEqual(diagnostic.periodSumDiffersFromLatestCumulative, true)
        XCTAssertFalse(diagnostic.includesCurrentUTCDay)
        XCTAssertEqual(snapshot.totals.first?.usageCost, 9)
        XCTAssertEqual(snapshot.usage.map(\.cost), [0, 0])
        XCTAssertEqual(snapshot.usageProductTotals?.first?.cost, 9)
        XCTAssertEqual(snapshot.usageProductTotals?.first?.source, "cumulative")
        XCTAssertEqual(snapshot.usageProductTotals?.first?.rawServiceNames, ["KV Storage"])
        XCTAssertEqual(snapshot.usageTrends?.first?.points.map(\.cost), [7, 9])
        XCTAssertEqual(snapshot.usageTotalTrends?.first?.points.map(\.cost), [7, 9])
        XCTAssertEqual(snapshot.usageTrends?.first?.points.last?.cost, snapshot.usageProductTotals?.first?.cost)
        let json = String(data: try JSONEncoder().encode(diagnostic), encoding: .utf8)!
        XCTAssertFalse(json.contains(":7")); XCTAssertFalse(json.contains(":9"))
    }
}
extension BillingCoreTests {
    func testZeroNonRecurringSubscriptionsDoNotRequireDates() async throws {
        func fetch(_ priceField: String, _ plan: String = "free") async throws -> BillingSnapshot {
            let mock = ScriptTransport { request, _ in
                let path = request.url!.path
                if path.hasSuffix("/info") { return (200, #"{"success":true,"result":{"covered":true,"subscriptions":[{"id":"s","billing_cycle_anchor_timestamp":"2026-02-01T00:00:00Z","start_timestamp":"2026-01-01T00:00:00Z"}]}}"#, [:]) }
                if path.hasSuffix("/billable-usage") { return (200, #"{"success":true,"result":[{"BillingPeriodStart":"2026-02-01T00:00:00Z","BillingCurrency":"USD","ContractedCost":2,"ChargePeriodStart":"2026-02-01T00:00:00Z","ChargePeriodEnd":"2026-02-02T00:00:00Z","ServiceName":"Test"}]}"#, [:]) }
                if path.hasSuffix("/subscriptions") { return (200, "{\"success\":true,\"result\":[{\"state\":\"Paid\",\"frequency\":\"not-applicable\",\(priceField)\"rate_plan\":{\"id\":\"\(plan)\"}}]}", [:]) }
                return (200, #"{"success":true,"result":[],"result_info":{"page":1,"total_pages":1}}"#, [:])
            }
            return try await BillingService(transport: mock).fetchSnapshot(account: AccountProfile(id: "a", name: "A"), token: "token", now: ISO8601DateFormatter().date(from: "2026-02-15T00:00:00Z")!)
        }
        let free = try await fetch("\"price\":0,")
        let other = try await fetch("\"price\":0,", "other")
        XCTAssertTrue(free.isComplete); XCTAssertTrue(other.isComplete)
        XCTAssertEqual(free.totals.first?.total, 2)
        let missing = try await fetch("")
        XCTAssertFalse(missing.isComplete); XCTAssertNil(missing.totals.first?.total)
        let nonzero = try await fetch("\"price\":1,")
        XCTAssertFalse(nonzero.isComplete)
    }
    func testErrorMessageClassificationIsPrivate() async throws {
        let mock = ScriptTransport { request, _ in
            let path = request.url!.path
            if path.hasSuffix("/info") { return (200, #"{"success":true,"result":{"covered":true,"subscriptions":[{"id":"s","billing_cycle_anchor_timestamp":"2026-02-01T00:00:00Z","start_timestamp":"2026-01-01T00:00:00Z"}]}}"#, [:]) }
            if path.hasSuffix("/billable-usage") || path.hasSuffix("/subscriptions") { return (200, #"{"success":true,"result":[]}"#, [:]) }
            if path.hasSuffix("/zones") { return (200, #"{"success":true,"result":[{"id":"z1","name":"private-name"}],"result_info":{"page":1,"total_pages":1}}"#, [:]) }
            return (404, #"{"success":false,"errors":[{"code":1207,"message":"Subscription not found for private-name"}]}"#, [:])
        }
        let snapshot = try await BillingService(transport: mock).fetchSnapshot(account: AccountProfile(id: "a", name: "A"), token: "token", now: ISO8601DateFormatter().date(from: "2026-02-15T00:00:00Z")!)
        let issues = snapshot.issues.joined(separator: "\n")
        XCTAssertTrue(issues.contains("codes=1207, no_subscription_message=true, not_found_message=true, no_active_subscription=false"))
        XCTAssertFalse(issues.contains("private-name"))
        XCTAssertFalse(snapshot.isComplete)
    }
}
extension BillingCoreTests {
    func testCumulativeByDimensionAndPeriodFallback() async throws {
        let mock = ScriptTransport { request, _ in
            let path = request.url!.path
            if path.hasSuffix("/info") { return (200, #"{"success":true,"result":{"covered":true,"subscriptions":[{"id":"s","billing_cycle_anchor_timestamp":"2026-02-01T00:00:00Z","start_timestamp":"2026-01-01T00:00:00Z"}]}}"#, [:]) }
            if path.hasSuffix("/billable-usage") { return (200, #"{"success":true,"result":[{"BillingPeriodStart":"2026-02-01T00:00:00Z","BillingCurrency":"USD","ZoneId":"a","ContractedCost":0,"CumulatedContractedCost":7,"ChargePeriodStart":"2026-02-01T00:00:00Z","ChargePeriodEnd":"2026-02-02T00:00:00Z","ServiceName":"KV Storage"},{"BillingPeriodStart":"2026-02-01T00:00:00Z","BillingCurrency":"USD","ZoneId":"a","ContractedCost":0,"CumulatedContractedCost":9,"ChargePeriodStart":"2026-02-02T00:00:00Z","ChargePeriodEnd":"2026-02-03T00:00:00Z","ServiceName":"KV Storage"},{"BillingPeriodStart":"2026-02-01T00:00:00Z","BillingCurrency":"USD","ZoneId":"b","ContractedCost":2,"CumulatedContractedCost":4,"ChargePeriodStart":"2026-02-01T00:00:00Z","ChargePeriodEnd":"2026-02-02T00:00:00Z","ServiceName":"KV Storage"},{"BillingPeriodStart":"2026-02-01T00:00:00Z","BillingCurrency":"USD","ContractedCost":2,"ChargePeriodStart":"2026-02-01T00:00:00Z","ChargePeriodEnd":"2026-02-02T00:00:00Z","ServiceName":"Other"}]}"#, [:]) }
            if path.hasSuffix("/subscriptions") { return (200, #"{"success":true,"result":[]}"#, [:]) }
            return (200, #"{"success":true,"result":[],"result_info":{"page":1,"total_pages":1}}"#, [:])
        }
        let snapshot = try await BillingService(transport: mock).fetchSnapshot(account: AccountProfile(id: "a", name: "A"), token: "token", now: ISO8601DateFormatter().date(from: "2026-02-15T00:00:00Z")!)
        XCTAssertEqual(snapshot.totals.first?.usageCost, 15)
        XCTAssertEqual(snapshot.usageProductTotals?.first { $0.serviceName == "KV Storage" }?.cost, 13)
        XCTAssertEqual(snapshot.usageProductTotals?.first { $0.serviceName == "Other" }?.source, "period-sum")
        XCTAssertEqual(snapshot.usage.count, 4)
        XCTAssertEqual(snapshot.usage.compactMap(\.cost).reduce(0, +), 4)
    }
}
extension BillingCoreTests {
    func testOnlyExplicitNoActiveSubscriptionIsIgnored() async throws {
        func fetch(status: Int, code: Int, message: String) async throws -> BillingSnapshot {
            let mock = ScriptTransport { request, _ in
                let path = request.url!.path
                if path.hasSuffix("/info") { return (200, #"{"success":true,"result":{"covered":true,"subscriptions":[{"id":"s","billing_cycle_anchor_timestamp":"2026-02-01T00:00:00Z","start_timestamp":"2026-01-01T00:00:00Z"}]}}"#, [:]) }
                if path.hasSuffix("/billable-usage") { return (200, #"{"success":true,"result":[{"BillingPeriodStart":"2026-02-01T00:00:00Z","BillingCurrency":"USD","ContractedCost":2,"ChargePeriodStart":"2026-02-01T00:00:00Z","ChargePeriodEnd":"2026-02-02T00:00:00Z","ServiceName":"Test"}]}"#, [:]) }
                if path.hasSuffix("/subscriptions") { return (200, #"{"success":true,"result":[]}"#, [:]) }
                if path.hasSuffix("/zones") { return (200, #"{"success":true,"result":[{"id":"z","name":"example"}],"result_info":{"page":1,"total_pages":1}}"#, [:]) }
                let data = try! JSONSerialization.data(withJSONObject: ["success": false, "errors": [["code": code, "message": message]]])
                return (status, String(data: data, encoding: .utf8)!, [:])
            }
            return try await BillingService(transport: mock).fetchSnapshot(account: AccountProfile(id: "a", name: "A"), token: "token", now: ISO8601DateFormatter().date(from: "2026-02-15T00:00:00Z")!)
        }
        let message = "The zone does not have an active subscription"
        let expected = try await fetch(status: 404, code: 1207, message: message)
        XCTAssertTrue(expected.isComplete); XCTAssertEqual(expected.totals.first?.total, 2)
        for variant in ["The zone does  not have an active subscription", "The zone does\nnot have an active subscription", "The zone does ‘not’ have an active subscription", "The zone does—not have an active subscription"] {
            let normalized = try await fetch(status: 404, code: 1207, message: variant)
            XCTAssertTrue(normalized.isComplete, variant)
        }
        let core = try await fetch(status: 404, code: 1207, message: "Add a core subscription first and try again. The zone does not have an active core subscription.")
        XCTAssertTrue(core.isComplete)
        let coreShort = try await fetch(status: 404, code: 1207, message: "No active core subscription.")
        XCTAssertTrue(coreShort.isComplete)
        let legacy = try await fetch(status: 404, code: 1207, message: "The zone does not have an active legacy subscription.")
        XCTAssertFalse(legacy.isComplete)
        let wrongCode = try await fetch(status: 404, code: 1234, message: message)
        let wrongStatus = try await fetch(status: 403, code: 1207, message: message)
        let unknown = try await fetch(status: 404, code: 1207, message: "Resource not found")
        let different = try await fetch(status: 404, code: 1207, message: "The zone does not have an expired subscription")
        XCTAssertFalse(different.isComplete)
        XCTAssertTrue(different.issues.contains { $0.contains("no_active_subscription=false") })
        XCTAssertFalse(wrongCode.isComplete); XCTAssertFalse(wrongStatus.isComplete); XCTAssertFalse(unknown.isComplete)
        XCTAssertTrue(wrongCode.issues.contains { $0.contains("HTTP 404") })
    }
}
extension BillingCoreTests {
    func testErrorWordsPreserveSafeQualifiersWithoutDisclosure() async throws {
        let mock = ScriptTransport { request, _ in
            let path = request.url!.path
            if path.hasSuffix("/info") { return (200, #"{"success":true,"result":{"covered":true,"subscriptions":[{"id":"s","billing_cycle_anchor_timestamp":"2026-02-01T00:00:00Z","start_timestamp":"2026-01-01T00:00:00Z"}]}}"#, [:]) }
            if path.hasSuffix("/billable-usage") || path.hasSuffix("/subscriptions") { return (200, #"{"success":true,"result":[]}"#, [:]) }
            if path.hasSuffix("/zones") { return (200, #"{"success":true,"result":[{"id":"z","name":"secret-name"}],"result_info":{"page":1,"total_pages":1}}"#, [:]) }
            return (404, #"{"success":false,"errors":[{"code":1207,"message":"The zone secret-name does not have an active legacy subscription"}]}"#, [:])
        }
        let snapshot = try await BillingService(transport: mock).fetchSnapshot(account: AccountProfile(id: "a", name: "A"), token: "token", now: ISO8601DateFormatter().date(from: "2026-02-15T00:00:00Z")!)
        let issue = try XCTUnwrap(snapshot.issues.first { $0.contains("HTTP 404") })
        XCTAssertFalse(snapshot.isComplete)
        XCTAssertTrue(issue.contains("no_active_subscription=false"))
        XCTAssertTrue(issue.contains("active,legacy,subscription"))
        XCTAssertTrue(issue.contains("zone,_,_,does"))
        XCTAssertFalse(issue.contains("secret")); XCTAssertFalse(issue.contains("name"))
    }
}
extension BillingCoreTests {
    func testNoSubscriptionSummaryRedactsSensitiveValues() async throws {
        let mock = ScriptTransport { request, _ in
            let path = request.url!.path
            if path.hasSuffix("/info") { return (200, #"{"success":true,"result":{"covered":true,"subscriptions":[{"id":"s","billing_cycle_anchor_timestamp":"2026-02-01T00:00:00Z","start_timestamp":"2026-01-01T00:00:00Z"}]}}"#, [:]) }
            if path.hasSuffix("/billable-usage") || path.hasSuffix("/subscriptions") { return (200, #"{"success":true,"result":[]}"#, [:]) }
            if path.hasSuffix("/zones") { return (200, #"{"success":true,"result":[{"id":"z","name":"sample.example.com"}],"result_info":{"page":1,"total_pages":1}}"#, [:]) }
            return (404, #"{"success":false,"errors":[{"code":1207,"message":"The zone does not have an active legacy subscription. user@example.com sample.example.com https://secret.example/path abcdef0123456789abcdeffedcba1234 123e4567-e89b-12d3-a456-426614174000 $12.34 bearerSecret1234 verylongopaquestringABC123"}]}"#, [:])
        }
        let snapshot = try await BillingService(transport: mock).fetchSnapshot(account: AccountProfile(id: "a", name: "A"), token: "bearerSecret1234", now: ISO8601DateFormatter().date(from: "2026-02-15T00:00:00Z")!)
        let issue = try XCTUnwrap(snapshot.issues.first { $0.contains("HTTP 404") })
        XCTAssertTrue(issue.contains("active legacy subscription"))
        for secret in ["user@example.com", "sample.example.com", "https://", "abcdef0123456789", "123e4567", "12.34", "bearerSecret1234", "verylongopaquestringABC123"] { XCTAssertFalse(issue.contains(secret), secret) }
        let summary = try XCTUnwrap(issue.components(separatedBy: "summary=").last)
        XCTAssertLessThanOrEqual(summary.count, 240)
        XCTAssertFalse(snapshot.isComplete)
    }
}
