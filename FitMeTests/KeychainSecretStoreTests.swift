import Foundation
import Testing
@testable import FitMe

struct KeychainSecretStoreTests {
    /// A unique service per run so tests never touch the app's real key.
    let store = KeychainSecretStore(service: "fitme.tests.\(UUID().uuidString)")

    @Test func writeReadReplaceDelete() throws {
        #expect(try store.read(.claudeAPIKey) == nil)

        try store.write("first", for: .claudeAPIKey)
        #expect(try store.read(.claudeAPIKey) == "first")

        try store.write("second", for: .claudeAPIKey)
        #expect(try store.read(.claudeAPIKey) == "second")

        try store.delete(.claudeAPIKey)
        #expect(try store.read(.claudeAPIKey) == nil)
        try store.delete(.claudeAPIKey) // deleting a missing key is not an error
    }
}
