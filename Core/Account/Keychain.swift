// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

///
/// `Keychain` stores the `Credentials` obtained from Login Flow v2, keyed by the address of the server they authenticate against.
///
/// Every item lives in the data-protection Keychain, on macOS as on iOS, because that is the Keychain whose access is decided by the Keychain access group rather than by a list of trusted programs on each item. The `keychain-access-groups` entitlement in `Cirruscope.entitlements` puts the apps and the widget extension in the same group, so the extension reads what an app stored without anybody being asked: its own identifier is `…cirruscope.widgets`, and the shared group is what lets it read the apps' items at all.
/// Items are written to the default access group, which is the first one that entitlement names.
/// Releases up to and including `1.1.0` stored their credentials in macOS's file-based Keychain instead, where every program other than the one that created an item is met with a prompt — the widget extension included, and once more after every sign-in. The macOS app moves those items across at launch, and again at every launch until it has succeeded, in `Keychain+FileBasedKeychain.swift`.
///
enum Keychain {
    /// `service` is the constant `kSecAttrService` value under which every credential item is filed, so the items can be enumerated and cleared as a group.
    ///
    /// It comes from `InfoPlist.keychainServiceIdentifier` rather than from `Bundle.main.bundleIdentifier`, because the two agree only inside the apps. In the widget extension the running bundle is `…cirruscope.widgets`, so deriving it from there would file and query under a service nothing was ever written to, and `accounts()` would answer an empty array indistinguishable from a signed-out account. Reading it from the `Info.plist` keeps the value tied to the base bundle identifier — still a single build setting, so a rename still needs no code change — and makes every bundle in the group agree on it.
    static let service: String = InfoPlist.keychainServiceIdentifier

    /// `logger` records Keychain access under the `Keychain` category, at debug level for successful reads, writes, and clears and at error level for failures; it is not `private` so the macOS app's move out of the file-based Keychain logs through it as well.
    static let logger = Logger(for: Keychain.self)

    /// `query(_:)` is a query over the credential items in the data-protection Keychain, with `attributes` added to it.
    ///
    /// Every query this file makes over the data-protection Keychain is built here, so none can leave out `kSecUseDataProtectionKeychain`; the move in `Keychain+FileBasedKeychain.swift` sets the flag to `true` on its own two, and the two queries here addressing the file-based Keychain, in `holdsFileBasedItems(service:)` and `clearAll()`, set it to `false` themselves. On iOS the flag changes nothing, iOS having no other Keychain. On macOS it is what confines a query to the data-protection Keychain: measured in an entitled process, a query without it searches the file-based Keychain as well — and a deletion without it deletes from both — while one setting it to `false` addresses the file-based Keychain alone (see `FileBasedKeychainMoveTests`).
    private static func query(_ attributes: [String: Any] = [:]) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true,
        ]

        query.merge(attributes) { _, new in new }

        return query
    }

    /// `store(_:for:)` persists `credentials` for `server`, replacing any credentials previously stored for the same server.
    ///
    /// It throws `CirruscopeError.keychainFailure` if the Keychain rejects the write.
    static func store(_ credentials: Credentials, for server: URL) throws {
        let data = try JSONEncoder().encode(credentials)
        let item = query([kSecAttrAccount as String: server.absoluteString])

        SecItemDelete(item as CFDictionary)

        var attributes = item
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)

        guard status == errSecSuccess else {
            logger.error("Keychain store failed: OSStatus \(status, privacy: .public)")
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
        let query = query([
            kSecAttrAccount as String: server.absoluteString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ])

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
    /// The enumeration asks for attributes only and reads each item's data separately. The data-protection Keychain would return both in one query, but macOS's file-based Keychain rejects `kSecReturnData` together with `kSecMatchLimitAll` with `errSecParam`, and the move out of that Keychain has to enumerate it this way, so one shape serves both; a second lookup per account costs nothing at the one or two items this holds.
    /// An item whose account attribute is not a parsable URL, or whose data does not decode, is skipped rather than reported: the only way one gets in is a hand-edited Keychain item, and there is nothing useful for a caller to do about it.
    /// A Keychain that cannot be read answers the same empty array as one holding nothing; a caller that has to tell those apart uses `storedAccounts()`.
    static func accounts() -> [ServerAccount] {
        (try? storedAccounts()) ?? []
    }

    /// `storedAccounts()` is `accounts()` for a caller that must not mistake a Keychain it could not read for one holding no credentials.
    ///
    /// It answers an empty array only when the Keychain says there is nothing stored, and throws `CirruscopeError.keychainFailure` with the status for any other refusal, of the enumeration or of reading any one item's data. The widget is one caller that needs the difference, because it forgets the rows it last drew when nobody is signed in, and a read that merely failed must not cost it those rows; `UnreadNotifications` is another, because it clears the app icon badge when nobody is signed in, and `AccountStore.forgetCachesIfSignedOut()` a third, which empties the caches only when nobody is signed in.
    static func storedAccounts() throws -> [ServerAccount] {
        let query = query([
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ])

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            logger.debug("No stored credentials at all")
            return []
        }

        guard status == errSecSuccess else {
            logger.error("Keychain enumeration failed: OSStatus \(status, privacy: .public)")
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

    /// `holdsFileBasedItems(service:)` is whether macOS's file-based Keychain holds any item filed under `service`, which means a credential the app has not moved out of it yet.
    ///
    /// It asks for attributes alone, which the file-based Keychain hands out without consulting the item's list of trusted programs, so the widget extension can ask it without anybody being prompted. That is what lets the extension tell nobody being signed in apart from the app not having moved the credentials yet, and draw the second as its stale state, or its redacted placeholder where no feed was ever saved, rather than as signed out.
    /// The query sets `kSecUseDataProtectionKeychain` to `false` rather than leaving it out, because on macOS a query without it searches both Keychains and would report the data-protection items as well. On iOS, which has only the data-protection Keychain, the flag has no effect and the query finds the very items `storedAccounts()` does, so it is meaningful there only where `storedAccounts()` has just answered that there are none.
    static func holdsFileBasedItems(service: String = service) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: false,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?

        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    /// `clearAll()` removes every credential item the app has stored.
    ///
    /// `AccountStore.disconnect()` calls this when the account is disconnected so that no credentials remain for a server the app no longer talks to.
    /// It also deletes whatever the file-based Keychain still holds under the same service. A credential the macOS app has not moved yet would otherwise be moved on the next launch and sign the account straight back in; on iOS the second deletion addresses the same Keychain as the first and finds nothing left.
    static func clearAll() {
        let dataProtection = SecItemDelete(query() as CFDictionary)

        let fileBased: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: false,
        ]

        let fileBasedDeletion = SecItemDelete(fileBased as CFDictionary)

        // A file-based item that outlives a sign-out is moved back in on the next launch, and keeps the widget on its
        // stale state meanwhile, so a deletion that failed is worth a line in the log.
        for (keychain, status) in [("data-protection", dataProtection), ("file-based", fileBasedDeletion)] where status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Could not clear the \(keychain, privacy: .public) Keychain: OSStatus \(status, privacy: .public)")
        }

        logger.debug("Cleared all stored credentials")
    }
}
