// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import UserNotifications

/// This extension names what the macOS app asks permission for.
extension NotificationAuthorization {
    /// `options` is alerts, sounds and the badge, the Mac posting the web interface's notifications as well as the server's.
    static var options: UNAuthorizationOptions {
        [.alert, .sound, .badge]
    }
}
