// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Cocoa
import os

/// `WebWindowController`'s conformance to `NSWindowDelegate` does two unrelated jobs for the window it hosts: it records the window's size, so the next web window opens at that size (issue #82), and it tells the hosted page when the window enters or leaves its own, native fullscreen, so the header stops reserving room for traffic lights that are no longer in it (issue #95).
///
/// The storyboard's "Web Window" scene already connects the window's `delegate` outlet to this window controller, so every hook below is reached without any wiring in code.
///
/// **Recording the size.** Between them the two size hooks cover every way a user settles on one: dragging a resize edge, and whatever the window measures when it closes — which is also how a zoomed (green-button) size is picked up, zooming firing no live-resize notification. What they cannot cover is quitting with a window still open, `NSWindow.willCloseNotification` not being posted when the application terminates; `AppDelegate.applicationWillTerminate(_:)` records the frontmost web window for that case. Neither hook decides anything itself: `WebWindowFrame` owns where the frame is kept and which states are worth remembering — fullscreen is not — so both callers stay one line and the rule lives in one place.
///
/// **Reporting fullscreen.** Each leg states where the window is heading rather than reading its style mask, because AppKit flips `.fullScreen` somewhere inside a transition it does not document — and `macOSTests/Windows/WebWindowFrameTests` records that the bit cannot even be set by hand to find out, `-[NSWindow setStyleMask:]` raising rather than answering. The `will` hooks are what make the change invisible: the page reflows before AppKit's animation has anything to show, where reporting at `did` would slide the header's contents at the instant the animation lands, and on the way *out* would let the returning traffic lights arrive over a header that had not moved yet. The `did` hooks re-assert the same value idempotently, and the two `DidFailTo` hooks put it back when AppKit abandons a transition it announced.
/// It is reported per window, deliberately, and not through a notification the way `NextcloudHeaderHeight` broadcasts a header height. That height is one server's answer and belongs to every window at once; this is one window's own state, and pushing it to all of them would drop a sibling window's inset and put its traffic lights straight over Nextcloud's app menu.
/// Leaving fullscreen also has to reposition the window buttons by hand. `WebWindow.repositionControlButtons()` steps aside while `.fullScreen` is set and otherwise re-runs only from a layout pass or a newly reported header height, so a window whose last layout pass of the transition still carried the bit would keep AppKit's default placement until it was next resized.
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
