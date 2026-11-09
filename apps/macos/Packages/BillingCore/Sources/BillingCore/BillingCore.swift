import Foundation
import Security

public enum AccountSource: String, Codable, Hashable { case cloudflare, sample }
public struct AccountProfile: Codable, Identifiable, Hashable {
    public let id: String
    public var name: String
    public var source: AccountSource
    public init(id: String, name: String, source: AccountSource = .cloudflare) { self.id = id; self.name = name; self.source = source }
    private enum CodingKeys: String, CodingKey { case id, name, source }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        source = values.contains(.source) ? try values.decode(AccountSource.self, forKey: .source) : .cloudflare
    }
}
public struct Cycle: Codable, Hashable {
    public let start: Date
    public let end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = end }
}
public struct FixedSubscription: Codable, Hashable {
    public let id: String
    public let currency: String
    public let price: Decimal?
    public let period: Cycle
    public let name: String
    public init(id: String, currency: String, price: Decimal?, period: Cycle, name: String = "") {
        self.id = id; self.currency = currency; self.price = price; self.period = period; self.name = name
    }
}
public struct UsageCharge: Codable, Hashable {
    public let id: String
    public let currency: String
    public let cost: Decimal?
    public let period: Cycle
    public let serviceName: String
    public init(id: String, currency: String, cost: Decimal?, period: Cycle, serviceName: String = "") {
        self.id = id; self.currency = currency; self.cost = cost; self.period = period; self.serviceName = serviceName
    }
}
public struct CurrencyTotals: Codable, Hashable {
    public let currency: String
    public let fixedCost: Decimal?
    public let usageCost: Decimal?
    public let forecastCost: Decimal?
    public let isComplete: Bool
    public var total: Decimal? { guard isComplete, let fixedCost, let usageCost else { return nil }; return fixedCost + usageCost }
    public init(currency: String, fixedCost: Decimal?, usageCost: Decimal?, forecastCost: Decimal?, isComplete: Bool = true) { self.currency = currency; self.fixedCost = fixedCost; self.usageCost = usageCost; self.forecastCost = forecastCost; self.isComplete = isComplete }
}
public struct UsageProductTotal: Codable {
    public let serviceName: String
    public let currency: String
    public let cost: Decimal?
    /// "cumulative", "period-sum", or "mixed" for multiple underlying dimensions.
    public let source: String
    public let isComplete: Bool
    public let rawServiceNames: [String]?
    public init(serviceName: String, currency: String, cost: Decimal?, source: String, isComplete: Bool, rawServiceNames: [String]? = nil) { self.serviceName = serviceName; self.currency = currency; self.cost = cost; self.source = source; self.isComplete = isComplete; self.rawServiceNames = rawServiceNames }
}
/// An actual cumulative observation at a UTC charge-period end.
public struct UsageTrendPoint: Codable, Hashable {
    public let at: Date
    public let cost: Decimal
    public let startsSegment: Bool
    public init(at: Date, cost: Decimal, startsSegment: Bool = false) { self.at = at; self.cost = cost; self.startsSegment = startsSegment }
}
public struct UsageTrend: Codable {
    public let currency: String
    public let serviceName: String
    public let points: [UsageTrendPoint]
    public let isComplete: Bool
    public let source: String
    public init(currency: String, serviceName: String, points: [UsageTrendPoint], isComplete: Bool, source: String = "cumulative") { self.currency = currency; self.serviceName = serviceName; self.points = points; self.isComplete = isComplete; self.source = source }
}
/// Non-monetary observations for comparing API coverage; never includes IDs or costs.
public struct UsageSourceDiagnostic: Codable {
    public let kind: String
    public let allCumulativePresent: Bool
    public let periodSumDiffersFromLatestCumulative: Bool?
    public let includesCurrentUTCDay: Bool
    public let hasFuturePeriodEnd: Bool
    public init(kind: String, allCumulativePresent: Bool, periodSumDiffersFromLatestCumulative: Bool?, includesCurrentUTCDay: Bool, hasFuturePeriodEnd: Bool) {
        self.kind = kind; self.allCumulativePresent = allCumulativePresent; self.periodSumDiffersFromLatestCumulative = periodSumDiffersFromLatestCumulative; self.includesCurrentUTCDay = includesCurrentUTCDay; self.hasFuturePeriodEnd = hasFuturePeriodEnd
    }
}
public struct BillingSnapshot: Codable {
    public let accountID: String
    public let cycles: [Cycle]
    public let totals: [CurrencyTotals]
    public let checkedAt: Date
    public let selectedCycle: Cycle?
    public let sourceAsOf: Date?
    public let fixedCostIsEstimate: Bool
    public let fixedEstimateNote: String?
    public let forecastIsEstimate: Bool
    public let forecastNote: String?
    public let isComplete: Bool
    public let subscriptions: [FixedSubscription]
    public let usage: [UsageCharge]
    public let issues: [String]
    public let usageDiagnostics: [UsageSourceDiagnostic]?
    public let usageProductTotals: [UsageProductTotal]?
    public let usageTrends: [UsageTrend]?
    public let usageTotalTrends: [UsageTrend]?
    /// Free-allowance consumption for cumulative products; nil in snapshots saved before quota tracking.
    public let usageQuotas: [UsageQuota]?
    public init(accountID: String, cycles: [Cycle], totals: [CurrencyTotals], checkedAt: Date, isComplete: Bool, subscriptions: [FixedSubscription] = [], usage: [UsageCharge] = [], issues: [String] = [], sourceAsOf: Date? = nil, forecastIsEstimate: Bool = true, selectedCycle: Cycle? = nil, forecastNote: String? = nil, fixedCostIsEstimate: Bool = false, fixedEstimateNote: String? = nil, usageDiagnostics: [UsageSourceDiagnostic]? = nil, usageProductTotals: [UsageProductTotal]? = nil, usageTrends: [UsageTrend]? = nil, usageTotalTrends: [UsageTrend]? = nil, usageQuotas: [UsageQuota]? = nil) { self.usageQuotas = usageQuotas; self.usageTrends = usageTrends; self.usageTotalTrends = usageTotalTrends; self.usageProductTotals = usageProductTotals; self.usageDiagnostics = usageDiagnostics; self.fixedCostIsEstimate = fixedCostIsEstimate; self.fixedEstimateNote = fixedEstimateNote; self.forecastNote = forecastNote; self.selectedCycle = selectedCycle; self.sourceAsOf = sourceAsOf; self.forecastIsEstimate = forecastIsEstimate; self.accountID = accountID; self.cycles = cycles; self.totals = totals; self.checkedAt = checkedAt; self.isComplete = isComplete; self.subscriptions = subscriptions; self.usage = usage; self.issues = issues }
}
public enum BillingCalculator {
    public static func calculate(cycle: Cycle, subscriptions: [FixedSubscription], usage: [UsageCharge], now: Date, complete: Bool = true) -> [CurrencyTotals] {
        let currencies = Set(subscriptions.map(\.currency) + usage.map(\.currency)).sorted()
        return currencies.map { currency in
            var fixed: Decimal = 0, metered: Decimal = 0
            var knownFixed = true, knownUsage = true
            var seenFixed: [String: FixedSubscription] = [:]
            var seenUsage: [String: UsageCharge] = [:]
            for item in subscriptions where item.currency == currency {
                let key = "\(item.id)|\(item.period.start.timeIntervalSince1970)|\(item.period.end.timeIntervalSince1970)"
                if let previous = seenFixed[key] { if previous.price != item.price { knownFixed = false }; continue }; seenFixed[key] = item
                let length = item.period.end.timeIntervalSince(item.period.start)
                let overlap = max(0, min(cycle.end, item.period.end).timeIntervalSince(max(cycle.start, item.period.start)))
                guard length > 0 else { knownFixed = false; continue }
                if overlap == 0 { continue }
                guard let price = item.price else { knownFixed = false; continue }
                fixed += price * Decimal(overlap / length)
            }
            for item in usage where item.currency == currency {
                if let previous = seenUsage[item.id] { if previous != item { knownUsage = false }; continue }; seenUsage[item.id] = item
                if item.period.end <= cycle.start || item.period.start >= cycle.end { continue }
                guard item.period.start >= cycle.start && item.period.end <= cycle.end, item.period.end > item.period.start, let cost = item.cost else { knownUsage = false; continue }
                metered += cost
            }
            let elapsed = min(max(now.timeIntervalSince(cycle.start), 0), cycle.end.timeIntervalSince(cycle.start))
            let duration = cycle.end.timeIntervalSince(cycle.start)
            let forecast: Decimal? = knownFixed && knownUsage && elapsed > 0 && duration > 0 ? fixed + metered * Decimal(duration / elapsed) : nil
            return CurrencyTotals(currency: currency, fixedCost: fixed, usageCost: metered, forecastCost: complete ? forecast : nil, isComplete: complete && knownFixed && knownUsage)
        }
    }
}
public enum Freshness {
    public static func isStale(checkedAt: Date, now: Date = Date()) -> Bool { now.timeIntervalSince(checkedAt) >= 6 * 3600 }
}
public struct BudgetEvent: Hashable {
    public let key: String
    public let threshold: String
}
public enum BudgetEvaluator {
    public static func evaluate(actual: Decimal?, forecast: Decimal?, budget: Decimal, currency: String, cycle: Cycle) -> [BudgetEvent] {
        guard budget > 0 else { return [] }
        var labels: [String] = []
        if let actual, actual >= budget * Decimal(string: "0.8")! { labels.append("80") }
        if let actual, actual >= budget { labels.append("100") }
        if let forecast, forecast >= budget { labels.append("forecast") }
        return labels.map { BudgetEvent(key: "\(currency):\(Int(cycle.start.timeIntervalSince1970)):\($0)", threshold: $0) }
    }
}
public protocol TokenStore { func save(_ token: String, accountID: String) throws; func load(accountID: String) throws -> String?; func delete(accountID: String) throws }
public struct KeychainError: Error { public let status: OSStatus; public init(_ status: OSStatus) { self.status = status } }

/// Cache only billing results; credentials must remain in the token store.
public struct SnapshotCache {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    private func file(_ accountID: String) -> URL {
        let safe = Data(accountID.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        return directory.appendingPathComponent(safe + ".json")
    }
    public func save(_ snapshot: BillingSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: file(snapshot.accountID), options: .atomic)
    }
    public func delete(accountID: String) throws { let url = file(accountID); if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
    public func load(accountID: String) throws -> BillingSnapshot? {
        let url = file(accountID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let snapshot = try JSONDecoder().decode(BillingSnapshot.self, from: Data(contentsOf: url))
        guard snapshot.accountID == accountID else { return nil }
        return snapshot
    }
}
