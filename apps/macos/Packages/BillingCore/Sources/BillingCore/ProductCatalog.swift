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
    public func product(for serviceName: String) -> CatalogProduct? {
        let normalized = serviceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return products.first { $0.name.lowercased() == normalized || $0.key.lowercased() == normalized || ($0.aliases ?? []).contains(where: { normalized.hasPrefix($0.lowercased()) }) }
    }
}
