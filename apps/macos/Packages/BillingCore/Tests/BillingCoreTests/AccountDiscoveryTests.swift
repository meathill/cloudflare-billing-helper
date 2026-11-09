import XCTest
@testable import BillingCore
private struct DiscoveryMock: BillingTransport {
    let handler: (URLRequest) throws -> (Int, String)
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body) = try handler(request)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
final class AccountDiscoveryTests: XCTestCase {
    private func id(_ n: Int) -> String { String(format: "%032x", n) }
    private func response(items: [(String, String)], page: Int = 1, perPage: Int = 50, total: Int) throws -> String {
        let object: [String: Any] = ["success": true, "result": items.map { ["id": $0.0, "name": $0.1] }, "result_info": ["page": page, "per_page": perPage, "total_count": total, "count": items.count]]
        return String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }
    func testFirstPageAndTokenOnlyInAuthorization() async throws {
        let body = try response(items: [(id(1), "One")], total: 1)
        let mock = DiscoveryMock { request in
            XCTAssertEqual(request.url?.host, "api.cloudflare.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer private-token")
            XCTAssertFalse(request.url!.absoluteString.contains("private-token")); XCTAssertNil(request.httpBody)
            return (200, body)
        }
        let accounts = try await AccountDiscovery(transport: mock).discover(token: "private-token")
        XCTAssertEqual(accounts.map(\.id), [id(1)])
    }
    func testMultiplePagesAndDeduplication() async throws {
        let first = try response(items: (0..<50).map { (id($0), "Account \($0)") }, page: 1, total: 51)
        let second = try response(items: [(id(0), "Duplicate")], page: 2, total: 51)
        let mock = DiscoveryMock { request in
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "page" }!.value!
            return (200, page == "1" ? first : second)
        }
        let accounts = try await AccountDiscovery(transport: mock).discover(token: "secret")
        XCTAssertEqual(accounts.count, 50); XCTAssertEqual(accounts.first?.name, "Account 0")
    }
    func testEmptyInvalidIDAndPagination() async throws {
        let values: [(String, AccountDiscoveryError)] = [
            (try response(items: [], total: 0), .noAccounts),
            (try response(items: [("not-an-id", "A")], total: 1), .invalidResponse),
            (try response(items: [(id(1), "A")], page: 2, total: 1), .invalidResponse),
            (#"{"success":true,"result":[]}"#, .invalidResponse),
            (try response(items: [(id(1), "A")], total: 51), .invalidResponse)
        ]
        for (body, expected) in values {
            do { _ = try await AccountDiscovery(transport: DiscoveryMock { _ in (200, body) }).discover(token: "token"); XCTFail("expected error") }
            catch { XCTAssertEqual(error as? AccountDiscoveryError, expected) }
        }
    }
    func testHTTPAndNetworkErrorsDoNotLeakToken() async throws {
        for (status, expected) in [(401, AccountDiscoveryError.invalidToken), (403, .insufficientPermissions), (500, .httpStatus(500))] {
            do { _ = try await AccountDiscovery(transport: DiscoveryMock { _ in (status, "{}") }).discover(token: "private-token"); XCTFail("expected error") }
            catch { XCTAssertEqual(error as? AccountDiscoveryError, expected); XCTAssertFalse(String(describing: error).contains("private-token")) }
        }
        struct SensitiveError: Error, CustomStringConvertible { var description: String { "private-token" } }
        do { _ = try await AccountDiscovery(transport: DiscoveryMock { _ in throw SensitiveError() }).discover(token: "private-token"); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? AccountDiscoveryError, .networkError); XCTAssertFalse(String(describing: error).contains("private-token")) }
    }
    func testCancellation() async throws {
        let discovery = AccountDiscovery(transport: DiscoveryMock { _ in throw CancellationError() })
        do { _ = try await discovery.discover(token: "token"); XCTFail("expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
