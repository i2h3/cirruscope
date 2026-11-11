// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import os

/// `NextcloudHeaderHeight` remembers how tall the connected server draws its header, so `WebWindow` can center the standard window buttons inside a bar the server sizes rather than inside a height the app assumed.
enum NextcloudHeaderHeight {
    /// `logger` records this facility's activity under the `NextcloudHeaderHeight` category.
    private static let logger = Logger(for: NextcloudHeaderHeight.self)

    /// `defaultsKey` is the `UserDefaults.standard` key the last reported header height is kept under.
    static let defaultsKey = "NextcloudHeaderHeight"

    /// `plausibleHeights` is the range of header heights worth believing, in points.
    ///
    /// The floor rejects a header caught collapsed or mid-animation, whose measured height says nothing about where the buttons belong; the ceiling rejects a measurement of something that is not the header the app lays out against — a guest layout's, or one taken while the page had reflowed — which would otherwise fling the buttons down into the content where the user cannot reach them. Current servers sit in the middle of it: 50 points on Nextcloud 34, 44 on 35.
    private static let plausibleHeights: ClosedRange<CGFloat> = 20 ... 120

    /// `isPlausible(_:)` reports whether `height` is worth believing as the height of Nextcloud's header.
    static func isPlausible(_ height: CGFloat) -> Bool {
        height.isFinite && plausibleHeights.contains(height)
    }

    /// `lastKnown(key:)` is the header height last reported by a page, or `nil` when none has ever been reported or the stored value is no longer one worth believing.
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

    /// `record(_:key:notifyChange:)` remembers `height` as the height of Nextcloud's header and announces the change, ignoring a height not worth believing and doing nothing at all when it matches what is already stored.
    @MainActor
    static func record(_ height: CGFloat, key: String = defaultsKey, notifyChange: @MainActor () -> Void = { NextcloudHeaderHeight.postDidChange() }) {
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
        notifyChange()
    }

    /// `postDidChange()` posts `Notification.Name.nextcloudHeaderHeightDidChange`, and is the production default for `record(_:key:notifyChange:)`'s `notifyChange`.
    @MainActor
    static func postDidChange() {
        NotificationCenter.default.post(name: .nextcloudHeaderHeightDidChange, object: nil)
    }
}
