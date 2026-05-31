import Foundation
import Security
import EmbrCore

final class KeychainTokenStore: TokenStoring {
    static let shared = KeychainTokenStore()

    private let service = "com.guitaripod.embr.credentials"
    private let account = "twitch"
    private let queue = DispatchQueue(label: "com.guitaripod.embr.keychain")

    init() {}

    func load() async -> StoredCredentials? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.readSync())
            }
        }
    }

    func save(_ credentials: StoredCredentials) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.writeSync(credentials)
                continuation.resume()
            }
        }
    }

    func clear() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.deleteSync()
                continuation.resume()
            }
        }
    }

    private func readSync() -> StoredCredentials? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                AppLogger.shared.warn("keychain read failed: \(status)", category: .auth)
            }
            return nil
        }
        do {
            return try TwitchJSON.decoder.decode(StoredCredentials.self, from: data)
        } catch {
            AppLogger.shared.error("keychain decode failed: \(error)", category: .auth)
            return nil
        }
    }

    private func writeSync(_ credentials: StoredCredentials) {
        guard let data = try? TwitchJSON.encoder.encode(credentials) else {
            AppLogger.shared.error("keychain encode failed", category: .auth)
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insert = baseQuery()
            insert.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            if addStatus != errSecSuccess {
                AppLogger.shared.error("keychain add failed: \(addStatus)", category: .auth)
            }
        } else if updateStatus != errSecSuccess {
            AppLogger.shared.error("keychain update failed: \(updateStatus)", category: .auth)
        }
    }

    private func deleteSync() {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            AppLogger.shared.warn("keychain delete failed: \(status)", category: .auth)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
