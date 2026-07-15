// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `AppGroup` resolves the shared App Group container declared in `Cirruscope.entitlements`, so `AssetCache` and `Settings` can persist assets and preferences somewhere a future app extension could also reach.
///
/// No extension target exists yet. Whoever adds one should add this file to it rather than re-deriving the identifier.
enum AppGroup {
    /// `InfoPlistKey` collects the string keys under which `AppGroup` reads statically configured values from the app's `Info.plist`.
    private enum InfoPlistKey {
        /// `identifier` is the key for the `Info.plist` entry that backs `AppGroup.identifier`.
        static let identifier = "AppGroupIdentifier"
    }

    /// `identifier` is the App Group identifier declared in `Cirruscope.entitlements`, read from `Info.plist` rather than hardcoded: the underlying bundle identifier — and therefore this App Group identifier, which is derived from it — is a brandable/customizable value that varies for differently-branded builds of this app.
    static var identifier: String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: InfoPlistKey.identifier) else {
            preconditionFailure("Info.plist is missing the \"\(InfoPlistKey.identifier)\" entry.")
        }

        guard let stringValue = value as? String else {
            preconditionFailure("Info.plist entry \"\(InfoPlistKey.identifier)\" must be a string but was \(value).")
        }

        return stringValue
    }

    /// `containerURL` is the on-disk location of the shared App Group container.
    ///
    /// Every build of this app is expected to carry a valid App Group entitlement matching `identifier`, so a failure to resolve it indicates a genuine provisioning/signing problem, not a legitimate degraded state to silently tolerate.
    static let containerURL: URL = {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            preconditionFailure("Could not resolve the App Group container for \"\(identifier)\". Check that the App Groups capability is registered and the entitlement matches.")
        }

        return url
    }()
}
