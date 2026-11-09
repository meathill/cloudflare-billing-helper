import XCTest
@testable import BillingCore

final class KeychainTokenStoreTests: XCTestCase {
    func testRepeatedLoadUsesTheRememberedToken() throws {
        let memory = TokenMemory()
        var reads = 0
        let first = try rememberedToken(accountID: "account", memory: memory) { reads += 1; return "secret" }
        let second = try rememberedToken(accountID: "account", memory: memory) { reads += 1; return "other" }
        XCTAssertEqual(first, "secret")
        XCTAssertEqual(second, "secret")
        XCTAssertEqual(reads, 1)
        memory.set("account", "updated")
        XCTAssertEqual(try rememberedToken(accountID: "account", memory: memory) { reads += 1; return "ignored" }, "updated")
        XCTAssertEqual(reads, 1)
        memory.remove("account")
        XCTAssertEqual(try rememberedToken(accountID: "account", memory: memory) { reads += 1; return "fresh" }, "fresh")
        XCTAssertEqual(reads, 2)
    }

    func testMissingTokenIsNotRemembered() throws {
        let memory = TokenMemory()
        var reads = 0
        XCTAssertNil(try rememberedToken(accountID: "account", memory: memory) { reads += 1; return nil })
        XCTAssertNil(try rememberedToken(accountID: "account", memory: memory) { reads += 1; return nil })
        XCTAssertEqual(reads, 2)
    }

    func testDataProtectionQueryIsSeparateFromLoginKeychain() {
        let protected = billingTokenQuery(accountID: "abc", dataProtection: true)
        let legacy = billingTokenQuery(accountID: "abc", dataProtection: false)
        XCTAssertEqual(protected[kSecUseDataProtectionKeychain as String] as? Bool, true)
        XCTAssertNil(legacy[kSecUseDataProtectionKeychain as String])
        XCTAssertEqual(protected[kSecAttrService as String] as? String, "CloudflareBillingHelper")
        XCTAssertEqual(protected[kSecAttrAccount as String] as? String, "abc")
    }
}
