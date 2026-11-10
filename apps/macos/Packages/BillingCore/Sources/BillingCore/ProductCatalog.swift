import Foundation

public struct CatalogProduct: Decodable, Hashable {
    public let key: String
    public let name: String
    public let family: String
    public let aliases: [String]?
    public let unit: String?
    /// Free allowance per billing cycle, in `unit`.
    public let included: Double?
    /// "cumulative" (summed over the cycle) or "gauge" (average level, e.g. storage).
    public let kind: String?
    public let unitPrice: Double?
}
/// Loads the shared billing-spec catalog. Prices in it are descriptive only; billing totals use official API costs.
/// Allowances and prices only feed free-quota projections.
public struct ProductCatalog {
    public let products: [CatalogProduct]
    public init(data: Data) throws { products = try JSONDecoder().decode([CatalogProduct].self, from: data) }
    public init(contentsOf url: URL) throws { try self.init(data: Data(contentsOf: url)) }
    /// Cloudflare service names may carry a trailing allowance note, e.g. "KV List Operations (First 1M is included)".
    public func product(for serviceName: String) -> CatalogProduct? {
        let normalized = serviceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = normalized.replacingOccurrences(of: "\\s*\\([^()]*\\)\\s*$", with: "", options: .regularExpression)
        func matches(_ name: String) -> CatalogProduct? { products.first { $0.name.lowercased() == name || $0.key.lowercased() == name || ($0.aliases ?? []).contains(where: { name.hasPrefix($0.lowercased()) }) } }
        return matches(normalized) ?? (base.isEmpty || base == normalized ? nil : matches(base))
    }
}
