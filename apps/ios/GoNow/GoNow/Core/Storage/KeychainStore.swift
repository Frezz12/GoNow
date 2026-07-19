import Foundation
import Security

protocol TokenStore: Sendable {
    func save(_ tokens: TokenSet) throws
    func read() throws -> TokenSet?
    func delete() throws
}

final class KeychainStore: TokenStore, @unchecked Sendable {
    private let service = "frezzy.GoNow.session"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func save(_ tokens: TokenSet) throws {
        let data = try encoder.encode(tokens)
        try save(data, account: "tokens")
    }

    func read() throws -> TokenSet? {
        guard let data = try read(account: "tokens") else { return nil }
        return try decoder.decode(TokenSet.self, from: data)
    }

    func delete() throws { try delete(account: "tokens") }

    func saveString(_ value: String, account: String) throws { try save(Data(value.utf8), account: account) }
    func readString(account: String) throws -> String? { try read(account: account).flatMap { String(data: $0, encoding: .utf8) } }

    private func save(_ data: Data, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insert = query
            attributes.forEach { insert[$0.key] = $0.value }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if updateStatus != errSecSuccess { throw KeychainError(status: updateStatus) }
    }

    private func read(account: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return data
    }

    private func delete(account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "Не удалось безопасно сохранить данные сессии (код \(status))." }
}
