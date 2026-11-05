import Foundation
import os
import Security

enum SecretKey: String, CaseIterable, Sendable {
    case claudeAPIKey = "claude-api-key"
}

/// Storage for secrets the user enters at runtime (never compiled into the app).
protocol SecretStore: Sendable {
    func read(_ key: SecretKey) throws -> String?
    func write(_ value: String, for key: SecretKey) throws
    func delete(_ key: SecretKey) throws
}

enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case undecodableValue
}

/// Generic-password Keychain items, readable only while the device is unlocked and never synced off-device.
struct KeychainSecretStore: SecretStore {
    let service: String

    func read(_ key: SecretKey) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.undecodableValue
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func write(_ value: String, for key: SecretKey) throws {
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery(for: key) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else { throw KeychainError.unexpectedStatus(updateStatus) }

        var attributes = baseQuery(for: key)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
    }

    func delete(_ key: SecretKey) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for key: SecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }
}

/// For previews and tests.
final class InMemorySecretStore: SecretStore {
    private let values = OSAllocatedUnfairLock(initialState: [SecretKey: String]())

    func read(_ key: SecretKey) throws -> String? {
        values.withLock { $0[key] }
    }

    func write(_ value: String, for key: SecretKey) throws {
        values.withLock { $0[key] = value }
    }

    func delete(_ key: SecretKey) throws {
        values.withLock { $0[key] = nil }
    }
}
