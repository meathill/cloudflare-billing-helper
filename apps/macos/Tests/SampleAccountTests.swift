import XCTest
import BillingCore
@testable import MacApp

private final class SampleTestTokens: TokenStore {
    var values: [String: String] = [:]; var reads = 0; var writes = 0; var deletes = 0
    func save(_ token: String, accountID: String) throws { writes += 1; values[accountID] = token }
    func load(accountID: String) throws -> String? { reads += 1; return values[accountID] }
    func delete(accountID: String) throws { deletes += 1; values.removeValue(forKey: accountID) }
}
private actor SampleCounter { var value = 0; func increment() { value += 1 } }
private actor SampleGate {
    var continuation: CheckedContinuation<Void, Never>?
    var released = false
    func wait() async { if released { return }; await withCheckedContinuation { continuation = $0 } }
    func untilWaiting() async { while continuation == nil && !released { await Task.yield() } }
    func release() { released = true; continuation?.resume(); continuation = nil }
}
@MainActor final class SampleAccountTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_750_400)
    func testFreshInstallAddsOneLocalSampleWithoutCredentialsOrAutomaticNotifications() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!, tokens = SampleTestTokens(), calls = SampleCounter()
        var authorizationRequests = 0
        let model = AppModel(defaults: defaults, tokenStore: tokens, cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), startLifecycle: false, clock: { self.now }, requestNotificationAuthorization: { authorizationRequests += 1 }, deliverNotice: { _ in await calls.increment(); return true }, fetch: { account, _, _ in await calls.increment(); return SampleBilling.snapshot(now: self.now) })
        XCTAssertEqual(model.accounts, [SampleBilling.account]); XCTAssertEqual(model.selectedID, SampleBilling.account.id)
        XCTAssertTrue(model.isSampleSelected); XCTAssertFalse(model.budgetEnabled); XCTAssertNotNil(model.current)
        await model.refresh(SampleBilling.account); await model.refreshStale()
        XCTAssertEqual(tokens.reads, 0); XCTAssertEqual(tokens.writes, 0); XCTAssertEqual(tokens.deletes, 0); XCTAssertEqual(authorizationRequests, 0)
        let count = await calls.value; XCTAssertEqual(count, 0)
        XCTAssertEqual(accountDisplayName(SampleBilling.account), tr("Sample account", "示例账户"))
    }
    func testUpgradePreservesRealSelectionAndDeletionDoesNotReviveSample() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!, directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), tokens = SampleTestTokens()
        let id = String(repeating: "a", count: 32)
        let oldData = Data("[{\"id\":\"\(id)\",\"name\":\"Real\"}]".utf8)
        defaults.set(oldData, forKey: "accounts"); defaults.set(id, forKey: "selected"); defaults.set("120", forKey: "budget.\(id).USD.amount"); defaults.set(true, forKey: "budget.\(id).USD.enabled")
        try tokens.save("real-token", accountID: id); let cache = SnapshotCache(directory: directory)
        try cache.save(BillingSnapshot(accountID: id, cycles: [], totals: [], checkedAt: now, isComplete: true))
        let model = AppModel(defaults: defaults, tokenStore: tokens, cacheDirectory: directory, startLifecycle: false, clock: { self.now })
        XCTAssertEqual(model.accounts.count, 2); XCTAssertEqual(model.accounts.first?.source, .cloudflare); XCTAssertEqual(model.selectedID, id)
        XCTAssertTrue(model.hasSampleAccount); XCTAssertEqual(defaults.string(forKey: "budget.\(id).USD.amount"), "120")
        model.select(SampleBilling.account.id); model.delete(SampleBilling.account)
        XCTAssertFalse(model.hasSampleAccount); XCTAssertEqual(model.selectedID, id); XCTAssertEqual(tokens.deletes, 0); XCTAssertEqual(tokens.values[id], "real-token"); XCTAssertNotNil(try cache.load(accountID: id))
        let restarted = AppModel(defaults: defaults, tokenStore: tokens, cacheDirectory: directory, startLifecycle: false, clock: { self.now })
        XCTAssertFalse(restarted.hasSampleAccount); XCTAssertEqual(restarted.accounts.map(\.id), [id]); XCTAssertEqual(restarted.selectedID, id)
        restarted.addSampleAccount(); XCTAssertTrue(restarted.hasSampleAccount); XCTAssertEqual(restarted.selectedID, id)
        let restored = AppModel(defaults: defaults, tokenStore: tokens, cacheDirectory: directory, startLifecycle: false, clock: { self.now })
        XCTAssertTrue(restored.hasSampleAccount); XCTAssertEqual(restored.selectedID, id); XCTAssertEqual(tokens.deletes, 0)
    }
    func testInvalidExistingAccountDataIsNotOverwrittenBySampleInitialization() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!, invalid = Data("not-valid-account-json".utf8)
        defaults.set(invalid, forKey: "accounts")
        let model = AppModel(defaults: defaults, tokenStore: SampleTestTokens(), cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), startLifecycle: false, clock: { self.now })
        XCTAssertTrue(model.accounts.isEmpty); XCTAssertFalse(model.hasSampleAccount)
        XCTAssertEqual(defaults.data(forKey: "accounts"), invalid); XCTAssertNil(defaults.object(forKey: "sample.initialized"))
    }
    func testAutomaticSelectionUsesNewAccountCurrencyForBudget() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!, directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), tokens = SampleTestTokens()
        let id = String(repeating: "c", count: 32), real = AccountProfile(id: id, name: "EUR")
        defaults.set(try JSONEncoder().encode([real]), forKey: "accounts"); defaults.set(id, forKey: "selected"); defaults.set("77", forKey: "budget.\(id).EUR.amount")
        try tokens.save("secret", accountID: id)
        try SnapshotCache(directory: directory).save(BillingSnapshot(accountID: id, cycles: [], totals: [CurrencyTotals(currency: "EUR", fixedCost: 0, usageCost: 0, forecastCost: nil)], checkedAt: now, isComplete: true))
        let model = AppModel(defaults: defaults, tokenStore: tokens, cacheDirectory: directory, startLifecycle: false, clock: { self.now })
        model.select(SampleBilling.account.id); model.delete(SampleBilling.account)
        XCTAssertEqual(model.selectedID, id); XCTAssertEqual(model.budgetCurrency, "EUR"); XCTAssertEqual(model.budgetText, "77")
        model.delete(real); XCTAssertTrue(model.accounts.isEmpty)
        model.budgetCurrency = "EUR"; model.addSampleAccount()
        XCTAssertEqual(model.selectedID, SampleBilling.account.id); XCTAssertEqual(model.budgetCurrency, "USD"); XCTAssertEqual(model.current?.accountID, SampleBilling.account.id)
    }
    func testSampleBudgetIsSeparateAndOnlyRequestsPermissionAfterOptIn() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!, tokens = SampleTestTokens(), delivered = expectation(description: "sample thresholds"); delivered.expectedFulfillmentCount = 3
        var authorizationRequests = 0
        let model = AppModel(defaults: defaults, tokenStore: tokens, cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), startLifecycle: false, clock: { self.now }, requestNotificationAuthorization: { authorizationRequests += 1 }, deliverNotice: { _ in delivered.fulfill(); return true })
        XCTAssertFalse(model.budgetEnabled); XCTAssertEqual(authorizationRequests, 0)
        model.budgetEnabled = true; model.budgetText = "1"; model.saveBudget()
        XCTAssertEqual(authorizationRequests, 1); XCTAssertEqual(defaults.string(forKey: "sample.budget.USD.amount"), "1")
        await model.refresh(SampleBilling.account); await fulfillment(of: [delivered], timeout: 2)
        XCTAssertNil(defaults.object(forKey: "budget.\(SampleBilling.account.id).USD.amount")); XCTAssertEqual(tokens.reads, 0)
        model.delete(SampleBilling.account); XCTAssertNil(defaults.object(forKey: "sample.budget.USD.amount")); XCTAssertEqual(tokens.deletes, 0)
    }
    func testRealRefreshCompletingAfterSampleSelectionDoesNotChangeVisibleSample() async throws {
        let id = String(repeating: "b", count: 32), real = AccountProfile(id: id, name: "Real"), defaults = UserDefaults(suiteName: UUID().uuidString)!, tokens = SampleTestTokens(), gate = SampleGate()
        defaults.set(try JSONEncoder().encode([real]), forKey: "accounts"); defaults.set(id, forKey: "selected"); try tokens.save("secret", accountID: id)
        let model = AppModel(defaults: defaults, tokenStore: tokens, cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), startLifecycle: false, clock: { self.now }, fetch: { account, _, _ in await gate.wait(); return BillingSnapshot(accountID: account.id, cycles: [], totals: [], checkedAt: self.now, isComplete: true) })
        let refresh = Task { await model.refresh(real) }; await gate.untilWaiting(); model.select(SampleBilling.account.id); await gate.release(); await refresh.value
        XCTAssertEqual(model.selectedID, SampleBilling.account.id); XCTAssertEqual(model.current?.accountID, SampleBilling.account.id); XCTAssertNotNil(model.snapshots[id])
    }
}
