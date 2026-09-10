// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `KeychainServiceIdentifierTests` pins the one property that makes `Keychain`'s service identifier safe to read from `Info.plist` instead of from the running bundle.
///
/// `Keychain` files every credential under `InfoPlist.keychainServiceIdentifier`, which resolves to `$(CIRRUSCOPE_BASE_BUNDLE_IDENTIFIER)`. It used to derive that value from `Bundle.main.bundleIdentifier` instead, and the change is invisible to everybody who already has credentials stored *only* because those two strings are equal inside an app. They are equal by coincidence of two build settings agreeing, not by construction: `PRODUCT_BUNDLE_IDENTIFIER` is separately assigned the same base identifier in `Cirruscope/Cirruscope.xcconfig`. Move one without the other and every stored credential becomes unreachable — the app would not fail to build, would not log anything, and would simply present a signed-out account to somebody who had signed in.
/// This suite runs in both test targets, so it holds the property on iOS as well as macOS. It deliberately asserts nothing about the widget extension, where the two values are *supposed* to differ: that is the entire reason the indirection exists, and no test target is hosted by an app extension to check it from.
///
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
