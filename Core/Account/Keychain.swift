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

    /// `credentials(for:)` returns the credentials stored for `server`, or `nil` if none have been stored or the stored value cannot be decoded.
    static func credentials(for server: URL) -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: server.absoluteString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound {
                logger.debug("No stored credentials for \(server)")
            } else {
                logger.error("Keychain read failed: OSStatus \(status)")
            }
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
    /// It exists because the address a credential was filed under is itself the fact a process with no store needs to recover an account: `store(_:for:)` writes it as the item's `kSecAttrAccount`, so an item carries both halves of a `ServerAccount` and reading it back recovers the address without a second place to persist it. `Store.restored()` takes the first one on iOS, and the widget extension takes it on both platforms, having no store at all. The macOS app itself does not use this — `AccountStore` is authoritative there, the Keychain merely follows it, and `credentials(for:)` is the lookup that fits.
    /// **The enumeration asks for attributes only and reads each item's data separately, and must keep doing so.** macOS's file-based Keychain refuses to return item *data* for more than one match: `kSecReturnData` together with `kSecMatchLimitAll` is rejected with `errSecParam`, whether or not anything matches. iOS has only the data-protection Keychain and accepts it, so the combination reads as correct everywhere it was first used and fails on exactly one platform. `kSecUseDataProtectionKeychain` would also make macOS accept it, and is deliberately not set: it selects a different Keychain, so every credential already stored by a shipped release would become invisible and every Mac would silently sign itself out. A second lookup per account costs nothing at the one or two items this holds.
    /// An item whose account attribute is not a parsable URL, or whose data does not decode, is skipped rather than reported: the only way one gets in is a hand-edited Keychain item, and there is nothing useful for a caller to do about it.
    static func accounts() -> [ServerAccount] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            if status == errSecItemNotFound {
                logger.debug("No stored credentials at all")
            } else {
                logger.error("Keychain enumeration failed: OSStatus \(status)")
            }

            return []
        }

        let accounts = items.compactMap { item -> ServerAccount? in
            guard
                let account = item[kSecAttrAccount as String] as? String,
                let server = URL(string: account),
                let credentials = credentials(for: server)
            else {
                logger.error("Skipped a stored credential that could not be read back")
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
