import Foundation
import Security
import os

/// Where the GitHub token lives. Only the Keychain: never UserDefaults, never a file, never a log.
protocol VaultTokenStore: AnyObject {
    /// The token, or nil if none is saved (or this process can't reach it).
    func read() -> String?
    /// Saves (replacing any earlier token). Returns where it went.
    @discardableResult
    func save(_ token: String) throws -> VaultTokenLocation
    func delete()
}

/// Where a saved token ended up.
enum VaultTokenLocation: String, Codable {
    /// In the App Group's keychain access group: the widget can read it and fetch on its own.
    case sharedWithWidget
    /// In the app's own keychain group (the signing didn't allow the shared one): the widget shows
    /// the app's last import and never fetches.
    case appOnly

    static let storageKey = "vault_token_location"

    static func load(from defaults: UserDefaults) -> VaultTokenLocation? {
        defaults.string(forKey: storageKey).flatMap(VaultTokenLocation.init(rawValue:))
    }
}

enum VaultTokenError: Error, Equatable {
    case empty
    case keychain(OSStatus)
}

/// The four Security calls the store makes, so the fallback can be tested without a keychain
/// (the unit tests have no host app and no entitlements).
struct KeychainCalls {
    var add: (CFDictionary) -> OSStatus = { SecItemAdd($0, nil) }
    var copy: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>) -> OSStatus = { SecItemCopyMatching($0, $1) }
    var delete: (CFDictionary) -> OSStatus = { SecItemDelete($0) }
}

/// The token as one generic password. It is saved with the App Group identifier (resolved from
/// `ALTAppGroups`, never hardcoded) as its access group: app groups are keychain access groups on
/// iOS, so the widget can read it without a keychain-access-groups entitlement, which SideStore's
/// free-account signing may not carry. If the system refuses that group (`errSecMissingEntitlement`),
/// it falls back to the app's default group and records that the widget can't fetch.
/// Readable after the first unlock (background refresh and the widget run while locked), this
/// device only (never in a backup or iCloud Keychain).
final class KeychainVaultTokenStore: VaultTokenStore {
    static let service = "com.liamratcliffe.StickyNotes.vault"
    static let account = "github-token"

    let accessGroup: String?
    let defaults: UserDefaults
    var calls: KeychainCalls

    init(
        accessGroup: String? = SharedPersistence.appGroupIdentifier,
        defaults: UserDefaults = SharedPersistence.sharedDefaults,
        calls: KeychainCalls = KeychainCalls()
    ) {
        self.accessGroup = accessGroup
        self.defaults = defaults
        self.calls = calls
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    func read() -> String? {
        // No access group in the query: it finds the item in any group this process may read
        // (the app finds either; the widget only finds the shared one).
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = calls.copy(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                AppLogger.vault.error("Token read failed: \(status, privacy: .public)")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func save(_ token: String) throws -> VaultTokenLocation {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VaultTokenError.empty }
        delete()

        var item = baseQuery
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        if let accessGroup {
            var shared = item
            shared[kSecAttrAccessGroup as String] = accessGroup
            let status = calls.add(shared as CFDictionary)
            if status == errSecSuccess {
                record(.sharedWithWidget)
                return .sharedWithWidget
            }
            guard status == errSecMissingEntitlement else {
                AppLogger.vault.error("Token save failed: \(status, privacy: .public)")
                throw VaultTokenError.keychain(status)
            }
            AppLogger.vault.info("Shared keychain group refused; saving for the app only")
        }

        let status = calls.add(item as CFDictionary)
        guard status == errSecSuccess else {
            AppLogger.vault.error("Token save failed: \(status, privacy: .public)")
            throw VaultTokenError.keychain(status)
        }
        record(.appOnly)
        return .appOnly
    }

    func delete() {
        // No access group: removes the item from every group this process can reach.
        let status = calls.delete(baseQuery as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            AppLogger.vault.error("Token delete failed: \(status, privacy: .public)")
        }
        defaults.removeObject(forKey: VaultTokenLocation.storageKey)
    }

    private func record(_ location: VaultTokenLocation) {
        defaults.set(location.rawValue, forKey: VaultTokenLocation.storageKey)
    }
}

#if DEBUG
/// Tests and the screenshot harness: a token in memory, never the real Keychain.
final class InMemoryVaultTokenStore: VaultTokenStore {
    private var token: String?
    var location: VaultTokenLocation = .sharedWithWidget

    init(token: String? = nil) {
        self.token = token
    }

    func read() -> String? { token }

    @discardableResult
    func save(_ token: String) throws -> VaultTokenLocation {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VaultTokenError.empty }
        self.token = trimmed
        return location
    }

    func delete() {
        token = nil
    }
}
#endif
