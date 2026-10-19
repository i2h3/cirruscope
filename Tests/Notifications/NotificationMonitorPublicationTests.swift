// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `NotificationMonitorPublicationTests` covers which list of notifications the monitor publishes after each kind of fetch, the list the iPhone's account menu counts.
///
/// It exists because the count must follow the same distinction the badge does: an answer from the server replaces the list, an answer that there is nothing to count empties it, and a fetch that learned nothing leaves it exactly as it stood.
///
struct NotificationMonitorPublicationTests {
    ///
    /// `current` is the list published before each case's fetch.
    ///
    private static let current = ServerNotificationFixture.items([1, 2])

    @Test
    func `An answer from the server replaces the list`() {
        let fetched = ServerNotificationFixture.items([2, 3, 4])

        #expect(NotificationMonitor.published(after: .fetched(fetched, account: ServerNotificationFixture.alice), current: Self.current) == fetched)
    }

    @Test(arguments: [UnreadNotifications.Outcome.noAccount, .endpointUnavailable, .credentialsRejected])
    func `An answer that there is nothing to count empties the list`(outcome: UnreadNotifications.Outcome) {
        #expect(NotificationMonitor.published(after: outcome, current: Self.current).isEmpty)
    }

    @Test(arguments: [UnreadNotifications.Outcome.cancelled, .unreachable])
    func `A fetch that learned nothing keeps the list`(outcome: UnreadNotifications.Outcome) {
        #expect(NotificationMonitor.published(after: outcome, current: Self.current) == Self.current)
    }
}
