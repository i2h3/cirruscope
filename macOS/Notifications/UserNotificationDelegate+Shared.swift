// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import UserNotifications

///
/// This extension builds the macOS app's notification center delegate.
///
/// It exists per platform because the Mac presents notifications as banners even while Cirruscope is the active app, brings itself forward before it opens a server notification, and posts notifications of its own besides the server's — the web interface's and finished downloads' — whose taps `UserNotifier` answers.
///
extension UserNotificationDelegate {
    ///
    /// `shared` is the delegate `AppDelegate` installs at launch, retained for the app's lifetime because the notification center holds it weakly.
    ///
    static let shared = UserNotificationDelegate(presentationOptions: [.banner, .sound, .list], willOpen: { NSApp.activate() }, respondToOther: { UserNotifier.shared.respond(toNotificationWithIdentifier: $0, userInfo: $1) })
}
