import Foundation
import BillingCore

struct SavedBudget: Equatable, Identifiable {
    let accountID: String
    let accountName: String
    let currency: String
    let amount: String
    let enabled: Bool
    var id: String { "\(accountID)|\(currency)" }
}

func collectSavedBudgets(accounts: [AccountProfile], defaults: UserDefaults) -> [SavedBudget] {
    accounts.flatMap { account in
        let prefix = account.source == .sample ? "sample.budget." : "budget.\(account.id)."
        let name = account.source == .sample ? tr("Sample account", "示例账户") : account.name
        return savedBudgetCurrencies(prefix: prefix, defaults: defaults).compactMap { currency -> SavedBudget? in
            let base = prefix + currency
            let amount = defaults.string(forKey: base + ".amount") ?? ""
            let enabled = defaults.bool(forKey: base + ".enabled")
            guard enabled else { return nil }
            return SavedBudget(accountID: account.id, accountName: name, currency: currency, amount: amount, enabled: enabled)
        }
    }
}

private func savedBudgetCurrencies(prefix: String, defaults: UserDefaults) -> [String] {
    let currencies = defaults.dictionaryRepresentation().keys.compactMap { key -> String? in
        guard key.hasPrefix(prefix) else { return nil }
        let rest = key.dropFirst(prefix.count)
        guard let separator = rest.lastIndex(of: ".") else { return nil }
        let field = rest[rest.index(after: separator)...]
        guard field == "amount" || field == "enabled" else { return nil }
        let currency = String(rest[..<separator])
        return currency.isEmpty ? nil : currency
    }
    return Array(Set(currencies)).sorted()
}
