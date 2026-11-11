// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import WebKit

/// Receives what `iOSScript.notificationsPanelState` reports about Nextcloud's notifications menu: whether the page offers one, which of the script's candidate selectors matched it, and whether its panel is open.
@Observable
@MainActor
final class NotificationsPanelBridge: NSObject, WKScriptMessageHandler {
    /// The name `iOSScript.notificationsPanelState` posts to, and the name the handler is registered under.
    static let messageName = "notificationsPanelState"

    /// Whether the loaded page offers a notifications menu at all.
    private(set) var isAvailable = false

    /// Whether that menu's panel is currently open, as the page reports it.
    private(set) var isOpen = false

    /// Which of the script's candidate selectors matched the menu's trigger, or an empty string while none did.
    private(set) var matchedSelector = ""

    /// Records what the page reports under the `NotificationsPanelBridge` category.
    private let logger = Logger(for: NotificationsPanelBridge.self)

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else {
            logger.error("Received a notifications panel state message with an unexpected body")
            return
        }

        isAvailable = body["available"] as? Bool ?? false
        isOpen = body["open"] as? Bool ?? false
        matchedSelector = body["selector"] as? String ?? ""

        // At `.notice` because only `.notice` and above are persisted to the log store, and this line is the record of
        // what Nextcloud's DOM actually is on the server this build met. Each value is marked public because a
        // `Logger` redacts a dynamic string by default, and a selector logged as `<private>` is the one thing this
        // line exists to say. None of it is personal: a selector, and two booleans.
        logger.notice("Notifications menu: available \(self.isAvailable, privacy: .public), open \(self.isOpen, privacy: .public), matched \(self.matchedSelector, privacy: .public)")
    }
}
