// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import UserNotifications

/// This extension names what the iOS app asks permission for.
extension NotificationAuthorization {
    /// `options` is alerts and the badge, and deliberately not sounds, since no notification the app posts carries one and asking would be asking for permission the app has no use for.
    static var options: UNAuthorizationOptions {
        [.alert, .badge]
    }
}
