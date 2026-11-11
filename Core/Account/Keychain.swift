// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

/// `Keychain` stores the `Credentials` obtained from Login Flow v2, keyed by the address of the server they authenticate against.
enum Keychain {
    /// `service` is the constant `kSecAttrService` value under which every credential item is filed, so the items can be enumerated and cleared as a group.
    static let service: String = InfoPlist.keychainServiceIdentifier

    /// `logger` records Keychain access under the `Keychain` category, at debug level for successful reads, writes, and clears and at error level for failures; it is not `private` so the macOS app's move out of the file-based Keychain logs through it as well.
    static let logger = Logger(for: Keychain.self)

    /// `query(_:)` is a query over the credential items in the data-protection Keychain, with `attributes` added to it.
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
    static func accounts() -> [ServerAccount] {
        (try? storedAccounts()) ?? []
    }

    /// `storedAccounts()` is `accounts()` for a caller that must not mistake a Keychain it could not read for one holding no credentials.
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
