// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import WebKit

///
/// Receives what `iOSScript.notificationsPanelState` reports about Nextcloud's notifications menu: whether the page offers one, which of the script's candidate selectors matched it, and whether its panel is open.
///
/// It is a class, and an `NSObject` at that, for the reason `AppNavigationBridge` is: `WKScriptMessageHandler` is a class-bound Objective-C protocol and a SwiftUI `View` is a struct. `NextcloudView.init()` registers it on the `WebPage.Configuration` before building the page, the configuration being a struct the page copies at initialization.
/// Unlike `AppNavigationBridge` it decides nothing about what is on screen. The account menu's "Notifications" item follows the server's own unread count, and the panel reveals itself through a stylesheet rule keyed on its own open state, so nothing here has to be kept in step with the page. It exists for the two things only the page can answer.
/// The first is diagnostic, and is why every message is logged at `.notice`: no selector for Nextcloud's notifications bell could be verified past the minimum supported server version, so the log — read back after one hand test against a live server — is where that answer is recorded rather than guessed at again. It also separates the two failures that look identical on screen, an unmatched selector from a panel that opened invisibly.
/// The second is that a panel closing is the moment notifications may just have been dismissed in the web view, which is a cue to re-read the count rather than leave a badge arguing with what the user has just seen.
///
@Observable
@MainActor
final class NotificationsPanelBridge: NSObject, WKScriptMessageHandler {
    ///
    /// The name `iOSScript.notificationsPanelState` posts to, and the name the handler is registered under.
    ///
    /// It is the script's own vocabulary, which is why the string lives beside the script rather than in a shared type — the same arrangement `AppNavigationBridge.messageName` has.
    ///
    static let messageName = "notificationsPanelState"

    ///
    /// Whether the loaded page offers a notifications menu at all.
    ///
    /// `false` for a public share, for the login page, and for every moment a document is still loading, which is why nothing in the interface is gated on it.
    ///
    private(set) var isAvailable = false

    ///
    /// Whether that menu's panel is currently open, as the page reports it.
    ///
    private(set) var isOpen = false

    ///
    /// Which of the script's candidate selectors matched the menu's trigger, or an empty string while none did.
    ///
    private(set) var matchedSelector = ""

    ///
    /// Records what the page reports under the `NotificationsPanelBridge` category.
    ///
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
