// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import UserNotifications

/// `NotificationAuthorization` asks for the permission notifications need, and writes down what the system currently allows.
enum NotificationAuthorization {
    /// `logger` records every request and every reading of the settings under the `NotificationAuthorization` category.
    private static let logger = Logger(for: NotificationAuthorization.self)

    /// `requestIfUndetermined(reason:)` asks for this app's options if the user has not answered yet, then writes down what the system allows.
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

    /// `logState(reason:)` writes down what the system currently allows, so a notification or a badge that never appears can be explained after the fact.
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
