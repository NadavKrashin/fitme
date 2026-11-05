import Testing
@testable import FitMe

@MainActor
struct SettingsModelTests {
    @Test func savesTrimmedKeyAndShowsOnlyAHint() throws {
        let secrets = InMemorySecretStore()
        let model = SettingsModel(secrets: secrets)
        model.apiKeyDraft = "  sk-ant-secret-1234\n"

        model.saveKey()

        #expect(try secrets.read(.claudeAPIKey) == "sk-ant-secret-1234")
        #expect(model.savedKeyHint == "••••1234")
        #expect(model.apiKeyDraft.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test func blankDraftCannotBeSaved() {
        let model = SettingsModel(secrets: InMemorySecretStore())
        model.apiKeyDraft = "   "
        #expect(!model.canSave)
    }

    @Test func loadsAndRemovesExistingKey() throws {
        let secrets = InMemorySecretStore()
        try secrets.write("sk-ant-abcd", for: .claudeAPIKey)
        let model = SettingsModel(secrets: secrets)
        #expect(model.savedKeyHint == "••••abcd")

        model.removeKey()

        #expect(try secrets.read(.claudeAPIKey) == nil)
        #expect(model.savedKeyHint == nil)
    }

    @Test func surfacesStorageFailures() {
        let model = SettingsModel(secrets: FailingSecretStore())
        #expect(model.errorMessage != nil)
    }
}

private struct FailingSecretStore: SecretStore {
    func read(_: SecretKey) throws -> String? {
        throw KeychainError.unexpectedStatus(-1)
    }

    func write(_: String, for _: SecretKey) throws {
        throw KeychainError.unexpectedStatus(-1)
    }

    func delete(_: SecretKey) throws {
        throw KeychainError.unexpectedStatus(-1)
    }
}
