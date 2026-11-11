// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `NotificationRefreshTaskConfigurationTests` covers the agreement between the identifier the app registers its background refresh under and the property-list entries the system requires for it.
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
