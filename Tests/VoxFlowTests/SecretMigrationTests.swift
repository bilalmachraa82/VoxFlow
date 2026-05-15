import XCTest
@testable import VoxFlow

final class SecretMigrationTests: XCTestCase {
    func testMigratesLegacyUserDefaultsSecretsIntoSecretStoreAndDeletesLegacyValues() throws {
        let suiteName = "VoxFlow.SecretMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("stt-key", forKey: "vox.openAITranscriptionKey")
        defaults.set("polish-key", forKey: "vox.polishKey")
        let store = InMemorySecretStore()

        SecretMigration.migrateLegacyUserDefaults(defaults: defaults, store: store)

        XCTAssertEqual(store.string(for: .openAITranscriptionKey), "stt-key")
        XCTAssertEqual(store.string(for: .polishKey), "polish-key")
        XCTAssertNil(defaults.string(forKey: "vox.openAITranscriptionKey"))
        XCTAssertNil(defaults.string(forKey: "vox.polishKey"))
    }

    func testDoesNotOverwriteExistingKeychainSecretWithLegacyValue() throws {
        let suiteName = "VoxFlow.SecretMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("legacy-key", forKey: "vox.openAITranscriptionKey")
        let store = InMemorySecretStore()
        store.set("existing-key", for: .openAITranscriptionKey)

        SecretMigration.migrateLegacyUserDefaults(defaults: defaults, store: store)

        XCTAssertEqual(store.string(for: .openAITranscriptionKey), "existing-key")
        XCTAssertNil(defaults.string(forKey: "vox.openAITranscriptionKey"))
    }
}

private final class InMemorySecretStore: SecretStoring {
    private var values: [SecretKey: String] = [:]

    func string(for key: SecretKey) -> String {
        values[key] ?? ""
    }

    func set(_ value: String, for key: SecretKey) {
        values[key] = value
    }

    func delete(_ key: SecretKey) {
        values.removeValue(forKey: key)
    }
}
