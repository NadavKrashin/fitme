import Foundation
import Observation
import os

/// Manages the Claude API key the user pastes in. The key lives only in the Keychain.
@MainActor
@Observable
final class SettingsModel {
    var apiKeyDraft = ""
    private(set) var savedKeyHint: String?
    private(set) var errorMessage: String?

    private let secrets: any SecretStore

    init(secrets: any SecretStore) {
        self.secrets = secrets
        loadSavedKey()
    }

    var canSave: Bool {
        !apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func saveKey() {
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        perform("save") {
            try secrets.write(key, for: .claudeAPIKey)
            apiKeyDraft = ""
            savedKeyHint = Self.hint(for: key)
        }
    }

    func removeKey() {
        perform("remove") {
            try secrets.delete(.claudeAPIKey)
            savedKeyHint = nil
        }
    }

    private func loadSavedKey() {
        perform("read") {
            savedKeyHint = try secrets.read(.claudeAPIKey).map(Self.hint)
        }
    }

    private func perform(_ action: String, _ body: () throws -> Void) {
        do {
            try body()
            errorMessage = nil
        } catch {
            Logger.settings.error("Couldn't \(action) API key: \(String(describing: error))")
            errorMessage = "Couldn't \(action) the API key. Please try again."
        }
    }

    /// Enough of the key to recognize it, never enough to use it.
    static func hint(for key: String) -> String {
        "••••\(key.suffix(4))"
    }
}
