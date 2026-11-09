import Foundation

struct UsageTrendObservation {
    let serviceName: String
    let currency: String
    let period: Cycle
    let cumulative: Decimal?
}

/// Each input array is one complete API dimension, never a product-level sum.
enum UsageTrendBuilder {
    private struct Key: Hashable { let service: String; let currency: String }
    static func build(cycle: Cycle, now: Date, dimensions: [[UsageTrendObservation]], products: [UsageProductTotal], totals: [CurrencyTotals], usageComplete: Bool) -> (products: [UsageTrend], totals: [UsageTrend]) {
        var grouped: [Key: [[UsageTrendObservation]]] = [:]
        for dimension in dimensions {
            guard let item = dimension.first else { continue }
            grouped[Key(service: item.serviceName, currency: item.currency), default: []].append(dimension)
        }
        var productTrends: [UsageTrend] = []
        for product in products where product.source == "cumulative" {
            let key = Key(service: product.serviceName, currency: product.currency)
            guard let dimensionRows = grouped[key], !dimensionRows.isEmpty else { continue }
            var maps: [[Date: Decimal]] = []
            var starts: [[Date: Date]] = []
            var coverageComplete = usageComplete && product.isComplete
            for rows in dimensionRows {
                let ordered = rows.sorted { $0.period.end < $1.period.end }
                var ambiguousEnds = Set<Date>()
                for index in ordered.indices {
                    for other in ordered.indices where other > index {
                        let a = ordered[index].period, b = ordered[other].period
                        if a.end == b.end || (a.start < b.end && b.start < a.end) {
                            ambiguousEnds.insert(a.end); ambiguousEnds.insert(b.end)
                        }
                    }
                }
                if !ambiguousEnds.isEmpty { coverageComplete = false }
                var map: [Date: Decimal] = [:]
                var startsByEnd: [Date: Date] = [:]
                var seenEnds = Set<Date>()
                var expectedStart = cycle.start
                for row in ordered {
                    guard row.currency == product.currency, row.serviceName == product.serviceName,
                          row.period.start >= cycle.start, row.period.end <= min(cycle.end, now), row.period.end > row.period.start else { coverageComplete = false; continue }
                    if row.period.start != expectedStart { coverageComplete = false }
                    expectedStart = row.period.end
                    guard !ambiguousEnds.contains(row.period.end), let value = row.cumulative else { coverageComplete = false; continue }
                    if !seenEnds.insert(row.period.end).inserted { coverageComplete = false; map.removeValue(forKey: row.period.end); startsByEnd.removeValue(forKey: row.period.end); continue }
                    map[row.period.end] = value
                    startsByEnd[row.period.end] = row.period.start
                }
                maps.append(map)
                starts.append(startsByEnd)
            }
            guard let first = maps.first, !first.isEmpty else { continue }
            let dates = maps.dropFirst().reduce(Set(first.keys)) { $0.intersection($1.keys) }.sorted()
            guard !dates.isEmpty else { continue }
            if maps.contains(where: { Set($0.keys) != Set(dates) }) { coverageComplete = false }
            let points = dates.enumerated().map { index, date in
                let breaks = index == 0 || starts.contains { $0[date] != dates[index - 1] }
                return UsageTrendPoint(at: date, cost: maps.reduce(Decimal.zero) { $0 + $1[date]! }, startsSegment: breaks)
            }
            if points.last?.cost != product.cost { coverageComplete = false }
            productTrends.append(UsageTrend(currency: product.currency, serviceName: product.serviceName, points: points, isComplete: coverageComplete))
        }
        productTrends.sort { ($0.currency, $0.serviceName) < ($1.currency, $1.serviceName) }
        var totalTrends: [UsageTrend] = []
        for currency in Set(products.map(\.currency)).sorted() {
            let expected = products.filter { $0.currency == currency }
            let series = productTrends.filter { $0.currency == currency }
            guard !expected.isEmpty, series.count == expected.count, let first = series.first else { continue }
            let maps = series.map { Dictionary(uniqueKeysWithValues: $0.points.map { ($0.at, $0.cost) }) }
            let dates = maps.dropFirst().reduce(Set(first.points.map(\.at))) { $0.intersection($1.keys) }.sorted()
            guard !dates.isEmpty else { continue }
            let points = dates.enumerated().map { index, date in
                let breaks = index == 0 || series.contains { trend in
                    guard let position = trend.points.firstIndex(where: { $0.at == date }) else { return true }
                    return trend.points[position].startsSegment || position == 0 || trend.points[position - 1].at != dates[index - 1]
                }
                return UsageTrendPoint(at: date, cost: maps.reduce(Decimal.zero) { $0 + $1[date]! }, startsSegment: breaks)
            }
            let complete = series.allSatisfy(\.isComplete) && maps.allSatisfy { Set($0.keys) == Set(dates) } && points.last?.cost == totals.first(where: { $0.currency == currency })?.usageCost
            totalTrends.append(UsageTrend(currency: currency, serviceName: "", points: points, isComplete: complete))
        }
        return (productTrends, totalTrends)
    }
}
