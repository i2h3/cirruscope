// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import Security

/// `KeychainScratchService` gives one test case a Keychain service of its own, in both the file-based and the data-protection Keychain, and deletes everything filed under it from both when the case ends.
///
/// It exists because the move out of the file-based Keychain can only be exercised with real items, and real items must never be the developer's own: the app files its credentials under `Keychain.service`, and a case that wrote or deleted under that would be signing them out. A service named for the case is one nothing else ever touches, so what a case writes here can only be what the case itself reads back.
final class KeychainScratchService {
    /// `service` is the `kSecAttrService` value this case files its items under, unique to the instance.
    let service = "de.i2h3.cirruscope.tests.keychain-move.\(UUID().uuidString)"

    /// `account` is the `kSecAttrAccount` value a case files its item under when it names no other, shaped like the server address the app uses.
    let account = "https://cloud.example.com"

    deinit {
        for dataProtection in [false, true] {
            var query = itemQuery(dataProtection: dataProtection)
            query.removeValue(forKey: kSecAttrAccount as String)
            SecItemDelete(query as CFDictionary)
        }
    }

    /// `unflaggedValue()` is the item's data as a query that leaves `kSecUseDataProtectionKeychain` out finds it, or `nil` when it finds none.
    func unflaggedValue() -> String? {
        var query = itemQuery(dataProtection: false)
        query.removeValue(forKey: kSecUseDataProtectionKeychain as String)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?

        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(decoding: data, as: UTF8.self)
    }

    /// `unflaggedDelete()` deletes the item with a query that leaves `kSecUseDataProtectionKeychain` out, answering the status the Keychain gave.
    @discardableResult
    func unflaggedDelete() -> OSStatus {
        var query = itemQuery(dataProtection: false)
        query.removeValue(forKey: kSecUseDataProtectionKeychain as String)

        return SecItemDelete(query as CFDictionary)
    }

    /// `itemQuery(dataProtection:account:)` addresses the item filed under `account`, or under `self.account` when none is given, in the data-protection Keychain when `dataProtection` is set, and in the file-based one alone otherwise.
    func itemQuery(dataProtection: Bool, account: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account ?? self.account,
        ]

        // Always set, to `false` as well: a query that leaves the flag out searches both Keychains.
        query[kSecUseDataProtectionKeychain as String] = dataProtection

        return query
    }

    /// `add(_:dataProtection:account:)` files `value` as the data of the item under `account` in the chosen Keychain, answering the status the Keychain gave.
    @discardableResult
    func add(_ value: String, dataProtection: Bool, account: String? = nil) -> OSStatus {
        var attributes = itemQuery(dataProtection: dataProtection, account: account)
        attributes[kSecValueData as String] = Data(value.utf8)

        return SecItemAdd(attributes as CFDictionary, nil)
    }

    /// `value(dataProtection:account:)` is the data of the item under `account` in the chosen Keychain as text, or `nil` when that Keychain holds no such item.
    func value(dataProtection: Bool, account: String? = nil) -> String? {
        var query = itemQuery(dataProtection: dataProtection, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?

        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(decoding: data, as: UTF8.self)
    }

    /// `delete(dataProtection:)` deletes the item from the chosen Keychain, answering the status the Keychain gave.
    @discardableResult
    func delete(dataProtection: Bool) -> OSStatus {
        SecItemDelete(itemQuery(dataProtection: dataProtection) as CFDictionary)
    }
}
