// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import Testing

///
/// `UsageDescriptionTests` covers the reasons each app gives the system for what it asks the person's permission to use: the camera and the microphone a call in Nextcloud Talk needs, and the local network a server hosted there is reached through.
///
/// The suite exists because no build step notices a reason going missing, and each one goes missing differently.
/// An app that gives neither the camera nor the microphone reason is given no `navigator.mediaDevices` by WebKit at all, so nobody is ever asked and Talk blames the missing devices on HTTPS; one that gives only one of the two is ended by the system the first time a page asks for the other device.
/// The local network reason is what the system's alert says the first time the app's own requests reach a server on the local network, the web view's traffic being exempt from local network privacy, and without it the alert has no reason of the app's own to give, if it is shown at all.
/// It reads the property list of the app hosting the run, which is each app in turn, the suite being shared, because the reasons are build settings substituted into that list and the substitution is the part that can go wrong.
/// That is also all a run can prove about the local network reason, the Simulator raising no local network alert at all.
///
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
