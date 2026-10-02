// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import Security
import Testing

///
/// `KeychainEnumerationTests` pins the shape of the queries `Keychain` makes against both of the Keychains a Mac has, because one of them rejects a shape the other accepts.
///
/// macOS's file-based Keychain refuses to return item *data* for more than one match: `kSecReturnData` together with `kSecMatchLimitAll` answers `errSecParam`, whether or not anything matches. The data-protection Keychain — the only one iOS has, and the one `Keychain` now uses on macOS too — accepts it. `accounts()` was once written with that combination and worked for as long as iOS was its only caller; the first macOS caller, the widget extension, got an empty array and reported itself signed out on a Mac that was signed in. The macOS app still enumerates the file-based Keychain at every launch, to move any items left there, so the shape that Keychain accepts still matters.
/// Every case runs once against each Keychain, `kSecUseDataProtectionKeychain` set to `false` addressing the file-based one alone on macOS; on iOS, where the flag has no effect, both runs address the same Keychain.
/// The queries below are made against a service nothing is ever filed under, so nothing is read, written, or deleted. That is what makes the assertion possible at all: a malformed query answers `errSecParam` whether or not it matches anything, while a well-formed one that matches nothing answers `errSecItemNotFound`. The distinction between those two return values is the whole test.
///
struct KeychainEnumerationTests {
    /// `unusedService` is a `kSecAttrService` value no item is filed under, so every query here matches nothing.
    private static let unusedService = "de.i2h3.cirruscope.tests.keychain-enumeration"

    /// `status(of:dataProtection:)` is the result of asking the Keychain for `attributes`, which are added to a query matching nothing, made against the data-protection Keychain when `dataProtection` is set.
    private static func status(of attributes: [String: Any], dataProtection: Bool) -> OSStatus {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: unusedService,
        ]

        // Set to `false` as well rather than left out, which on macOS would search both Keychains at once.
        query[kSecUseDataProtectionKeychain as String] = dataProtection

        query.merge(attributes) { _, new in new }

        var result: CFTypeRef?

        return SecItemCopyMatching(query as CFDictionary, &result)
    }

    ///
    /// The enumeration `accounts()` makes, and the one the move out of the file-based Keychain makes, has to be one each Keychain accepts. Answering `errSecItemNotFound` is the *success* here: it means the query was understood and simply matched nothing.
    ///
    @Test(arguments: [false, true])
    func `Enumerating attributes without data is accepted`(dataProtection: Bool) {
        let status = Self.status(of: [
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ], dataProtection: dataProtection)

        #expect(status == errSecItemNotFound)
    }

    ///
    /// This is the combination that was there before, and it is asserted rather than merely avoided so that the reason it cannot come back is written down and checked. macOS's file-based Keychain answers `errSecParam`; the data-protection Keychain accepts it, which is exactly why reading the code is not enough to tell the two apart.
    ///
    @Test(arguments: [false, true])
    func `Enumerating with data is rejected only by macOS's file-based Keychain`(dataProtection: Bool) {
        let status = Self.status(of: [
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ], dataProtection: dataProtection)

        #if os(macOS)
            #expect(status == (dataProtection ? errSecItemNotFound : errSecParam))
        #else
            #expect(status == errSecItemNotFound)
        #endif
    }

    ///
    /// Reading one item's data is what `credentials(for:)` does, what `accounts()` does per item, and what the move does to each file-based item, so it has to be accepted by both.
    ///
    @Test(arguments: [false, true])
    func `Reading the data of a single item is accepted`(dataProtection: Bool) {
        let status = Self.status(of: [
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ], dataProtection: dataProtection)

        #expect(status == errSecItemNotFound)
    }
}
