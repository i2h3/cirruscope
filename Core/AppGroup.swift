// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// `AppGroup` resolves the shared App Group container declared in `Cirruscope.entitlements`.
///
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

    /// `containerURL` is the on-disk location of the shared App Group container, which every bundle of the app reaches and which is required rather than optional.
    ///
    /// The apps and the widget extension share their data through it — the store, the cached assets and the widget's last good feed — so a build that is not entitled to it is not a working build of the app, and there is deliberately no location private to one bundle to fall back on. Every target that carries `Cirruscope.entitlements` is signed with it by the checked-in configuration (see AGENTS.md → Building and Signing), so reaching this trap means that configuration was overridden.
    ///
    /// Only iOS reports a missing entitlement here. macOS answers a URL of the expected form even for a build that is not entitled, and the sandbox then refuses whatever is opened under it, which is where such a build stops instead: `AppDatabase.container` traps once the store cannot be opened. The widget extension opens no store, so on macOS an unentitled one does not stop at all: `AssetCache` logs a fault and `ActivityFeedStore` writes nothing.
    static let containerURL: URL = {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            preconditionFailure("This build is not entitled to the App Group \"\(identifier)\"; every build must be signed with Cirruscope.entitlements, see AGENTS.md → Building and Signing.")
        }

        return url
    }()
}
