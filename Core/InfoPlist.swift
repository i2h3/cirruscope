// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// Facility to read values from a bundle's own Info.plist file.
///
enum InfoPlist {
    ///
    /// Property list keys.
    ///
    private enum Key {
        ///
        /// Property list key.
        ///
        static let minimumSupportedServerMajorVersion = "MinimumSupportedNextcloudMajorVersion"

        ///
        /// Property list key.
        ///
        static let applicationName = "ApplicationName"

        ///
        /// Property list key.
        ///
        static let keychainServiceIdentifier = "KeychainServiceIdentifier"

        ///
        /// Property list key.
        ///
        static let privacyPolicy = "PrivacyPolicy"

        ///
        /// Property list key.
        ///
        static let support = "SupportURL"
    }

    ///
    /// The lowest Nextcloud major version the app accepts.
    ///
    static var minimumSupportedServerMajorVersion: Int {
        guard let value = Bundle.main.object(forInfoDictionaryKey: Key.minimumSupportedServerMajorVersion) else {
            preconditionFailure("Info.plist is missing the \"\(Key.minimumSupportedServerMajorVersion)\" entry.")
        }

        if let intValue = value as? Int {
            return intValue
        }

        if let stringValue = value as? String, let intValue = Int(stringValue) {
            return intValue
        }

        preconditionFailure("Info.plist entry \"\(Key.minimumSupportedServerMajorVersion)\" must be an integer or a string representing one but was \(type(of: value)).")
    }

    ///
    /// The name of the application every bundle in this app group belongs to, as presented to a server.
    ///
    /// This is deliberately not `CFBundleName`, which Xcode derives from `PRODUCT_NAME` and therefore reads `Widgets` inside the extension — an explicit `CFBundleName` in the extension's own `Info.plist` does not win, because the generated property list overwrites it. A server administrator reading a session list should see one application, not one entry per bundle that happens to make requests.
    ///
    static var applicationName: String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: Key.applicationName) else {
            preconditionFailure("Info.plist is missing the \"\(Key.applicationName)\" entry.")
        }

        guard let stringValue = value as? String else {
            preconditionFailure("Info.plist entry \"\(Key.applicationName)\" must be a string but was \(value).")
        }

        return stringValue
    }

    ///
    /// The `kSecAttrService` value every Keychain item of this app group is filed under.
    ///
    /// Every bundle in the group — both apps and the widget extension — resolves the same string, which is what lets the extension read what an app wrote. Deriving it from `Bundle.main.bundleIdentifier` instead would give the extension its own identifier and silently match nothing.
    ///
    static var keychainServiceIdentifier: String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: Key.keychainServiceIdentifier) else {
            preconditionFailure("Info.plist is missing the \"\(Key.keychainServiceIdentifier)\" entry.")
        }

        guard let stringValue = value as? String else {
            preconditionFailure("Info.plist entry \"\(Key.keychainServiceIdentifier)\" must be a string but was \(value).")
        }

        return stringValue
    }

    ///
    /// The URL of Cirruscope's online privacy policy.
    ///
    static var privacyPolicy: URL {
        guard let value = Bundle.main.object(forInfoDictionaryKey: Key.privacyPolicy) else {
            preconditionFailure("Info.plist is missing the \"\(Key.privacyPolicy)\" entry.")
        }

        guard let stringValue = value as? String, let url = URL(string: stringValue) else {
            preconditionFailure("Info.plist entry \"\(Key.privacyPolicy)\" must be a string representing a valid URL but was \(value).")
        }

        return url
    }

    ///
    /// The URL of Cirruscope's online support page.
    ///
    static var support: URL {
        guard let value = Bundle.main.object(forInfoDictionaryKey: Key.support) else {
            preconditionFailure("Info.plist is missing the \"\(Key.support)\" entry.")
        }

        guard let stringValue = value as? String, let url = URL(string: stringValue) else {
            preconditionFailure("Info.plist entry \"\(Key.support)\" must be a string representing a valid URL but was \(value).")
        }

        return url
    }
}
