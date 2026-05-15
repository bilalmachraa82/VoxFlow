import Foundation
import Security

enum SecretKey: String, CaseIterable {
    case openAITranscriptionKey = "vox.openAITranscriptionKey"
    case polishKey = "vox.polishKey"

    var account: String { rawValue }
    var legacyDefaultsKey: String { rawValue }
}

protocol SecretStoring: AnyObject {
    func string(for key: SecretKey) -> String
    func set(_ value: String, for key: SecretKey)
    func delete(_ key: SecretKey)
}

final class KeychainSecretStore: SecretStoring {
    private let service: String

    init(service: String = "com.bilal.voxflow") {
        self.service = service
    }

    func string(for key: SecretKey) -> String {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return value
    }

    func set(_ value: String, for key: SecretKey) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            delete(key)
            return
        }

        let data = Data(trimmed.utf8)
        let query = baseQuery(for: key)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    func delete(_ key: SecretKey) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    private func baseQuery(for key: SecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.account
        ]
    }
}

enum SecretMigration {
    static func migrateLegacyUserDefaults(
        defaults: UserDefaults = .standard,
        store: SecretStoring
    ) {
        for key in SecretKey.allCases {
            guard let legacyValue = defaults.string(forKey: key.legacyDefaultsKey),
                  !legacyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                continue
            }

            if store.string(for: key).isEmpty {
                store.set(legacyValue, for: key)
            }
            defaults.removeObject(forKey: key.legacyDefaultsKey)
        }
    }
}
