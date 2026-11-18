// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// To be used in SwiftUI previews and tests.
struct InfoPlistMock: InfoPlistReading {
    let applicationName: String
    let keychainServiceIdentifier: String
    let minimumSupportedServerMajorVersion: Int
    let privacyPolicy: URL?
    let server: URL?
    let support: URL?
    let appStoreReview: URL?

    init(applicationName: String = "Mocked Name", keychainServiceIdentifier: String = "MockedKeychainServiceIdentifier", minimumSupportedServerMajorVersion: Int = 1, privacyPolicy: URL? = nil, server: URL? = nil, support: URL? = nil, appStoreReview: URL? = nil) {
        self.applicationName = applicationName
        self.keychainServiceIdentifier = keychainServiceIdentifier
        self.minimumSupportedServerMajorVersion = minimumSupportedServerMajorVersion
        self.privacyPolicy = privacyPolicy
        self.server = server
        self.support = support
        self.appStoreReview = appStoreReview
    }
}
