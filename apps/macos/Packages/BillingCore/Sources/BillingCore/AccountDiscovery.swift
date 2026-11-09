import Foundation

public enum AccountDiscoveryError: Error, Equatable {
    case invalidToken, insufficientPermissions, noAccounts, invalidResponse, networkError, httpStatus(Int)
}
private final class DiscoveryRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
/// Never forwards the bearer token to an HTTP redirect target.
public struct AccountDiscoveryTransport: BillingTransport {
    private static let delegate = DiscoveryRedirectBlocker()
    private static let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    public init() {}
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccountDiscoveryError.invalidResponse }
        return (data, http)
    }
}
private struct DiscoveryResponse: Decodable {
    struct Item: Decodable { let id: String; let name: String }
    struct Page: Decodable { let page: Int?; let per_page: Int?; let total_count: Int?; let count: Int?; let total_pages: Int? }
    let success: Bool
    let result: [Item]?
    let result_info: Page?
}
public struct AccountDiscovery {
    private let transport: any BillingTransport
    public init(transport: any BillingTransport = AccountDiscoveryTransport()) { self.transport = transport }
    public func discover(token: String) async throws -> [AccountProfile] {
        guard !token.isEmpty, token == token.trimmingCharacters(in: .whitespacesAndNewlines), !token.contains(where: { $0.isWhitespace || $0.isNewline }) else { throw AccountDiscoveryError.invalidToken }
        var page = 1, expectedTotal: Int?, seen = Set<String>(), result: [AccountProfile] = []
        while true {
            try Task.checkCancellation()
            var url = URLComponents(string: "https://api.cloudflare.com/client/v4/accounts")!
            url.queryItems = [.init(name: "page", value: String(page)), .init(name: "per_page", value: "50")]
            var request = URLRequest(url: url.url!, timeoutInterval: 30)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let data: Data, response: HTTPURLResponse
            do { (data, response) = try await transport.data(for: request) }
            catch is CancellationError { throw CancellationError() }
            catch { if Task.isCancelled { throw CancellationError() }; throw AccountDiscoveryError.networkError }
            if response.statusCode == 401 { throw AccountDiscoveryError.invalidToken }
            if response.statusCode == 403 { throw AccountDiscoveryError.insufficientPermissions }
            guard (200...299).contains(response.statusCode) else { throw AccountDiscoveryError.httpStatus(response.statusCode) }
            guard let envelope = try? JSONDecoder().decode(DiscoveryResponse.self, from: data), envelope.success,
                  let accounts = envelope.result, let info = envelope.result_info, info.page == page,
                  let perPage = info.per_page, (1...50).contains(perPage), let total = info.total_count, total >= 0,
                  accounts.count <= perPage, info.count == nil || info.count == accounts.count,
                  expectedTotal == nil || expectedTotal == total else { throw AccountDiscoveryError.invalidResponse }
            expectedTotal = total
            let totalPages = max(1, total / perPage + (total % perPage == 0 ? 0 : 1))
            guard page <= totalPages, info.total_pages == nil || info.total_pages == totalPages || (total == 0 && info.total_pages == 0),
                  (page == totalPages || accounts.count == perPage), (page != totalPages || accounts.count == total - (page - 1) * perPage) else { throw AccountDiscoveryError.invalidResponse }
            for account in accounts {
                let id = account.id
                guard id.utf8.count == 32, id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }), !account.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AccountDiscoveryError.invalidResponse }
                if seen.insert(id).inserted { result.append(AccountProfile(id: id, name: account.name)) }
            }
            if page == totalPages { break }
            page += 1
        }
        guard !result.isEmpty else { throw AccountDiscoveryError.noAccounts }
        return result
    }
}
