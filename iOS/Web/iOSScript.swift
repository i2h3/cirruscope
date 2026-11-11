// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

/// `iOSScript` enumerates the JavaScript resources bundled with the iOS app that `NextcloudView` injects into or evaluates within its `WebPage`.
enum iOSScript: String {
    /// `notificationsPanel` clicks Nextcloud's notifications bell to open the panel it hangs in the page header.
    case notificationsPanel = "NotificationsPanel"

    /// `notificationsPanelState` resolves Nextcloud's notifications menu, publishes the selector that matched onto `<html>`, and reports its availability and open state through the `notificationsPanelState` message handler.
    case notificationsPanelState = "NotificationsPanelState"

    /// `safeAreaInsets` publishes the margins the app's own interface covers onto `<html>` as the four `--cirruscope-safe-area-*` custom properties `Cirruscope.css` insets Nextcloud's content by.
    case safeAreaInsets = "SafeAreaInsets"

    /// Records failures to load a bundled script under the `iOSScript` category.
    private static let logger = Logger(for: iOSScript.self)

    /// The JavaScript text of the bundled `.js` resource backing this case, or `nil` if the resource is missing from the bundle or cannot be decoded as UTF-8.
    var source: String? {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "js") else {
            Self.logger.error("Could not find bundled script resource \(self.rawValue).js")
            return nil
        }

        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            Self.logger.error("Could not decode bundled script resource \(self.rawValue).js")
            return nil
        }

        return source
    }
}
