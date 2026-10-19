// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import UserNotifications

///
/// This extension names what the macOS app asks permission for.
///
extension NotificationAuthorization {
    ///
    /// `options` is alerts, sounds and the badge, the Mac posting the web interface's notifications as well as the server's.
    ///
    /// The badge is essential and not only for a notification's own badge: once an app is a `UNUserNotificationCenter` client, macOS gates the app icon badge — the Dock tile's label `DockBadge` sets included — behind the notification "Badges" setting this option authorizes, and without it the label is silently not drawn although it is assigned.
    ///
    static var options: UNAuthorizationOptions {
        [.alert, .sound, .badge]
    }
}
