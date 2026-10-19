// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `UnreadNotificationsBadgeUpdateTests` covers the one decision `UnreadNotifications` makes without a server: what each possible result of a fetch means for the app icon badge.
///
/// The decision lives in one place precisely so that the live monitors and the background job cannot reach different conclusions from the same answer, and this is where that place is held to what it promises. The distinction worth protecting is between a fetch that learned there is nothing to count and one that learned nothing at all: the first must clear the badge, the second must leave it alone, and getting those two the wrong way round is not a crash but a lie — a stale number the user acts on, or a cleared badge that reads as "all read" when the request never left the device.
///
struct UnreadNotificationsBadgeUpdateTests {
    @Test(arguments: [0, 1, 3, 1500])
    func `A fetch that reached the server shows exactly as many as it found`(count: Int) {
        let outcome = UnreadNotifications.Outcome.fetched(ServerNotificationFixture.items((0 ..< count).map { $0 + 1 }), account: ServerNotificationFixture.alice)

        #expect(outcome.badgeUpdate == .set(count))
    }

    @Test
    func `A count past what the Mac would shorten is still shown in full`() {
        // macOS caps its Dock badge at "999+" because that badge is a string it has to keep narrow. iOS is handed an
        // integer and lays it out itself, so there is nothing here to shorten and no cap to match — pinned because the
        // two platforms differing is deliberate rather than an oversight to be "fixed" later.
        let outcome = UnreadNotifications.Outcome.fetched(ServerNotificationFixture.items(Array(1 ... 1000)), account: ServerNotificationFixture.alice)

        #expect(outcome.badgeUpdate == .set(1000))
    }

    @Test(arguments: [UnreadNotifications.Outcome.noAccount, .endpointUnavailable, .credentialsRejected])
    func `An outcome that learned there is nothing to count clears the badge`(outcome: UnreadNotifications.Outcome) {
        #expect(outcome.badgeUpdate == .clear)
    }

    @Test(arguments: [UnreadNotifications.Outcome.cancelled, .unreachable])
    func `An outcome that learned nothing leaves the badge alone`(outcome: UnreadNotifications.Outcome) {
        #expect(outcome.badgeUpdate == .unchanged)
    }

    @Test
    func `Clearing the badge and finding nothing unread are different answers`() {
        // Both end up drawing no badge, and they must still not be one case: `clear` is what an app with no account
        // says, and a server that answers "none queued" is a working server reporting zero. Collapsing them would mean
        // a transient failure could not be told from an empty inbox at the one point that decision is made.
        let outcome = UnreadNotifications.Outcome.fetched([], account: ServerNotificationFixture.alice)

        #expect(outcome.badgeUpdate != .clear)
    }
}
