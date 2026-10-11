import Foundation
import Security
import XCTest

/// The Keychain store's choices, with the Security calls faked (the tests have no host app and no
/// keychain entitlements): the shared App Group access group first, the app's own group if the
/// signing refuses it.
final class VaultTokenStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""
    private var added: [[String: Any]] = []

    override func setUp() {
        let made = StoreTestSupport.makeDefaults()
        defaults = made.defaults
        suiteName = made.name
        added = []
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func store(addResults: [OSStatus]) -> KeychainVaultTokenStore {
        var results = addResults
        var calls = KeychainCalls()
        calls.add = { [unowned self] query in
            self.added.append((query as NSDictionary) as? [String: Any] ?? [:])
            return results.isEmpty ? errSecSuccess : results.removeFirst()
        }
        calls.delete = { _ in errSecItemNotFound }
        calls.copy = { _, _ in errSecItemNotFound }
        return KeychainVaultTokenStore(accessGroup: "group.test.app", defaults: defaults, calls: calls)
    }

    func testSavesToTheSharedGroupFirst() throws {
        let location = try store(addResults: [errSecSuccess]).save("github_pat_abc")
        XCTAssertEqual(location, .sharedWithWidget)
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(added[0][kSecAttrAccessGroup as String] as? String, "group.test.app")
        XCTAssertEqual(added[0][kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertEqual(added[0][kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(VaultTokenLocation.load(from: defaults), .sharedWithWidget)
    }

    func testFallsBackToTheAppsOwnGroupWithoutTheEntitlement() throws {
        let location = try store(addResults: [errSecMissingEntitlement, errSecSuccess]).save("github_pat_abc")
        XCTAssertEqual(location, .appOnly)
        XCTAssertEqual(added.count, 2)
        XCTAssertNil(added[1][kSecAttrAccessGroup as String], "the second try has no access group")
        XCTAssertEqual(VaultTokenLocation.load(from: defaults), .appOnly)
    }

    func testOtherKeychainErrorsAreThrown() {
        XCTAssertThrowsError(try store(addResults: [errSecDuplicateItem]).save("github_pat_abc")) { error in
            XCTAssertEqual(error as? VaultTokenError, .keychain(errSecDuplicateItem))
        }
        XCTAssertThrowsError(try store(addResults: []).save("  \n ")) { error in
            XCTAssertEqual(error as? VaultTokenError, .empty)
        }
    }

    func testTheTokenIsTrimmedAndNeverWrittenToDefaults() throws {
        try store(addResults: []).save("  github_pat_SECRET \n")
        let data = try XCTUnwrap(added.first?[kSecValueData as String] as? Data)
        XCTAssertEqual(String(data: data, encoding: .utf8), "github_pat_SECRET")
        let stored = defaults.dictionaryRepresentation().values.map { "\($0)" }
        XCTAssertFalse(stored.contains { $0.contains("SECRET") })
    }
}
