// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import WebKit

/// Receives what `Script.sidebarToggleState` reports about Nextcloud's app-navigation toggle, so `NextcloudView` can show its own toolbar control only where there is one and reflect whether it is currently open.
@Observable
@MainActor
final class AppNavigationBridge: NSObject, WKScriptMessageHandler {
    /// The name `Script.sidebarToggleState` posts to, and the name the handler is registered under.
    static let messageName = "sidebarToggleState"

    /// Whether the loaded Nextcloud app offers an app-navigation toggle at all.
    private(set) var isAvailable = false

    /// Whether Nextcloud's app navigation is currently shown.
    private(set) var isExpanded = false

    /// Records what the page reports under the `AppNavigationBridge` category.
    private let logger = Logger(for: AppNavigationBridge.self)

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else {
            logger.error("Received an app-navigation state message with an unexpected body")
            return
        }

        isAvailable = body["available"] as? Bool ?? false
        isExpanded = body["expanded"] as? Bool ?? false
    }
}
