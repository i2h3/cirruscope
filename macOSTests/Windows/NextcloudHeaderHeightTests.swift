// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
@testable import Cirruscope
import Testing

/// `NextcloudHeaderHeightTests` covers `NextcloudHeaderHeight`, which remembers how tall the connected server draws Nextcloud's header so the window buttons are centered in it rather than in a height the app assumed (issue #102).
@MainActor
struct NextcloudHeaderHeightTests {
    /// `removeStoredHeight(key:)` deletes the `UserDefaults` entry a height is kept under, returning the domain to the state a machine that had never recorded that key would be in.
    private func removeStoredHeight(key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }

    @Test(arguments: [
        // The two heights current servers actually declare: 50 points on Nextcloud 34, 44 on 35.
        (CGFloat(50), true),
        (CGFloat(44), true),
        // Both ends of the range, and the first value outside each.
        (CGFloat(20), true),
        (CGFloat(19), false),
        (CGFloat(120), true),
        (CGFloat(121), false),
        // A header caught collapsed, hidden, or mid-animation reports a height that says nothing about where the buttons belong.
        (CGFloat(0), false),
        (CGFloat(1), false),
        (CGFloat(-44), false),
        // A measurement of something that is not the header the window is laid out against.
        (CGFloat(5000), false),
        // Refused explicitly rather than left to the range comparison, a `nan` comparing false against everything.
        (CGFloat.nan, false),
        (CGFloat.infinity, false),
    ])
    func `A reported height is believed only within the range a real header falls in`(height: CGFloat, isPlausible: Bool) {
        #expect(NextcloudHeaderHeight.isPlausible(height) == isPlausible)
    }

    @Test
    func `A recorded height is read back afterwards`() {
        let key = "NextcloudHeaderHeightTests.RoundTrip"
        removeStoredHeight(key: key)
        defer { removeStoredHeight(key: key) }
        var announcements = 0

        NextcloudHeaderHeight.record(44, key: key, notifyChange: { announcements += 1 })

        #expect(NextcloudHeaderHeight.lastKnown(key: key) == 44)
        #expect(announcements == 1)
    }

    @Test
    func `A fractional height is recorded as whole points`() {
        let key = "NextcloudHeaderHeightTests.Rounding"
        removeStoredHeight(key: key)
        defer { removeStoredHeight(key: key) }

        var announcements = 0

        NextcloudHeaderHeight.record(43.6, key: key, notifyChange: { announcements += 1 })

        #expect(NextcloudHeaderHeight.lastKnown(key: key) == 44)
        #expect(announcements == 1)
    }

    @Test
    func `No height is known while no page has reported one`() {
        let key = "NextcloudHeaderHeightTests.NothingReported"
        removeStoredHeight(key: key)
        defer { removeStoredHeight(key: key) }

        #expect(UserDefaults.standard.object(forKey: key) == nil)
        #expect(NextcloudHeaderHeight.lastKnown(key: key) == nil)
    }

    @Test
    func `An implausible report leaves the height already recorded in place`() {
        let key = "NextcloudHeaderHeightTests.ImplausibleReport"
        removeStoredHeight(key: key)
        defer { removeStoredHeight(key: key) }

        var announcements = 0

        NextcloudHeaderHeight.record(44, key: key, notifyChange: { announcements += 1 })
        NextcloudHeaderHeight.record(0, key: key, notifyChange: { announcements += 1 })

        #expect(NextcloudHeaderHeight.lastKnown(key: key) == 44)
        #expect(announcements == 1, "A report that is not believed changes nothing to announce.")
    }

    /// Every page load reports its header, so most reports repeat the height already recorded, and each one announced would have every open window re-center its buttons for nothing.
    @Test
    func `Only a report that changes the recorded height is announced`() {
        let key = "NextcloudHeaderHeightTests.Announcement"
        removeStoredHeight(key: key)
        defer { removeStoredHeight(key: key) }
        var announcements = 0

        NextcloudHeaderHeight.record(44, key: key, notifyChange: { announcements += 1 })
        NextcloudHeaderHeight.record(44, key: key, notifyChange: { announcements += 1 })
        NextcloudHeaderHeight.record(44.3, key: key, notifyChange: { announcements += 1 })

        #expect(announcements == 1, "A height that rounds to the one recorded is no change.")

        NextcloudHeaderHeight.record(50, key: key, notifyChange: { announcements += 1 })

        #expect(announcements == 2)
        #expect(NextcloudHeaderHeight.lastKnown(key: key) == 50)
    }

    @Test
    func `A stored height outside the believable range is ignored on the way out as well`() {
        let key = "NextcloudHeaderHeightTests.ImplausibleStoredValue"
        removeStoredHeight(key: key)
        defer { removeStoredHeight(key: key) }

        // Written past `record(_:key:notifyChange:)` on purpose: this is the shape of a value left behind by an older build
        // under a wider rule, or by anyone editing the defaults domain by hand, which must not place the buttons
        // somewhere unreachable just because it was stored once.
        UserDefaults.standard.set(5000.0, forKey: key)

        #expect(NextcloudHeaderHeight.lastKnown(key: key) == nil)
    }
}
