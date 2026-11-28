// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

/// `macOSScript` enumerates the JavaScript resources bundled with the app for injection into or evaluation within its web views.
enum macOSScript: String {
    /// `windowDrag` forwards `mousedown` events that land on Nextcloud's header to the `windowDrag` message handler so the host window can begin a drag.
    case windowDrag = "WindowDrag"

    /// `sidebarShortcut` claims the ⌃⌘S keystroke inside the page and reports it through the `sidebarShortcut` message handler, for the cases in which no `WebWindow` is offered the key equivalent — element fullscreen above all, where WebKit hosts the web view in a window of its own.
    case sidebarShortcut = "SidebarShortcut"

    /// `searchShortcuts` claims ⌘K and ⌘F keystrokes aimed at an editable control inside the page and re-dispatches them synthetically on `<body>`, so the page's own search shortcuts fire even while a text field has focus, and reports a ⌘F the page declined — or that repeats while the page's search field has focus — through the `findPanel` message handler (issue #153).
    case searchShortcuts = "SearchShortcuts"

    /// `headerHeight` measures Nextcloud's own header and reports its height through the `headerHeight` message handler, once on injection and again whenever that header is resized.
    case headerHeight = "HeaderHeight"

    /// `notificationBridge` overrides the web Notification API so notifications created by the Nextcloud web interface are forwarded to the `notification` message handler instead of being lost.
    case notificationBridge = "NotificationBridge"

    /// `appearanceAttributes` sets the `data-cirruscope-translucency`, `data-cirruscope-full-width`, `data-cirruscope-accent`, and `data-cirruscope-accent-bright` attributes on `<html>` that `Cirruscope.css` scopes its translucency, full-width, and accent-color rules to, along with the `--cirruscope-accent-color` custom property those accent rules re-derive Nextcloud's primary color family from and the `--cirruscope-window-button-clearance` one the header's leading inset is measured by.
    case appearanceAttributes = "AppearanceAttributes"

    /// `findMatchCount` contributes `findMatchCount` to the page's `Cirruscope` namespace, answering how many times the find bar's query occurs in the page's rendered text, since `WKFindResult` reports no total on macOS.
    case findMatchCount = "FindMatchCount"

    /// `logger` records failures to load a bundled script under the `macOSScript` category.
    private static let logger = Logger(for: macOSScript.self)

    /// `source` is the JavaScript text of the bundled `.js` resource backing this case, or `nil` if the resource is missing from the bundle or cannot be decoded as UTF-8.
    var source: String? {
        guard
            let url = Bundle.main.url(forResource: rawValue, withExtension: "js"), let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            Self.logger.error("Could not load bundled script resource \(rawValue).js")
            return nil
        }

        return source
    }
}
