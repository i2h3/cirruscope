// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa
import os

/// `WebWindowController`'s conformance to `NSWindowDelegate` does two unrelated jobs for the window it hosts: it records the window's size, so the next web window opens at that size (issue #82), and it tells the hosted page when the window enters or leaves its own, native fullscreen, so the header stops reserving room for traffic lights that are no longer in it (issue #95).
extension WebWindowController: NSWindowDelegate {
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        logger.debug("Web window did end live resize")
        WebWindowFrame.record(window)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        logger.debug("Web window will close")
        WebWindowFrame.record(window)
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        logger.debug("Web window will enter full screen")
        reportFullScreen(true, for: notification.object as? NSWindow)
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        logger.debug("Web window did enter full screen")
        reportFullScreen(true, for: notification.object as? NSWindow)
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        logger.debug("Web window will exit full screen")
        reportFullScreen(false, for: notification.object as? NSWindow)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        logger.debug("Web window did exit full screen")
        reportFullScreen(false, for: notification.object as? NSWindow)

        (notification.object as? WebWindow)?.repositionControlButtons()
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        logger.debug("Web window did fail to enter full screen")
        reportFullScreen(false, for: window)
    }

    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        logger.debug("Web window did fail to exit full screen")
        reportFullScreen(true, for: window)
    }

    /// `reportFullScreen(_:for:)` tells `window`'s hosted page whether it is in the window's own, native fullscreen, so `Cirruscope.css` insets the header past the traffic lights or stops doing so.
    ///
    /// The value is stated by the caller rather than read from the window, for the reason the conformance's own documentation gives: inside a transition the style mask is not yet the answer.
    /// It steps aside while the content view controller's view has not loaded, because the web view it would reach is an implicitly unwrapped outlet the storyboard has not connected yet, and a transition can be announced before a window has ever been shown.
    private func reportFullScreen(_ isFullScreen: Bool, for window: NSWindow?) {
        guard let webViewController = window?.contentViewController as? WebViewController else {
            return
        }

        guard webViewController.isViewLoaded else {
            return
        }

        webViewController.reapplyAppearance(windowIsFullScreen: isFullScreen)
    }
}
