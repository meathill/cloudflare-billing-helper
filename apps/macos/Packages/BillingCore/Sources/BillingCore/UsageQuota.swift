import Foundation

/// One observed charge period with quantities for one API dimension.
struct UsageQuantityObservation {
    let dimension: AnyHashable
    let serviceName: String
    let currency: String
    let period: Cycle
    let consumed: Double?
    let cumulativeBillable: Double?
    let cost: Decimal?
}

public enum QuotaStatus: String, Codable, Hashable { case ok, warn, danger, exhausted, unknown }

/// Average consumed quantity per day for one observed charge-period end.
public struct UsageQuotaPoint: Codable, Hashable {
    public let at: Date
    public let perDay: Double
    public init(at: Date, perDay: Double) { self.at = at; self.perDay = perDay }
}

/// Free-allowance consumption and projection for one cumulative product.
public struct UsageQuota: Codable, Hashable {
    public let serviceName: String
    public let currency: String
    public let unit: String?
    /// Consumed quantity in this cycle through `asOf`.
    public let used: Double
    /// Quantity Cloudflare already prices (beyond the free allowance).
    public let billable: Double?
    public let included: Double?
    /// "api" when inferred as consumed minus billable, "catalog" for the built-in allowance.
    public let includedSource: String?
    public let asOf: Date
    public let dailyRate: Double
    /// "recent" when based on the last few observed days, "cycle" for the whole-cycle average.
    public let rateBasis: String
    public let projectedTotal: Double
    /// Projected (or, when exhausted, observed) date the allowance runs out.
    public let exhaustionDate: Date?
    public let status: QuotaStatus
    public let projectedOverageCost: Decimal?
    public let points: [UsageQuotaPoint]
    public let isComplete: Bool
    public var usedFraction: Double? { included.flatMap { $0 > 0 ? used / $0 : nil } }
    public var needsAttention: Bool { status == .danger || status == .exhausted }
    public init(serviceName: String, currency: String, unit: String?, used: Double, billable: Double?, included: Double?, includedSource: String?, asOf: Date, dailyRate: Double, rateBasis: String, projectedTotal: Double, exhaustionDate: Date?, status: QuotaStatus, projectedOverageCost: Decimal?, points: [UsageQuotaPoint], isComplete: Bool) {
        self.serviceName = serviceName; self.currency = currency; self.unit = unit; self.used = used; self.billable = billable; self.included = included; self.includedSource = includedSource; self.asOf = asOf; self.dailyRate = dailyRate; self.rateBasis = rateBasis; self.projectedTotal = projectedTotal; self.exhaustionDate = exhaustionDate; self.status = status; self.projectedOverageCost = projectedOverageCost; self.points = points; self.isComplete = isComplete
    }
}

enum UsageQuotaBuilder {
    static let recentWindow: TimeInterval = 7 * 86400
    static let warnFraction = 0.7
    private struct Key: Hashable { let service: String; let currency: String }

    static func build(cycle: Cycle, now: Date, observations: [UsageQuantityObservation], catalog: ProductCatalog?) -> [UsageQuota] {
        let cutoff = min(cycle.end, now)
        let grouped = Dictionary(grouping: observations) { Key(service: $0.serviceName, currency: $0.currency) }
        var result: [UsageQuota] = []
        for (key, rows) in grouped {
            let spec = catalog?.product(for: key.service)
            guard let spec, spec.kind != "gauge" else { continue }
            let eligible = rows.filter { $0.period.start >= cycle.start && $0.period.end <= cutoff && $0.period.end > $0.period.start }
            guard let asOf = eligible.map(\.period.end).max() else { continue }
            let complete = eligible.count == rows.count && eligible.allSatisfy { $0.consumed != nil }
            let used = eligible.compactMap(\.consumed).reduce(0, +)

            var billable: Double? = 0
            for (_, dimensionRows) in Dictionary(grouping: eligible, by: \.dimension) {
                guard let latest = dimensionRows.max(by: { $0.period.end < $1.period.end }), let value = latest.cumulativeBillable, let total = billable else { billable = nil; break }
                billable = total + value
            }
            let included: Double?, includedSource: String?
            if let billable, billable > 0, used > billable { included = used - billable; includedSource = "api" }
            else if let value = spec.included { included = value; includedSource = "catalog" }
            else { included = nil; includedSource = nil }

            let byEnd = Dictionary(grouping: eligible, by: \.period.end)
            let points = byEnd.keys.sorted().map { end in
                UsageQuotaPoint(at: end, perDay: byEnd[end]!.reduce(0) { $0 + ($1.consumed ?? 0) / max($1.period.end.timeIntervalSince($1.period.start) / 86400, 1e-9) })
            }

            let observedDays = asOf.timeIntervalSince(cycle.start) / 86400
            let recent = eligible.filter { $0.period.end > asOf.addingTimeInterval(-recentWindow) }
            let recentStart = recent.map(\.period.start).min() ?? cycle.start
            let recentDays = asOf.timeIntervalSince(recentStart) / 86400
            let rateBasis = recentStart > cycle.start ? "recent" : "cycle"
            let rate: Double
            if rateBasis == "recent", recentDays > 0 { rate = recent.compactMap(\.consumed).reduce(0, +) / recentDays }
            else { rate = observedDays > 0 ? used / observedDays : 0 }
            let remainingDays = max(0, cycle.end.timeIntervalSince(asOf) / 86400)
            let projectedTotal = used + rate * remainingDays

            var status = QuotaStatus.unknown
            var exhaustionDate: Date?
            if let included, included > 0 {
                if used >= included {
                    status = .exhausted
                    var running = 0.0
                    for end in byEnd.keys.sorted() {
                        running += byEnd[end]!.compactMap(\.consumed).reduce(0, +)
                        if running >= included { exhaustionDate = end; break }
                    }
                } else {
                    let date = rate > 0 ? asOf.addingTimeInterval((included - used) / rate * 86400) : nil
                    if let date, date <= cycle.end { status = .danger; exhaustionDate = date }
                    else { status = used / included >= warnFraction ? .warn : .ok }
                }
            }

            var overageCost: Decimal?
            if let included {
                let cost = eligible.compactMap(\.cost).reduce(Decimal.zero, +)
                // Cloudflare rounds some products up to whole pricing units (e.g. $5 per started million KV lists),
                // so cost ÷ billable overstates the marginal price; it is only a fallback.
                let price: Double?
                if let unitPrice = spec.unitPrice { price = unitPrice }
                else if let billable, billable > 0, cost > 0 { price = NSDecimalNumber(decimal: cost).doubleValue / billable }
                else { price = nil }
                if let price { overageCost = Decimal(max(0, projectedTotal - included) * price) }
            }
            result.append(UsageQuota(serviceName: key.service, currency: key.currency, unit: spec.unit, used: used, billable: billable, included: included, includedSource: includedSource, asOf: asOf, dailyRate: rate, rateBasis: rateBasis, projectedTotal: projectedTotal, exhaustionDate: exhaustionDate, status: status, projectedOverageCost: overageCost, points: points, isComplete: complete))
        }
        return result.sorted { ($0.currency, $0.serviceName) < ($1.currency, $1.serviceName) }
    }
}
