// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

/// `macOSScript` enumerates the JavaScript resources bundled with the app that `WebViewController` injects into or evaluates within its `WKWebView`.
///
/// Each case maps to a `.js` file of the same name in `macOS/Scripts/`, which keeps the scripts in standalone files that can be edited with JavaScript tooling instead of being embedded as string literals in Swift source.
/// These are the scripts only macOS runs. The two both apps share — the app-navigation toggle and the state it reports — are `Script` cases in `Cirruscope/`.
/// `WebViewController` reads `source` at the moment it needs a script, either to install it as a `WKUserScript` via `installUserScript(_:injectionTime:)` or to evaluate it on demand with `WKWebView.evaluateJavaScript(_:)`.
enum macOSScript: String {
    /// `windowDrag` forwards `mousedown` events that land on Nextcloud's header to the `windowDrag` message handler so the host window can begin a drag.
    ///
    /// `WebViewController.installWindowDragBridge()` installs it as a user script that runs at the end of every document load.
    case windowDrag = "WindowDrag"

    /// `sidebarShortcut` claims the ⌃⌘S keystroke inside the page and reports it through the `sidebarShortcut` message handler, for the cases in which no `WebWindow` is offered the key equivalent — element fullscreen above all, where WebKit hosts the web view in a window of its own.
    ///
    /// `WebViewController.installSidebarShortcutBridge()` installs it as a user script that runs at the start of every document load, before the page's own scripts attach the keyboard handlers it has to be offered the event ahead of.
    case sidebarShortcut = "SidebarShortcut"

    /// `headerHeight` measures Nextcloud's own header and reports its height through the `headerHeight` message handler, once on injection and again whenever that header is resized.
    ///
    /// `WebViewController.installHeaderHeightBridge()` installs it as a user script that runs at the end of every document load, there being no header to measure before the document exists.
    case headerHeight = "HeaderHeight"

    /// `notificationBridge` overrides the web Notification API so notifications created by the Nextcloud web interface are forwarded to the `notification` message handler instead of being lost.
    ///
    /// `WebViewController.installNotificationBridge()` installs it as a user script that runs at the start of every document load, before the page's own scripts read the API.
    case notificationBridge = "NotificationBridge"

    /// `appearanceAttributes` sets the `data-cirruscope-translucency`, `data-cirruscope-full-width`, `data-cirruscope-accent`, and `data-cirruscope-accent-bright` attributes on `<html>` that `Cirruscope.css` scopes its translucency, full-width, and accent-color rules to, along with the `--cirruscope-accent-color` custom property those accent rules re-derive Nextcloud's primary color family from and the `--cirruscope-window-button-clearance` one the header's leading inset is measured by.
    ///
    /// Unlike the other cases its resource runs nothing on its own: it contributes `applyAppearanceAttributes` to the page's `Cirruscope` namespace, and `WebViewController.appearanceAttributeScript(windowIsFullScreen:)` emits it followed by a call carrying the account's current appearance settings, the app's effective accent color, and the host window's button clearance — both to install as a document-start user script and to re-apply on demand with `WKWebView.evaluateJavaScript(_:)`. The namespace assignment is idempotent, so the second path cannot disturb a document that already ran the first.
    /// The clearance is the one value of the five that describes a single window rather than the account or the system, and it rides along here because every path that re-applies the others already re-applies it too — one publication schedule rather than two that can fall out of step.
    case appearanceAttributes = "AppearanceAttributes"

    /// `logger` records failures to load a bundled script under the `macOSScript` category.
    private static let logger = Logger(for: macOSScript.self)

    /// `source` is the JavaScript text of the bundled `.js` resource backing this case, or `nil` if the resource is missing from the bundle or cannot be decoded as UTF-8.
    ///
    /// It is read lazily at the point of use so edits to the underlying `.js` file take effect without any change to Swift source.
    var source: String? {
        guard
            let url = Bundle.main.url(forResource: rawValue, withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            Self.logger.error("Could not load bundled script resource \(rawValue).js")
            return nil
        }

        return source
    }
}
