import Foundation

public protocol BillingTransport { func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) }
public struct URLSessionBillingTransport: BillingTransport {
    public init() {}
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BillingError.invalidResponse }
        return (data, http)
    }
}
public enum BillingError: Error { case invalidToken, insufficientPermissions, httpStatus(Int), requestFailure(status: Int, codes: [Int], noSubscriptionMessage: Bool, notFoundMessage: Bool, messageWords: [String], noActiveSubscription: Bool, safeSummary: String?), decoding(path: String), invalidResponse, apiFailure, unsupportedAccount, noBillingCycle }
private struct Envelope<T: Decodable>: Decodable { let success: Bool; let result: T; let result_info: PageInfo? }
private struct PageInfo: Decodable { let page: Int?; let total_pages: Int? }
private struct APIStatus: Decodable { struct Item: Decodable { let code: Int?; let message: String? }; let success: Bool?; let errors: [Item]? }
private struct RatePlan: Decodable { let id: String?; let currency: String?; let externally_managed: Bool? }
private struct Info: Decodable { let covered: Bool; let subscriptions: [Anchor] }
private struct Anchor: Decodable { let id: String; let billing_cycle_anchor_timestamp: String; let start_timestamp: String; let end_timestamp: String? }
private struct Subscription: Decodable { let id: String?; let currency: String?; let price: Decimal?; let current_period_start: String?; let current_period_end: String?; let state: String?; let frequency: String?; let initial_period_start: String?; let rate_plan: RatePlan? }
private struct Zone: Decodable { let id: String; let name: String }
private struct Usage: Decodable { let BillingCurrency: String?; let ContractedCost: Decimal?; let CumulatedContractedCost: Decimal?; let ConsumedQuantity: Double?; let CumulatedPricingQuantity: Double?; let ChargePeriodStart: String?; let ChargePeriodEnd: String?; let ServiceName: String?; let SubscriptionId: String?; let ZoneId: String?; let BillingPeriodStart: String?; let PricingUnit: String?; let ConsumedUnit: String?; let ChargeDescription: String?; let ServiceFamilyName: String? }
private struct UsageDimension: Hashable {
    let subscription: String?; let zone: String?; let currency: String?; let service: String?; let family: String?; let description: String?; let pricingUnit: String?; let consumedUnit: String?; let billingStart: String?
    init(_ row: Usage) { subscription = row.SubscriptionId; zone = row.ZoneId; currency = row.BillingCurrency; service = row.ServiceName; family = row.ServiceFamilyName; description = row.ChargeDescription; pricingUnit = row.PricingUnit; consumedUnit = row.ConsumedUnit; billingStart = row.BillingPeriodStart }
}
private struct ProductKey: Hashable { let service: String; let currency: String }
public struct BillingService {
    private let transport: any BillingTransport
    private let catalog: ProductCatalog?
    public init(transport: any BillingTransport = URLSessionBillingTransport(), catalog: ProductCatalog? = nil) { self.transport = transport; self.catalog = catalog }
    private func safeErrorSummary(_ messages: [String], token: String) -> String {
        var value = messages.joined(separator: " | ")
        if !token.isEmpty { value = value.replacingOccurrences(of: token, with: "[redacted]") }
        // Only retain ASCII in local diagnostics; normalize controls and obscure
        // identifying, network and financial values before truncating.
        value = String(value.unicodeScalars.map { $0.isASCII ? Character($0) : " " })
        let patterns = [
            #"(?i)\b(?:https?|ftp)://[^\s<>"']+"#,
            #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            #"(?i)\b(?:[A-Z0-9-]+\.)+[A-Z]{2,}\b"#,
            #"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#,
            #"(?i)\b[0-9a-f]{16,}\b"#,
            #"\b[A-Za-z0-9_-]{16,}\b"#,
            #"\b[A-Za-z0-9_]+-[A-Za-z0-9_-]+\b"#,
            #"[$€£]?[-+]?\d[\d,.]*%?"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return "[redacted]" }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            value = regex.stringByReplacingMatches(in: value, range: range, withTemplate: "[redacted]")
        }
        value = value.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        return String(value.prefix(240))
    }
    private func get<T: Decodable>(_ path: String, token: String, query: [URLQueryItem] = [], diagnostic: Bool = false) async throws -> Envelope<T> {
        var components = URLComponents(string: "https://api.cloudflare.com/client/v4" + path)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        for attempt in 0..<3 {
            let (data, response) = try await transport.data(for: request)
            if response.statusCode == 401 { throw BillingError.invalidToken }
            let status = try? JSONDecoder().decode(APIStatus.self, from: data)
            let codes = status?.errors?.compactMap(\.code) ?? []
            if diagnostic && (!(200...299).contains(response.statusCode) || status?.success == false) {
                let messages = (status?.errors ?? []).compactMap(\.message).map { $0.lowercased() }
                let noSubscription = messages.contains { message in
                    message.contains("subscription") && ["no subscription", "no active subscription", "not found", "does not exist", "does not have", "has no", "could not find", "unable to find", "doesn't have"].contains { message.contains($0) }
                }
                let notFound = messages.contains { $0.contains("not found") }
                let noActiveSubscription = messages.contains { message in
                    let normalized = message.split { !$0.isASCII || !$0.isLetter }.joined(separator: " ")
                    return ["no active subscription", "does not have an active subscription", "has no active subscription", "doesn t have an active subscription", "does not have an active core subscription", "no active core subscription"].contains { normalized.contains($0) }
                }
                let allowed = Set(["zone", "subscription", "not", "does", "have", "has", "a", "an", "active", "find", "could", "unable", "missing", "found", "no", "available", "for", "to", "the", "is", "this", "requested", "resource", "exist", "was", "with", "of", "s", "t", "paid", "free", "legacy", "billing", "plan", "contract", "current", "currently", "subscriptions", "valid", "any", "such", "been"])
                let words = messages.flatMap { $0.split { !$0.isASCII || !$0.isLetter }.map(String.init) }.map { allowed.contains($0) ? $0 : "_" }
                let summary: String? = response.statusCode == 404 && codes == [1207] && path.hasPrefix("/zones/") && path.hasSuffix("/subscription") ? safeErrorSummary((status?.errors ?? []).compactMap(\.message), token: token) : nil
                throw BillingError.requestFailure(status: response.statusCode, codes: codes, noSubscriptionMessage: noSubscription, notFoundMessage: notFound, messageWords: Array(words.prefix(40)), noActiveSubscription: noActiveSubscription, safeSummary: summary)
            }
            if response.statusCode == 403 { throw BillingError.insufficientPermissions }
            if response.statusCode == 429 || (500...599).contains(response.statusCode) {
                if attempt < 2 { let delay = min(Double(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? pow(2, Double(attempt)), 30); try await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000)); continue }
            }
            guard (200...299).contains(response.statusCode) else { throw BillingError.httpStatus(response.statusCode) }
            let envelope: Envelope<T>
            do { envelope = try JSONDecoder().decode(Envelope<T>.self, from: data) }
            catch let DecodingError.keyNotFound(key, context) { throw BillingError.decoding(path: (context.codingPath.map(\.stringValue) + [key.stringValue]).joined(separator: ".")) }
            catch let DecodingError.typeMismatch(_, context) { throw BillingError.decoding(path: context.codingPath.map(\.stringValue).joined(separator: ".")) }
            catch let DecodingError.valueNotFound(_, context) { throw BillingError.decoding(path: context.codingPath.map(\.stringValue).joined(separator: ".")) }
            catch let DecodingError.dataCorrupted(context) { throw BillingError.decoding(path: context.codingPath.map(\.stringValue).joined(separator: ".")) }
            catch { throw BillingError.invalidResponse }
            guard envelope.success else { throw BillingError.apiFailure }
            return envelope
        }
        throw BillingError.invalidResponse
    }
    private func diagnosticIssue(_ source: String, _ error: Error) -> String {
        switch error {
        case BillingError.requestFailure(let status, let codes, let noSubscription, let notFound, let words, let noActive, let summary): return "\(source) unavailable: HTTP \(status), codes=\(codes.map(String.init).joined(separator: ",")), no_subscription_message=\(noSubscription), not_found_message=\(notFound), no_active_subscription=\(noActive), message_words=\(words.joined(separator: ","))" + (summary.map { ", summary=\($0)" } ?? "")
        case BillingError.decoding(let path): return "\(source) unavailable: decoding path=\(path)"
        case BillingError.insufficientPermissions: return "\(source) unavailable: HTTP 403"
        case BillingError.httpStatus(let status): return "\(source) unavailable: HTTP \(status)"
        default: return "\(source) unavailable: network or invalid response"
        }
    }
    private func subscriptionDiagnostic(_ item: Subscription, source: String) -> String {
        let missing = [("id", item.id == nil), ("state", item.state == nil), ("frequency", item.frequency == nil), ("currency", item.currency == nil), ("current_period_start", item.current_period_start == nil), ("current_period_end", item.current_period_end == nil), ("price", item.price == nil)].filter { $0.1 }.map { $0.0 }
        let invalidDates = [("current_period_start", item.current_period_start != nil && date(item.current_period_start) == nil), ("current_period_end", item.current_period_end != nil && date(item.current_period_end) == nil)].filter { $0.1 }.map { $0.0 }
        let plan = item.rate_plan?.id.map { ["free", "partners_free"].contains($0) ? "free" : "other" } ?? "missing"
        let price = item.price.map { $0 == 0 ? "zero" : "nonzero" } ?? "missing"
        let state = item.state.map { ["Trial", "Provisioned", "Paid", "AwaitingPayment", "Cancelled", "Failed", "Expired"].contains($0) ? $0 : "other" } ?? "missing"
        let frequency = item.frequency.map { ["weekly", "monthly", "quarterly", "yearly", "not-applicable"].contains($0) ? $0 : "other" } ?? "missing"
        return "Incomplete subscription: \(source); missing=\(missing.joined(separator: ",")); invalid_dates=\(invalidDates.joined(separator: ",")); plan=\(plan); price=\(price); state=\(state); frequency=\(frequency); rate_plan_present=\(item.rate_plan != nil); plan_currency_present=\(item.rate_plan?.currency != nil)"
    }
    private func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
    public func fetchSnapshot(account: AccountProfile, token: String, cycle selected: Cycle? = nil, now: Date = Date()) async throws -> BillingSnapshot {
        let base = "/accounts/\(account.id)"
        let info: Envelope<Info> = try await get(base + "/billable-usage/info", token: token)
        guard info.result.covered else { throw BillingError.unsupportedAccount }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let cycles: [Cycle] = Array(Set(info.result.subscriptions.compactMap { anchor -> Cycle? in
            guard let start = date(anchor.start_timestamp), start <= now, (date(anchor.end_timestamp) ?? .distantFuture) > now, let origin = date(anchor.billing_cycle_anchor_timestamp) else { return nil }
            let day = calendar.component(.day, from: origin)
            func boundary(_ month: Date) -> Date? { guard let range = calendar.range(of: .day, in: .month, for: month), let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else { return nil }; return calendar.date(byAdding: .day, value: min(day, range.count) - 1, to: first) }
            guard var from = boundary(now) else { return nil }
            if from > now { guard let first = calendar.date(from: calendar.dateComponents([.year, .month], from: now)), let previous = calendar.date(byAdding: .month, value: -1, to: first), let value = boundary(previous) else { return nil }; from = value }
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: calendar.date(from: calendar.dateComponents([.year, .month], from: from))!), let end = boundary(nextMonth) else { return nil }
            return Cycle(start: from, end: end)
        })).sorted { $0.start < $1.start }
        guard let cycle = selected ?? cycles.last else { throw BillingError.noBillingCycle }
        let fmt = DateFormatter(); fmt.calendar = Calendar(identifier: .gregorian); fmt.timeZone = TimeZone(secondsFromGMT: 0)!; fmt.locale = Locale(identifier: "en_US_POSIX"); fmt.dateFormat = "yyyy-MM-dd"
        let records: Envelope<[Usage]> = try await get(base + "/billable-usage", token: token, query: [.init(name: "from", value: fmt.string(from: cycle.start)), .init(name: "to", value: fmt.string(from: min(cycle.end, now)))])
        var issues: [String] = []
        var all: [(Subscription, String, String)] = []
        do {
            let accountSubscriptions: Envelope<[Subscription]> = try await get(base + "/subscriptions", token: token, diagnostic: true)
            all = accountSubscriptions.result.map { ($0, "Account", "account") }
        } catch BillingError.invalidToken { throw BillingError.invalidToken } catch is CancellationError { throw CancellationError() } catch { issues.append(diagnosticIssue("account subscriptions", error)) }
        var page = 1
        do { repeat {
            let zones: Envelope<[Zone]> = try await get("/zones", token: token, query: [.init(name: "account.id", value: account.id), .init(name: "page", value: String(page)), .init(name: "per_page", value: "50")])
            for zone in zones.result {
                do {
                    let subscription: Envelope<Subscription?> = try await get("/zones/\(zone.id)/subscription", token: token, diagnostic: true)
                    if let value = subscription.result { all.append((value, zone.name, "zone")) }
                } catch BillingError.invalidToken { throw BillingError.invalidToken }
                catch BillingError.requestFailure(let status, let codes, _, _, _, let noActive, _) where status == 404 && codes == [1207] && noActive {
                    // Cloudflare explicitly says this zone has no active subscription.
                } catch is CancellationError { throw CancellationError() } catch { issues.append(diagnosticIssue("zone subscription", error)) }
            }
            guard let totalPages = zones.result_info?.total_pages else { issues.append("Zone pagination unavailable"); break }
            if page >= totalPages { break }; page += 1
        } while true } catch BillingError.invalidToken { throw BillingError.invalidToken } catch is CancellationError { throw CancellationError() } catch { issues.append(diagnosticIssue("zones", error)) }
        var calculationFixed: [FixedSubscription] = []
        var fixedEstimate = false
        let fixed: [FixedSubscription] = all.compactMap { item, name, source in
            // A terminated subscription whose last possible period ended before this
            // cycle cannot contribute, even if other historical fields are missing.
            if let state = item.state, ["Expired", "Cancelled"].contains(state),
               let end = date(info.result.subscriptions.first { $0.id == item.id }?.end_timestamp) ?? date(item.current_period_end), end <= cycle.start { return nil }
            guard let state = item.state else { issues.append(subscriptionDiagnostic(item, source: source)); return nil }
            if state == "Failed" { return nil }
            if state == "Expired" { issues.append("Expired subscription coverage unavailable: \(source)"); return nil }
            guard ["Trial", "Provisioned", "Paid", "AwaitingPayment", "Cancelled", "Expired"].contains(state) else { issues.append("Unknown subscription state: \(source)"); return nil }
            // An explicit zero-priced, non-recurring plan contributes no fixed charge.
            // Missing price or externally managed billing remains unknown.
            if state == "Paid", item.frequency == "not-applicable", item.price == 0,
               item.rate_plan?.externally_managed != true { return nil }
            guard let id = item.id, let currency = item.currency, let start = date(item.current_period_start), let end = date(item.current_period_end) else { issues.append(subscriptionDiagnostic(item, source: source)); return nil }
            if item.price == nil { issues.append(subscriptionDiagnostic(item, source: source)) }
            let original = FixedSubscription(id: id, currency: currency, price: item.price, period: Cycle(start: start, end: end), name: name)
            let anchor = info.result.subscriptions.first { $0.id == id }
            let validStart = date(item.initial_period_start) ?? date(anchor?.start_timestamp)
            let validEnd = date(anchor?.end_timestamp)
            if state == "Cancelled" && validEnd == nil { issues.append("Cancelled subscription end unavailable: \(source)") }
            let clippedStart = max(start, validStart ?? start)
            let clippedEnd = min(end, validEnd ?? end)
            if clippedStart < clippedEnd && end > start {
                let fraction = Decimal(clippedEnd.timeIntervalSince(clippedStart) / end.timeIntervalSince(start))
                calculationFixed.append(FixedSubscription(id: id, currency: currency, price: item.price.map { $0 * fraction }, period: Cycle(start: clippedStart, end: clippedEnd), name: name))
            } else if end <= start { issues.append("Invalid subscription period: \(source)") }
            let needsBefore = cycle.start < start && (validStart == nil || validStart! < start)
            let needsAfter = cycle.end > end && (validEnd == nil || validEnd! > end)
            if needsBefore || needsAfter {
                // Historical/current-period prices are the only prices returned by this endpoint.
                // Never infer a lifetime when the API does not identify its start.
                guard let validStart, let frequency = item.frequency, state != "Cancelled", state != "Expired", validEnd == nil,
                      ["weekly", "monthly", "quarterly", "yearly"].contains(frequency) else {
                    issues.append("Subscription coverage incomplete: \(source)"); return original
                }
                let origin = date(anchor?.billing_cycle_anchor_timestamp) ?? start
                let day = calendar.component(.day, from: origin)
                func shifted(_ reference: Date, _ direction: Int) -> Date? {
                    if frequency == "weekly" { return calendar.date(byAdding: .day, value: 7 * direction, to: reference) }
                    let step = frequency == "yearly" ? 12 : frequency == "quarterly" ? 3 : 1
                    guard let first = calendar.date(from: calendar.dateComponents([.year, .month], from: reference)),
                          let target = calendar.date(byAdding: .month, value: step * direction, to: first),
                          let days = calendar.range(of: .day, in: .month, for: target) else { return nil }
                    let components = calendar.dateComponents([.hour, .minute, .second], from: reference)
                    guard let boundary = calendar.date(byAdding: .day, value: min(day, days.count) - 1, to: target) else { return nil }
                    return calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: components.second ?? 0, of: boundary)
                }
                func add(_ a: Date, _ b: Date) {
                    let lower = max(a, validStart), upper = min(b, validEnd ?? .distantFuture)
                    guard lower < upper, lower < cycle.end, upper > cycle.start else { return }
                    let fraction = Decimal(upper.timeIntervalSince(lower) / b.timeIntervalSince(a))
                    calculationFixed.append(FixedSubscription(id: id, currency: currency, price: item.price.map { $0 * fraction }, period: Cycle(start: lower, end: upper), name: name))
                    fixedEstimate = true
                }
                var left = start, right = end
                for _ in 0..<120 {
                    if left <= cycle.start || left <= validStart { break }
                    guard let prior = shifted(left, -1), prior < left else { issues.append("Cannot calculate subscription recurrence: \(source)"); break }
                    add(prior, left); left = prior
                }
                for _ in 0..<120 {
                    if right >= cycle.end { break }
                    guard let next = shifted(right, 1), next > right else { issues.append("Cannot calculate subscription recurrence: \(source)"); break }
                    add(right, next); right = next
                }
                if left > max(cycle.start, validStart) || right < cycle.end { issues.append("Subscription recurrence limit reached: \(source)") }
            }
            return original
        }
        let nonUsageIssueCount = issues.count
        var usageKeys = Set<String>()
        var dimensions: [String: UsageDimension] = [:]
        var cumulativeCosts: [String: Decimal] = [:]
        var quantities: [String: (consumed: Double?, billable: Double?)] = [:]
        let charges: [UsageCharge] = records.result.enumerated().compactMap { index, item in
            if let billingStart = item.BillingPeriodStart {
                guard let parsed = date(billingStart) else { issues.append("Invalid usage billing period: \(index)"); return nil }
                if parsed != cycle.start { return nil }
            } else { issues.append("Missing usage billing period: \(index)") }
            guard let currency = item.BillingCurrency, let start = date(item.ChargePeriodStart), let end = date(item.ChargePeriodEnd) else { issues.append("Incomplete usage row \(index)"); return nil }
            if item.ContractedCost == nil { issues.append("Missing usage cost: \(index)") }
            let identity = [item.SubscriptionId, item.ZoneId, item.ServiceName, item.ServiceFamilyName, item.ChargeDescription, item.PricingUnit, item.ConsumedUnit, item.BillingCurrency, item.BillingPeriodStart, item.ChargePeriodStart, item.ChargePeriodEnd]
            guard let encodedID = try? JSONEncoder().encode(identity) else { issues.append("Usage identity encoding unavailable"); return nil }
            let id = encodedID.base64EncodedString()
            if !usageKeys.insert(id).inserted { issues.append("Ambiguous duplicate usage dimensions: \(index)") }
            else { dimensions[id] = UsageDimension(item); cumulativeCosts[id] = item.CumulatedContractedCost; quantities[id] = (item.ConsumedQuantity, item.CumulatedPricingQuantity) }
            return UsageCharge(id: id, currency: currency, cost: item.ContractedCost, period: Cycle(start: start, end: end), serviceName: catalog?.product(for: item.ServiceName ?? "")?.name ?? item.ServiceName ?? "")
        }
        let kvRows = records.result.filter { row in
            guard let name = row.ServiceName?.lowercased(), name.contains("kv storage"), let billingStart = date(row.BillingPeriodStart) else { return false }
            return billingStart == cycle.start
        }
        var usageDiagnostics: [UsageSourceDiagnostic] = []
        if !kvRows.isEmpty {
            let groups = Dictionary(grouping: kvRows) { row in
                [row.SubscriptionId, row.ZoneId, row.BillingCurrency, row.ServiceName, row.ServiceFamilyName, row.ChargeDescription, row.PricingUnit, row.ConsumedUnit].map { $0 ?? "" }.joined(separator: "|")
            }
            var comparable = true, differs = false
            for rows in groups.values {
                let ordered = rows.sorted { (date($0.ChargePeriodEnd) ?? .distantPast) < (date($1.ChargePeriodEnd) ?? .distantPast) }
                let ends = ordered.compactMap { date($0.ChargePeriodEnd) }
                guard ends.count == rows.count, Set(ends).count == ends.count, let last = ordered.last,
                      let cumulative = last.CumulatedContractedCost, rows.allSatisfy({ $0.ContractedCost != nil }) else { comparable = false; continue }
                let sum = rows.reduce(Decimal.zero) { $0 + ($1.ContractedCost ?? 0) }
                if sum != cumulative { differs = true }
            }
            let dayStart = calendar.startOfDay(for: now)
            usageDiagnostics.append(UsageSourceDiagnostic(kind: "kv-storage", allCumulativePresent: kvRows.allSatisfy { $0.CumulatedContractedCost != nil }, periodSumDiffersFromLatestCumulative: comparable ? differs : nil, includesCurrentUTCDay: kvRows.contains { row in guard let start = date(row.ChargePeriodStart) else { return false }; return start >= dayStart && start <= now }, hasFuturePeriodEnd: kvRows.contains { row in guard let end = date(row.ChargePeriodEnd) else { return false }; return end > now }))
        }
        var firstByID: [String: UsageCharge] = [:]
        for charge in charges where firstByID[charge.id] == nil { firstByID[charge.id] = charge }
        let dimensionGroups = Dictionary(grouping: firstByID.values.compactMap { charge -> (UsageDimension, UsageCharge)? in dimensions[charge.id].map { ($0, charge) } }, by: { $0.0 })
        var normalized: [UsageCharge] = []
        var sources: [String: String] = [:]
        for (_, pairs) in dimensionGroups {
            let group = pairs.map { $0.1 }.sorted { $0.period.end < $1.period.end }
            let eligibleRows = group.filter { $0.period.start >= cycle.start && $0.period.end <= min(now, cycle.end) && $0.period.end > $0.period.start }
            for (prior, next) in zip(eligibleRows, eligibleRows.dropFirst()) where next.period.start < prior.period.end || next.period.end == prior.period.end { issues.append("Ambiguous overlapping usage periods") }
            if eligibleRows.count != group.count { issues.append("Usage outside observable cycle coverage") }
            guard let latest = eligibleRows.last else { continue }
            let cumulative = cumulativeCosts[latest.id]
            let known = eligibleRows.allSatisfy { $0.cost != nil }
            let amount: Decimal? = cumulative ?? (known ? eligibleRows.reduce(Decimal.zero) { $0 + ($1.cost ?? 0) } : nil)
            let source = cumulative != nil ? "cumulative" : "period-sum"
            let normalizedID = latest.id
            sources[normalizedID] = source
            normalized.append(UsageCharge(id: normalizedID, currency: latest.currency, cost: amount, period: Cycle(start: cycle.start, end: latest.period.end), serviceName: latest.serviceName))
        }
        let groups = Dictionary(grouping: normalized, by: { ProductKey(service: $0.serviceName, currency: $0.currency) })
        let sourceAsOf = normalized.map(\.period.end).min()
        let products: [UsageProductTotal] = groups.map { key, rows in
            let valid = rows.allSatisfy { $0.cost != nil } && issues.count == nonUsageIssueCount
            let sourceSet = Set(rows.compactMap { sources[$0.id] })
            return UsageProductTotal(serviceName: key.service, currency: key.currency, cost: rows.compactMap(\.cost).reduce(Decimal.zero, +), source: sourceSet.count == 1 ? (sourceSet.first ?? "period-sum") : "mixed", isComplete: valid, rawServiceNames: Array(Set(rows.compactMap { dimensions[$0.id]?.service })).sorted())
        }.sorted { ($0.currency, $0.serviceName) < ($1.currency, $1.serviceName) }
        if fixed.isEmpty && charges.isEmpty { issues.append("No currency or charge data available") }
        let rawTotals = BillingCalculator.calculate(cycle: cycle, subscriptions: calculationFixed, usage: normalized, now: sourceAsOf ?? cycle.start, complete: issues.isEmpty)
        let totals = rawTotals.map { total -> CurrencyTotals in
            let relevant = normalized.filter { $0.currency == total.currency }
            var projected: Decimal = 0
            var canForecast = total.isComplete && !relevant.isEmpty && charges.filter { $0.currency == total.currency }.allSatisfy { $0.period.end <= now }
            for charge in relevant {
                let end = charge.period.end
                guard end > cycle.start else { canForecast = false; continue }
                let part = BillingCalculator.calculate(cycle: cycle, subscriptions: [], usage: [charge], now: end).first
                guard let usageForecast = part?.forecastCost, part?.isComplete == true else { canForecast = false; continue }
                projected += usageForecast
            }
            return CurrencyTotals(currency: total.currency, fixedCost: total.fixedCost, usageCost: total.usageCost, forecastCost: canForecast ? total.fixedCost.map { $0 + projected } : nil, isComplete: total.isComplete)
        }
        let trendGroups = Dictionary(grouping: charges.compactMap { charge -> (UsageDimension, UsageCharge)? in dimensions[charge.id].map { ($0, charge) } }, by: { $0.0 })
        let trendInputs = trendGroups.values.map { pairs in
            pairs.map { pair in
                UsageTrendObservation(serviceName: pair.1.serviceName, currency: pair.1.currency, period: pair.1.period, cumulative: cumulativeCosts[pair.1.id])
            }
        }
        let trendResult = UsageTrendBuilder.build(cycle: cycle, now: now, dimensions: trendInputs, products: products, totals: totals, usageComplete: issues.count == nonUsageIssueCount)
        let quantityRows = firstByID.values.compactMap { charge -> UsageQuantityObservation? in
            guard let dimension = dimensions[charge.id] else { return nil }
            return UsageQuantityObservation(dimension: dimension, serviceName: charge.serviceName, currency: charge.currency, period: charge.period, consumed: quantities[charge.id]?.consumed, cumulativeBillable: quantities[charge.id]?.billable, cost: charge.cost)
        }
        let quotas = UsageQuotaBuilder.build(cycle: cycle, now: now, observations: quantityRows, catalog: catalog)
        return BillingSnapshot(accountID: account.id, cycles: cycles, totals: totals, checkedAt: now, isComplete: issues.isEmpty && totals.allSatisfy { $0.total != nil }, subscriptions: fixed, usage: charges, issues: issues, sourceAsOf: sourceAsOf, forecastIsEstimate: true, selectedCycle: cycle, forecastNote: sourceAsOf == nil ? "No observed usage period end is available for forecasting." : (totals.contains { $0.forecastCost == nil } ? "Forecast unavailable for incomplete or unobserved usage." : nil), fixedCostIsEstimate: fixedEstimate, fixedEstimateNote: fixedEstimate ? "Adjacent service periods use the current subscription price; historical or future prices may differ." : nil, usageDiagnostics: usageDiagnostics, usageProductTotals: products, usageTrends: trendResult.products, usageTotalTrends: trendResult.totals, usageQuotas: quotas)
    }
}
