import SwiftUI
import AppKit
import BillingCore
#if !DIRECT_DISTRIBUTION
import StoreKit
#endif

func accountDisplayName(_ account: AccountProfile) -> String {
    account.source == .sample ? tr("Sample account", "示例账户") : account.name
}

enum AppPage: String, CaseIterable, Identifiable {
    case overview, accounts, budget, settings, about
    var id: String { rawValue }
    var title: String {
        switch self { case .overview: return tr("Overview", "费用概览"); case .accounts: return tr("Accounts", "账户"); case .budget: return tr("Budget alerts", "预算提醒"); case .settings: return tr("Settings", "应用设置"); case .about: return tr("About", "关于") }
    }
    var shortcut: KeyEquivalent {
        switch self { case .overview: return "1"; case .accounts: return "2"; case .budget: return "3"; case .settings: return "4"; case .about: return "5" }
    }
    var shortcutLabel: String {
        switch self { case .overview: return "⌘1"; case .accounts: return "⌘2"; case .budget: return "⌘3"; case .settings: return "⌘4"; case .about: return "⌘5" }
    }
    var symbol: String {
        switch self { case .overview: return "chart.bar"; case .accounts: return "person.crop.circle"; case .budget: return "bell"; case .settings: return "gearshape"; case .about: return "info.circle" }
    }
    static func initial(hasAccounts: Bool, requested: String?) -> AppPage { requested.flatMap(AppPage.init(rawValue:)) ?? (hasAccounts ? .overview : .accounts) }
}

struct Panel: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { BrandMark(size: 30); VStack(alignment: .leading) { Text("Billing Helper").font(.headline); Text("for Cloudflare®").secondaryText().fixedSize(horizontal: false, vertical: true) }; Spacer(); if model.demo && !model.isStoreScreenshot { StatusPill(tr("Demo", "演示")) } }
            if model.accounts.isEmpty {
                Text(model.demo ? tr("No demo accounts remain.", "没有剩余的演示账户。") : tr("Add an account to see billing estimates.", "添加账户以查看费用估算。 ")).secondaryText().fixedSize(horizontal: false, vertical: true)
                if model.demo && !model.isStoreScreenshot { Button(tr("Restore demo data", "恢复演示数据")) { model.restoreDemo() } }
            } else {
                Picker(tr("Account", "账户"), selection: Binding(get: { model.selectedID }, set: { model.select($0) })) { ForEach(model.accounts) { Text(accountDisplayName($0)).tag($0.id) } }
                if model.isSampleSelected { Label(tr("Local sample data", "本地示例数据"), systemImage: "doc.text").font(.caption).foregroundStyle(BrandPalette.muted) }
                if let snapshot = model.current {
                    ForEach(model.totals, id: \.currency) { total in
                        HStack { Text(tr("Current estimated cost", "当前估算费用")); Spacer(); Text(money(total.total, total.currency)).font(.title3.weight(.semibold)).monospacedDigit() }
                        Text(tr("Fixed subscription cost + usage charges incurred", "本账期固定费 + 已产生按量费")).font(.caption).foregroundStyle(BrandPalette.muted)
                        HStack { Text(tr("Estimated end-of-cycle total", "账期结束预计总费用")); Spacer(); Text(money(total.forecastCost, total.currency)).monospacedDigit() }.secondaryText()
                        Text(tr("Includes fixed cost; not an extra charge or final bill.", "已包含固定费，并非额外收费或最终账单。")).font(.caption).foregroundStyle(BrandPalette.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    let alerts = quotaAlerts(snapshot, cycle: model.activeCycle)
                    if !alerts.isEmpty { QuotaAlertList(quotas: Array(alerts.prefix(3))) }
                    if !snapshot.isComplete { Label(tr("Some billing data is unavailable.", "部分账单数据不可用。"), systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(BrandPalette.warning) }
                    Text(tr("Last checked: ", "上次检查：") + formatDateTime(snapshot.checkedAt)).font(.caption).foregroundStyle(BrandPalette.muted)
                } else if let activity = model.billingActivity { Text(activity).secondaryText().fixedSize(horizontal: false, vertical: true) }
                else { Text(tr("No saved billing data yet.", "暂无保存的账单数据。")).secondaryText().fixedSize(horizontal: false, vertical: true) }
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(BrandPalette.danger) }
            Divider()
            HStack {
                Button { if let account = model.accounts.first(where: { $0.id == model.selectedID }) { Task { await model.refresh(account, cycle: model.activeCycle) } } } label: { Label(tr("Refresh", "刷新"), systemImage: "arrow.clockwise") }.disabled(model.loading || model.accounts.isEmpty || model.demo)
                Spacer()
                Button(tr("Open app", "打开应用")) { MainWindowPresenter.shared.show(model: model) }
                Button(tr("Quit", "退出")) { NSApp.terminate(nil) }
            }
        }.padding(16).frame(width: 320).fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var page: AppPage?
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                BrandHeader().padding(.horizontal, 16).padding(.top, 24)
                VStack(spacing: 4) {
                    ForEach(AppPage.allCases) { item in
                        Button { page = item } label: {
                            Label(item.title, systemImage: item.symbol).font(.system(size: 14, weight: page == item ? .semibold : .regular))
                                .foregroundStyle(page == item ? BrandPalette.accentText : BrandPalette.text)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 11)
                                .background(page == item ? BrandPalette.selection : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).keyboardShortcut(item.shortcut, modifiers: .command).help(item.title + " (" + item.shortcutLabel + ")").accessibilityAddTraits(page == item ? .isSelected : [])
                    }
                }.padding(.horizontal, 10)
                Spacer()
                HStack { Label(tr("Stored locally", "仅保存在本机"), systemImage: "lock"); Spacer(); Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")") }.font(.caption).foregroundStyle(BrandPalette.muted).padding(16)
            }.frame(width: 220).frame(maxHeight: .infinity).background(BrandPalette.sidebar)
            Rectangle().fill(BrandPalette.separator).frame(width: 1)
            ScrollViewReader { proxy in GeometryReader { geometry in ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch page ?? .overview {
                    case .overview: OverviewPage(contentWidth: min(980, max(0, geometry.size.width - 64)))
                    case .accounts: AccountsPage(scrollToManual: { proxy.scrollTo("manual-setup", anchor: .top) })
                    case .budget: BudgetPage()
                    case .settings: GeneralPage()
                    case .about: AboutPage()
                    }
                }.frame(width: min(980, max(0, geometry.size.width - 64)), alignment: .leading).frame(maxWidth: .infinity, alignment: .topLeading).padding(32)
            } } }.frame(maxWidth: .infinity, maxHeight: .infinity).background(BrandPalette.background)
        }.frame(minWidth: 900, minHeight: 650).onAppear {
            if page == nil { let args = CommandLine.arguments; let requested = args.firstIndex(of: "--preview-page").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }; page = AppPage.initial(hasAccounts: !model.accounts.isEmpty, requested: model.isDesignPreview ? requested : nil) }
        }
    }
}

struct PageHeading: View {
    let title: String; let subtitle: String
    var body: some View { VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 30, weight: .bold)).foregroundStyle(BrandPalette.text).accessibilityAddTraits(.isHeader); Text(subtitle).secondaryText().fixedSize(horizontal: false, vertical: true) } }
}

private struct OverviewPage: View {
    let contentWidth: CGFloat
    @EnvironmentObject var model: AppModel
    var body: some View {
        PageHeading(title: tr("Overview", "费用概览"), subtitle: tr("Estimated costs for your selected billing cycle", "查看所选账期的费用估算"))
        if model.accounts.isEmpty {
            BillingSection(title: tr("No accounts", "尚无账户"), subtitle: tr("Add an account from the sidebar to see billing.", "前往账户页面添加账户后查看费用。")) { EmptyView() }
        } else {
            if let snapshot = model.current, usesWideOverview(contentWidth: contentWidth) {
                HStack(alignment: .top, spacing: 16) {
                    controls.frame(maxWidth: .infinity, alignment: .topLeading)
                    costSummary(snapshot).frame(width: 300, alignment: .topLeading)
                }
            } else {
                controls
                if let snapshot = model.current { costSummary(snapshot) }
            }
            if let snapshot = model.current {
                BillingSection(title: tr("Products", "产品明细"), subtitle: tr("Bars show free-quota usage when the product has a free allowance, otherwise its share of known usage charges.", "有免费额度的产品显示额度已用比例，其余产品显示占已知按量费用的比例。")) { ProductDetails(snapshot: snapshot, cycle: model.activeCycle, isSample: model.isSampleSelected) }
                Text(tr("Cloudflare data may update daily. Estimates exclude taxes and credits and are not final invoices.", "Cloudflare 数据可能按日更新，估算不含税费与抵扣，也不是最终账单。 ")).secondaryText().fixedSize(horizontal: false, vertical: true)
            } else { BillingSection(title: tr("No saved billing data yet", "暂无保存的账单数据")) { EmptyView() } }
        }
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text(tr("Account", "账户")).gridColumnAlignment(.trailing)
                    Picker(tr("Account", "账户"), selection: Binding(get: { model.selectedID }, set: { model.select($0) })) { ForEach(model.accounts) { Text(accountDisplayName($0)).tag($0.id) } }.labelsHidden().frame(maxWidth: 280, alignment: .leading)
                }
                if let snapshot = model.current {
                    GridRow {
                        Text(tr("Billing cycle", "账期"))
                        Picker(tr("Billing cycle", "账期"), selection: Binding(get: { model.activeCycle }, set: { cycle in if let cycle, let account = model.accounts.first(where: { $0.id == model.selectedID }) { Task { await model.refresh(account, cycle: cycle) } } })) { ForEach(snapshot.cycles, id: \.self) { Text(cycleLabel($0)).tag(Optional($0)) } }.labelsHidden().frame(maxWidth: 280, alignment: .leading)
                    }
                }
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Button { if let account = model.accounts.first(where: { $0.id == model.selectedID }) { Task { await model.refresh(account, cycle: model.activeCycle) } } } label: { Label(tr("Refresh", "刷新"), systemImage: "arrow.clockwise") }.disabled(model.loading || (model.demo && !model.isStoreScreenshot))
                }
            }
            if model.isSampleSelected { Label(tr("Local sample data · not a Cloudflare account", "本地示例数据，非 Cloudflare 账户"), systemImage: "doc.text").font(.caption).foregroundStyle(BrandPalette.muted) }
            if let snapshot = model.current {
                HStack { Text(tr("Last checked: ", "上次检查：") + formatDateTime(snapshot.checkedAt)); if let asOf = snapshot.sourceAsOf { Text("·"); Text(tr("Usage through: ", "用量数据截至：") + formatDateTime(asOf)) } }.font(.caption).foregroundStyle(BrandPalette.muted)
                if !model.demo && Freshness.isStale(checkedAt: snapshot.checkedAt) { Text(tr("Saved data may be out of date.", "缓存数据可能已过期。 ")).font(.caption).foregroundStyle(BrandPalette.warning) }
                if !snapshot.issues.isEmpty { DisclosureGroup(tr("Why data is incomplete", "数据不完整的原因")) { ForEach(Array(snapshot.issues.prefix(3).enumerated()), id: \.offset) { _, issue in Text(issueDescription(issue)).secondaryText().fixedSize(horizontal: false, vertical: true) } }.font(.caption) }
            }
            if let cycle = model.activeCycle { PeriodProgress(cycle: cycle, now: model.isDesignPreview ? (model.current?.checkedAt ?? Date()) : Date()) }
            if let activity = model.billingActivity { HStack { ProgressView().controlSize(.small); Text(activity).secondaryText() } }
            if let error = model.error { Text(error).foregroundStyle(BrandPalette.danger).fixedSize(horizontal: false, vertical: true) }
        }
    }
    private func costSummary(_ snapshot: BillingSnapshot) -> some View {
        BillingSection(title: tr("Current estimated cost", "当前估算费用"), subtitle: tr("Fixed subscription cost + usage charges incurred.", "本账期固定费 + 已产生按量费。")) {
            ForEach(model.totals, id: \.currency) { total in
                VStack(alignment: .leading, spacing: 8) {
                    Text(money(total.total, total.currency)).font(.title2.weight(.semibold)).monospacedDigit().accessibilityLabel(tr("Current estimated cost", "当前估算费用") + ": " + money(total.total, total.currency))
                    amountRow(snapshot.isComplete ? tr("Fixed cost", "本账期固定费") : tr("Known fixed subtotal", "已知固定费用小计"), money(total.fixedCost, total.currency))
                    amountRow(snapshot.isComplete ? tr("Usage incurred", "已产生按量费") : tr("Known usage subtotal", "已知按量费用小计"), money(total.usageCost, total.currency))
                    Divider()
                    amountRow(tr("Estimated end-of-cycle total", "账期结束预计总费用"), money(total.forecastCost, total.currency), strong: true)
                    Text(tr("Fixed cost + projected usage at the current pace; not an extra charge.", "按当前用量速度估算整期总额，已含固定费，非额外收费。 ")).font(.caption).foregroundStyle(BrandPalette.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !snapshot.isComplete { Label(tr("Some billing data is unavailable.", "部分账单数据不可用。"), systemImage: "exclamationmark.triangle").foregroundStyle(BrandPalette.warning) }
            if snapshot.fixedCostIsEstimate { Text(tr("Other service periods use current subscription prices; historical prices may differ.", "其他服务期按当前订阅价格推算，历史价格可能不同。 ")).secondaryText().fixedSize(horizontal: false, vertical: true) }
            if snapshot.forecastNote != nil { Text(tr("Forecast unavailable: not enough complete usage data.", "无法预测：完整用量数据不足。 ")).secondaryText().fixedSize(horizontal: false, vertical: true) }
        }
    }
    private func amountRow(_ label: String, _ amount: String, strong: Bool = false) -> some View { HStack(alignment: .firstTextBaseline) { Text(label).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 8); Text(amount).monospacedDigit().fontWeight(strong ? .semibold : .regular) }.font(strong ? .subheadline.weight(.semibold) : .callout) }
}

private struct AccountsPage: View {
    let scrollToManual: () -> Void
    @EnvironmentObject var model: AppModel
    @FocusState private var accountNameFocused: Bool
    @State private var name = ""; @State private var accountID = ""; @State private var token = ""
    @State private var manualExpanded = false; @State private var discoveryToken = ""
    @State private var discoveryTask: Task<Void, Never>?; @State private var discoveryTaskID = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
        PageHeading(title: tr("Accounts", "账户"), subtitle: tr("Manage Cloudflare connections", "管理 Cloudflare 连接"))
        BillingSection(title: tr("Connected accounts", "已连接账户"), subtitle: tr("\(model.accounts.count) account(s)", "\(model.accounts.count) 个账户")) {
            if model.accounts.isEmpty { Text(model.demo ? tr("No demo accounts remain.", "没有剩余的演示账户。") : tr("No accounts connected yet.", "尚未连接账户。 ")).secondaryText().fixedSize(horizontal: false, vertical: true) }
            ForEach(model.accounts) { account in
                HStack(spacing: 12) {
                    Text(String(accountDisplayName(account).prefix(1)).uppercased()).font(.headline).frame(width: 38, height: 38).background(account.id == model.selectedID ? BrandPalette.accent : BrandPalette.separator, in: RoundedRectangle(cornerRadius: 9)).foregroundStyle(account.id == model.selectedID ? BrandPalette.onAccent : BrandPalette.text).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(accountDisplayName(account)).fontWeight(.semibold).lineLimit(1).truncationMode(.tail).accessibilityLabel(accountDisplayName(account)); if account.id == model.selectedID { StatusPill(tr("Current", "当前账户")).fixedSize() } }
                        Text(account.source == .sample ? tr("Local sample · No Cloudflare account ID", "本地示例，无 Cloudflare 账户 ID") : shortID(account.id)).font(.caption).foregroundStyle(BrandPalette.muted).accessibilityLabel(account.source == .sample ? tr("Local sample, no Cloudflare account ID", "本地示例，无 Cloudflare 账户 ID") : tr("Account ID ", "账户 ID ") + account.id)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    accountStatus(account).fixedSize()
                    Menu {
                        Button(tr("Edit", "编辑")) { name = account.name; accountID = account.id; token = ""; manualExpanded = true; DispatchQueue.main.async { scrollToManual(); accountNameFocused = true } }.disabled(account.source == .sample || (model.demo && !model.isStoreScreenshot))
                        Button(tr("Make current", "设为当前")) { model.select(account.id) }.disabled(account.id == model.selectedID)
                        Button(tr("Remove", "移除"), role: .destructive) { model.delete(account) }
                    } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel(tr("Actions for ", "账户操作：") + accountDisplayName(account))
                }.padding(.vertical, 4)
                if account.id != model.accounts.last?.id { Divider().overlay(BrandPalette.separator) }
            }
            if model.demo && !model.isStoreScreenshot { Button(tr("Restore demo data", "恢复演示数据")) { model.restoreDemo() } }
            if !model.demo && !model.hasSampleAccount { Button(tr("Add sample account", "添加示例账户")) { model.addSampleAccount() } }
        }
        BillingSection(title: tr("Connect an account", "连接新账户"), subtitle: tr("Use a read-only token to connect your Cloudflare accounts.", "使用只读令牌连接你的 Cloudflare 账户。")) {
            if model.demo && !model.isStoreScreenshot {
                Text(tr("Demo mode uses sample data and does not access accounts, Keychain or notifications.", "演示模式使用示例数据，不访问真实账户、钥匙串或通知。 ")).secondaryText().fixedSize(horizontal: false, vertical: true).frame(maxWidth: 480, alignment: .leading)
            }
            Group {
                HStack(spacing: 20) { step("1", tr("Create token", "创建令牌")); step("2", tr("Paste token", "粘贴令牌")); step("3", tr("Select accounts", "选择账户")) }
                Button { if !model.demo { NSWorkspace.shared.open(tokenTemplateURL()) } } label: { Label(tr("Create read-only token", "创建只读令牌"), systemImage: "arrow.up.right.square").fontWeight(.semibold).foregroundStyle(BrandPalette.onAccent).padding(.horizontal, 14).padding(.vertical, 8).background(BrandPalette.accent, in: RoundedRectangle(cornerRadius: 7)) }.buttonStyle(.plain).help(tr("Opens Cloudflare in your browser", "在浏览器中打开 Cloudflare"))
                Text(tr("Confirm Account Settings Read, Billing Read and Zone Read; narrow the scope as needed.", "请确认 Account Settings Read、Billing Read 和 Zone Read，并按需缩小授权范围。 ")).secondaryText().fixedSize(horizontal: false, vertical: true).frame(maxWidth: 480, alignment: .leading)
                HStack {
                    SecureField(tr("Cloudflare API token", "粘贴 Cloudflare API 令牌"), text: $discoveryToken).textFieldStyle(.roundedBorder).disabled(model.discovering || model.importing || !model.discoveredAccounts.isEmpty)
                    if model.discoveredAccounts.isEmpty { Button(tr("Find accounts", "读取账户")) { beginDiscovery() }.disabled(model.discovering || model.importing || discoveryToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
                Label(tr("Token is stored in macOS Keychain.", "令牌仅存于 macOS 钥匙串。"), systemImage: "lock").secondaryText().fixedSize(horizontal: false, vertical: true)
                if !model.discoveredAccounts.isEmpty {
                    Text(tr("Select accounts to add", "选择要添加的账户")).font(.headline)
                    ForEach(model.discoveredAccounts) { account in
                        let exists = model.accounts.contains { $0.id == account.id }
                        let restoring = model.missingTokenIDs.contains(account.id)
                        Toggle(isOn: Binding(get: { model.selectedDiscoveredIDs.contains(account.id) }, set: { checked in if checked { model.selectedDiscoveredIDs.insert(account.id) } else { model.selectedDiscoveredIDs.remove(account.id) } })) {
                            VStack(alignment: .leading) { Text(account.name); Text(account.id + (restoring ? tr(" (token missing; adding restores it)", "（令牌缺失，添加后恢复）") : (exists ? tr(" (already added)", "（已添加）") : ""))).font(.caption).foregroundStyle(restoring ? BrandPalette.warning : BrandPalette.muted) }
                        }.disabled((exists && !restoring) || model.importing)
                    }
                    HStack { Button(tr("Add selected accounts", "添加所选账户")) { if model.importDiscovered() { discoveryToken = "" } }.disabled(model.importing || model.selectedDiscoveredIDs.isEmpty); Button(tr("Cancel", "取消")) { clearDiscovery() } }
                }
                if model.discovering || model.importing { HStack { ProgressView().controlSize(.small); Button(tr("Cancel", "取消")) { clearDiscovery() } } }
                if let message = model.discoveryMessage { Text(message).secondaryText().fixedSize(horizontal: false, vertical: true) }
            }.disabled(model.demo && !model.isStoreScreenshot)
            DisclosureGroup(tr("Advanced manual setup", "高级手动配置"), isExpanded: $manualExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(tr("Account name", "账户名称"), text: $name).focused($accountNameFocused)
                    TextField(tr("Account ID", "账户 ID"), text: $accountID)
                    SecureField(tr("API token", "API 令牌"), text: $token)
                    Text(tr("Use Account > Billing > Read and Zone > Zone > Read.", "使用 Account > Billing > Read 和 Zone > Zone > Read。 ")).secondaryText().fixedSize(horizontal: false, vertical: true)
                    HStack { Link(tr("Create API token", "创建 API 令牌"), destination: tokenTemplateURL()); Link(tr("Find account ID", "查找账户 ID"), destination: URL(string: "https://developers.cloudflare.com/fundamentals/account/find-account-and-zone-ids/")!) }
                    Button(tr("Validate and save", "验证并保存")) { Task { if await model.saveAccount(name: name, id: accountID, token: token) { name = ""; accountID = ""; token = ""; manualExpanded = false } } }.disabled(model.loading)
                }.padding(.top, 10)
            }.disabled(model.demo && !model.isStoreScreenshot).id("manual-setup")
        }
        if let error = model.error { Text(error).foregroundStyle(BrandPalette.danger).fixedSize(horizontal: false, vertical: true) }
        }.onDisappear { clearDiscovery(); token = "" }
    }
    private func beginDiscovery() { let id = UUID(); discoveryTaskID = id; discoveryTask = Task { await model.discoverAccounts(token: discoveryToken); if discoveryTaskID == id { discoveryTask = nil } } }
    private func clearDiscovery() { discoveryTaskID = UUID(); discoveryTask?.cancel(); discoveryTask = nil; model.cancelDiscovery(); discoveryToken = "" }
    private func shortID(_ id: String) -> String { id.count > 12 ? "\(id.prefix(4))…\(id.suffix(4))" : id }
    private func step(_ number: String, _ label: String) -> some View { HStack(spacing: 6) { Text(number).font(.caption.weight(.semibold)).frame(width: 22, height: 22).background(BrandPalette.separator, in: Circle()); Text(label).font(.caption) } }
    @ViewBuilder private func accountStatus(_ account: AccountProfile) -> some View {
        if account.source == .sample { StatusPill(tr("Local sample data", "本地示例数据")) }
        else { switch accountDisplayStatus(demo: model.demo && !model.isStoreScreenshot, loading: model.accountIsLoading(account.id), error: model.accountError(account.id), snapshot: model.snapshots[account.id], now: model.isStoreScreenshot ? (model.snapshots[account.id]?.checkedAt ?? Date()) : Date()) {
        case .demo: StatusPill(tr("Demo", "演示"))
        case .checking: StatusPill(tr("Checking", "检查中"))
        case .error: StatusPill(tr("Needs attention", "需要处理"), tone: .danger)
        case .stale: StatusPill(tr("Out of date", "需要刷新"), tone: .warning)
        case .partial: StatusPill(tr("Partial", "部分可用"), tone: .warning)
        case .available: StatusPill(tr("Available", "可用"), tone: .success)
        case .unchecked: StatusPill(tr("Not checked", "未检查"))
        } }
    }

}

private struct GeneralPage: View {
    @EnvironmentObject var model: AppModel
    @State private var showPrivacyPolicy = false
    var body: some View {
        PageHeading(title: tr("Settings", "应用设置"), subtitle: tr("Choose how Billing Helper runs on this Mac.", "设置费用助手在此 Mac 上的运行方式。"))
        BillingSection(title: tr("Startup", "启动行为")) { Toggle(tr("Launch at login", "登录时启动"), isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunch($0) })).disabled((model.demo || model.isDesignPreview) && !model.isStoreScreenshot) }
        BillingSection(title: tr("Privacy", "隐私")) {
            Label(tr("Tokens are stored in macOS Keychain. Billing data is requested directly from Cloudflare.", "令牌保存在 macOS 钥匙串，账单数据直接从 Cloudflare 获取。"), systemImage: "lock").secondaryText().fixedSize(horizontal: false, vertical: true)
            Button(tr("Privacy policy", "隐私政策")) { showPrivacyPolicy = true }
                .sheet(isPresented: $showPrivacyPolicy) { PrivacyPolicySheet() }
        }
        if let error = model.error { Text(error).foregroundStyle(BrandPalette.danger).fixedSize(horizontal: false, vertical: true) }
    }
}
enum PrivacyPolicyDocument {
    static func load(from url: URL?) -> String? {
        guard let url else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
    static func languages(in content: String) -> [String] { content.components(separatedBy: "\n---\n") }
}

struct PrivacyPolicySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var chinese = (previewLanguage ?? Locale.preferredLanguages.first ?? "en").hasPrefix("zh")
    private let content = PrivacyPolicyDocument.load(from: Bundle.main.url(forResource: "privacy-policy-draft", withExtension: "md"))
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(tr("Privacy policy", "隐私政策")).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Picker(tr("Language", "语言"), selection: $chinese) { Text("English").tag(false); Text("简体中文").tag(true) }.labelsHidden().frame(width: 125)
                Button(tr("Done", "完成")) { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            ScrollView {
                if let content {
                    let sections = PrivacyPolicyDocument.languages(in: content)
                    let policy = sections.count == 2 ? sections[chinese ? 1 : 0] : content
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(policy.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                            let text = line.trimmingCharacters(in: .whitespaces)
                            if text.hasPrefix("## ") { Text(String(text.dropFirst(3))).font(.headline).accessibilityAddTraits(.isHeader).padding(.top, 8) }
                            else if text.hasPrefix("# ") { Text(String(text.dropFirst(2))).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader) }
                            else if text.isEmpty { Color.clear.frame(height: 4).accessibilityHidden(true) }
                            else { Text(text).fixedSize(horizontal: false, vertical: true) }
                        }
                    }.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(24)
                } else {
                    Text(tr("The privacy policy could not be loaded.", "无法加载隐私政策。"))
                        .foregroundStyle(BrandPalette.danger).padding(24)
                }
            }
        }.frame(minWidth: 560, minHeight: 500).frame(idealWidth: 680, idealHeight: 680)
    }
}

private enum AboutLinks {
    static let author = URL(string: "https://meathill.com/about")!
    static let github = URL(string: "https://github.com/meathill")!
    static let source = URL(string: "https://github.com/meathill/cloudflare-billing-helper")!
    static let issues = URL(string: "https://github.com/meathill/cloudflare-billing-helper/issues")!
}

private struct AboutPage: View {
    @EnvironmentObject private var model: AppModel
    #if !DIRECT_DISTRIBUTION
    @StateObject private var tips = AppStoreTipStore()
    #endif
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }
    var body: some View {
        PageHeading(title: tr("About", "关于"), subtitle: tr("The app and the person behind it.", "了解这款应用和它的作者。"))
        BillingSection(title: tr("About this app", "关于应用")) {
            HStack(alignment: .center, spacing: 16) {
                BrandMark(size: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Billing Helper for Cloudflare®").font(.title3.weight(.semibold))
                    Text(tr("Version \(version) · Build \(build)", "版本 \(version) · 构建 \(build)")).secondaryText()
                }
            }
            Text(tr("A native menu bar companion for Cloudflare® billing: see fixed subscriptions, usage charges, trends and budget alerts. A browser extension is also available.", "在菜单栏查看 Cloudflare® 账户的固定订阅、按量费用、趋势和预算提醒；同时提供浏览器扩展。 ")).fixedSize(horizontal: false, vertical: true)
            Text(tr("Cloudflare® is a trademark and/or registered trademark of Cloudflare, Inc. in the United States and other jurisdictions. This independent app is not affiliated with, sponsored by or endorsed by Cloudflare.", "Cloudflare® 是 Cloudflare, Inc. 在美国及其他国家和地区的商标和/或注册商标。本独立应用与 Cloudflare 无关联，也未获其赞助或背书。 ")).secondaryText().fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 20) {
                Link(destination: AboutLinks.source) { Label(tr("Source code", "项目源码"), systemImage: "arrow.up.right.square") }
                Link(destination: AboutLinks.issues) { Label(tr("Report an issue", "问题反馈"), systemImage: "arrow.up.right.square") }
            }
        }
        BillingSection(title: tr("Author", "作者")) {
            Text(tr("Meathill", "肉山（Meathill）")).font(.headline)
            Text(tr("Independent full-stack developer and product creator, focused on Cloudflare®, AI applications and cross-platform development.", "独立全栈开发者、产品作者，专注 Cloudflare®、AI 应用与跨端开发。 ")).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 20) {
                Link(destination: AboutLinks.author) { Label(tr("About Meathill", "了解作者"), systemImage: "arrow.up.right.square") }
                Link(destination: AboutLinks.github) { Label("GitHub", systemImage: "arrow.up.right.square") }
            }
        }
        BillingSection(title: tr("Support development", "支持开发")) {
            #if DIRECT_DISTRIBUTION
            Text(tr("Support development on Buy Me a Coffee. Support is optional and does not unlock features.", "可通过 Buy Me a Coffee 自愿支持开发，不会解锁应用功能。")).fixedSize(horizontal: false, vertical: true)
            if let url = DistributionChannel.supportURL {
                Link(destination: url) {
                    Label(tr("Buy me a coffee", "请我喝杯咖啡"), systemImage: "cup.and.saucer.fill")
                        .fontWeight(.semibold).foregroundStyle(BrandPalette.onAccent).padding(.horizontal, 14).padding(.vertical, 8)
                        .background(BrandPalette.accent, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain)
            }
            #else
            Text(tr("Send an optional one-time tip through the App Store. It does not unlock features.", "可通过 App Store 一次性自愿支持开发，不会解锁应用功能。 ")).fixedSize(horizontal: false, vertical: true)
            if model.isStoreScreenshot {
                Label(tr("Buy me a coffee", "请我喝杯咖啡"), systemImage: "cup.and.saucer.fill")
                    .fontWeight(.semibold).foregroundStyle(BrandPalette.onAccent).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(BrandPalette.accent, in: RoundedRectangle(cornerRadius: 7))
            } else if let product = tips.product {
                Button { Task { await tips.purchase(product) } } label: {
                    Label(tr("Buy me a coffee · \(product.displayPrice)", "请我喝杯咖啡 · \(product.displayPrice)"), systemImage: "cup.and.saucer.fill")
                        .fontWeight(.semibold).foregroundStyle(BrandPalette.onAccent).padding(.horizontal, 14).padding(.vertical, 8)
                        .background(BrandPalette.accent, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).disabled(tips.isPurchasing)
            } else if tips.isLoading {
                ProgressView().controlSize(.small).accessibilityLabel(tr("Loading support option", "正在加载支持选项"))
            } else {
                Button(tr("Try loading support option again", "重新加载支持选项")) { Task { await tips.load() } }
                    .disabled(tips.isPurchasing)
            }
            if let message = tips.message {
                Text(tips.localizedMessage(message)).font(.caption).secondaryText().fixedSize(horizontal: false, vertical: true)
            }
            #endif
        }
        #if !DIRECT_DISTRIBUTION
        .task { if !model.isDesignPreview { await tips.start() } }
        #endif
    }
}

#if !DIRECT_DISTRIBUTION
@MainActor private final class AppStoreTipStore: ObservableObject {
    private static let productID = "com.meathill.CloudflareBillingHelper.tip.coffee"
    @Published private(set) var product: Product?
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var message: Message?
    private var updatesTask: Task<Void, Never>?
    private var isStarted = false

    enum Message { case unavailable, pending, failed, thankYou }

    init() {}

    deinit { updatesTask?.cancel() }

    func start() async {
        guard !isStarted else { return }
        isStarted = true
        updatesTask = Task {
            for await result in StoreKit.Transaction.updates {
                await finishIfVerified(result)
            }
        }
        await load()
    }

    func load() async {
        guard product == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            product = try await Product.products(for: [Self.productID]).first
            if product == nil { message = .unavailable }
        } catch {
            message = .unavailable
        }
    }

    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        message = nil
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let result): await finishIfVerified(result)
            case .pending: message = .pending
            case .userCancelled: break
            @unknown default: message = .failed
            }
        } catch {
            message = .failed
        }
    }

    func localizedMessage(_ message: Message) -> String {
        switch message {
        case .unavailable: return tr("The App Store support option is temporarily unavailable.", "App Store 支持选项暂时不可用。")
        case .pending: return tr("Your purchase is awaiting approval.", "购买正在等待批准。")
        case .failed: return tr("The purchase could not be verified. Please try again.", "无法验证此次购买，请重试。")
        case .thankYou: return tr("Thank you for supporting development.", "感谢你支持持续开发。")
        }
    }

    private func finishIfVerified(_ result: VerificationResult<StoreKit.Transaction>) async {
        switch result {
        case .verified(let transaction):
            guard transaction.productID == Self.productID else { return }
            await transaction.finish()
            message = .thankYou
        case .unverified:
            message = .failed
        }
    }
}
#endif

func cycleLabel(_ cycle: Cycle) -> String {
    let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .none
    formatter.locale = Locale(identifier: previewLanguage ?? Locale.current.identifier)
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return "\(formatter.string(from: cycle.start)) – \(formatter.string(from: cycle.end.addingTimeInterval(-1)))"
}

private func issueDescription(_ issue: String) -> String {
    if issue.contains("Zone") { return tr("Zone data could not be read. Check Zone Read permissions and the selected zone scope.", "无法读取域名数据，请检查 Zone Read 权限和域名范围。") }
    if issue.contains("subscription") || issue.contains("Subscription") { return tr("Subscription data is incomplete. Check Billing Read permissions and refresh.", "订阅数据不完整，请检查 Billing Read 权限后刷新。") }
    return tr("Cloudflare returned incomplete usage or pricing data. Refresh later.", "Cloudflare 返回的用量或价格数据不完整，请稍后刷新。")
}

private func formatDateTime(_ date: Date) -> String {
    date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: previewLanguage ?? Locale.current.identifier)))
}

func tokenTemplateURL() -> URL {
    let groups = [["key": "billing", "type": "read"], ["key": "account_settings", "type": "read"], ["key": "zone", "type": "read"]]
    let data = try! JSONSerialization.data(withJSONObject: groups, options: [.sortedKeys])
    var components = URLComponents(string: "https://dash.cloudflare.com/profile/api-tokens")!
    components.queryItems = [URLQueryItem(name: "permissionGroupKeys", value: String(decoding: data, as: UTF8.self)), URLQueryItem(name: "accountId", value: "*"), URLQueryItem(name: "zoneId", value: "all"), URLQueryItem(name: "name", value: "Billing Helper for Cloudflare")]
    return components.url!
}

struct UsageDisplayRow {
    let name: String
    let currency: String
    let cost: Decimal?
    let sourceLabel: String
}
func usageDisplayRows(snapshot: BillingSnapshot, cycle: Cycle?) -> [UsageDisplayRow]? {
    guard let totals = snapshot.usageProductTotals, let cycle, snapshot.selectedCycle == cycle else { return nil }
    let rows = totals.map { total in
        let label: String
        switch total.source {
        case "cumulative": label = tr("Cloudflare accumulated cost", "Cloudflare 累计费用")
        case "period-sum": label = tr("Sum of period charges", "按时段费用合计")
        case "mixed": label = tr("Mixed cost sources", "混合费用来源")
        default: label = tr("Cost source unavailable", "费用来源不可用")
        }
        let recognized = ["cumulative", "period-sum", "mixed"].contains(total.source)
        return UsageDisplayRow(name: total.serviceName, currency: total.currency, cost: total.isComplete && recognized ? total.cost : nil, sourceLabel: label)
    }
    return rows.sorted { left, right in
        switch (left.cost, right.cost) {
        case (nil, .some): return true
        case (.some, nil): return false
        case let (.some(a), .some(b)) where a != b: return a > b
        default:
            let order = left.name.localizedStandardCompare(right.name)
            if order != .orderedSame { return order == .orderedAscending }
            if left.name != right.name { return left.name < right.name }
            return left.currency < right.currency
        }
    }
}

enum AccountDisplayStatus { case demo, checking, error, stale, partial, available, unchecked }
func accountDisplayStatus(demo: Bool, loading: Bool, error: String?, snapshot: BillingSnapshot?, now: Date = Date()) -> AccountDisplayStatus {
    if demo { return .demo }
    if loading { return .checking }
    if error != nil { return .error }
    guard let snapshot else { return .unchecked }
    if Freshness.isStale(checkedAt: snapshot.checkedAt, now: now) { return .stale }
    return snapshot.isComplete ? .available : .partial
}

func usesWideOverview(contentWidth: CGFloat) -> Bool { contentWidth >= 700 }
