// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import Testing

/// `MediaCaptureUsageDescriptionTests` covers the reasons each app gives the system for using the camera and the microphone, which a call in Nextcloud Talk cannot start without.
///
/// The suite exists because nothing else notices their absence: WebKit refuses a page's request for a device the app has declared no reason to use before anyone is asked, so the only symptom is a call without picture or sound, and the iOS app was built exactly that way until these were added to it.
/// It reads the property list of the app hosting the run, which is each app in turn, the suite being shared, because the reasons are build settings substituted into that list and the substitution is the part that can go wrong.
struct MediaCaptureUsageDescriptionTests {
    @Test(arguments: ["NSCameraUsageDescription", "NSMicrophoneUsageDescription"])
    func `The app gives the system a reason to use the device`(key: String) throws {
        let reason = try #require(Bundle.main.object(forInfoDictionaryKey: key) as? String)

        #expect(reason.isEmpty == false)
    }
}
