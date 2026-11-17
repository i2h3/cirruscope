// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// Facility to read values from a bundle's own Info.plist file.
struct InfoPlist: InfoPlistReading {
    /// Property list keys.
    private enum Key {
        /// Property list key.
        static let minimumSupportedServerMajorVersion = "MinimumSupportedNextcloudMajorVersion"

        /// Property list key.
        static let applicationName = "ApplicationName"

        /// Property list key.
        static let keychainServiceIdentifier = "KeychainServiceIdentifier"

        /// Property list key.
        static let privacyPolicy = "PrivacyPolicy"

        /// Property list key.
        static let server = "ServerURL"

        /// Property list key.
        static let support = "SupportURL"

        static let appStoreReview = "AppStoreReviewURL"
    }

    @MainActor
    static let shared: any InfoPlistReading = InfoPlist()

    init() {}

    var minimumSupportedServerMajorVersion: Int {
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

    var applicationName: String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: Key.applicationName) else {
            preconditionFailure("Info.plist is missing the \"\(Key.applicationName)\" entry.")
        }

        guard let stringValue = value as? String else {
            preconditionFailure("Info.plist entry \"\(Key.applicationName)\" must be a string but was \(value).")
        }

        return stringValue
    }

    var keychainServiceIdentifier: String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: Key.keychainServiceIdentifier) else {
            preconditionFailure("Info.plist is missing the \"\(Key.keychainServiceIdentifier)\" entry.")
        }

        guard let stringValue = value as? String else {
            preconditionFailure("Info.plist entry \"\(Key.keychainServiceIdentifier)\" must be a string but was \(value).")
        }

        return stringValue
    }

    var privacyPolicy: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: Key.privacyPolicy) else {
            return nil
        }

        guard let stringValue = value as? String else {
            return nil
        }

        guard stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        guard let url = URL(string: stringValue) else {
            preconditionFailure("Info.plist entry \"\(Key.privacyPolicy)\" must be a string representing a valid URL but was \(value).")
        }

        return url
    }

    var server: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: Key.server) else {
            return nil
        }

        guard let stringValue = value as? String else {
            return nil
        }

        guard stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        guard let url = URL(string: stringValue) else {
            preconditionFailure("Info.plist entry \"\(Key.server)\" must be a string representing a valid URL but was \(value).")
        }

        return url
    }

    var support: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: Key.support) else {
            return nil
        }

        guard let stringValue = value as? String else {
            return nil
        }

        guard stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        guard let url = URL(string: stringValue) else {
            preconditionFailure("Info.plist entry \"\(Key.support)\" must be a string representing a valid URL but was \(value).")
        }

        return url
    }

    var appStoreReview: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: Key.appStoreReview) else {
            preconditionFailure("Info.plist is missing the \"\(Key.appStoreReview)\" entry.")
        }

        guard let stringValue = value as? String else {
            preconditionFailure("Info.plist entry \"\(Key.appStoreReview)\" must be a string but was \(value).")
        }

        guard stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        guard let url = URL(string: stringValue) else {
            return nil
        }

        return url
    }
}
