// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import Testing

/// `UsageDescriptionTests` covers the reasons each app gives the system for what it asks the person's permission to use: the camera and the microphone a call in Nextcloud Talk needs, and the local network a server hosted there is reached through.
///
/// The suite exists because nothing else notices a reason going missing. WebKit refuses a page's request for a device the app has declared no reason to use before anyone is asked, so the only symptom is a call without picture or sound, and the iOS app was built exactly that way until the camera and microphone reasons were added to it, and without the local network one until later still.
/// It reads the property list of the app hosting the run, which is each app in turn, the suite being shared, because the reasons are build settings substituted into that list and the substitution is the part that can go wrong.
struct UsageDescriptionTests {
    @Test(arguments: ["NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSLocalNetworkUsageDescription"])
    func `The app gives the system a reason for what it asks to use`(key: String) throws {
        let reason = try #require(Bundle.main.object(forInfoDictionaryKey: key) as? String)

        #expect(reason.isEmpty == false)
    }
}
