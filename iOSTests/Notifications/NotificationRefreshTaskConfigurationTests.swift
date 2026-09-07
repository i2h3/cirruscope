// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `NotificationRefreshTaskConfigurationTests` covers the agreement between the identifier the app registers its background refresh under and the property-list entries the system requires for it.
///
/// The suite exists because that agreement is otherwise unverifiable until far too late. `BGTaskScheduler.register` answers whether it accepted an identifier, and SwiftUI's `.backgroundTask(_:)` — which is what performs the registration here — does not pass that answer on, so an identifier the system does not permit is refused in silence at launch. Nothing then fails, nothing is logged by the app, and the symptom months later is "the badge is never current", with no way left to tell a misconfigured build from a scheduler that simply chose not to run the task.
/// It reads the real property list rather than the source of the substitutions, because the substitutions are the part that can go wrong: both entries derive from one build setting so they cannot disagree, and this is what proves that the derivation actually happened. `iOSTests` is hosted by the app, so `Bundle.main` here is the app's own bundle.
/// It is in `iOSTests` rather than `Tests` because both the type and the keys belong to the iOS app alone — `BackgroundTasks` is unavailable on macOS.
///
struct NotificationRefreshTaskConfigurationTests {
    @Test
    func `The identifier the app registers is one the system permits`() throws {
        let permitted = try #require(Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String])

        #expect(permitted.contains(NotificationRefreshTask.identifier))
    }

    @Test
    func `The app declares the background mode an app refresh task needs`() throws {
        let modes = try #require(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])

        #expect(modes.contains("fetch"))
    }

    @Test
    func `The identifier is scoped to this build's own bundle identifier`() throws {
        // The identifier is derived from `CIRRUSCOPE_BASE_BUNDLE_IDENTIFIER`, which is the brandable value a
        // differently-branded build changes. Asserting the prefix rather than the whole string is what lets such a
        // build pass this suite while still catching an identifier left pointing at somebody else's bundle.
        let bundleIdentifier = try #require(Bundle.main.bundleIdentifier)

        #expect(NotificationRefreshTask.identifier.hasPrefix(bundleIdentifier))
    }

    @Test
    func `The task is not asked to start sooner than the system would honour`() {
        // Fifteen minutes is the floor the system applies to an app refresh task regardless of what is asked for, so
        // a shorter interval here would not buy a faster wake-up — it would only make the request read as if it had.
        #expect(NotificationRefreshTask.earliestInterval >= 15 * 60)
    }
}
