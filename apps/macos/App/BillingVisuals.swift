import SwiftUI
import Charts
import BillingCore

struct PeriodProgress: View {
    let cycle: Cycle
    let now: Date
    private var progress: (elapsed: Int, total: Int, fraction: Double) { cycleProgress(cycle: cycle, now: now) }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(tr("Billing cycle elapsed", "账期进度")); Spacer(); Text(tr("\(progress.elapsed) of \(progress.total) days", "已过 \(progress.elapsed) / \(progress.total) 天")) }.font(.caption).foregroundStyle(BrandPalette.muted)
            ProgressView(value: progress.fraction).tint(BrandPalette.accent)
                .accessibilityLabel(tr("Billing cycle elapsed", "账期进度"))
                .accessibilityValue(tr("\(progress.elapsed) of \(progress.total) days", "已过 \(progress.elapsed) / \(progress.total) 天"))
        }
    }
}

func cycleProgress(cycle: Cycle, now: Date) -> (elapsed: Int, total: Int, fraction: Double) {
    let duration = cycle.end.timeIntervalSince(cycle.start)
    guard duration > 0 else { return (0, 0, 0) }
    let elapsed = min(max(now.timeIntervalSince(cycle.start), 0), duration)
    return (Int(elapsed / 86400), max(1, Int(ceil(duration / 86400))), elapsed / duration)
}

struct TrendSegment: Identifiable {
    let id: Int
    let points: [UsageTrendPoint]
}
func trendSegments(_ points: [UsageTrendPoint], cycle: Cycle) -> [TrendSegment] {
    let sorted = points.sorted { $0.at < $1.at }
    var result: [TrendSegment] = []
    var startNewSegment = true
    for point in sorted {
        guard point.at >= cycle.start, point.at <= cycle.end, NSDecimalNumber(decimal: point.cost).doubleValue.isFinite else { startNewSegment = true; continue }
        if startNewSegment || point.startsSegment { result.append(TrendSegment(id: result.count, points: [point])) }
        else { let previous = result.removeLast(); result.append(TrendSegment(id: previous.id, points: previous.points + [point])) }
        startNewSegment = false
    }
    return result
}

func observedTrendDomain(points: [UsageTrendPoint], cycle: Cycle) -> ClosedRange<Date>? {
    guard let first = points.first?.at, let last = points.last?.at else { return nil }
    if first < last { return first...last }
    let before = max(cycle.start, first.addingTimeInterval(-43200))
    let after = min(cycle.end, first.addingTimeInterval(43200))
    if before < after { return before...after }
    return first.addingTimeInterval(-1)...first.addingTimeInterval(1)
}

private func trendDate(_ date: Date) -> String {
    var style = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale(identifier: previewLanguage ?? Locale.current.identifier))
    style.timeZone = TimeZone(secondsFromGMT: 0)!
    return date.formatted(style)
}

struct UsageTrendChart: View {
    let trend: UsageTrend
    let cycle: Cycle
    var compact = false
    private var segments: [TrendSegment] { trendSegments(trend.points, cycle: cycle) }
    private var points: [UsageTrendPoint] { segments.flatMap(\.points) }
    var body: some View {
        if let first = points.first, let last = points.last, let domain = observedTrendDomain(points: points, cycle: cycle) {
            VStack(alignment: .leading, spacing: 6) {
                if !compact { Text(tr("Currency: ", "币种：") + trend.currency).font(.caption).foregroundStyle(BrandPalette.muted) }
                Chart {
                    ForEach(segments) { segment in
                        ForEach(Array(segment.points.enumerated()), id: \.offset) { _, point in
                            if segment.points.count > 1 {
                                LineMark(x: .value(tr("Date", "日期"), point.at), y: .value(tr("Cumulative usage cost", "累计按量费用"), NSDecimalNumber(decimal: point.cost).doubleValue), series: .value("segment", segment.id)).interpolationMethod(.linear).foregroundStyle(BrandPalette.accent)
                            } else {
                                PointMark(x: .value(tr("Date", "日期"), point.at), y: .value(tr("Cumulative usage cost", "累计按量费用"), NSDecimalNumber(decimal: point.cost).doubleValue)).foregroundStyle(BrandPalette.accent)
                            }
                        }
                    }
                }.chartXScale(domain: domain).chartXAxis(.hidden).chartYAxis { if !compact { AxisMarks(position: .leading) } }
                    .frame(height: compact ? 30 : 120)
                    .accessibilityLabel(tr("Cumulative usage cost trend", "累计按量费用趋势"))
                    .accessibilityValue(tr("\(trendDate(first.at)): \(money(first.cost, trend.currency)); \(trendDate(last.at)): \(money(last.cost, trend.currency)).", "\(trendDate(first.at))：\(money(first.cost, trend.currency))；\(trendDate(last.at))：\(money(last.cost, trend.currency))。"))
                if !compact {
                    HStack { Text(trendDate(first.at)); Spacer(); if first.at != last.at { Text(trendDate(last.at)) } }.font(.caption2).foregroundStyle(BrandPalette.muted)
                    Text(tr("Data through: \(trendDate(last.at)), \(money(last.cost, trend.currency))", "数据截至：\(trendDate(last.at))，\(money(last.cost, trend.currency))")).secondaryText()
                    if !trend.isComplete { Text(tr("Some dates are missing or the latest point is not aligned with the current total.", "部分日期缺少数据，或最新点与当前小计未对齐。")).font(.caption).foregroundStyle(BrandPalette.warning).fixedSize(horizontal: false, vertical: true) }
                    DisclosureGroup(tr("Daily cumulative records", "每日累计记录")) {
                        ForEach(Array(points.enumerated()), id: \.offset) { _, point in HStack { Text(trendDate(point.at)); Spacer(); Text(money(point.cost, trend.currency)).monospacedDigit() }.font(.caption) }
                    }
                }
            }
        } else { Text(tr("No observed trend points are available.", "暂无可用的趋势数据点。")).secondaryText() }
    }
}

func usableTrend(_ trend: UsageTrend, cycle: Cycle) -> Bool {
    trend.source == "cumulative" && !trendSegments(trend.points, cycle: cycle).isEmpty
}
func usesProductTrendFallback(snapshot: BillingSnapshot, cycle: Cycle?) -> Bool {
    guard let cycle, snapshot.selectedCycle == cycle else { return false }
    let hasTotal = snapshot.usageTotalTrends?.contains { usableTrend($0, cycle: cycle) } ?? false
    let hasProduct = snapshot.usageTrends?.contains { usableTrend($0, cycle: cycle) } ?? false
    return !hasTotal && hasProduct
}

struct UsageTrendsSummary: View {
    let snapshot: BillingSnapshot
    let cycle: Cycle?
    var body: some View {
        if let cycle, snapshot.selectedCycle == cycle {
            if snapshot.usageTotalTrends == nil && snapshot.usageTrends == nil {
                Text(tr("Refresh to load the cumulative cost trend.", "刷新后加载累计费用趋势。")).secondaryText().fixedSize(horizontal: false, vertical: true)
            } else {
                let currencies = Set(snapshot.totals.map(\.currency) + (snapshot.usageTrends ?? []).map(\.currency) + (snapshot.usageTotalTrends ?? []).map(\.currency)).sorted()
                if currencies.isEmpty { Text(tr("No trend data is available for this cycle.", "本账期暂无可用趋势数据。")).secondaryText() }
                ForEach(currencies, id: \.self) { currency in
                    let total = snapshot.usageTotalTrends?.first { $0.currency == currency && usableTrend($0, cycle: cycle) }
                    let products = (snapshot.usageTrends ?? []).filter { $0.currency == currency && usableTrend($0, cycle: cycle) }
                    if let total {
                        VStack(alignment: .leading, spacing: 8) { Text(currency).font(.headline); UsageTrendChart(trend: total, cycle: cycle) }
                    } else if !products.isEmpty {
                        ProductTrendPicker(snapshot: snapshot, cycle: cycle, currency: currency, trends: products)
                            .id("\(snapshot.accountID)|\(cycle.start.timeIntervalSince1970)|\(cycle.end.timeIntervalSince1970)|\(currency)")
                    } else {
                        VStack(alignment: .leading, spacing: 6) { Text(currency).font(.headline); Text(tr("No reliable trend data is available for this cycle.", "本账期暂无可信趋势数据。")).secondaryText().fixedSize(horizontal: false, vertical: true) }
                    }
                }
            }
        } else { Text(tr("Refresh to load the cumulative cost trend.", "刷新后加载累计费用趋势。")).secondaryText().fixedSize(horizontal: false, vertical: true) }
    }
}

func orderedProductTrends(_ trends: [UsageTrend], snapshot: BillingSnapshot, cycle: Cycle, currency: String) -> [UsageTrend] {
    let rows = usageDisplayRows(snapshot: snapshot, cycle: cycle) ?? []
    func cost(_ trend: UsageTrend) -> Decimal? { rows.first { $0.currency == currency && $0.name == trend.serviceName }?.cost }
    return trends.filter { $0.currency == currency && usableTrend($0, cycle: cycle) }.sorted { left, right in
        switch (cost(left), cost(right)) {
        case let (.some(a), .some(b)) where a != b: return a > b
        case (.some, nil): return true
        case (nil, .some): return false
        default: return left.serviceName.localizedStandardCompare(right.serviceName) == .orderedAscending
        }
    }
}
func selectedProductTrend(_ trends: [UsageTrend], selectedName: String?) -> UsageTrend? {
    trends.first(where: { $0.serviceName == selectedName }) ?? trends.first
}

private struct ProductTrendPicker: View {
    let snapshot: BillingSnapshot
    let cycle: Cycle
    let currency: String
    let trends: [UsageTrend]
    @State private var selection: String?
    private var options: [UsageTrend] { orderedProductTrends(trends, snapshot: snapshot, cycle: cycle, currency: currency) }
    private var selected: UsageTrend? { selectedProductTrend(options, selectedName: selection) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Product dates differ; view one product's cumulative cost.", "各产品数据日期不同，先查看单个产品的累计费用。 ")).font(.caption).foregroundStyle(BrandPalette.muted).fixedSize(horizontal: false, vertical: true)
            if let selected {
                HStack {
                    Text(tr("Product", "产品"))
                    Picker(tr("Product", "产品"), selection: Binding(get: { selected.serviceName }, set: { selection = $0 })) {
                        ForEach(Array(options.enumerated()), id: \.offset) { _, trend in Text(productTrendLabel(trend.serviceName)).lineLimit(1).truncationMode(.tail).tag(trend.serviceName) }
                    }.labelsHidden().pickerStyle(.menu).frame(maxWidth: 240, alignment: .leading).clipped()
                }
                UsageTrendChart(trend: selected, cycle: cycle)
            }
        }.onAppear { if selection == nil { selection = options.first?.serviceName } }
         .onChange(of: options.map(\.serviceName)) { names in if let selection, !names.contains(selection) { self.selection = names.first } }
    }
}

private let displayCatalog: ProductCatalog? = Bundle.main.url(forResource: "catalog", withExtension: "json").flatMap { try? ProductCatalog(contentsOf: $0) }
func serviceBaseName(_ name: String) -> String {
    name.replacingOccurrences(of: "\\s*\\([^()]*\\)\\s*$", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
}
func productFamily(_ name: String, catalog: ProductCatalog? = displayCatalog) -> String {
    let base = serviceBaseName(name)
    switch base.lowercased() { case "r2": return "r2"; case "kv": return "kv"; case "images": return "images"; default: break }
    guard !base.isEmpty, let product = catalog?.product(for: base) else { return "other" }
    if product.key.hasPrefix("images-") { return "images" }
    return ["workers", "kv", "r2", "d1", "do"].contains(product.family) ? product.family : "other"
}
func shortProductName(_ name: String, catalog: ProductCatalog? = displayCatalog) -> String {
    let base = serviceBaseName(name)
    guard !base.isEmpty else { return tr("Unknown service", "未知服务") }
    guard let product = catalog?.product(for: base) else { return name.trimmingCharacters(in: .whitespacesAndNewlines) }
    switch product.key {
    case "workers-cpu-ms": return tr("CPU time", "CPU 时间")
    case "workers-standard-requests": return tr("Requests", "请求")
    case "worker-build-minutes": return tr("Build time", "构建时间")
    case "kv-storage", "r2-data-storage", "d1-storage", "do-sql-storage": return tr("Storage", "存储")
    case "kv-read-operations": return tr("Reads", "读取")
    case "kv-write-operations": return tr("Writes", "写入")
    case "kv-delete-operations": return tr("Deletes", "删除")
    case "kv-list-operations": return tr("Lists", "列举")
    case "r2-class-a-operations": return tr("Class A operations", "A 类操作")
    case "r2-class-b-operations": return tr("Class B operations", "B 类操作")
    case "d1-rows-read", "do-storage-rows-read": return tr("Rows read", "读取行数")
    case "d1-rows-written", "do-storage-rows-written": return tr("Rows written", "写入行数")
    case "do-compute-requests": return tr("Compute requests", "计算请求")
    case "do-compute-duration": return tr("Compute duration", "计算时长")
    case "images-transformed": return tr("Transformations", "转换")
    default: return product.name
    }
}
private func familyLabel(_ family: String) -> String {
    switch family { case "workers": return "Workers"; case "kv": return "Workers KV"; case "r2": return "R2"; case "d1": return "D1"; case "do": return "Durable Objects"; case "images": return "Images"; default: return tr("Other services", "其他服务") }
}

func productTrendLabel(_ name: String, catalog: ProductCatalog? = displayCatalog) -> String {
    let family = familyLabel(productFamily(name, catalog: catalog)), short = shortProductName(name, catalog: catalog)
    return family.caseInsensitiveCompare(short) == .orderedSame ? family : family + " · " + short
}
func usageShareDenominator(rows: [UsageDisplayRow], reportedUsage: Decimal?) -> Decimal? {
    guard let reportedUsage, reportedUsage > 0, !rows.isEmpty, rows.allSatisfy({ $0.cost != nil && $0.cost! >= 0 }) else { return nil }
    let sum = rows.compactMap(\.cost).reduce(Decimal.zero, +)
    return sum == reportedUsage ? reportedUsage : nil
}

/// Zero-cost rows collapse unless `keepVisible` says otherwise (e.g. a free quota that is running out).
func partitionProducts(_ rows: [UsageDisplayRow], keepVisible: (UsageDisplayRow) -> Bool = { _ in false }) -> (visible: [UsageDisplayRow], zero: [UsageDisplayRow]) {
    let collapsed = rows.map { $0.cost == 0 && !keepVisible($0) }
    return (rows.indices.filter { !collapsed[$0] }.map { rows[$0] }, rows.indices.filter { collapsed[$0] }.map { rows[$0] })
}

struct ProductDetails: View {
    let snapshot: BillingSnapshot
    let cycle: Cycle?
    var isSample = false
    @State private var showZero: Set<String> = []
    private var usageRows: [UsageDisplayRow]? { usageDisplayRows(snapshot: snapshot, cycle: cycle) }
    private var subscriptions: [FixedSubscription] {
        guard let cycle else { return [] }; var seen = Set<String>()
        return snapshot.subscriptions.filter { $0.period.start < cycle.end && $0.period.end > cycle.start && seen.insert("\($0.id)|\($0.period.start.timeIntervalSince1970)|\($0.period.end.timeIntervalSince1970)").inserted }
    }
    var body: some View {
        if let usageRows {
            if snapshot.usageTrends == nil { Text(tr("Refresh to load product trends.", "刷新后加载产品趋势。")).font(.caption).foregroundStyle(BrandPalette.muted) }
            else if snapshot.usageTrends?.isEmpty == true { Text(tr("No product trend data is available for this cycle.", "本账期暂无可用产品趋势数据。")).font(.caption).foregroundStyle(BrandPalette.muted) }
            if usageRows.isEmpty { Text(tr("No usage charges are available.", "暂无按量费用数据。")).secondaryText() }
            let currencies = Set(usageRows.map(\.currency)).sorted()
            ForEach(currencies, id: \.self) { currency in
                let currencyRows = usageRows.filter { $0.currency == currency }
                let denominator = usageShareDenominator(rows: currencyRows, reportedUsage: snapshot.totals.first(where: { $0.currency == currency })?.usageCost)
                let partition = partitionProducts(currencyRows) { row in usageQuota(for: row, in: snapshot).map { [.warn, .danger, .exhausted].contains($0.status) } ?? false }
                let active = partition.visible
                let zero = partition.zero
                VStack(alignment: .leading, spacing: 14) {
                    Text(currency).font(.headline)
                    if denominator == nil { Text(tr("Usage-cost shares are unavailable when the total is zero, incomplete, or includes negative adjustments.", "按量费用为零、数据不完整或包含负调整时，无法计算费用占比。")).font(.caption).foregroundStyle(BrandPalette.muted).fixedSize(horizontal: false, vertical: true) }
                    familyRows(active, denominator: denominator)
                    if !zero.isEmpty {
                        DisclosureGroup(isExpanded: Binding(get: { showZero.contains(currency) }, set: { if $0 { showZero.insert(currency) } else { showZero.remove(currency) } })) {
                            familyRows(zero, denominator: denominator)
                        } label: { Text(tr("\(zero.count) zero-cost product(s)", "\(zero.count) 个零费用产品")) }
                    }
                }
            }
        } else { Text(tr("Product costs unavailable until the next refresh.", "产品费用将在下次刷新后显示。")).secondaryText() }
        if !subscriptions.isEmpty {
            Divider()
            Text(tr("Fixed subscriptions", "固定订阅")).font(.headline)
            ForEach(Array(subscriptions.enumerated()), id: \.offset) { _, item in
                DisclosureGroup(isSample && item.name == "Example subscription" ? tr("Example subscription", "示例订阅") : (item.name == "Account" ? tr("Account subscription", "账户订阅") : item.name)) {
                    HStack { Text(tr("Current service period overlap", "当前服务期分摊")); Spacer(); Text(money(cycle.flatMap { BillingCalculator.calculate(cycle: $0, subscriptions: [item], usage: [], now: snapshot.sourceAsOf ?? $0.start).first?.fixedCost }, item.currency)) }
                    HStack { Text(tr("Subscription price", "订阅原价")); Spacer(); Text(money(item.price, item.currency)) }
                    Text(cycleLabel(item.period)).font(.caption)
                }
            }
        }
    }
    @ViewBuilder private func familyRows(_ rows: [UsageDisplayRow], denominator: Decimal?) -> some View {
        let families = rows.map { productFamily($0.name) }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        ForEach(families, id: \.self) { family in
            VStack(alignment: .leading, spacing: 12) {
                Text(familyLabel(family)).font(.subheadline.weight(.semibold))
                ForEach(Array(rows.filter { productFamily($0.name) == family }.enumerated()), id: \.offset) { _, row in
                    productRow(row, family: family, denominator: denominator)
                }
            }
        }
    }
    @ViewBuilder private func productRow(_ row: UsageDisplayRow, family: String, denominator: Decimal?) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(shortProductName(row.name)).fontWeight(.medium).accessibilityLabel(familyLabel(family) + ": " + shortProductName(row.name))
                    Spacer(minLength: 8)
                    Text(money(row.cost, row.currency)).monospacedDigit()
                }
                if let amount = row.cost, let denominator {
                    let share = NSDecimalNumber(decimal: amount / denominator).doubleValue
                    if share.isFinite && share >= 0 && share <= 1 {
                        HStack(spacing: 8) {
                            UsageShareBar(value: share)
                            Text(share.formatted(.percent.precision(.fractionLength(1)))).font(.caption).foregroundStyle(BrandPalette.muted).accessibilityHidden(true)
                        }
                    }
                } else if let amount = row.cost, amount < 0 {
                    Text(tr("Negative adjustment", "负费用调整")).font(.caption).foregroundStyle(BrandPalette.muted)
                }
                if let quota = usageQuota(for: row, in: snapshot) { QuotaUsageView(quota: quota) }
                DisclosureGroup(tr("Details", "详情")) {
                    let product = snapshot.usageProductTotals?.first { $0.currency == row.currency && $0.serviceName == row.name }
                    if let names = product?.rawServiceNames, !names.isEmpty { Text(tr("Cloudflare services: ", "Cloudflare 服务名：") + names.joined(separator: ", ")).secondaryText().fixedSize(horizontal: false, vertical: true) }
                    else { Text(tr("Service: ", "服务名：") + (row.name.isEmpty ? tr("Unknown service", "未知服务") : row.name)).secondaryText().fixedSize(horizontal: false, vertical: true) }
                    Text(row.sourceLabel).secondaryText()
                }.font(.caption)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let cycle, let trend = snapshot.usageTrends?.first(where: { $0.currency == row.currency && $0.serviceName == row.name }), trend.source == "cumulative", !trend.points.isEmpty {
                VStack(alignment: .trailing, spacing: 3) {
                    UsageTrendChart(trend: trend, cycle: cycle, compact: true).frame(width: 140)
                    if !trend.isComplete { Text(tr("Partial trend", "趋势数据不完整")).font(.caption2).foregroundStyle(BrandPalette.warning) }
                }
            } else {
                Text("—").foregroundStyle(BrandPalette.muted).frame(width: 140, alignment: .center).accessibilityLabel(tr("Trend unavailable", "趋势不可用"))
            }
        }.padding(.vertical, 8)
    }
}

/// Free-allowance alerts for the selected cycle: exhausted first, then the earliest projected exhaustion.
func quotaAlerts(_ snapshot: BillingSnapshot?, cycle: Cycle?) -> [UsageQuota] {
    guard let snapshot, let cycle, snapshot.selectedCycle == cycle else { return [] }
    return (snapshot.usageQuotas ?? []).filter(\.needsAttention).sorted {
        ($0.status == .exhausted ? 0 : 1, $0.exhaustionDate ?? .distantFuture, $0.serviceName) < ($1.status == .exhausted ? 0 : 1, $1.exhaustionDate ?? .distantFuture, $1.serviceName)
    }
}
func usageQuota(for row: UsageDisplayRow, in snapshot: BillingSnapshot) -> UsageQuota? {
    snapshot.usageQuotas?.first { $0.serviceName == row.name && $0.currency == row.currency }
}
private func quantityUnit(_ unit: String) -> String {
    switch unit {
    case "ops", "requests": return tr(unit, "次")
    case "rows": return tr(unit, "行")
    case "ms": return tr(unit, "毫秒")
    case "minutes": return tr(unit, "分钟")
    case "hours": return tr(unit, "小时")
    case "emails": return tr(unit, "封")
    case "images": return tr(unit, "张")
    case "events": return tr(unit, "条")
    default: return unit
    }
}
func formatQuantity(_ value: Double, unit: String?) -> String {
    let number = value.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)).locale(Locale(identifier: previewLanguage ?? Locale.current.identifier)))
    guard let unit, !unit.isEmpty else { return number }
    return number + " " + quantityUnit(unit)
}
private func quotaDate(_ date: Date) -> String {
    date.formatted(Date.FormatStyle().month(.abbreviated).day().locale(Locale(identifier: previewLanguage ?? Locale.current.identifier)))
}
func quotaStatusText(_ quota: UsageQuota) -> String {
    switch quota.status {
    case .exhausted: return quota.exhaustionDate.map { tr("Free quota used up on \(quotaDate($0))", "免费额度已于 \(quotaDate($0)) 用完") } ?? tr("Free quota used up", "免费额度已用完")
    case .danger: return quota.exhaustionDate.map { tr("Projected to run out \(quotaDate($0))", "预计 \(quotaDate($0)) 用完免费额度") } ?? tr("Projected to run out this cycle", "预计本账期内用完免费额度")
    case .warn: return tr("Most of the free quota is used", "免费额度已用大半")
    case .ok: return tr("Not projected to run out this cycle", "本账期内预计不会用完")
    case .unknown: return tr("Free quota unknown", "免费额度未知")
    }
}
func quotaUsageText(_ quota: UsageQuota) -> String {
    let used = formatQuantity(quota.used, unit: quota.unit)
    let share = quota.usedFraction.map { " (" + $0.formatted(.percent.precision(.fractionLength(0))) + ")" } ?? ""
    let usage = quota.included.map { tr("Used \(used) of \(formatQuantity($0, unit: quota.unit))", "已用 \(used) / \(formatQuantity($0, unit: quota.unit))") + share } ?? tr("Used \(used)", "已用 \(used)")
    guard quota.dailyRate > 0 else { return usage }
    let rate = formatQuantity(quota.dailyRate, unit: quota.unit)
    return usage + " · " + (quota.rateBasis == "recent" ? tr("\(rate)/day over the last 7 days", "近 7 天日均 \(rate)") : tr("\(rate)/day this cycle", "本账期日均 \(rate)"))
}
func quotaOverageText(_ quota: UsageQuota) -> String? {
    guard let cost = quota.projectedOverageCost, cost > 0 else { return nil }
    return tr("Estimated overage this cycle ≈ \(money(cost, quota.currency))", "预计本账期超额 ≈ \(money(cost, quota.currency))")
}
func quotaColor(_ status: QuotaStatus) -> Color {
    switch status {
    case .exhausted, .danger: return BrandPalette.danger
    case .warn: return BrandPalette.warning
    case .ok: return BrandPalette.success
    case .unknown: return BrandPalette.muted
    }
}

/// Consumed share of a free allowance; the fill is capped at the allowance.
struct QuotaBar: View {
    let quota: UsageQuota
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(BrandPalette.separator)
                Capsule().fill(quotaColor(quota.status)).frame(width: geometry.size.width * min(max(quota.usedFraction ?? 0, 0), 1))
            }
        }.frame(height: 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tr("Free quota used", "免费额度使用量"))
            .accessibilityValue(quotaUsageText(quota))
    }
}

struct QuotaUsageView: View {
    let quota: UsageQuota
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if quota.included != nil { QuotaBar(quota: quota) }
            Text(quotaUsageText(quota)).font(.caption).foregroundStyle(BrandPalette.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text(quotaStatusText(quota)).foregroundStyle(quota.status == .ok ? BrandPalette.muted : quotaColor(quota.status))
                if let overage = quotaOverageText(quota) { Text("·").foregroundStyle(BrandPalette.muted); Text(overage).foregroundStyle(BrandPalette.danger) }
            }.font(.caption).fixedSize(horizontal: false, vertical: true)
            if !quota.isComplete { Text(tr("Some usage quantities are missing.", "部分用量数据缺失。")).font(.caption2).foregroundStyle(BrandPalette.warning) }
        }
    }
}

struct QuotaAlertList: View {
    let quotas: [UsageQuota]
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 12) {
            ForEach(quotas, id: \.serviceName) { quota in
                if compact {
                    Label(productTrendLabel(quota.serviceName) + tr(": ", "：") + quotaStatusText(quota), systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(quotaColor(quota.status)).fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(productTrendLabel(quota.serviceName)).fontWeight(.medium)
                        QuotaUsageView(quota: quota)
                    }
                }
            }
        }
    }
}

struct UsageShareBar: View {
    let value: Double
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(BrandPalette.separator)
                Capsule().fill(BrandPalette.accent).frame(width: geometry.size.width * value)
            }
        }.frame(height: 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tr("Share of usage charges", "按量费用占比"))
            .accessibilityValue(value.formatted(.percent.precision(.fractionLength(1))))
    }
}
