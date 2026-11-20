// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import os
import WebKit

/// `FindBarWindowController` is the window controller of the storyboard "Find Bar Window" scene: it carries the web view the find bar searches, attaches the panel to the web window so it stays above it, and remembers the panel's frame across launches, placing it at the web window's top trailing corner the first time. Its `FindBarViewController` reads `webView` through this controller on each use, since the scene nib loads before `WebViewController` can set it.
final class FindBarWindowController: NSWindowController {
    /// `webView` is the web view whose page the find bar searches; `WebViewController` sets it right after instantiating this controller.
    weak var webView: WKWebView?

    /// `frameAutosaveName` is the name under which the panel's frame is remembered across launches.
    private static let frameAutosaveName = "CirruscopeFindBar"

    /// `logger` records this window controller's activity under the `FindBarWindowController` category.
    private let logger = Logger(for: FindBarWindowController.self)

    /// `findBarViewController` is the panel's content view controller owning the find actions; reading it loads the window first, so the controller exists.
    var findBarViewController: FindBarViewController? {
        _ = window
        return contentViewController as? FindBarViewController
    }

    override func windowDidLoad() {
        super.windowDidLoad()

        guard let panel = window else {
            logger.error("The Find Bar Window scene loaded no window")
            return
        }

        webView?.window?.addChildWindow(panel, ordered: .above)
        panel.setFrameAutosaveName(Self.frameAutosaveName)

        if panel.setFrameUsingName(Self.frameAutosaveName) == false, let webWindow = webView?.window {
            var frame = panel.frame
            frame.origin.x = webWindow.frame.maxX - frame.width - 16
            frame.origin.y = webWindow.frame.maxY - frame.height - 16
            panel.setFrame(frame, display: false)
        }
    }
}
