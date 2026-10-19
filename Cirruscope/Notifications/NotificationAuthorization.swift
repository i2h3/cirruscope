// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import UserNotifications

///
/// `NotificationAuthorization` asks for the permission notifications need, and writes down what the system currently allows.
///
/// It asks only while the user has not answered yet, which is the only time the system would prompt anyway, so every caller may ask whenever a server is connected without a second thought.
/// What it asks for differs between the two apps, and each declares its own options in a file of its own, the rest being the same on both.
/// Everything here goes through the async calls of `UNUserNotificationCenter`, so no completion handler is ever written whose isolation could be wrong; see AGENTS.md → Concurrency.
/// It lives in `Cirruscope/` because the widget extension asks for nothing.
///
enum NotificationAuthorization {
    ///
    /// `logger` records every request and every reading of the settings under the `NotificationAuthorization` category.
    ///
    private static let logger = Logger(for: NotificationAuthorization.self)

    ///
    /// `requestIfUndetermined(reason:)` asks for this app's options if the user has not answered yet, then writes down what the system allows.
    ///
    /// `reason` names who asked, so a prompt that appeared, or one that did not, can be traced back to the moment that caused it.
    ///
    static func requestIfUndetermined(reason: StaticString) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        if settings.authorizationStatus == .notDetermined {
            do {
                let granted = try await center.requestAuthorization(options: options)

                if granted {
                    logger.notice("Notification authorization was granted (\(reason))")
                } else {
                    logger.notice("Notification authorization was denied (\(reason))")
                }
            } catch {
                logger.error("Requesting notification authorization failed (\(reason)): \(error.localizedDescription, privacy: .public)")
            }
        }

        await logState(reason: reason)
    }

    ///
    /// `logState(reason:)` writes down what the system currently allows, so a notification or a badge that never appears can be explained after the fact.
    ///
    /// Every value is logged as its raw integer, because an integer prints in the clear in the log store while a `String` would be redacted, and this is a line read back out of a device's log archive days later.
    /// `authorizationStatus` is `UNAuthorizationStatus` — 0 not determined, 1 denied, 2 authorized, 3 provisional, 4 ephemeral — and every other value is `UNNotificationSetting` — 0 not supported, 1 disabled, 2 enabled.
    /// A status of 2 with an alert or badge setting of 1 is the state where everything in the app works and nothing is visible, the user having switched that off in Settings after allowing notifications, and nothing else in a log would tell you that.
    ///
    static func logState(reason: StaticString) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let authorizationStatus = settings.authorizationStatus.rawValue
        let alertSetting = settings.alertSetting.rawValue
        let badgeSetting = settings.badgeSetting.rawValue
        let soundSetting = settings.soundSetting.rawValue
        let notificationCenterSetting = settings.notificationCenterSetting.rawValue

        logger.notice("Notification authorization status is \(authorizationStatus, privacy: .public), alerts \(alertSetting, privacy: .public), badge \(badgeSetting, privacy: .public), sound \(soundSetting, privacy: .public), Notification Center \(notificationCenterSetting, privacy: .public) (\(reason))")
    }
}
