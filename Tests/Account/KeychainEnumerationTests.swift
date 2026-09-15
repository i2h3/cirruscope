// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import Security
import Testing

///
/// `KeychainEnumerationTests` pins the shape of the query `Keychain.accounts()` makes, which is valid on one platform and not on the other.
///
/// macOS's file-based Keychain refuses to return item *data* for more than one match: `kSecReturnData` together with `kSecMatchLimitAll` answers `errSecParam`, whether or not anything matches. iOS has only the data-protection Keychain, which accepts it. `accounts()` was written with that combination and worked for as long as iOS was its only caller; the first macOS caller — the widget extension, which has no store and so must recover its account from the Keychain — got an empty array and reported itself signed out, on a Mac that was signed in.
/// The queries below are made against a service nothing is ever filed under, so nothing is read, written, or deleted. That is what makes the assertion possible at all: a malformed query answers `errSecParam` whether or not it matches anything, while a well-formed one that matches nothing answers `errSecItemNotFound`. The distinction between those two return values is the whole test.
///
struct KeychainEnumerationTests {
    /// `unusedService` is a `kSecAttrService` value no item is filed under, so every query here matches nothing.
    private static let unusedService = "de.i2h3.cirruscope.tests.keychain-enumeration"

    ///
    /// `keychainIsQueryable` is whether this process may ask the Keychain anything at all.
    ///
    /// The project signs ad-hoc by default so that a fresh clone builds with no Apple Developer account — see `DECISIONS.md` → "Why ad-hoc code signing by default?" — and an unsigned iOS build carries no `application-identifier` entitlement. iOS then answers `errSecMissingEntitlement` to every query whatever its shape, which is not a fact about the shape, so there is nothing for these assertions to learn and they are skipped rather than failed. macOS's file-based Keychain asks for no such entitlement and answers normally, which is where the difference this suite exists for can actually be observed.
    ///
    private static let keychainIsQueryable = status(of: [kSecMatchLimit as String: kSecMatchLimitOne]) != errSecMissingEntitlement

    /// `status(of:)` is the result of asking the Keychain for `attributes`, which are added to a query matching nothing.
    private static func status(of attributes: [String: Any]) -> OSStatus {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: unusedService,
        ]

        query.merge(attributes) { _, new in new }

        var result: CFTypeRef?

        return SecItemCopyMatching(query as CFDictionary, &result)
    }

    ///
    /// The query `accounts()` actually makes has to be one the platform accepts. Answering `errSecItemNotFound` is the *success* here: it means the query was understood and simply matched nothing.
    ///
    @Test(.enabled(if: keychainIsQueryable))
    func `Enumerating attributes without data is accepted`() {
        let status = Self.status(of: [
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ])

        #expect(status == errSecItemNotFound)
    }

    ///
    /// This is the combination that was there before, and it is asserted rather than merely avoided so that the reason it cannot come back is written down and checked. On macOS it answers `errSecParam`; on iOS it is accepted, which is exactly why reading the code is not enough to tell the two apart.
    ///
    @Test(.enabled(if: keychainIsQueryable))
    func `Enumerating with data is rejected on macOS and accepted on iOS`() {
        let status = Self.status(of: [
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ])

        #if os(macOS)
            #expect(status == errSecParam)
        #else
            #expect(status == errSecItemNotFound)
        #endif
    }

    ///
    /// Reading one item's data is what `credentials(for:)` does and what `accounts()` now does per item, so it has to be accepted everywhere.
    ///
    @Test(.enabled(if: keychainIsQueryable))
    func `Reading the data of a single item is accepted`() {
        let status = Self.status(of: [
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ])

        #expect(status == errSecItemNotFound)
    }
}
