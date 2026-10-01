// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

///
/// `Keychain` stores the `Credentials` obtained from Login Flow v2, keyed by the address of the server they authenticate against.
///
/// Items use the default Keychain access group, which the `keychain-access-groups` entitlement in `Cirruscope.entitlements` sets to the base bundle identifier for every bundle that carries it. Two apps alone would need no entitlement at all — the default group is each app's own — but the widget extension does: its own identifier is `…cirruscope.widgets`, and that entitlement is what puts its items in the same group as the apps'.
///
enum Keychain {
    /// `service` is the constant `kSecAttrService` value under which every credential item is filed, so the items can be enumerated and cleared as a group.
    ///
    /// It comes from `InfoPlist.keychainServiceIdentifier` rather than from `Bundle.main.bundleIdentifier`, because the two agree only inside the apps. In the widget extension the running bundle is `…cirruscope.widgets`, so deriving it from there would file and query under a service nothing was ever written to, and `accounts()` would answer an empty array indistinguishable from a signed-out account. Reading it from the `Info.plist` keeps the value tied to the base bundle identifier — still a single build setting, so a rename still needs no code change — and makes every bundle in the group agree on it.
    private static let service: String = InfoPlist.keychainServiceIdentifier

    /// `logger` records Keychain access under the `Keychain` category, at debug level for successful reads, writes, and clears and at error level for failures.
    private static let logger = Logger(for: Keychain.self)

    /// `store(_:for:)` persists `credentials` for `server`, replacing any credentials previously stored for the same server.
    ///
    /// It throws `CirruscopeError.keychainFailure` if the Keychain rejects the write.
    static func store(_ credentials: Credentials, for server: URL) throws {
        let data = try JSONEncoder().encode(credentials)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: server.absoluteString,
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)

        guard status == errSecSuccess else {
            logger.error("Keychain store failed: OSStatus \(status)")
            throw CirruscopeError.keychainFailure(status)
        }

        logger.debug("Stored credentials for \(server)")
    }

    /// `credentials(for:)` returns the credentials stored for `server`, or `nil` if none have been stored, the stored value cannot be decoded, or the Keychain refuses the read; a caller that has to tell those apart uses `storedCredentials(for:)`.
    static func credentials(for server: URL) -> Credentials? {
        (try? storedCredentials(for: server)) ?? nil
    }

    /// `storedCredentials(for:)` is `credentials(for:)` for a caller that must not mistake a Keychain it could not read for one holding nothing for `server`.
    ///
    /// It answers `nil` when the Keychain holds no item for `server` or the item's data does not decode, neither of which reading again would change, and throws `CirruscopeError.keychainFailure` with the status for any other refusal, such as a locked Keychain or an access check failing for a moment.
    static func storedCredentials(for server: URL) throws -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: server.absoluteString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            logger.debug("No stored credentials for \(server)")
            return nil
        }

        guard status == errSecSuccess else {
            logger.error("Keychain read failed: OSStatus \(status, privacy: .public)")
            throw CirruscopeError.keychainFailure(status)
        }

        guard let data = result as? Data else {
            logger.error("Keychain read succeeded but returned no data")
            return nil
        }

        guard let credentials = try? JSONDecoder().decode(Credentials.self, from: data) else {
            logger.error("Stored credentials could not be decoded")
            return nil
        }

        logger.debug("Retrieved stored credentials for \(server)")
        return credentials
    }

    /// `accounts()` returns every server the app currently holds credentials for, paired with those credentials; in no particular order, the Keychain imposing none.
    ///
    /// It exists because the address a credential was filed under is itself the fact a process with no store needs to recover an account: `store(_:for:)` writes it as the item's `kSecAttrAccount`, so an item carries both halves of a `ServerAccount` and reading it back recovers the address without a second place to persist it. `Store.restored()` takes the first one on iOS, and the widget extension takes it on both platforms, having no store at all. The macOS app uses it only to repair a store that has lost its account — `AccountStore` is authoritative there, the Keychain merely follows it, and `credentials(for:)` is the lookup that fits otherwise.
    /// **The enumeration asks for attributes only and reads each item's data separately, and must keep doing so.** macOS's file-based Keychain refuses to return item *data* for more than one match: `kSecReturnData` together with `kSecMatchLimitAll` is rejected with `errSecParam`, whether or not anything matches. iOS has only the data-protection Keychain and accepts it, so the combination reads as correct everywhere it was first used and fails on exactly one platform. `kSecUseDataProtectionKeychain` would also make macOS accept it, and is deliberately not set: it selects a different Keychain, so every credential already stored by a shipped release would become invisible and every Mac would silently sign itself out. A second lookup per account costs nothing at the one or two items this holds.
    /// An item whose account attribute is not a parsable URL, or whose data does not decode, is skipped rather than reported: the only way one gets in is a hand-edited Keychain item, and there is nothing useful for a caller to do about it.
    /// A Keychain that cannot be read answers the same empty array as one holding nothing; a caller that has to tell those apart uses `storedAccounts()`.
    static func accounts() -> [ServerAccount] {
        (try? storedAccounts()) ?? []
    }

    /// `storedAccounts()` is `accounts()` for a caller that must not mistake a Keychain it could not read for one holding no credentials.
    ///
    /// It answers an empty array only when the Keychain says there is nothing stored, and throws `CirruscopeError.keychainFailure` with the status for any other refusal, of the enumeration or of reading any one item's data. The widget is one caller that needs the difference, because it forgets the rows it last drew when nobody is signed in, and a read that merely failed must not cost it those rows; `AccountStore.forgetCachesIfSignedOut()` is the other, which empties the caches only when nobody is signed in.
    static func storedAccounts() throws -> [ServerAccount] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            logger.debug("No stored credentials at all")
            return []
        }

        guard status == errSecSuccess else {
            logger.error("Keychain enumeration failed: OSStatus \(status)")
            throw CirruscopeError.keychainFailure(status)
        }

        guard let items = result as? [[String: Any]] else {
            logger.error("Keychain enumeration succeeded but returned no list of items")
            throw CirruscopeError.keychainFailure(status)
        }

        let accounts = try items.compactMap { item -> ServerAccount? in
            guard let account = item[kSecAttrAccount as String] as? String else {
                logger.error("Skipped a stored credential with no account attribute")
                return nil
            }

            guard let server = URL(string: account) else {
                logger.error("Skipped a stored credential whose account attribute is not an address")
                return nil
            }

            // A refused read throws out of the enumeration rather than skipping the item, because an item that is
            // there but unreadable is not the same answer as no item at all.
            guard let credentials = try storedCredentials(for: server) else {
                logger.error("Skipped a stored credential that could not be decoded")
                return nil
            }

            return ServerAccount(server: server, credentials: credentials)
        }

        logger.debug("Found stored credentials for \(accounts.count) server(s)")

        return accounts
    }

    /// `clearAll()` removes every credential item the app has stored.
    ///
    /// `AccountStore.disconnect()` calls this when the account is disconnected so that no credentials remain for a server the app no longer talks to.
    static func clearAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]

        SecItemDelete(query as CFDictionary)
        logger.debug("Cleared all stored credentials")
    }
}
