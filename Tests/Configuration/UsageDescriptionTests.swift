// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import Testing

/// `UsageDescriptionTests` covers the reasons each app gives the system for what it asks the person's permission to use: the camera and the microphone a call in Nextcloud Talk needs, and the local network a server hosted there is reached through.
struct UsageDescriptionTests {
    ///
    /// Each reason must be present and non-empty, an unsubstituted or misspelled build setting leaving the key out of the property list or its value blank.
    ///
    @Test(arguments: ["NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSLocalNetworkUsageDescription"])
    func `The app gives the system a reason for what it asks to use`(key: String) throws {
        let reason = try #require(Bundle.main.object(forInfoDictionaryKey: key) as? String)

        #expect(reason.isEmpty == false)
    }
}
