// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `ServerNotificationDeliveryTests` covers the decisions `ServerNotificationDispatcher` makes around posting, which are the parts of acting on a fetch that need no notification centre.
///
/// It exists because these decide whether a stale or overtaken fetch can still reach the badge, which outcomes claim a place in the order of fetches, and when notifications just posted are taken back because their account signed out while they were posted.
///
struct ServerNotificationDeliveryTests {
    ///
    /// `outcomes` is one of every kind of outcome a fetch can have.
    ///
    private static let outcomes: [UnreadNotifications.Outcome] = [.fetched(ServerNotificationFixture.items([1, 2]), account: ServerNotificationFixture.alice), .noAccount, .endpointUnavailable, .credentialsRejected, .cancelled, .unreachable]

    @Test(arguments: outcomes)
    func `An adopted fetch writes its own badge`(outcome: UnreadNotifications.Outcome) {
        #expect(ServerNotificationDispatcher.Delivery.adopted.badgeUpdate(for: outcome) == outcome.badgeUpdate)
    }

    @Test(arguments: [ServerNotificationDispatcher.Delivery.superseded, .notSignedIn, .keychainUnreadable, .abandoned])
    func `A fetch that was not adopted leaves the badge alone`(delivery: ServerNotificationDispatcher.Delivery) {
        for outcome in Self.outcomes {
            #expect(delivery.badgeUpdate(for: outcome) == .unchanged)
        }
    }

    @Test
    func `Each outcome uses its ticket the way what it learned calls for`() {
        #expect(ServerNotificationDispatcher.ticketUse(for: .fetched([], account: ServerNotificationFixture.alice)) == .commit)
        #expect(ServerNotificationDispatcher.ticketUse(for: .noAccount) == .admit)
        #expect(ServerNotificationDispatcher.ticketUse(for: .endpointUnavailable) == .admit)
        #expect(ServerNotificationDispatcher.ticketUse(for: .credentialsRejected) == .admit)
        #expect(ServerNotificationDispatcher.ticketUse(for: .cancelled) == .none)
        #expect(ServerNotificationDispatcher.ticketUse(for: .unreachable) == .none)
    }

    @Test(arguments: [RefreshAdmission.admitted, .anonymous, .signedOut, .signedInAgain, .storeHoldsAnotherAccount, .keychainUnreadable])
    func `Nothing posted is nothing to take back`(admission: RefreshAdmission) {
        #expect(ServerNotificationDispatcher.takesBack(posted: 0, admission: admission) == false)
    }

    @Test(arguments: [RefreshAdmission.anonymous, .signedOut, .signedInAgain, .storeHoldsAnotherAccount])
    func `Notifications posted for an account that signed out meanwhile are taken back`(admission: RefreshAdmission) {
        #expect(ServerNotificationDispatcher.takesBack(posted: 3, admission: admission))
    }

    @Test(arguments: [RefreshAdmission.admitted, .keychainUnreadable])
    func `Notifications posted for an account still signed in, or one the Keychain will not answer for, stay`(admission: RefreshAdmission) {
        #expect(ServerNotificationDispatcher.takesBack(posted: 3, admission: admission) == false)
    }
}
