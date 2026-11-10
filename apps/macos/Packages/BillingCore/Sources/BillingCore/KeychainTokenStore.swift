import Foundation
import LocalAuthentication
import Security

/// 登录钥匙串的「始终允许」绑的是这一次二进制的哈希，重新编译就会失效。
/// 数据保护钥匙串按团队 ID 和 bundle ID 授权，同一个已签名应用再次刷新不再弹窗。
public struct KeychainTokenStore: TokenStore {
    private let memory = TokenMemory()
    public init() {}

    public func save(_ token: String, accountID: String) throws {
        do {
            try storeDataProtected(token, accountID: accountID)
        } catch let error as KeychainError where error.status == errSecMissingEntitlement {
            try write(token, accountID: accountID, dataProtection: false)
        }
        memory.set(accountID, token)
    }

    public func load(accountID: String) throws -> String? {
        try rememberedToken(accountID: accountID, memory: memory) {
            if let token = try read(billingTokenQuery(accountID: accountID, dataProtection: true)) { return token }
            guard let legacy = try read(billingTokenQuery(accountID: accountID, dataProtection: false)) else { return nil }
            try? storeDataProtected(legacy, accountID: accountID)
            return legacy
        }
    }

    public func delete(accountID: String) throws {
        memory.remove(accountID)
        try remove(billingTokenQuery(accountID: accountID, dataProtection: true))
        try remove(billingTokenQuery(accountID: accountID, dataProtection: false))
    }

    /// Writes the data protection item and removes the legacy copy. A sandboxed app's query without
    /// `kSecUseDataProtectionKeychain` can still reach the data protection keychain, so the cleanup may
    /// delete the item just written; verify and write it again in that case.
    private func storeDataProtected(_ token: String, accountID: String) throws {
        let protected = billingTokenQuery(accountID: accountID, dataProtection: true)
        try write(token, accountID: accountID, dataProtection: true)
        deleteQuietly(billingTokenQuery(accountID: accountID, dataProtection: false))
        if (try? read(protected)) != token { try write(token, accountID: accountID, dataProtection: true) }
        guard try read(protected) == token else { throw KeychainError(errSecItemNotFound) }
    }

    private func write(_ token: String, accountID: String, dataProtection: Bool) throws {
        let query = billingTokenQuery(accountID: accountID, dataProtection: dataProtection)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data(token.utf8)] as CFDictionary)
        if status == errSecSuccess { return }
        if status != errSecItemNotFound { throw KeychainError(status) }
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        if dataProtection { item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly }
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError(added) }
    }

    private func read(_ query: [String: Any]) throws -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound || status == errSecMissingEntitlement { return nil }
        guard status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) else { throw KeychainError(status) }
        return token
    }

    private func remove(_ query: [String: Any]) throws {
        let quietStatus = SecItemDelete(silentQuery(query) as CFDictionary)
        if quietStatus == errSecSuccess || quietStatus == errSecItemNotFound || quietStatus == errSecMissingEntitlement { return }
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound { throw KeychainError(status) }
    }

    private func deleteQuietly(_ query: [String: Any]) {
        SecItemDelete(silentQuery(query) as CFDictionary)
    }

    private func silentQuery(_ query: [String: Any]) -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        var quiet = query
        quiet[kSecUseAuthenticationContext as String] = context
        return quiet
    }
}

final class TokenMemory: @unchecked Sendable {
    private var tokens: [String: String] = [:]
    private let lock = NSLock()
    func get(_ id: String) -> String? { lock.lock(); defer { lock.unlock() }; return tokens[id] }
    func set(_ id: String, _ token: String) { lock.lock(); defer { lock.unlock() }; tokens[id] = token }
    func remove(_ id: String) { lock.lock(); defer { lock.unlock() }; tokens.removeValue(forKey: id) }
}

func rememberedToken(accountID: String, memory: TokenMemory, load: () throws -> String?) throws -> String? {
    if let cached = memory.get(accountID) { return cached }
    guard let token = try load() else { return nil }
    memory.set(accountID, token)
    return token
}

func billingTokenQuery(accountID: String, dataProtection: Bool) -> [String: Any] {
    var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "CloudflareBillingHelper",
        kSecAttrAccount as String: accountID
    ]
    if dataProtection { query[kSecUseDataProtectionKeychain as String] = true }
    return query
}
