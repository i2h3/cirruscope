// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import UserNotifications

///
/// The number the home screen draws on the app icon.
///
/// The live monitor and the background refresh both write the badge through here, so there is one place a badge write is logged from; the notifications themselves are posted by the shared `ServerNotificationDispatcher`, and the authorization the badge needs is asked for by the shared `NotificationAuthorization`.
/// `UIApplication.applicationIconBadgeNumber` is deliberately not used. It has been deprecated since iOS 17 in favour of `setBadgeCount(_:)`, and reaching for it would pull UIKit into a type the background refresh calls, for nothing in return.
/// Everything here is `nonisolated`, which is what lets the background refresh call it without a hop; see AGENTS.md → Concurrency.
///
enum AppIconBadge {
    ///
    /// Records every badge write under the `AppIconBadge` category.
    ///
    static let logger = Logger(for: AppIconBadge.self)

    ///
    /// Apply one decision about the badge to the app icon.
    ///
    /// iOS takes an integer where macOS takes a label, so there is no counterpart here to the Mac's `"999+"` cap: there is no string to shorten, and the system lays out whatever number it is given in the user's own locale. The only clamp left is the lower bound, `setBadgeCount(_:)` rejecting a negative number with `UNError.Code.badgeInputInvalid`; zero is how the badge is cleared, there being no separate call for that.
    /// A denied authorization is not silent, which is what logging the failure is for: the call fails with `UNError.Code.notificationsNotAllowed`, code 1 in the `UNErrorDomain`. Nothing is retried and nothing is shown, because the system has already asked the user once and this app has nothing further to say about it — and the count is still true, so the account menu's own badge, which no authorization gates, keeps showing it.
    ///
    static func apply(_ update: UnreadNotifications.BadgeUpdate) async {
        let count: Int

        switch update {
            case let .set(value):
                count = max(0, value)

            case .clear:
                count = 0

            case .unchanged:
                logger.notice("Leaving the app icon badge as it stands")
                return
        }

        do {
            try await UNUserNotificationCenter.current().setBadgeCount(count)
            logger.notice("Set the app icon badge to \(count, privacy: .public)")
        } catch {
            logger.error("Could not set the app icon badge to \(count, privacy: .public): \(error.localizedDescription)")
        }
    }
}
