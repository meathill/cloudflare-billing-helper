import XCTest
import BillingCore
@testable import MacApp

private final class ImportTokens: TokenStore {
    var values: [String: String] = [:]
    var saves = 0
    func save(_ token: String, accountID: String) throws { saves += 1; values[accountID] = token }
    func load(accountID: String) throws -> String? { values[accountID] }
    func delete(accountID: String) throws { values.removeValue(forKey: accountID) }
}
private actor ImportGate {
    var continuation: CheckedContinuation<Void, Never>?
    var released = false
    func wait() async { if released { return }; await withCheckedContinuation { continuation = $0 } }
    func untilWaiting() async { while continuation == nil && !released { await Task.yield() } }
    func release() { released = true; continuation?.resume(); continuation = nil }
}
@MainActor final class AccountImportTests: XCTestCase {
    private func setup(profiles: [AccountProfile] = [], tokens: ImportTokens, discover: @escaping (String) async throws -> [AccountProfile], fetch: @escaping (AccountProfile, String, Cycle?) async throws -> BillingSnapshot) throws -> (AppModel, UserDefaults) {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(try JSONEncoder().encode(profiles), forKey: "accounts")
        return (AppModel(defaults: defaults, tokenStore: tokens, cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), seedSample: false, startLifecycle: false, discover: discover, fetch: fetch), defaults)
    }
    private func result(_ account: AccountProfile) -> BillingSnapshot { BillingSnapshot(accountID: account.id, cycles: [], totals: [], checkedAt: Date(), isComplete: true) }
    func testDiscoveryImportsOnlySelectedAndPreservesDuplicates() async throws {
        let existing = AccountProfile(id: "existing", name: "Original"), first = AccountProfile(id: "first", name: "First"), second = AccountProfile(id: "second", name: "Second"), tokens = ImportTokens()
        try tokens.save("existing-secret", accountID: existing.id)
        let (model, defaults) = try setup(profiles: [existing], tokens: tokens, discover: { _ in [existing, first, first, second] }, fetch: { account, _, _ in self.result(account) })
        await model.discoverAccounts(token: "  new-secret  ")
        XCTAssertEqual(model.discoveredAccounts.count, 3); XCTAssertEqual(model.selectedDiscoveredIDs, Set([first.id, second.id]))
        model.selectedDiscoveredIDs.remove(second.id)
        let success = model.importDiscovered(); XCTAssertTrue(success)
        XCTAssertEqual(model.accounts.map(\.id), [existing.id, first.id]); XCTAssertEqual(tokens.values[first.id], "new-secret"); XCTAssertEqual(tokens.values[existing.id], "existing-secret"); XCTAssertNil(tokens.values[second.id])
        let allDefaults = defaults.dictionaryRepresentation().description
        XCTAssertFalse(allDefaults.contains("new-secret")); XCTAssertFalse(allDefaults.contains("existing-secret"))
    }
    func testAllDuplicateAccountsDoNotSaveOrReplaceToken() async throws {
        let profile = AccountProfile(id: "existing", name: "Original"), tokens = ImportTokens(); try tokens.save("old", accountID: profile.id)
        let (model, _) = try setup(profiles: [profile], tokens: tokens, discover: { _ in [profile] }, fetch: { account, _, _ in self.result(account) })
        await model.discoverAccounts(token: "new"); XCTAssertTrue(model.selectedDiscoveredIDs.isEmpty)
        model.selectedDiscoveredIDs.insert(profile.id)
        XCTAssertTrue(model.importDiscovered()); XCTAssertEqual(tokens.saves, 1); XCTAssertEqual(tokens.values[profile.id], "old"); XCTAssertEqual(model.accounts, [profile])
    }
    func testDeniedDiscoveryAndEmptySelectionSaveNoToken() async throws {
        let tokens = ImportTokens(), (model, _) = try setup(tokens: tokens, discover: { _ in throw AccountDiscoveryError.insufficientPermissions }, fetch: { account, _, _ in self.result(account) })
        await model.discoverAccounts(token: "secret"); XCTAssertNotNil(model.discoveryMessage); XCTAssertTrue(model.discoveredAccounts.isEmpty); XCTAssertTrue(tokens.values.isEmpty)
        let first = AccountProfile(id: "first", name: "First"), store = ImportTokens()
        let (selecting, _) = try setup(tokens: store, discover: { _ in [first] }, fetch: { account, _, _ in self.result(account) })
        await selecting.discoverAccounts(token: "secret"); selecting.selectedDiscoveredIDs.removeAll()
        let success = selecting.importDiscovered(); XCTAssertFalse(success); XCTAssertTrue(store.values.isEmpty); XCTAssertTrue(selecting.accounts.isEmpty)
    }
    func testCancelDuringDiscoveryAndImportDoesNotSave() async throws {
        let profile = AccountProfile(id: "first", name: "First"), discoveryGate = ImportGate(), tokens = ImportTokens()
        let (model, _) = try setup(tokens: tokens, discover: { _ in await discoveryGate.wait(); return [profile] }, fetch: { account, _, _ in self.result(account) })
        let search = Task { await model.discoverAccounts(token: "secret") }; await discoveryGate.untilWaiting(); model.cancelDiscovery(); await discoveryGate.release(); await search.value
        XCTAssertTrue(model.discoveredAccounts.isEmpty); XCTAssertTrue(tokens.values.isEmpty)
        let store = ImportTokens()
        let (importer, _) = try setup(tokens: store, discover: { _ in [profile] }, fetch: { account, _, _ in self.result(account) })
        await importer.discoverAccounts(token: "secret"); importer.cancelDiscovery()
        let success = importer.importDiscovered(); XCTAssertFalse(success); XCTAssertTrue(importer.accounts.isEmpty); XCTAssertTrue(store.values.isEmpty)
    }
    func testPendingManualSaveIsNotOverwrittenByDiscoveryImport() async throws {
        let id = String(repeating: "a", count: 32), profile = AccountProfile(id: id, name: "Discovered"), gate = ImportGate(), tokens = ImportTokens()
        let (model, _) = try setup(tokens: tokens, discover: { _ in [profile] }, fetch: { account, token, _ in if token == "manual" { await gate.wait() }; return self.result(account) })
        let saving = Task { await model.saveAccount(name: "Manual", id: id, token: "manual") }
        await gate.untilWaiting(); await model.discoverAccounts(token: "discovered")
        XCTAssertTrue(model.importDiscovered()); XCTAssertNil(tokens.values[id])
        await gate.release(); let saved = await saving.value
        XCTAssertTrue(saved); XCTAssertEqual(tokens.values[id], "manual"); XCTAssertEqual(model.accounts.first?.name, "Manual")
    }
    func testDeleteDuringDiscoveryCannotReimportChangedAccount() async throws {
        let profile = AccountProfile(id: "existing", name: "Existing"), gate = ImportGate(), tokens = ImportTokens(); try tokens.save("old", accountID: profile.id)
        let (model, _) = try setup(profiles: [profile], tokens: tokens, discover: { _ in await gate.wait(); return [profile] }, fetch: { account, _, _ in self.result(account) })
        let searching = Task { await model.discoverAccounts(token: "new") }; await gate.untilWaiting(); model.delete(profile); await gate.release(); await searching.value
        XCTAssertTrue(model.accounts.isEmpty)
        let success = model.importDiscovered(); XCTAssertTrue(success); XCTAssertTrue(model.accounts.isEmpty); XCTAssertNil(tokens.values[profile.id])
    }
    func testBillingQueueAndPartialDataAreNotReportedAsErrors() async throws {
        let first = AccountProfile(id: "first", name: "First"), second = AccountProfile(id: "second", name: "Second"), tokens = ImportTokens(), gate = ImportGate()
        let (model, _) = try setup(tokens: tokens, discover: { _ in [first, second] }, fetch: { account, _, _ in
            if account.id == first.id { await gate.wait() }
            return BillingSnapshot(accountID: account.id, cycles: [], totals: [], checkedAt: Date(), isComplete: account.id != first.id, issues: account.id == first.id ? ["Account subscriptions unavailable"] : [])
        })
        await model.discoverAccounts(token: "secret"); XCTAssertTrue(model.importDiscovered())
        await gate.untilWaiting()
        XCTAssertEqual(model.billingActivity, tr("Checking billing…", "正在读取账单…")); XCTAssertNil(model.error)
        model.select(second.id); XCTAssertEqual(model.billingActivity, tr("Billing check queued.", "账单检查已排队。")); XCTAssertNil(model.error)
        model.select(first.id); await gate.release()
        for _ in 0..<200 { if model.current != nil && model.billingActivity == nil { break }; await Task.yield() }
        XCTAssertNil(model.error); XCTAssertEqual(model.current?.isComplete, false); XCTAssertEqual(model.current?.issues, ["Account subscriptions unavailable"])
    }
    func testAccountBillingPermissionFailureDoesNotPretendBillingWasVerified() async throws {
        let profile = AccountProfile(id: "first", name: "First"), tokens = ImportTokens(), counter = ImportCounter()
        let (model, _) = try setup(tokens: tokens, discover: { _ in [profile] }, fetch: { _, _, _ in await counter.increment(); throw BillingError.insufficientPermissions })
        await model.discoverAccounts(token: "secret"); let success = model.importDiscovered()
        let permissionMessage = tr("Token lacks billing permissions.", "令牌缺少账单读取权限。")
        for _ in 0..<100 { if await counter.value > 0, model.error == permissionMessage { break }; await Task.yield() }
        XCTAssertTrue(success); XCTAssertEqual(model.accounts.map(\.id), [profile.id]); XCTAssertEqual(tokens.values[profile.id], "secret")
        XCTAssertEqual(model.error, permissionMessage); XCTAssertNil(model.snapshots[profile.id])
    }
    func testTemplateContainsExpectedReadOnlyPermissions() throws {
        let items = try XCTUnwrap(URLComponents(url: tokenTemplateURL(), resolvingAgainstBaseURL: false)?.queryItems)
        let encoded = try XCTUnwrap(items.first(where: { $0.name == "permissionGroupKeys" })?.value)
        let groups = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [[String: String]])
        XCTAssertEqual(Set(groups.compactMap { $0["key"] }), Set(["billing", "account_settings", "zone"]))
        XCTAssertTrue(groups.allSatisfy { $0["type"] == "read" })
        XCTAssertEqual(items.first(where: { $0.name == "accountId" })?.value, "*")
        XCTAssertEqual(items.first(where: { $0.name == "zoneId" })?.value, "all")
    }
}
private actor ImportCounter { var value = 0; func increment() { value += 1 } }
