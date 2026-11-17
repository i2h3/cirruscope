// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// Requirements for a mockable facility to read a bundle's info property list.
protocol InfoPlistReading {
    /// The name of the application every bundle in this app group belongs to, as presented to a server.
    var applicationName: String { get }

    /// The `kSecAttrService` value every Keychain item of this app group is filed under.
    var keychainServiceIdentifier: String { get }

    /// The lowest Nextcloud major version the app accepts.
    var minimumSupportedServerMajorVersion: Int { get }

    /// The URL of Cirruscope's online privacy policy.
    var privacyPolicy: URL? { get }

    /// The pre-defined URL of the server to connect to.
    var server: URL? { get }

    /// The URL of Cirruscope's online support page.
    var support: URL? { get }

    /// The App Store page for writing a review of Cirruscope, which only the apps declare.
    var appStoreReview: URL? { get }
}
