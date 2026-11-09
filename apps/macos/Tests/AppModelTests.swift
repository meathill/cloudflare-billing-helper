import XCTest
import BillingCore
@testable import MacApp

private final class MemoryTokens: TokenStore {
    var values: [String: String] = [:]
    var reads = 0
    var deletes = 0
    func save(_ token: String, accountID: String) throws { values[accountID] = token }
    func load(accountID: String) throws -> String? { reads += 1; return values[accountID] }
    func delete(accountID: String) throws { deletes += 1; values.removeValue(forKey: accountID) }
}

@MainActor final class AppModelTests: XCTestCase {
    func testDeletionDuringRefreshCannotRestoreAccountOrCache() async throws {
        let id = String(repeating: "a", count: 32), profile = AccountProfile(id: String(repeating: "a", count: 32), name: "Test")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!, directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defaults.set(try JSONEncoder().encode([profile]), forKey: "accounts")
        let tokens = MemoryTokens(); try tokens.save("test", accountID: id)
        let gate = Gate()
        let model = AppModel(defaults: defaults, tokenStore: tokens, cacheDirectory: directory, seedSample: false, startLifecycle: false) { account, _, _ in
            await gate.wait(); return BillingSnapshot(accountID: account.id, cycles: [], totals: [], checkedAt: Date(), isComplete: true)
        }
        let task = Task { await model.refresh(profile) }
        await Task.yield(); model.delete(profile); await gate.release(); await task.value
        XCTAssertTrue(model.accounts.isEmpty); XCTAssertNil(model.snapshots[id]); XCTAssertNil(try SnapshotCache(directory: directory).load(accountID: id))
    }
    func testStaleAccountRefreshesAndSwitchKeepsSeparateSnapshots() async throws {
        let first = AccountProfile(id: String(repeating: "c", count: 32), name: "First"), second = AccountProfile(id: String(repeating: "d", count: 32), name: "Second")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!, directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defaults.set(try JSONEncoder().encode([first, second]), forKey: "accounts")
        let cache = SnapshotCache(directory: directory)
        try cache.save(BillingSnapshot(accountID: first.id, cycles: [], totals: [], checkedAt: Date().addingTimeInterval(-7 * 3600), isComplete: true))
        try cache.save(BillingSnapshot(accountID: second.id, cycles: [], totals: [], checkedAt: Date(), isComplete: true))
        let tokens = MemoryTokens(); try tokens.save("test", accountID: first.id); try tokens.save("test", accountID: second.id)
        let counter = Counter()
        let model = AppModel(defaults: defaults, tokenStore: tokens, cacheDirectory: directory, seedSample: false, startLifecycle: false) { account, _, _ in await counter.increment(); return BillingSnapshot(accountID: account.id, cycles: [], totals: [], checkedAt: Date(), isComplete: true) }
        await model.refreshStale(); let count = await counter.count; XCTAssertEqual(count, 1)
        model.select(second.id); XCTAssertEqual(model.current?.accountID, second.id)
        model.select(first.id); XCTAssertEqual(model.current?.accountID, first.id)
    }
    func testBudgetSuppressesIncompleteSnapshotAndDeduplicatesDeliveredNotice() async throws {
        let profile = AccountProfile(id: String(repeating: "e", count: 32), name: "Test"), defaults = UserDefaults(suiteName: UUID().uuidString)!, directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defaults.set(try JSONEncoder().encode([profile]), forKey: "accounts")
        defaults.set(true, forKey: "budget.\(profile.id).USD.enabled"); defaults.set("100", forKey: "budget.\(profile.id).USD.amount")
        let tokens = MemoryTokens(); try tokens.save("test", accountID: profile.id)
        let counter = Counter(), delivered = expectation(description: "notification delivered")
        let cycle = Cycle(start: Date().addingTimeInterval(-86400), end: Date().addingTimeInterval(86400))
        let complete = BillingSnapshot(accountID: profile.id, cycles: [cycle], totals: [CurrencyTotals(currency: "USD", fixedCost: 10, usageCost: 80, forecastCost: nil)], checkedAt: Date(), isComplete: true, selectedCycle: cycle)
        let incomplete = BillingSnapshot(accountID: profile.id, cycles: [cycle], totals: complete.totals, checkedAt: Date(), isComplete: false, selectedCycle: cycle)
        let model = AppModel(defaults: defaults, tokenStore: tokens, cacheDirectory: directory, seedSample: false, startLifecycle: false, deliverNotice: { _ in await counter.increment(); delivered.fulfill(); return true }) { _, _, _ in complete }
        model.notifyIfNeeded(incomplete); await Task.yield(); var count = await counter.count; XCTAssertEqual(count, 0)
        model.notifyIfNeeded(complete); await fulfillment(of: [delivered], timeout: 2)
        await Task.yield(); model.notifyIfNeeded(complete); await Task.yield(); count = await counter.count; XCTAssertEqual(count, 1)
    }
    func testDuplicateRefreshIsCoalesced() async throws {
        let profile = AccountProfile(id: String(repeating: "f", count: 32), name: "Test"), defaults = UserDefaults(suiteName: UUID().uuidString)!, directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defaults.set(try JSONEncoder().encode([profile]), forKey: "accounts"); let tokens = MemoryTokens(); try tokens.save("test", accountID: profile.id)
        let gate = Gate(), counter = Counter()
        let model = AppModel(defaults: defaults, tokenStore: tokens, cacheDirectory: directory, seedSample: false, startLifecycle: false) { account, _, _ in await counter.increment(); await gate.wait(); return BillingSnapshot(accountID: account.id, cycles: [], totals: [], checkedAt: Date(), isComplete: true) }
        let first = Task { await model.refresh(profile) }; await Task.yield(); await model.refresh(profile); let count = await counter.count; XCTAssertEqual(count, 1); await gate.release(); await first.value
    }
    func testBudgetFollowsSelectedAccount() throws {
        let first = AccountProfile(id: String(repeating: "1", count: 32), name: "First"), second = AccountProfile(id: String(repeating: "2", count: 32), name: "Second"), defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(try JSONEncoder().encode([first, second]), forKey: "accounts")
        defaults.set(true, forKey: "budget.\(first.id).USD.enabled"); defaults.set("100", forKey: "budget.\(first.id).USD.amount"); defaults.set(true, forKey: "budget.\(second.id).USD.enabled"); defaults.set("250", forKey: "budget.\(second.id).USD.amount")
        let model = AppModel(defaults: defaults, tokenStore: MemoryTokens(), cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), seedSample: false, startLifecycle: false)
        model.select(first.id); XCTAssertEqual(model.budgetText, "100"); model.select(second.id); XCTAssertEqual(model.budgetText, "250"); model.select(first.id); XCTAssertEqual(model.budgetText, "100")
    }
    func testLegacyDemoPreferenceAndArgumentCannotReplaceRealAccounts() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!, directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let profile = AccountProfile(id: String(repeating: "a", count: 32), name: "Real")
        let data = try JSONEncoder().encode([profile]); defaults.set(data, forKey: "accounts"); defaults.set(profile.id, forKey: "selected"); defaults.set(true, forKey: "demoMode")
        defaults.set("120", forKey: "budget.\(profile.id).USD.amount"); defaults.set(true, forKey: "budget.\(profile.id).USD.enabled")
        let cache = SnapshotCache(directory: directory); try cache.save(BillingSnapshot(accountID: profile.id, cycles: [], totals: [], checkedAt: Date(), isComplete: true))
        let tokens = MemoryTokens(); try tokens.save("real-token", accountID: profile.id)
        let originalArguments = CommandLine.arguments; CommandLine.arguments.append("--demo"); defer { CommandLine.arguments = originalArguments }
        let model = AppModel(designPreview: false, defaults: defaults, tokenStore: tokens, cacheDirectory: directory, seedSample: false, startLifecycle: false)
        XCTAssertFalse(model.demo); XCTAssertEqual(model.accounts, [profile]); XCTAssertEqual(model.selectedID, profile.id)
        XCTAssertNil(defaults.object(forKey: "demoMode")); XCTAssertEqual(defaults.data(forKey: "accounts"), data); XCTAssertEqual(defaults.string(forKey: "selected"), profile.id)
        XCTAssertEqual(defaults.string(forKey: "budget.\(profile.id).USD.amount"), "120"); XCTAssertTrue(defaults.bool(forKey: "budget.\(profile.id).USD.enabled"))
        XCTAssertEqual(tokens.values[profile.id], "real-token"); XCTAssertEqual(tokens.reads, 0); XCTAssertEqual(tokens.deletes, 0); XCTAssertNotNil(try cache.load(accountID: profile.id))
        model.setupDemo(seed: true); model.restoreDemo(); XCTAssertEqual(model.accounts, [profile]); XCTAssertEqual(model.selectedID, profile.id)
    }
    func testDemoModeDoesNotTouchRealTokenOrCache() throws {
        let profile = AccountProfile(id: String(repeating: "3", count: 32), name: "Real"), defaults = UserDefaults(suiteName: UUID().uuidString)!, directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defaults.set(try JSONEncoder().encode([profile]), forKey: "accounts")
        let snapshot = BillingSnapshot(accountID: profile.id, cycles: [], totals: [], checkedAt: Date(), isComplete: true)
        let cache = SnapshotCache(directory: directory); try cache.save(snapshot)
        let tokens = MemoryTokens(); try tokens.save("secret", accountID: profile.id)
        let model = AppModel(designPreview: true, previewDefaults: defaults, defaults: defaults, tokenStore: tokens, cacheDirectory: directory, seedSample: false, startLifecycle: false)
        XCTAssertEqual(tokens.reads, 0); XCTAssertEqual(model.accounts.count, 2); XCTAssertNil(model.snapshots[profile.id]); XCTAssertNotNil(try cache.load(accountID: profile.id))
        XCTAssertNil(defaults.object(forKey: "demoMode")); XCTAssertEqual(tokens.reads, 0); XCTAssertNotNil(try cache.load(accountID: profile.id))
    }
    func testDemoDeletionPersistsAndRemainsIsolatedFromRealData() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!, directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let real = AccountProfile(id: String(repeating: "a", count: 32), name: "Real")
        let encoded = try JSONEncoder().encode([real]); defaults.set(encoded, forKey: "accounts"); defaults.set(real.id, forKey: "selected")
        defaults.set("200", forKey: "budget.\(real.id).USD.amount")
        let cache = SnapshotCache(directory: directory); try cache.save(BillingSnapshot(accountID: real.id, cycles: [], totals: [], checkedAt: Date(), isComplete: true))
        let tokens = MemoryTokens(); try tokens.save("secret", accountID: real.id)
        let model = AppModel(designPreview: true, previewDefaults: defaults, defaults: defaults, tokenStore: tokens, cacheDirectory: directory, seedSample: false, startLifecycle: false)
        let first = try XCTUnwrap(model.accounts.first), second = try XCTUnwrap(model.accounts.last)
        model.select(second.id); model.delete(first)
        XCTAssertEqual(model.accounts.map(\.id), [second.id]); XCTAssertEqual(model.selectedID, second.id); XCTAssertNil(model.snapshots[first.id])
        await model.refresh(second); await model.refreshStale()
        let restarted = AppModel(designPreview: true, previewDefaults: defaults, defaults: defaults, tokenStore: tokens, cacheDirectory: directory, seedSample: false, startLifecycle: false)
        XCTAssertEqual(restarted.accounts.map(\.id), [second.id]); XCTAssertEqual(restarted.selectedID, second.id)
        restarted.delete(second); XCTAssertTrue(restarted.accounts.isEmpty); XCTAssertTrue(restarted.snapshots.isEmpty); XCTAssertEqual(restarted.selectedID, "")
        let emptyRestart = AppModel(designPreview: true, previewDefaults: defaults, defaults: defaults, tokenStore: tokens, cacheDirectory: directory, seedSample: false, startLifecycle: false)
        XCTAssertTrue(emptyRestart.accounts.isEmpty); XCTAssertEqual(emptyRestart.selectedID, "")
        emptyRestart.setupDemo(seed: true); XCTAssertEqual(emptyRestart.accounts.count, 2)
        let afterExport = AppModel(designPreview: true, previewDefaults: defaults, defaults: defaults, tokenStore: tokens, cacheDirectory: directory, seedSample: false, startLifecycle: false)
        XCTAssertTrue(afterExport.accounts.isEmpty)
        afterExport.restoreDemo(); XCTAssertEqual(afterExport.accounts.map(\.id), ["demo", "demo2"]); XCTAssertEqual(afterExport.selectedID, "demo")
        let restoredRestart = AppModel(designPreview: true, previewDefaults: defaults, defaults: defaults, tokenStore: tokens, cacheDirectory: directory, seedSample: false, startLifecycle: false)
        XCTAssertEqual(restoredRestart.accounts.count, 2); XCTAssertEqual(restoredRestart.selectedID, "demo")
        XCTAssertEqual(tokens.deletes, 0); XCTAssertEqual(tokens.reads, 0); XCTAssertEqual(tokens.values[real.id], "secret")
        XCTAssertEqual(defaults.data(forKey: "accounts"), encoded); XCTAssertEqual(defaults.string(forKey: "selected"), real.id); XCTAssertEqual(defaults.string(forKey: "budget.\(real.id).USD.amount"), "200")
        XCTAssertNotNil(try cache.load(accountID: real.id))
    }
    func testDeletingSelectedDemoAccountSelectsRemainingAccount() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = AppModel(designPreview: true, previewDefaults: defaults, defaults: defaults, tokenStore: MemoryTokens(), cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), seedSample: false, startLifecycle: false)
        let selected = model.accounts[0], remaining = model.accounts[1]
        model.delete(selected); XCTAssertEqual(model.selectedID, remaining.id); XCTAssertEqual(model.current?.accountID, remaining.id)
        let restarted = AppModel(designPreview: true, previewDefaults: defaults, defaults: defaults, tokenStore: MemoryTokens(), cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), seedSample: false, startLifecycle: false)
        XCTAssertEqual(restarted.selectedID, remaining.id); XCTAssertEqual(restarted.accounts.map(\.id), [remaining.id])
    }
    func testStaleRefreshKeepsSelectedUnexpiredCycle() async throws {
        let profile = AccountProfile(id: String(repeating: "4", count: 32), name: "Test"), defaults = UserDefaults(suiteName: UUID().uuidString)!, directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defaults.set(try JSONEncoder().encode([profile]), forKey: "accounts")
        let cycle = Cycle(start: Date().addingTimeInterval(-86400), end: Date().addingTimeInterval(86400))
        try SnapshotCache(directory: directory).save(BillingSnapshot(accountID: profile.id, cycles: [cycle], totals: [], checkedAt: Date().addingTimeInterval(-7 * 3600), isComplete: true, selectedCycle: cycle))
        let tokens = MemoryTokens(); try tokens.save("test", accountID: profile.id); let recorder = CycleRecorder()
        let model = AppModel(defaults: defaults, tokenStore: tokens, cacheDirectory: directory, seedSample: false, startLifecycle: false) { account, _, selected in await recorder.set(selected); return BillingSnapshot(accountID: account.id, cycles: [cycle], totals: [], checkedAt: Date(), isComplete: true, selectedCycle: selected) }
        await model.refreshStale(); let result = await recorder.cycle; XCTAssertEqual(result, cycle)
    }
    func testFailureBackoffAndAuthenticationPause() async throws {
        let profile = AccountProfile(id: String(repeating: "5", count: 32), name: "Test"), defaults = UserDefaults(suiteName: UUID().uuidString)!, directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defaults.set(try JSONEncoder().encode([profile]), forKey: "accounts"); let tokens = MemoryTokens(); try tokens.save("test", accountID: profile.id)
        let now = TestClock(), counter = Counter()
        let model = AppModel(defaults: defaults, tokenStore: tokens, cacheDirectory: directory, seedSample: false, startLifecycle: false, clock: { now.value }) { _, _, _ in await counter.increment(); throw BillingError.httpStatus(500) }
        await model.refreshStale(); now.value.addTimeInterval(60); await model.refreshStale(); var count = await counter.count; XCTAssertEqual(count, 1)
        now.value.addTimeInterval(240); await model.refreshStale(); count = await counter.count; XCTAssertEqual(count, 2)
        let authCounter = Counter(), auth = AppModel(defaults: defaults, tokenStore: tokens, cacheDirectory: directory, seedSample: false, startLifecycle: false, clock: { now.value }) { _, _, _ in await authCounter.increment(); throw BillingError.invalidToken }
        await auth.refreshStale(); now.value.addTimeInterval(24 * 3600); await auth.refreshStale(); var authCount = await authCounter.count; XCTAssertEqual(authCount, 1)
        let restarted = AppModel(defaults: defaults, tokenStore: tokens, cacheDirectory: directory, seedSample: false, startLifecycle: false, clock: { now.value }) { _, _, _ in await authCounter.increment(); throw BillingError.invalidToken }
        await restarted.refreshStale(); authCount = await authCounter.count; XCTAssertEqual(authCount, 1)
        await restarted.refresh(profile); authCount = await authCounter.count; XCTAssertEqual(authCount, 2)
    }
    func testSavedBudgetsListEachAccountAndSurviveRelaunch() throws {
        let first = AccountProfile(id: String(repeating: "a", count: 32), name: "Alpha")
        let second = AccountProfile(id: String(repeating: "b", count: 32), name: "Beta")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defaults.set(try JSONEncoder().encode([first, second]), forKey: "accounts")
        defaults.set(first.id, forKey: "selected")
        var authorizationRequests = 0
        let model = AppModel(defaults: defaults, tokenStore: MemoryTokens(), cacheDirectory: directory, seedSample: false, startLifecycle: false, requestNotificationAuthorization: { authorizationRequests += 1 })
        XCTAssertTrue(model.savedBudgets.isEmpty)
        model.budgetEnabled = true
        model.budgetCurrency = "USD"
        model.budgetText = "80"
        model.saveBudget()
        model.budgetEnabled = false
        model.saveBudget()
        XCTAssertTrue(model.savedBudgets.isEmpty)
        XCTAssertEqual(defaults.string(forKey: "budget.\(first.id).USD.amount"), "80")
        XCTAssertFalse(defaults.bool(forKey: "budget.\(first.id).USD.enabled"))
        model.budgetEnabled = true
        model.saveBudget()
        model.select(second.id)
        model.budgetEnabled = false
        model.budgetCurrency = "EUR"
        model.budgetText = "30"
        model.saveBudget()
        XCTAssertEqual(authorizationRequests, 2)
        XCTAssertEqual(model.savedBudgets.map { "\($0.accountName):\($0.currency):\($0.amount):\($0.enabled)" }, ["Alpha:USD:80:true"])
        XCTAssertEqual(defaults.string(forKey: "budget.\(second.id).EUR.amount"), "30")
        let reloaded = AppModel(defaults: defaults, tokenStore: MemoryTokens(), cacheDirectory: directory, seedSample: false, startLifecycle: false, requestNotificationAuthorization: {})
        XCTAssertEqual(reloaded.savedBudgets.map(\.id), ["\(first.id)|USD"])
        XCTAssertEqual(reloaded.savedBudgets.map(\.amount), ["80"])
        reloaded.disableSavedBudget(reloaded.savedBudgets[0])
        XCTAssertTrue(reloaded.savedBudgets.isEmpty)
        XCTAssertEqual(defaults.string(forKey: "budget.\(first.id).USD.amount"), "80")
        XCTAssertFalse(defaults.bool(forKey: "budget.\(first.id).USD.enabled"))
        reloaded.select(first.id)
        XCTAssertFalse(reloaded.budgetEnabled)
        XCTAssertEqual(reloaded.budgetText, "80")
        reloaded.budgetEnabled = true
        reloaded.saveBudget()
        XCTAssertEqual(reloaded.savedBudgets.map(\.accountID), [first.id])
        reloaded.delete(second)
        XCTAssertEqual(reloaded.savedBudgets.map(\.accountID), [first.id])
    }
    func testFreshCachedAccountDoesNotRefreshOnStartupCheck() async throws {
        let profile = AccountProfile(id: String(repeating: "b", count: 32), name: "Test"), defaults = UserDefaults(suiteName: UUID().uuidString)!, directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defaults.set(try JSONEncoder().encode([profile]), forKey: "accounts")
        try SnapshotCache(directory: directory).save(BillingSnapshot(accountID: profile.id, cycles: [], totals: [], checkedAt: Date(), isComplete: true))
        let tokens = MemoryTokens(); try tokens.save("test", accountID: profile.id)
        let counter = Counter()
        let model = AppModel(defaults: defaults, tokenStore: tokens, cacheDirectory: directory, seedSample: false, startLifecycle: false) { account, _, _ in await counter.increment(); return BillingSnapshot(accountID: account.id, cycles: [], totals: [], checkedAt: Date(), isComplete: true) }
        await model.refreshStale(); let count = await counter.count; XCTAssertEqual(count, 0)
    }
    func testQuotaAlertsNotifyOncePerLevelOnlyWhenEnabled() async throws {
        let profile = AccountProfile(id: String(repeating: "9", count: 32), name: "Quota"), defaults = UserDefaults(suiteName: UUID().uuidString)!, directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defaults.set(try JSONEncoder().encode([profile]), forKey: "accounts")
        let cycle = Cycle(start: Date().addingTimeInterval(-10 * 86400), end: Date().addingTimeInterval(20 * 86400))
        func snapshot(_ status: QuotaStatus) -> BillingSnapshot {
            let quota = UsageQuota(serviceName: "KV List Operations", currency: "USD", unit: "ops", used: 800_000, billable: 0, included: 1_000_000, includedSource: "catalog", asOf: Date(), dailyRate: 100_000, rateBasis: "recent", projectedTotal: 2_800_000, exhaustionDate: Date().addingTimeInterval(2 * 86400), status: status, projectedOverageCost: 9, points: [], isComplete: true)
            return BillingSnapshot(accountID: profile.id, cycles: [cycle], totals: [], checkedAt: Date(), isComplete: false, selectedCycle: cycle, usageQuotas: [quota])
        }
        let counter = Counter(), bodies = BodyRecorder()
        var authorizations = 0
        let model = AppModel(defaults: defaults, tokenStore: MemoryTokens(), cacheDirectory: directory, seedSample: false, startLifecycle: false, requestNotificationAuthorization: { authorizations += 1 }, deliverNotice: { request in await counter.increment(); await bodies.append(request.content.body); return true })
        model.notifyIfNeeded(snapshot(.danger)); for _ in 0..<5 { await Task.yield() }
        var count = await counter.count; XCTAssertEqual(count, 0)
        model.setQuotaAlerts(true); XCTAssertEqual(authorizations, 1); XCTAssertTrue(defaults.bool(forKey: "quotaAlertsEnabled"))
        model.notifyIfNeeded(snapshot(.danger)); for _ in 0..<5 { await Task.yield() }
        model.notifyIfNeeded(snapshot(.danger)); for _ in 0..<5 { await Task.yield() }
        count = await counter.count; XCTAssertEqual(count, 1)
        model.notifyIfNeeded(snapshot(.exhausted)); for _ in 0..<5 { await Task.yield() }
        model.notifyIfNeeded(snapshot(.warn)); for _ in 0..<5 { await Task.yield() }
        count = await counter.count; XCTAssertEqual(count, 2)
        let first = await bodies.values.first ?? ""
        XCTAssertTrue(first.hasPrefix("Quota: "), first)
    }
}
private actor BodyRecorder { var values: [String] = []; func append(_ value: String) { values.append(value) } }
private actor Counter { var count = 0; func increment() { count += 1 } }
private actor Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func wait() async { if released { return }; await withCheckedContinuation { continuation = $0 } }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

private actor CycleRecorder { var cycle: Cycle?; func set(_ value: Cycle?) { cycle = value } }

@MainActor private final class TestClock { var value = Date(timeIntervalSince1970: 1_800_000_000) }
