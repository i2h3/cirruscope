// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

extension Keychain {
    /// `moveFileBasedItems(service:)` moves every credential macOS's file-based Keychain holds under `service` into the data-protection Keychain, and answers how many it copied across.
    @discardableResult
    static func moveFileBasedItems(service: String = Keychain.service) -> Int {
        // `false` rather than left out: in an entitled process a query without the flag searches the data-protection
        // Keychain as well, so deleting "the file-based copy" without it would delete the copy just made.
        let fileBased: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: false,
        ]

        var enumeration = fileBased
        enumeration[kSecReturnAttributes as String] = true
        enumeration[kSecMatchLimit as String] = kSecMatchLimitAll

        var result: CFTypeRef?
        let status = SecItemCopyMatching(enumeration as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            logger.debug("No credential in the file-based Keychain; nothing to move")
            return 0
        }

        guard status == errSecSuccess else {
            logger.error("Could not enumerate the file-based Keychain to move its credentials: OSStatus \(status, privacy: .public)")
            return 0
        }

        guard let items = result as? [[String: Any]] else {
            logger.error("Enumerating the file-based Keychain succeeded but returned no list of items")
            return 0
        }

        logger.notice("Found \(items.count, privacy: .public) credential(s) in the file-based Keychain; moving them into the data-protection Keychain")

        let dataProtectionCredentials: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true,
        ]

        let dataProtectionHoldsCredential = SecItemCopyMatching(dataProtectionCredentials as CFDictionary, nil) == errSecSuccess
        var moved = 0

        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String else {
                logger.error("Skipped a file-based credential with no account attribute")
                continue
            }

            var fileBasedItem = fileBased
            fileBasedItem[kSecAttrAccount as String] = account

            guard dataProtectionHoldsCredential == false else {
                let deletion = SecItemDelete(fileBasedItem as CFDictionary)
                logger.notice("The data-protection Keychain already holds a credential; removed the file-based one instead of moving it, OSStatus \(deletion, privacy: .public)")
                continue
            }

            var dataProtectionItem = dataProtectionCredentials
            dataProtectionItem[kSecAttrAccount as String] = account

            var read = fileBasedItem
            read[kSecReturnData as String] = true
            read[kSecMatchLimit as String] = kSecMatchLimitOne

            var data: CFTypeRef?
            let readStatus = SecItemCopyMatching(read as CFDictionary, &data)

            guard readStatus == errSecSuccess else {
                logger.error("Could not read a file-based credential to move it; leaving it for the next launch: OSStatus \(readStatus, privacy: .public)")
                continue
            }

            guard let data = data as? Data else {
                logger.error("Reading a file-based credential succeeded but returned no data; leaving it for the next launch")
                continue
            }

            var addition = dataProtectionItem
            addition[kSecValueData as String] = data
            addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

            let addStatus = SecItemAdd(addition as CFDictionary, nil)

            guard addStatus == errSecSuccess else {
                logger.error("Could not write a credential into the data-protection Keychain; leaving the file-based one for the next launch: OSStatus \(addStatus, privacy: .public)")
                continue
            }

            moved += 1

            let deletion = SecItemDelete(fileBasedItem as CFDictionary)

            guard deletion == errSecSuccess else {
                logger.error("Copied a credential into the data-protection Keychain but could not remove the file-based one, which the next launch removes: OSStatus \(deletion, privacy: .public)")
                continue
            }

            logger.notice("Moved a credential into the data-protection Keychain")
        }

        logger.notice("Moved \(moved, privacy: .public) of \(items.count, privacy: .public) credential(s) from the file-based Keychain into the data-protection Keychain")

        return moved
    }
}
