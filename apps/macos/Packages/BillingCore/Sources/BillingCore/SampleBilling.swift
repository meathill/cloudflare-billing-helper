import Foundation

/// Synthetic local data for exploring the product; no network or credential access.
public enum SampleBilling {
    public static let account = AccountProfile(id: "local-sample-account", name: "Example account", source: .sample)
    public static func snapshot(now: Date = Date()) -> BillingSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        let cycle = Cycle(start: start, end: end)
        let daysInCycle = calendar.dateComponents([.day], from: start, to: end).day!
        let observedDays = min(daysInCycle, max(0, Int(now.timeIntervalSince(start) / 86_400)))
        let entries: [(name: String, rate: Decimal)] = [
            ("Workers Standard Requests", Decimal(string: "0.08")!),
            ("R2 Data Storage", Decimal(string: "0.03")!)
        ]
        let fixed = FixedSubscription(id: "sample-workers-plan", currency: "USD", price: 5, period: cycle, name: "Example subscription")
        var charges: [UsageCharge] = [], productTotals: [UsageProductTotal] = [], trends: [UsageTrend] = []
        for entry in entries {
            var points: [UsageTrendPoint] = []
            if observedDays > 0 {
                for day in 1...observedDays {
                    let from = start.addingTimeInterval(Double(day - 1) * 86_400)
                    let to = start.addingTimeInterval(Double(day) * 86_400)
                    charges.append(UsageCharge(id: "sample-\(entry.name)-\(day)", currency: "USD", cost: entry.rate, period: Cycle(start: from, end: to), serviceName: entry.name))
                    points.append(UsageTrendPoint(at: to, cost: entry.rate * Decimal(day), startsSegment: day == 1))
                }
            }
            productTotals.append(UsageProductTotal(serviceName: entry.name, currency: "USD", cost: entry.rate * Decimal(observedDays), source: "cumulative", isComplete: true, rawServiceNames: [entry.name]))
            if !points.isEmpty { trends.append(UsageTrend(currency: "USD", serviceName: entry.name, points: points, isComplete: true)) }
        }
        let daily = entries.reduce(Decimal.zero) { $0 + $1.rate }
        let metered = daily * Decimal(observedDays)
        let forecast: Decimal? = observedDays > 0 ? 5 + daily * Decimal(daysInCycle) : nil
        let totals = [CurrencyTotals(currency: "USD", fixedCost: 5, usageCost: metered, forecastCost: forecast)]
        let totalPoints: [UsageTrendPoint] = observedDays > 0 ? (1...observedDays).map { UsageTrendPoint(at: start.addingTimeInterval(Double($0) * 86_400), cost: daily * Decimal($0), startsSegment: $0 == 1) } : []
        let totalTrends = totalPoints.isEmpty ? [] : [UsageTrend(currency: "USD", serviceName: "", points: totalPoints, isComplete: true)]
        return BillingSnapshot(accountID: account.id, cycles: [cycle], totals: totals, checkedAt: now, isComplete: true, subscriptions: [fixed], usage: charges, sourceAsOf: totalPoints.last?.at, forecastIsEstimate: true, selectedCycle: cycle, forecastNote: forecast == nil ? "No complete sample day yet." : nil, usageProductTotals: productTotals, usageTrends: trends, usageTotalTrends: totalTrends)
    }
}
