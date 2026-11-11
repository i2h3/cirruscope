// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import UserNotifications

/// This extension builds the macOS app's notification center delegate.
extension UserNotificationDelegate {
    /// `shared` is the delegate `AppDelegate` installs at launch, retained for the app's lifetime because the notification center holds it weakly.
    static let shared = UserNotificationDelegate(presentationOptions: [.banner, .sound, .list], willOpen: { NSApp.activate() }, respondToOther: { UserNotifier.shared.respond(toNotificationWithIdentifier: $0, userInfo: $1) })
}
