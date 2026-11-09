import XCTest
import BillingCore
@testable import MacApp

private final class ForbiddenPreviewTokens: TokenStore {
    var reads = 0; var saves = 0; var deletes = 0
    func save(_ token: String, accountID: String) throws { saves += 1 }
    func load(accountID: String) throws -> String? { reads += 1; return "secret" }
    func delete(accountID: String) throws { deletes += 1 }
}
private actor PreviewCalls { var value = 0; func hit() { value += 1 } }
@MainActor final class DesignPreviewTests: XCTestCase {
    func testPreviewForcesDemoAndCannotAccessRealServicesOrPreferences() async throws {
        let realDefaults = UserDefaults(suiteName: UUID().uuidString)!, real = AccountProfile(id: "real", name: "Real")
        let data = try JSONEncoder().encode([real]); realDefaults.set(data, forKey: "accounts"); realDefaults.set(false, forKey: "demoMode")
        let tokens = ForbiddenPreviewTokens(), calls = PreviewCalls()
        let model = AppModel(designPreview: true, defaults: realDefaults, tokenStore: tokens, cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), startLifecycle: true, deliverNotice: { _ in await calls.hit(); return true }, discover: { _ in await calls.hit(); return [real] }, fetch: { account, _, _ in await calls.hit(); return BillingSnapshot(accountID: account.id, cycles: [], totals: [], checkedAt: Date(), isComplete: true) })
        XCTAssertTrue(model.isDesignPreview); XCTAssertTrue(model.demo); XCTAssertFalse(model.accounts.contains(where: { $0.id == real.id }))
        await model.discoverAccounts(token: "test"); await model.refresh(real); model.saveBudget(); model.setLaunch(true)
        XCTAssertEqual(tokens.reads, 0); XCTAssertEqual(tokens.saves, 0); XCTAssertEqual(tokens.deletes, 0)
        let count = await calls.value; XCTAssertEqual(count, 0); XCTAssertEqual(realDefaults.data(forKey: "accounts"), data); XCTAssertFalse(realDefaults.bool(forKey: "demoMode"))
    }
    func testStoreScreenshotModeIsPreviewOnlyAndKeepsServicesIsolated() async throws {
        let original = CommandLine.arguments; CommandLine.arguments.append(contentsOf: ["--export-previews", "--store-screenshot"]); defer { CommandLine.arguments = original }
        let realDefaults = UserDefaults(suiteName: UUID().uuidString)!, previewDefaults = UserDefaults(suiteName: UUID().uuidString)!, tokens = ForbiddenPreviewTokens(), calls = PreviewCalls()
        let profile = AccountProfile(id: "real", name: "Real"); let data = try JSONEncoder().encode([profile]); realDefaults.set(data, forKey: "accounts")
        let preview = AppModel(designPreview: true, previewDefaults: previewDefaults, defaults: realDefaults, tokenStore: tokens, startLifecycle: true, deliverNotice: { _ in await calls.hit(); return true }, discover: { _ in await calls.hit(); return [profile] }, fetch: { account, _, _ in await calls.hit(); return BillingSnapshot(accountID: account.id, cycles: [], totals: [], checkedAt: Date(), isComplete: true) })
        XCTAssertTrue(preview.isStoreScreenshot); XCTAssertTrue(preview.demo)
        preview.setupDemo(seed: true); XCTAssertEqual(preview.accounts.count, 2)
        preview.setupStoreSampleScreenshot(); XCTAssertEqual(preview.accounts, [SampleBilling.account]); XCTAssertEqual(preview.current?.accountID, SampleBilling.account.id)
        await preview.discoverAccounts(token: "test"); await preview.refresh(profile); preview.budgetEnabled = true; preview.saveBudget(); preview.setLaunch(true)
        let count = await calls.value; XCTAssertEqual(count, 0); XCTAssertEqual(tokens.reads, 0); XCTAssertEqual(tokens.saves, 0); XCTAssertEqual(tokens.deletes, 0); XCTAssertEqual(realDefaults.data(forKey: "accounts"), data)
        let normal = AppModel(designPreview: false, defaults: realDefaults, tokenStore: tokens, seedSample: false, startLifecycle: false)
        XCTAssertFalse(normal.isStoreScreenshot); XCTAssertFalse(normal.demo); XCTAssertEqual(normal.accounts, [profile])
    }
    func testAccountFailureAndStalenessNeverShowAvailable() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let fresh = BillingSnapshot(accountID: "a", cycles: [], totals: [], checkedAt: now, isComplete: true)
        let old = BillingSnapshot(accountID: "a", cycles: [], totals: [], checkedAt: now.addingTimeInterval(-7 * 3600), isComplete: true)
        let partial = BillingSnapshot(accountID: "a", cycles: [], totals: [], checkedAt: now, isComplete: false)
        XCTAssertEqual(accountDisplayStatus(demo: false, loading: false, error: "failed", snapshot: fresh, now: now), .error)
        XCTAssertEqual(accountDisplayStatus(demo: false, loading: false, error: nil, snapshot: old, now: now), .stale)
        XCTAssertEqual(accountDisplayStatus(demo: false, loading: false, error: nil, snapshot: partial, now: now), .partial)
        XCTAssertEqual(accountDisplayStatus(demo: false, loading: false, error: nil, snapshot: fresh, now: now), .available)
    }
    func testInitialPageDependsOnAccountsOrExplicitPreview() {
        XCTAssertEqual(AppPage.initial(hasAccounts: true, requested: nil), .overview)
        XCTAssertEqual(AppPage.initial(hasAccounts: false, requested: nil), .accounts)
        XCTAssertEqual(AppPage.initial(hasAccounts: true, requested: "budget"), .budget)
        XCTAssertEqual(AppPage.initial(hasAccounts: true, requested: "about"), .about)
        XCTAssertEqual(AppPage.initial(hasAccounts: true, requested: "unknown"), .overview)
        XCTAssertEqual(AppPage.allCases.map(\.shortcutLabel), ["⌘1", "⌘2", "⌘3", "⌘4", "⌘5"])
    }
}
