// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import os

/// `NextcloudHeaderHeight` remembers how tall the connected server draws its header, so `WebWindow` can center the standard window buttons inside a bar the server sizes rather than inside a height the app assumed.
///
/// The height used to be a constant, and it was Nextcloud server 34's: that release declared `$header-height: 50px`, server 35 declares `44px`, and the traffic lights consequently sat visibly low on 35 (issue #102). There is no version to key a table off either — a theme may override the property, and it may be declared in a unit that grows with the browser's text size — so the height is measured where it is true and reported back: `macOS/Scripts/HeaderHeight.js` measures Nextcloud's own `#header` on every page load and whenever it is resized, and `WebViewController` records what it reports here.
///
/// The value is kept in `UserDefaults.standard`, the same domain and for the same reasons as `WebWindowFrame`'s remembered window size (see DECISIONS.md → "Why do all web windows share one remembered size?"). It is this app's own window chrome rather than the connected account's data, so it should survive a log out — which `AccountStore.disconnect()` would not let it — and it is read during the first layout pass of the first window, before any page has loaded, so it must not depend on an entitlement an ad-hoc build cannot carry (see AGENTS.md → "Building and Signing"). One value serves every window, all of them showing the same server; a height recorded against one server is simply corrected by the first page load against the next.
///
/// Nothing is assumed in place of a value that was never reported: `lastKnown(key:)` answers `nil` and `WebWindow` then leaves the buttons wherever AppKit put them, which is wrong nowhere rather than right for one server release. That costs a single visible shift on the very first window of a fresh install, once its first page load reports; every launch after that reads the value back before the window is shown.
enum NextcloudHeaderHeight {
    /// `logger` records this facility's activity under the `NextcloudHeaderHeight` category.
    private static let logger = Logger(for: NextcloudHeaderHeight.self)

    /// `defaultsKey` is the `UserDefaults.standard` key the last reported header height is kept under.
    ///
    /// It is the default argument of both `lastKnown(key:)` and `record(_:key:)` rather than being read directly by them, so a test can exercise this facility under a key of its own instead of overwriting the height the developer's real windows are laid out against.
    static let defaultsKey = "NextcloudHeaderHeight"

    /// `plausibleHeights` is the range of header heights worth believing, in points.
    ///
    /// The floor rejects a header caught collapsed or mid-animation, whose measured height says nothing about where the buttons belong; the ceiling rejects a measurement of something that is not the header the app lays out against — a guest layout's, or one taken while the page had reflowed — which would otherwise fling the buttons down into the content where the user cannot reach them. Current servers sit in the middle of it: 50 points on Nextcloud 34, 44 on 35.
    private static let plausibleHeights: ClosedRange<CGFloat> = 20 ... 120

    /// `isPlausible(_:)` reports whether `height` is worth believing as the height of Nextcloud's header.
    ///
    /// It is a pure rule of its own so it can be exercised directly, `record(_:key:)` needing a defaults domain to write into; `WebWindowFrame.isRecordable(styleMask:)` is split out from its own caller for the same reason. Non-finite values are refused explicitly rather than left to the range comparison, a `nan` comparing `false` against everything including a containment check.
    static func isPlausible(_ height: CGFloat) -> Bool {
        height.isFinite && plausibleHeights.contains(height)
    }

    /// `lastKnown(key:)` is the header height last reported by a page, or `nil` when none has ever been reported or the stored value is no longer one worth believing.
    ///
    /// `WebWindow.repositionControlButtons()` reads it on every layout pass and steps aside entirely while it is `nil`. The stored value is re-checked against `isPlausible(_:)` rather than trusted for having once passed it, so a value written by an older build under a wider rule — or by anyone editing the defaults domain by hand — cannot place the buttons somewhere unreachable.
    /// `object(forKey:)` is what distinguishes "never reported" from a stored zero, `double(forKey:)` answering `0` for both.
    static func lastKnown(key: String = defaultsKey) -> CGFloat? {
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return nil
        }

        let height = CGFloat(UserDefaults.standard.double(forKey: key))

        guard isPlausible(height) else {
            logger.error("Stored header height \(height) is not plausible; ignoring it")
            return nil
        }

        return height
    }

    /// `record(_:key:)` remembers `height` as the height of Nextcloud's header and announces the change, ignoring a height not worth believing and doing nothing at all when it matches what is already stored.
    ///
    /// `WebViewController` calls it for every report from `macOS/Scripts/HeaderHeight.js`. The height is rounded to whole points before being compared and stored, which is also what keeps a page reporting a fractional height from announcing a change no window would place a button differently for.
    /// An implausible report leaves the previously recorded height in place rather than clearing it: a page that measured its header while it was collapsed says nothing about the header, so the last height that *was* believable remains the better answer.
    static func record(_ height: CGFloat, key: String = defaultsKey) {
        guard isPlausible(height) else {
            logger.error("Ignoring reported header height \(height), which is not plausible")
            return
        }

        let rounded = height.rounded()

        guard rounded != lastKnown(key: key) else {
            logger.debug("Reported header height \(rounded) matches the one already recorded")
            return
        }

        UserDefaults.standard.set(Double(rounded), forKey: key)
        logger.notice("Recorded Nextcloud header height \(rounded, privacy: .public)")
        NotificationCenter.default.post(name: .nextcloudHeaderHeightDidChange, object: nil)
    }
}
