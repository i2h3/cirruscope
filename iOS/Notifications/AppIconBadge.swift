// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import UserNotifications

///
/// The number the home screen draws on the app icon.
///
/// It is the only thing this app puts in front of the user from native code on iOS: no banner and no sound is posted, and the notifications themselves are read in the web interface. Both halves of the refresh write the badge through here, so there is one caller of `UNUserNotificationCenter` in the app and one place a badge write is logged from.
/// `UIApplication.applicationIconBadgeNumber` is deliberately not used. It has been deprecated since iOS 17 in favour of `setBadgeCount(_:)`, and reaching for it would pull UIKit into a type the background refresh calls, for nothing in return.
/// Everything here is `nonisolated`, which is what lets the background refresh call it without a hop; see AGENTS.md → Concurrency.
///
enum AppIconBadge {
    ///
    /// Records every badge write, and every reading of the authorization that gates it, under the `AppIconBadge` category.
    ///
    static let logger = Logger(for: AppIconBadge.self)

    ///
    /// Ask for the authorization the badge needs, which is `.badge` and nothing else.
    ///
    /// Asked right after a sign-in succeeds, so the prompt arrives with a server actually connected rather than in front of an empty launch. Asked at all because the app icon badge is gated behind this option for any `UNUserNotificationCenter` client: without it `setBadgeCount(_:)` fails and the icon stays bare no matter what number is assigned. macOS asks for `[.alert, .sound, .badge]` because it also posts banners; nothing on iOS does, so asking for either would be asking for permission the app has no use for.
    /// The system prompts only while the authorization state is undetermined. Asking again after a denial is neither an error nor a second prompt — it reports `false`, which is why the outcome is written down rather than acted on.
    ///
    static func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.badge])

            if granted {
                logger.notice("Notification authorization for the app icon badge was granted")
            } else {
                logger.notice("Notification authorization for the app icon badge was denied")
            }
        } catch {
            logger.error("Requesting notification authorization for the app icon badge failed: \(error.localizedDescription)")
        }

        await logAuthorizationState()
    }

    ///
    /// Record what the system currently allows, so a badge that never appears can be explained after the fact.
    ///
    /// Both values are logged as their raw integers rather than as names, because an integer prints in the clear in the log store while a `String` would be redacted, and this is a line read back out of a device's log archive days later. `authorizationStatus` is `UNAuthorizationStatus` — 0 not determined, 1 denied, 2 authorized, 3 provisional, 4 ephemeral — and `badgeSetting` is `UNNotificationSetting` — 0 not supported, 1 disabled, 2 enabled.
    /// A status of 2 with a badge setting of 1 is the state where everything in this app works and nothing is visible, the user having switched Badges off in Settings after allowing notifications. Nothing else in a log would tell you that, which is the whole reason this line exists.
    ///
    static func logAuthorizationState() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let authorizationStatus = settings.authorizationStatus.rawValue
        let badgeSetting = settings.badgeSetting.rawValue

        logger.notice("Notification authorization status is \(authorizationStatus, privacy: .public) and the badge setting is \(badgeSetting, privacy: .public)")
    }

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
