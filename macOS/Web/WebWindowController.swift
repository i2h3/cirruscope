// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa
import os

/// `WebWindowController` is the window controller for the storyboard "Web Window" scene, carrying the URL its `WebViewController` should load.
class WebWindowController: NSWindowController {
    /// `targetURL` is the URL the hosted `WebViewController` should load, or `nil` to load `AccountStore.serverAddress`.
    var targetURL: URL?

    /// `logger` records this window controller's activity under the `WebWindowController` category.
    let logger = Logger(for: WebWindowController.self)

    override func windowDidLoad() {
        super.windowDidLoad()
        logger.debug("Did load")

        // Opt the window into AppKit state restoration; `AppDelegate` recreates it on relaunch and `WebWindow`
        // encodes which page it shows. The per-window identifier is assigned by whoever creates the window.
        window?.isRestorable = true
        window?.restorationClass = AppDelegate.self

        observeHeaderHeight()
    }

    /// `observeHeaderHeight()` subscribes to `Notification.Name.nextcloudHeaderHeightDidChange` so a newly reported Nextcloud header height re-centers this window's standard window buttons in it.
    private func observeHeaderHeight() {
        NotificationCenter.default.addObserver(self, selector: #selector(headerHeightDidChange), name: .nextcloudHeaderHeightDidChange, object: nil)
    }

    @objc
    private func headerHeightDidChange() {
        logger.debug("Nextcloud header height changed; re-centering the window buttons in it")
        (window as? WebWindow)?.repositionControlButtons()
    }
}
