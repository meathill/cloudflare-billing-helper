import SwiftUI
import BillingCore

struct BudgetPage: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var isAmountFocused: Bool
    @State private var committedAmount = ""
    @State private var highlightedBudgetID: String?
    @State private var highlightTask: Task<Void, Never>?

    private var canSaveAmount: Bool { model.budgetText != committedAmount }
    private var controlsDisabled: Bool { model.demo && !model.isStoreScreenshot }

    var body: some View {
        PageHeading(title: tr("Budget alerts", "预算提醒"), subtitle: tr("Choose when this Mac notifies you about spending.", "设置此 Mac 的费用提醒。"))
        if model.accounts.isEmpty { BillingSection(title: tr("No accounts", "尚无账户"), subtitle: tr("Connect an account before setting a budget.", "连接账户后即可设置预算。")) { EmptyView() } }
        else {
            BillingSection(title: tr("Budget", "预算"), subtitle: tr("Budgets are separate for each account and currency.", "每个账户和币种单独设置预算。")) {
                Picker(tr("Account", "账户"), selection: Binding(get: { model.selectedID }, set: { model.select($0) })) { ForEach(model.accounts) { Text(accountDisplayName($0)).tag($0.id) } }
                if model.isSampleSelected { Text(tr("This sample budget is separate from your Cloudflare accounts. Alerts are off until you enable them.", "示例预算与真实 Cloudflare 账户分开，提醒在你启用前保持关闭。")).secondaryText().fixedSize(horizontal: false, vertical: true) }
                Toggle(tr("Budget notifications", "预算通知"), isOn: Binding(get: { model.budgetEnabled }, set: { turnOnNotifications($0) })).disabled(controlsDisabled)
                if model.budgetEnabled {
                    Picker(tr("Currency", "币种"), selection: $model.budgetCurrency) { ForEach(Array(Set(model.current?.totals.map(\.currency) ?? ["USD"])).sorted(), id: \.self) { Text($0).tag($0) } }
                        .onChange(of: model.budgetCurrency) { _ in model.loadBudget(); committedAmount = model.budgetText }
                        .disabled(controlsDisabled)
                    HStack {
                        TextField(tr("Budget amount", "预算金额"), text: $model.budgetText)
                            .focused($isAmountFocused)
                            .onSubmit { saveAmount() }
                        Button(tr("Save budget", "保存预算")) { saveAmount() }
                            .disabled(!canSaveAmount)
                    }
                    .disabled(controlsDisabled)
                }
                Text(tr("Alerts at 80%, 100% and when the forecast exceeds the budget, per currency and cycle.", "每个币种和账期在达到 80%、100% 及预测超额时提醒。")).secondaryText().fixedSize(horizontal: false, vertical: true)
            }
            .onAppear { committedAmount = model.budgetText }
            .onChange(of: model.selectedID) { _ in committedAmount = model.budgetText }
            .onDisappear { highlightTask?.cancel() }
            BillingSection(title: tr("Free quota alerts", "免费额度预警"), subtitle: tr("Applies to every connected account.", "对所有已连接账户生效。")) {
                Toggle(tr("Notify before free quotas run out", "免费额度即将用完时通知"), isOn: Binding(get: { model.quotaAlertsEnabled }, set: { model.setQuotaAlerts($0) })).disabled(controlsDisabled)
                Text(tr("Alerts once per product and cycle when recent daily usage would use up a free quota before the cycle ends, and again when it is used up.", "按近期每日用量推算某产品会在账期结束前用完免费额度时提醒一次，真正用完时再提醒一次；每个产品每个账期不重复。")).secondaryText().fixedSize(horizontal: false, vertical: true)
            }
            BillingSection(title: tr("Saved alerts", "已保存的提醒"), subtitle: tr("Delete a row to turn that alert off. The amount stays saved.", "删除一行即关闭该提醒，金额仍会保留。")) {
                if model.savedBudgets.isEmpty {
                    Text(tr("No alert is on. Turn notifications on and save an amount to list it here.", "还没有开启的提醒。打开通知并保存金额后，会出现在这里。")).secondaryText().fixedSize(horizontal: false, vertical: true)
                } else {
                    savedBudgetTable
                }
            }
        }
    }

    private var savedBudgetTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(tr("Account", "账户")).frame(maxWidth: .infinity, alignment: .leading)
                Text(tr("Budget", "预算")).frame(maxWidth: .infinity, alignment: .leading)
                Text(tr("Action", "操作")).frame(width: 64, alignment: .trailing)
            }
            .secondaryText()
            .padding(.bottom, 6)
            ForEach(model.savedBudgets) { budget in
                HStack(spacing: 12) {
                    Text(budget.accountName).fontWeight(.semibold).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(budget.amount.isEmpty ? budget.currency : "\(budget.currency) \(budget.amount)").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Button(tr("Delete", "删除"), role: .destructive) { turnOff(budget) }
                        .disabled(controlsDisabled)
                        .frame(width: 64, alignment: .trailing)
                        .accessibilityLabel(tr("Delete \(budget.accountName) \(budget.currency) alert", "删除 \(budget.accountName) \(budget.currency) 提醒"))
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
                .background(highlightedBudgetID == budget.id ? BrandPalette.success.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(highlightedBudgetID == budget.id ? BrandPalette.success : Color.clear, lineWidth: 1))
                .overlay(alignment: .bottom) { Rectangle().fill(BrandPalette.separator).frame(height: 1).opacity(highlightedBudgetID == budget.id ? 0 : 1) }
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: highlightedBudgetID)
        .animation(.easeInOut(duration: 0.25), value: model.savedBudgets)
    }

    private func turnOnNotifications(_ enabled: Bool) {
        model.budgetEnabled = enabled
        withAnimation(.easeInOut(duration: 0.25)) { model.saveBudget() }
    }

    private func saveAmount() {
        guard canSaveAmount, !controlsDisabled else { return }
        let savedID = "\(model.selectedID)|\(model.budgetCurrency)"
        withAnimation(.easeInOut(duration: 0.25)) { model.saveBudget() }
        committedAmount = model.budgetText
        isAmountFocused = false
        flash(savedID)
    }

    private func turnOff(_ budget: SavedBudget) {
        highlightTask?.cancel()
        if highlightedBudgetID == budget.id { highlightedBudgetID = nil }
        withAnimation(.easeInOut(duration: 0.25)) { model.disableSavedBudget(budget) }
    }

    private func flash(_ id: String) {
        highlightTask?.cancel()
        highlightedBudgetID = id
        highlightTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            highlightedBudgetID = nil
        }
    }
}
