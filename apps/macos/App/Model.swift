import SwiftUI
import AppKit
import Network
import ServiceManagement
import UserNotifications
import OSLog
import BillingCore

private let refreshLog = Logger(subsystem: "com.meathill.CloudflareBillingHelper", category: "refresh")

var previewLanguage: String?
func tr(_ en: String, _ zh: String) -> String { (previewLanguage ?? Locale.preferredLanguages.first ?? "en").hasPrefix("zh") ? zh : en }
func money(_ value: Decimal?, _ currency: String) -> String {
    guard let value else { return tr("Unavailable", "暂不可用") }
    return (value as NSDecimalNumber).decimalValue.formatted(.currency(code: currency).locale(Locale(identifier: previewLanguage ?? Locale.current.identifier)))
}

private final class PreviewTokenStore: TokenStore {
    private var values: [String: String] = [:]
    func save(_ token: String, accountID: String) throws { values[accountID] = token }
    func load(accountID: String) throws -> String? { values[accountID] }
    func delete(accountID: String) throws { values.removeValue(forKey: accountID) }
}

@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var accounts: [AccountProfile] = []
    @Published var selectedID = ""
    @Published var snapshots: [String: BillingSnapshot] = [:]
    @Published var selectedCycle: Cycle?
    @Published private var errors: [String: String] = [:]
    @Published private var loadingIDs = Set<String>()
    @Published private var queuedBillingIDs = Set<String>()
    @Published private var saving = false
    private var savingIDs = Set<String>()
    var error: String? { get { errors[selectedID] } set { errors[selectedID] = newValue } }
    var loading: Bool { saving || loadingIDs.contains(selectedID) }
    func accountError(_ id: String) -> String? { errors[id] }
    func accountIsLoading(_ id: String) -> Bool { loadingIDs.contains(id) || queuedBillingIDs.contains(id) }
    var billingActivity: String? {
        if loadingIDs.contains(selectedID) { return tr("Checking billing…", "正在读取账单…") }
        if queuedBillingIDs.contains(selectedID) { return tr("Billing check queued.", "账单检查已排队。") }
        return nil
    }
    @Published var budgetEnabled = false
    @Published var budgetText = ""
    @Published var budgetCurrency = "USD"
    @Published private(set) var savedBudgets: [SavedBudget] = []
    @Published private(set) var quotaAlertsEnabled = false
    @Published var launchAtLogin = false
    @Published var discovering = false
    @Published var importing = false
    @Published var discoveredAccounts: [AccountProfile] = []
    @Published var selectedDiscoveredIDs = Set<String>()
    @Published var discoveryMessage: String?
    /// Discovered accounts that are already added but whose Keychain token is missing; importing restores the token.
    @Published private(set) var missingTokenIDs = Set<String>()
    private var discoveryEpoch = 0
    private var discoveredGenerations: [String: Int] = [:]
    private var activeDiscoveryToken: String?
    private let discover: (String) async throws -> [AccountProfile]
    let demo: Bool
    let isDesignPreview: Bool
    let isStoreScreenshot: Bool
    private let defaults: UserDefaults
    private let tokens: any TokenStore
    private let cache: SnapshotCache
    private let fetch: (AccountProfile, String, Cycle?) async throws -> BillingSnapshot
    private let deliverNotice: (UNNotificationRequest) async -> Bool
    private let requestNotificationAuthorization: () -> Void
    private let clock: () -> Date
    private struct RetryState: Codable { var failures: Int; var next: Date?; var paused: Bool }
    private var retries: [String: RetryState] = [:]
    private var generations: [String: Int] = [:]
    private var monitor: NWPathMonitor?
    private var wakeObserver: NSObjectProtocol?
    private var timer: Timer?
    private var priorNetwork = false
    private var inFlight: [String: Cycle?] = [:]
    private var accountCycles: [String: Cycle] = [:]
    private var pendingNotices = Set<String>()
    var current: BillingSnapshot? { snapshots[selectedID] }
    var selectedAccount: AccountProfile? { accounts.first { $0.id == selectedID } }
    var isSampleSelected: Bool { selectedAccount?.source == .sample }
    var hasSampleAccount: Bool { accounts.contains { $0.source == .sample } }
    var activeCycle: Cycle? { current?.selectedCycle ?? current?.cycles.first }
    var totals: [CurrencyTotals] {
        current?.totals ?? []
    }
    init(designPreview: Bool? = nil, previewDefaults: UserDefaults? = nil, defaults injectedDefaults: UserDefaults = .standard, tokenStore: any TokenStore = KeychainTokenStore(), cacheDirectory: URL? = nil, seedSample: Bool = true, startLifecycle: Bool = true, clock: @escaping () -> Date = Date.init, requestNotificationAuthorization: (() -> Void)? = nil, deliverNotice: ((UNNotificationRequest) async -> Bool)? = nil, discover: ((String) async throws -> [AccountProfile])? = nil, fetch: ((AccountProfile, String, Cycle?) async throws -> BillingSnapshot)? = nil) {
        let isolated = designPreview ?? (Bundle.main.bundleIdentifier == "com.meathill.CloudflareBillingHelper.DesignPreview")
        isDesignPreview = isolated
        isStoreScreenshot = isolated && CommandLine.arguments.contains("--export-previews") && CommandLine.arguments.contains("--store-screenshot")
        demo = isolated
        defaults = isolated ? (previewDefaults ?? UserDefaults(suiteName: "com.meathill.CloudflareBillingHelper.DesignPreview.Fixtures")!) : injectedDefaults
        tokens = isolated ? PreviewTokenStore() : tokenStore
        self.clock = clock
        self.requestNotificationAuthorization = requestNotificationAuthorization ?? { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
        self.deliverNotice = deliverNotice ?? { request in await withCheckedContinuation { continuation in UNUserNotificationCenter.current().add(request) { error in continuation.resume(returning: error == nil) } } }
        let discoveryService = AccountDiscovery()
        self.discover = discover ?? { try await discoveryService.discover(token: $0) }
        let service = BillingService(transport: URLSessionBillingTransport(), catalog: Bundle.main.url(forResource: "catalog", withExtension: "json").flatMap { try? ProductCatalog(contentsOf: $0) })
        self.fetch = fetch ?? { account, token, cycle in try await service.fetchSnapshot(account: account, token: token, cycle: cycle) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CloudflareBillingHelper", isDirectory: true)
        cache = SnapshotCache(directory: isolated ? FileManager.default.temporaryDirectory.appendingPathComponent("CloudflareBillingHelper-DesignPreview", isDirectory: true) : (cacheDirectory ?? base.appendingPathComponent("cache")))
        if demo { setupDemo() } else {
        defaults.removeObject(forKey: "demoMode")
        let savedAccountsData = defaults.data(forKey: "accounts")
        let savedAccounts = savedAccountsData.flatMap { try? JSONDecoder().decode([AccountProfile].self, from: $0) }
        if let savedAccounts { accounts = savedAccounts }
        selectedID = defaults.string(forKey: "selected") ?? accounts.first?.id ?? ""
        if !accounts.contains(where: { $0.id == selectedID }) { selectedID = accounts.first?.id ?? "" }
        if seedSample, defaults.object(forKey: "sample.initialized") == nil, savedAccountsData == nil || savedAccounts != nil {
            if !accounts.contains(where: { $0.source == .sample }) {
                accounts.append(SampleBilling.account)
                if selectedID.isEmpty { selectedID = SampleBilling.account.id }
            }
            persist()
            defaults.set(true, forKey: "sample.initialized")
        }
        budgetEnabled = defaults.bool(forKey: "budgetEnabled")
        budgetText = defaults.string(forKey: "budget") ?? ""
        quotaAlertsEnabled = defaults.bool(forKey: "quotaAlertsEnabled")
        launchAtLogin = SMAppService.mainApp.status == .enabled
        for account in accounts {
            if account.source == .sample { snapshots[account.id] = SampleBilling.snapshot(now: clock()) }
            else { if let snapshot = try? cache.load(accountID: account.id) { snapshots[account.id] = snapshot }; loadRetry(for: account.id) }
        }
        syncSelectedBudget()
        reloadSavedBudgets()
        }
        guard startLifecycle, !isDesignPreview else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in await self?.refreshStale() } }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in await self?.refreshStale() } }
        let pathMonitor = NWPathMonitor(); monitor = pathMonitor
        pathMonitor.pathUpdateHandler = { [weak self] path in Task { @MainActor in
            guard let self else { return }; let connected = path.status == .satisfied
            if connected && !self.priorNetwork { await self.refreshStale() }; self.priorNetwork = connected
        } }
        pathMonitor.start(queue: DispatchQueue(label: "billing.network"))
        Task { await refreshStale() }
    }
    func setupDemo(seed: Bool = false) {
        guard isDesignPreview else { return }
        budgetEnabled = false; budgetText = ""; budgetCurrency = "USD"
        let account = AccountProfile(id: isStoreScreenshot ? "a1b2c3d4e5f67890123456789abc9f0e" : "demo", name: tr("Example account", "示例账户")); let second = AccountProfile(id: isStoreScreenshot ? "d4e5f67890123456789abcdef0127b8c" : "demo2", name: tr("Studio account", "工作室账户"))
        let available = [account, second]
        let saved = seed ? [account.id, second.id] : (defaults.stringArray(forKey: "demo.accountIDs") ?? [account.id, second.id])
        accounts = available.filter { saved.contains($0.id) }
        let priorSelection = seed ? account.id : (defaults.string(forKey: "demo.selected") ?? account.id)
        selectedID = accounts.contains(where: { $0.id == priorSelection }) ? priorSelection : (accounts.first?.id ?? "")
        snapshots.removeAll()
        let calendar = Calendar(identifier: .gregorian); let start = Date(timeIntervalSince1970: 1793491200); let end = calendar.date(byAdding: .month, value: 1, to: start)!; let demoNow = start.addingTimeInterval(3 * 86400)
        let cycle = Cycle(start: start, end: end)
        let fixed = [FixedSubscription(id: "workers", currency: "USD", price: 5, period: cycle, name: "Workers Paid")]
        let usage = [UsageCharge(id: "r2", currency: "USD", cost: Decimal(string: "3.42"), period: cycle, serviceName: "R2"), UsageCharge(id: "images", currency: "USD", cost: Decimal(string: "1.18"), period: cycle, serviceName: "Images")]
        func previewTrend(_ service: String, _ amounts: [String]) -> UsageTrend {
            let points = amounts.enumerated().map { index, amount in UsageTrendPoint(at: start.addingTimeInterval(Double(index + 1) * 86400), cost: Decimal(string: amount)!, startsSegment: index == 0) }
            return UsageTrend(currency: "USD", serviceName: service, points: points, isComplete: true, source: "cumulative")
        }
        let r2Trend = previewTrend("R2", ["1.00", "2.10", "3.42"])
        let imagesTrend = previewTrend("Images", ["0.30", "0.70", "1.18"])
        let totalTrend = previewTrend("", ["1.30", "2.80", "4.60"])
        snapshots[account.id] = BillingSnapshot(accountID: account.id, cycles: [cycle], totals: BillingCalculator.calculate(cycle: cycle, subscriptions: fixed, usage: usage, now: demoNow), checkedAt: demoNow, isComplete: true, subscriptions: fixed, usage: usage, sourceAsOf: demoNow, selectedCycle: cycle, usageProductTotals: [UsageProductTotal(serviceName: "R2", currency: "USD", cost: Decimal(string: "3.42"), source: "period-sum", isComplete: true), UsageProductTotal(serviceName: "Images", currency: "USD", cost: Decimal(string: "1.18"), source: "period-sum", isComplete: true)], usageTrends: [r2Trend, imagesTrend], usageTotalTrends: [totalTrend])
        let secondUsage = [UsageCharge(id: "kv", currency: "USD", cost: Decimal(string: "14.70"), period: cycle, serviceName: "KV")]; snapshots[second.id] = BillingSnapshot(accountID: second.id, cycles: [cycle], totals: BillingCalculator.calculate(cycle: cycle, subscriptions: fixed, usage: secondUsage, now: demoNow), checkedAt: demoNow, isComplete: true, subscriptions: fixed, usage: secondUsage, sourceAsOf: demoNow, selectedCycle: cycle, usageProductTotals: [UsageProductTotal(serviceName: "KV", currency: "USD", cost: Decimal(string: "14.70"), source: "period-sum", isComplete: true)], usageTrends: [previewTrend("KV", ["4.00", "9.00", "14.70"])], usageTotalTrends: [previewTrend("", ["4.00", "9.00", "14.70"])])
        snapshots = snapshots.filter { saved.contains($0.key) }
    }
    func setupStoreSampleScreenshot() {
        guard isDesignPreview, isStoreScreenshot else { return }
        let account = SampleBilling.account
        let snapshot = SampleBilling.snapshot(now: Date(timeIntervalSince1970: 1_793_750_400))
        accounts = [account]; selectedID = account.id; selectedCycle = nil
        snapshots = [account.id: snapshot]; budgetEnabled = false; budgetText = ""; budgetCurrency = "USD"
    }
    func setupProductFallbackPreview() {
        guard isDesignPreview, let snapshot = current, let cycle = snapshot.selectedCycle else { return }
        let longName = "Browser Run - Extremely Long Demonstration Service Name for Picker Layout Verification"
        let points = (1...3).map { UsageTrendPoint(at: cycle.start.addingTimeInterval(Double($0) * 86400), cost: 0, startsSegment: $0 == 1) }
        let extra = UsageTrend(currency: "USD", serviceName: longName, points: points, isComplete: true)
        let product = UsageProductTotal(serviceName: longName, currency: "USD", cost: 0, source: "cumulative", isComplete: true, rawServiceNames: [longName])
        snapshots[snapshot.accountID] = BillingSnapshot(accountID: snapshot.accountID, cycles: snapshot.cycles, totals: snapshot.totals, checkedAt: snapshot.checkedAt, isComplete: snapshot.isComplete, subscriptions: snapshot.subscriptions, usage: snapshot.usage, issues: snapshot.issues, sourceAsOf: snapshot.sourceAsOf, forecastIsEstimate: snapshot.forecastIsEstimate, selectedCycle: snapshot.selectedCycle, forecastNote: snapshot.forecastNote, fixedCostIsEstimate: snapshot.fixedCostIsEstimate, fixedEstimateNote: snapshot.fixedEstimateNote, usageDiagnostics: snapshot.usageDiagnostics, usageProductTotals: (snapshot.usageProductTotals ?? []) + [product], usageTrends: (snapshot.usageTrends ?? []) + [extra], usageTotalTrends: [], usageQuotas: snapshot.usageQuotas)
    }
    private func persistDemo() {
        defaults.set(accounts.map(\.id), forKey: "demo.accountIDs")
        defaults.set(selectedID, forKey: "demo.selected")
    }
    func restoreDemo() {
        guard isDesignPreview else { return }
        defaults.set(["demo", "demo2"], forKey: "demo.accountIDs")
        defaults.set("demo", forKey: "demo.selected")
        selectedCycle = nil; setupDemo()
    }
    func persist() { if let data = try? JSONEncoder().encode(accounts) { defaults.set(data, forKey: "accounts") }; defaults.set(selectedID, forKey: "selected") }
    func select(_ id: String) { if let cycle = selectedCycle { accountCycles[selectedID] = cycle }; selectedID = id; selectedCycle = accountCycles[id]; budgetCurrency = snapshots[id]?.totals.first?.currency ?? "USD"; if demo { persistDemo() } else { persist(); loadBudget() } }
    private func loadRetry(for id: String) {
        if let data = defaults.data(forKey: "retry.\(id)"), let state = try? JSONDecoder().decode(RetryState.self, from: data) {
            retries[id] = state
            if state.paused { errors[id] = tr("Automatic refresh paused. Update the token or refresh manually.", "自动刷新已暂停，请更新令牌或手动刷新。") }
        }
    }
    private func clearRetry(for id: String) { retries.removeValue(forKey: id); defaults.removeObject(forKey: "retry.\(id)") }
    func refreshStale() async {
        let now = clock()
        for account in accounts where snapshots[account.id].map({ Freshness.isStale(checkedAt: $0.checkedAt, now: now) }) ?? true {
            if let retry = retries[account.id], retry.paused || (retry.next.map { $0 > now } ?? false) { continue }
            let cycle = snapshots[account.id]?.selectedCycle
            await refresh(account, cycle: cycle.flatMap { $0.end > now ? $0 : nil })
        }
    }
    func refresh(_ account: AccountProfile, cycle: Cycle? = nil) async {
        guard !demo, accounts.contains(where: { $0.id == account.id && $0.source == account.source }) else { return }
        if account.source == .sample {
            snapshots[account.id] = SampleBilling.snapshot(now: clock()); errors.removeValue(forKey: account.id); queuedBillingIDs.remove(account.id)
            if let snapshot = snapshots[account.id] { notifyIfNeeded(snapshot) }
            return
        }
        if let existing = inFlight[account.id], existing == cycle { return }
        inFlight[account.id] = .some(cycle)
        let generation = (generations[account.id] ?? 0) + 1; generations[account.id] = generation
        queuedBillingIDs.remove(account.id); errors[account.id] = nil
        loadingIDs.insert(account.id); defer { if generations[account.id] == generation { inFlight.removeValue(forKey: account.id); loadingIDs.remove(account.id) } }
        do {
            guard let token = try tokens.load(accountID: account.id) else { throw AppError.missingToken }
            let result = try await fetch(account, token, cycle)
            guard generations[account.id] == generation, accounts.contains(where: { $0.id == account.id }) else { return }
            snapshots[account.id] = result; try cache.save(result); clearRetry(for: account.id); errors[account.id] = nil; if selectedID == account.id { budgetCurrency = result.totals.first?.currency ?? "USD"; loadBudget() }; notifyIfNeeded(result)
        } catch {
            guard generations[account.id] == generation, accounts.contains(where: { $0.id == account.id }) else { return }
            // BillingError descriptions carry only status codes, error codes and field paths; other errors log only their domain and code.
            let summary = error is BillingError || error is AppError ? String(describing: error) : "\((error as NSError).domain) \((error as NSError).code)"
            refreshLog.error("Refresh failed: \(summary, privacy: .public)")
            let count = min((retries[account.id]?.failures ?? 0) + 1, 8)
            let paused: Bool
            if case BillingError.invalidToken = error { paused = true } else if case BillingError.insufficientPermissions = error { paused = true } else if case AppError.missingToken = error { paused = true } else { paused = false }
            let delay = min(6 * 3600.0, 300.0 * pow(2.0, Double(count - 1)))
            let state = RetryState(failures: count, next: paused ? nil : clock().addingTimeInterval(delay), paused: paused)
            retries[account.id] = state; if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: "retry.\(account.id)") }
            if case BillingError.invalidToken = error { errors[account.id] = tr("API token is invalid.", "API 令牌无效。") } else if case BillingError.insufficientPermissions = error { errors[account.id] = tr("Token lacks billing permissions.", "令牌缺少账单读取权限。") } else if case AppError.missingToken = error { errors[account.id] = tr("This account's API token is missing from Keychain. Paste the token again on the Accounts page.", "钥匙串中找不到此账户的 API 令牌，请到账户页重新粘贴令牌。") } else if error is URLError { errors[account.id] = tr("Could not reach Cloudflare. Check your network, proxy or VPN. Showing saved data if available.", "连不上 Cloudflare，请检查网络、代理或 VPN。如有缓存，将显示上次保存的数据。") } else { errors[account.id] = tr("Refresh failed. Showing saved data if available.", "刷新失败。如有缓存，将显示上次保存的数据。") }
        }
    }
    func saveAccount(name: String, id: String, token: String) async -> Bool {
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !demo, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, id.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil, !token.isEmpty else { error = tr("Enter an account name, ID and API token.", "请输入账户名称、ID 和 API 令牌。"); return false }
        let account = AccountProfile(id: id, name: name)
        let generation = (generations[id] ?? 0) + 1; generations[id] = generation
        saving = true; savingIDs.insert(id); defer { saving = false; savingIDs.remove(id) }
        do {
            let result = try await fetch(account, token, nil)
            guard generations[id] == generation, !demo else { return false }
            try tokens.save(token, accountID: id)
            accounts.removeAll { $0.id == id }; accounts.append(account); selectedID = id; selectedCycle = nil
            snapshots[id] = result; try cache.save(result); clearRetry(for: id); persist(); error = nil; return true
        } catch { if case BillingError.invalidToken = error { self.error = tr("API token is invalid.", "API 令牌无效。") } else if case BillingError.insufficientPermissions = error { self.error = tr("Token lacks billing permissions.", "令牌缺少账单读取权限。") } else { self.error = tr("Could not validate this account. Check the ID, token permissions and connection.", "无法验证账户，请检查 ID、令牌权限和网络连接。") }; return false }
    }
    func delete(_ account: AccountProfile) {
        if demo {
            guard accounts.contains(where: { $0.id == account.id }) else { return }
            accounts.removeAll { $0.id == account.id }; snapshots.removeValue(forKey: account.id)
            if selectedID == account.id { selectedID = accounts.first?.id ?? ""; selectedCycle = nil }
            persistDemo(); return
        }
        if account.source == .sample {
            guard accounts.contains(where: { $0.id == account.id && $0.source == .sample }) else { return }
            generations[account.id, default: 0] += 1
            accounts.removeAll { $0.id == account.id && $0.source == .sample }; snapshots.removeValue(forKey: account.id)
            queuedBillingIDs.remove(account.id); loadingIDs.remove(account.id); errors.removeValue(forKey: account.id)
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("sample.budget.") || key.hasPrefix("sample.notice.") { defaults.removeObject(forKey: key) }
            defaults.set(true, forKey: "sample.initialized")
            if selectedID == account.id { selectedID = accounts.first?.id ?? ""; selectedCycle = nil; syncSelectedBudget() }
            persist(); reloadSavedBudgets(); return
        }
        generations[account.id, default: 0] += 1
        do { try tokens.delete(accountID: account.id) } catch { self.error = tr("Could not remove the token from Keychain.", "无法从钥匙串删除令牌。"); return }
        do { try cache.delete(accountID: account.id) } catch { self.error = tr("Could not remove cached billing data.", "无法删除缓存的账单数据。"); return }
        accounts.removeAll { $0.id == account.id }; snapshots.removeValue(forKey: account.id); clearRetry(for: account.id); loadingIDs.remove(account.id); queuedBillingIDs.remove(account.id); errors.removeValue(forKey: account.id)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("budget.\(account.id).") || key.hasPrefix("notice.\(account.id).") { defaults.removeObject(forKey: key) }
        if selectedID == account.id { selectedID = accounts.first?.id ?? ""; selectedCycle = nil; syncSelectedBudget() }; persist(); reloadSavedBudgets()
    }
    func addSampleAccount() {
        guard !demo, !hasSampleAccount, !accounts.contains(where: { $0.id == SampleBilling.account.id }) else { return }
        let account = SampleBilling.account
        accounts.append(account); snapshots[account.id] = SampleBilling.snapshot(now: clock())
        defaults.set(true, forKey: "sample.initialized")
        if selectedID.isEmpty { selectedID = account.id; syncSelectedBudget() }
        persist()
    }
    func cancelDiscovery() {
        discoveryEpoch += 1; discovering = false; importing = false
        discoveredAccounts = []; selectedDiscoveredIDs = []; discoveredGenerations = [:]; activeDiscoveryToken = nil; discoveryMessage = nil; missingTokenIDs = []
    }
    func discoverAccounts(token: String) async {
        guard !demo, !discovering, !importing else { return }
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { discoveryMessage = tr("Enter an API token.", "请输入 API 令牌。"); return }
        discoveryEpoch += 1; let epoch = discoveryEpoch; let baseline = generations
        discovering = true; discoveryMessage = nil; discoveredAccounts = []; selectedDiscoveredIDs = []; activeDiscoveryToken = nil
        defer { if epoch == discoveryEpoch { discovering = false } }
        do {
            let results = try await discover(token.trimmingCharacters(in: .whitespacesAndNewlines))
            guard epoch == discoveryEpoch, !demo else { return }
            var seen = Set<String>()
            discoveredAccounts = results.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
            discoveredGenerations = Dictionary(uniqueKeysWithValues: discoveredAccounts.map { ($0.id, baseline[$0.id] ?? 0) })
            missingTokenIDs = Set(discoveredAccounts.filter { candidate in accounts.contains(where: { $0.id == candidate.id && $0.source == .cloudflare }) && (try? tokens.load(accountID: candidate.id)) == nil }.map(\.id))
            selectedDiscoveredIDs = Set(discoveredAccounts.filter { candidate in !accounts.contains(where: { $0.id == candidate.id }) || missingTokenIDs.contains(candidate.id) }.map(\.id))
            activeDiscoveryToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if discoveredAccounts.isEmpty { discoveryMessage = tr("No accessible accounts were found.", "没有找到可访问的账户。") }
        } catch {
            guard epoch == discoveryEpoch else { return }
            if case AccountDiscoveryError.invalidToken = error { discoveryMessage = tr("API token is invalid.", "API 令牌无效。") }
            else if case AccountDiscoveryError.insufficientPermissions = error { discoveryMessage = tr("The token cannot list accounts. Check its Account Read permissions or use advanced manual setup.", "令牌无法列出账户，请检查账户读取权限或使用高级手动设置。") }
            else if case AccountDiscoveryError.noAccounts = error { discoveryMessage = tr("No accessible accounts were found.", "没有找到可访问的账户。") }
            else if case AccountDiscoveryError.networkError = error { discoveryMessage = tr("Could not reach Cloudflare (api.cloudflare.com). Your token was not checked. Check your network, proxy or VPN, then try again.", "连不上 Cloudflare（api.cloudflare.com），令牌还没有被校验。请检查网络、代理或 VPN 后重试。") }
            else if case AccountDiscoveryError.httpStatus(let status) = error { discoveryMessage = tr("Cloudflare returned HTTP \(status) while listing accounts. Try again later, or use advanced manual setup.", "Cloudflare 列出账户时返回 HTTP \(status)，请稍后重试，或使用高级手动配置。") }
            else { discoveryMessage = tr("Cloudflare returned an unexpected account list. Try again later, or use advanced manual setup.", "Cloudflare 返回的账户列表无法识别，请稍后重试，或使用高级手动配置。") }
            refreshLog.error("Account discovery failed: \(String(describing: error), privacy: .public)")
        }
    }
    func importDiscovered() -> Bool {
        guard !demo, !discovering, !importing else { return false }
        let chosen = discoveredAccounts.filter { selectedDiscoveredIDs.contains($0.id) }
        guard !chosen.isEmpty else { discoveryMessage = tr("Select at least one account.", "请至少选择一个账户。"); return false }
        guard let token = activeDiscoveryToken, !token.isEmpty else { return false }
        var added: [AccountProfile] = [], skipped = 0, failed = 0
        var remaining = Set<String>()
        for account in chosen {
            let restoring = missingTokenIDs.contains(account.id)
            guard !savingIDs.contains(account.id), restoring || !accounts.contains(where: { $0.id == account.id }), generations[account.id, default: 0] == discoveredGenerations[account.id] else { skipped += 1; continue }
            let generation = (generations[account.id] ?? 0) + 1; generations[account.id] = generation
            do {
                try tokens.save(token, accountID: account.id)
                if !restoring { accounts.append(account) }; clearRetry(for: account.id)
                errors[account.id] = nil; queuedBillingIDs.insert(account.id)
                if selectedID.isEmpty { selectedID = account.id; syncSelectedBudget() }
                persist(); added.append(account)
            } catch { failed += 1; remaining.insert(account.id); discoveredGenerations[account.id] = generation }
        }
        if !added.isEmpty { Task { for account in added { await refresh(account) } } }
        if failed > 0 {
            selectedDiscoveredIDs = remaining
            discoveryMessage = tr("Added \(added.count); skipped \(skipped). Could not save \(failed) account(s) in Keychain; try again.", "已添加 \(added.count) 个，跳过 \(skipped) 个；\(failed) 个账户无法保存到钥匙串，请重试。")
            return false
        }
        discoveredAccounts = []; selectedDiscoveredIDs = []; discoveredGenerations = [:]; activeDiscoveryToken = nil; missingTokenIDs = []
        discoveryMessage = tr("Added \(added.count) account(s); skipped \(skipped) existing or changed account(s). Billing data will be checked separately.", "已添加 \(added.count) 个账户，跳过 \(skipped) 个已存在或已变更的账户。账单数据将单独检查。")
        return true
    }
    private var budgetKey: String { isSampleSelected ? "sample.budget.\(budgetCurrency)" : "budget.\(selectedID).\(budgetCurrency)" }
    private func syncSelectedBudget() {
        budgetCurrency = snapshots[selectedID]?.totals.first?.currency ?? "USD"
        loadBudget()
    }
    func loadBudget() { budgetEnabled = defaults.bool(forKey: budgetKey + ".enabled"); budgetText = defaults.string(forKey: budgetKey + ".amount") ?? "" }
    func saveBudget() {
        guard !demo else { return }; defaults.set(budgetEnabled, forKey: budgetKey + ".enabled"); defaults.set(budgetText, forKey: budgetKey + ".amount")
        if budgetEnabled { requestNotificationAuthorization() }
        reloadSavedBudgets()
    }
    func disableSavedBudget(_ budget: SavedBudget) {
        guard !demo, let account = accounts.first(where: { $0.id == budget.accountID }) else { return }
        let base = account.source == .sample ? "sample.budget.\(budget.currency)" : "budget.\(account.id).\(budget.currency)"
        defaults.set(false, forKey: base + ".enabled")
        if account.id == selectedID, budget.currency == budgetCurrency { budgetEnabled = false }
        reloadSavedBudgets()
    }
    func usePreviewBudgets() {
        guard isDesignPreview else { return }
        savedBudgets = accounts.enumerated().map { index, account in
            SavedBudget(accountID: account.id, accountName: account.source == .sample ? tr("Sample account", "示例账户") : account.name, currency: "USD", amount: index == 0 ? "100" : "40", enabled: true)
        }
    }
    private func reloadSavedBudgets() { savedBudgets = collectSavedBudgets(accounts: accounts, defaults: defaults) }
    func setLaunch(_ enabled: Bool) {
        guard !demo else { launchAtLogin = false; return }
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; launchAtLogin = enabled }
        catch { launchAtLogin = SMAppService.mainApp.status == .enabled; self.error = tr("Could not update login item.", "无法更新登录启动设置。") }
    }
    func setQuotaAlerts(_ enabled: Bool) {
        guard !demo else { return }
        quotaAlertsEnabled = enabled; defaults.set(enabled, forKey: "quotaAlertsEnabled")
        guard enabled else { return }
        requestNotificationAuthorization()
        for snapshot in snapshots.values { notifyQuotaIfNeeded(snapshot) }
    }
    func notifyIfNeeded(_ s: BillingSnapshot) {
        notifyQuotaIfNeeded(s)
        guard !demo, s.isComplete, let account = accounts.first(where: { $0.id == s.accountID }), let cycle = s.selectedCycle ?? s.cycles.first else { return }
        for total in s.totals { let keyPrefix = account.source == .sample ? "sample.budget.\(total.currency)" : "budget.\(s.accountID).\(total.currency)"; guard defaults.bool(forKey: keyPrefix + ".enabled"), let budget = defaults.string(forKey: keyPrefix + ".amount").flatMap({ Decimal(string: $0) }) else { continue }; for event in BudgetEvaluator.evaluate(actual: total.total, forecast: total.forecastCost, budget: budget, currency: total.currency, cycle: cycle) {
            let key = account.source == .sample ? "sample.notice.\(event.key)" : "notice.\(s.accountID).\(event.key)"
            let accountName = account.source == .sample ? tr("Example account (sample)", "示例账户（本地样例）") : account.name
            let amount = event.threshold == "forecast" ? total.forecastCost : total.total
            let threshold = event.threshold == "forecast" ? tr("forecast exceeds budget", "预测超出预算") : tr("reached \(event.threshold)% of budget", "达到预算的 \(event.threshold)%")
            deliverOnce(key, accountID: s.accountID, title: tr("Cloudflare budget", "Cloudflare 预算"), body: "\(accountName): \(total.currency) \(money(amount, total.currency)), \(threshold).")
        } }
    }
    /// Notifies once per account, cycle, product and level when a free quota runs out or is projected to.
    func notifyQuotaIfNeeded(_ s: BillingSnapshot) {
        guard !demo, quotaAlertsEnabled, let account = accounts.first(where: { $0.id == s.accountID }), account.source != .sample, let cycle = s.selectedCycle, cycle.end > clock() else { return }
        for quota in quotaAlerts(s, cycle: cycle) {
            let key = "notice.\(s.accountID).quota.\(Int(cycle.start.timeIntervalSince1970)).\(quota.currency).\(quota.serviceName).\(quota.status.rawValue)"
            let overage = quotaOverageText(quota).map { ", " + $0 } ?? ""
            deliverOnce(key, accountID: s.accountID, title: tr("Cloudflare free quota", "Cloudflare 免费额度"), body: "\(account.name): \(productTrendLabel(quota.serviceName)), \(quotaStatusText(quota))\(overage).")
        }
    }
    private func deliverOnce(_ key: String, accountID: String, title: String, body: String) {
        guard !defaults.bool(forKey: key), !pendingNotices.contains(key) else { return }; pendingNotices.insert(key)
        let content = UNMutableNotificationContent(); content.title = title; content.body = body
        let generation = generations[accountID]; let request = UNNotificationRequest(identifier: key, content: content, trigger: nil)
        Task { let delivered = await deliverNotice(request); pendingNotices.remove(key); if delivered, generations[accountID] == generation, accounts.contains(where: { $0.id == accountID }) { defaults.set(true, forKey: key) } }
    }
    enum AppError: Error { case missingToken }
}

