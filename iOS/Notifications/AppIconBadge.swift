// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import UserNotifications

/// The number the home screen draws on the app icon.
enum AppIconBadge {
    /// Records every badge write under the `AppIconBadge` category.
    static let logger = Logger(for: AppIconBadge.self)

    /// Apply one decision about the badge to the app icon.
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
