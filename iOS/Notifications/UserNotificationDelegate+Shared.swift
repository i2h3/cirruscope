// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import UserNotifications

///
/// This extension builds the iOS app's notification center delegate.
///
/// It exists per platform because the iPhone lists a notification arriving while the app is in front in Notification Center without a banner or a sound — the web interface on screen shows it already — and posts no notifications of its own besides the server's, so there is nothing else to answer a tap on.
/// The system brings the app forward for a tap itself, so nothing is done before opening.
///
extension UserNotificationDelegate {
    ///
    /// `shared` is the delegate `iOSApp` installs as it is built, retained for the app's lifetime because the notification center holds it weakly.
    ///
    static let shared = UserNotificationDelegate(presentationOptions: [.list])
}
