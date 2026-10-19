// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import os

///
/// `DockBadge` draws the unread notification count on the Dock icon.
///
/// It is the Mac's half of the badge the shared notification monitor decides on; the iPhone writes the home screen's through `UNUserNotificationCenter` instead.
/// The label only appears at all once notification authorization includes the badge, which `NotificationAuthorization` asks for; see its macOS options.
///
@MainActor
enum DockBadge {
    ///
    /// `logger` records every label written under the `DockBadge` category.
    ///
    private static let logger = Logger(for: DockBadge.self)

    ///
    /// `apply(_:)` writes one decision about the badge onto the Dock tile, drawing nothing while no server is configured, and asks the Dock to repaint it promptly.
    ///
    static func apply(_ update: UnreadNotifications.BadgeUpdate) {
        let count: Int

        switch update {
            case let .set(value):
                count = value

            case .clear:
                count = 0

            case .unchanged:
                return
        }

        let label = AccountStore.shared.serverAddress == nil ? nil : label(for: count)

        logger.debug("Updating the Dock badge to \(label ?? "nothing", privacy: .public)")
        NSApp.dockTile.badgeLabel = label
        NSApp.dockTile.display()
    }

    ///
    /// `label(for:)` is what the Dock tile shows for `count` unread notifications: nothing for none, the count in the current locale's digits, and `999+` past that, so the badge stays narrow.
    ///
    nonisolated static func label(for count: Int) -> String? {
        guard count > 0 else {
            return nil
        }

        guard count <= 999 else {
            return "999+"
        }

        return count.formatted()
    }
}
