// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import os
import WebKit

/// `FindBarWindowController` is the window controller of the storyboard "Find Bar Window" scene: it carries the web view the find bar searches and attaches the panel to that web view's window so it stays above and moves with it. Its `FindBarViewController` reads `webView` through this controller on each use, since the scene nib loads before `WebViewController` can set it.
final class FindBarWindowController: NSWindowController {
    /// `webView` is the web view whose page the find bar searches; `WebViewController` sets it right after instantiating this controller.
    weak var webView: WKWebView?

    /// `logger` records this window controller's activity under the `FindBarWindowController` category.
    private let logger = Logger(for: FindBarWindowController.self)

    /// `findBarViewController` is the panel's content view controller owning the find actions; reading it loads the window first, so the controller exists.
    var findBarViewController: FindBarViewController? {
        _ = window
        return contentViewController as? FindBarViewController
    }

    /// `attachToWebWindow()` makes the panel a child window of the web view's window, so it follows that window, and places it at its top trailing corner. It runs when the find bar is shown rather than in `windowDidLoad`, because the storyboard instantiates this controller — and so would run `windowDidLoad` — before `WebViewController` can hand over the web view; it is a no-op once the panel is already attached.
    func attachToWebWindow() {
        guard let panel = window else {
            logger.error("The Find Bar Window scene loaded no window")
            return
        }

        guard panel.parent == nil else {
            return
        }

        guard let webWindow = webView?.window else {
            logger.notice("Not attaching the find panel, as the web view has no window (FindBarWindowController)")
            return
        }

        webWindow.addChildWindow(panel, ordered: .above)

        var frame = panel.frame
        frame.origin.x = webWindow.frame.maxX - frame.width - 16
        frame.origin.y = webWindow.frame.maxY - frame.height - 16
        panel.setFrame(frame, display: false)
    }
}
