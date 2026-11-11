// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `KeychainServiceIdentifierTests` pins the one property that makes `Keychain`'s service identifier safe to read from `Info.plist` instead of from the running bundle.
struct KeychainServiceIdentifierTests {
    ///
    /// The service identifier must equal the host app's own bundle identifier, or the switch away from `Bundle.main.bundleIdentifier` silently orphaned every credential stored by a shipped release.
    ///
    @Test
    func `The Keychain service identifier matches the app's bundle identifier`() throws {
        let bundleIdentifier = try #require(Bundle.main.bundleIdentifier)

        #expect(InfoPlist.keychainServiceIdentifier == bundleIdentifier)
    }

    ///
    /// The identifier has to be a usable `kSecAttrService` value, and an empty string is the shape a mistyped or unsubstituted build setting would take: `$(CIRRUSCOPE_BASE_BUNDLE_IDENTIFIER)` resolving to nothing leaves the key present and the value blank, which the accessor's own `guard` cannot catch.
    ///
    @Test
    func `The Keychain service identifier is not empty`() {
        #expect(InfoPlist.keychainServiceIdentifier.isEmpty == false)
    }
}
