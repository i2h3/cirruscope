// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit

/// `WebWindow` is the window of the storyboard "Web Window" scene that hosts `WebViewController`.
class WebWindow: NSWindow {
    /// `leadingInset` is the distance from the window's leading edge to the first window button.
    private static let leadingInset: CGFloat = 20

    /// `buttonSpacing` is the horizontal distance between the leading edges of adjacent window buttons.
    private static let buttonSpacing: CGFloat = 23

    /// `trailingGap` is the distance the page's own content keeps past the trailing edge of the last window button.
    ///
    /// It is what turns the buttons' own extent into a clearance a header can be laid out against, rather than a boundary the two share exactly.
    private static let trailingGap: CGFloat = 10

    /// `buttonTypes` are the standard window buttons this window places, in the order they are laid out from the leading edge.
    private static let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

    /// `restorableStateURLKey` is the coder key under which the displayed page URL is stored for window restoration.
    static let restorableStateURLKey = "url"

    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)

        // Persist the page the window currently shows so a relaunch can reopen it there. The window itself is the
        // restorable participant, so it (not the view controller) encodes the state AppKit hands to the restoration class.
        if let url = (contentViewController as? WebViewController)?.restorableURL {
            coder.encode(url as NSURL, forKey: Self.restorableStateURLKey)
        }
    }

    /// `performKeyEquivalent(with:)` claims ⌃⌘S — Cirruscope's own "Show/Hide Sidebar" shortcut — before the event ever reaches the hosted `WKWebView`.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if WebViewController.isSidebarToggleShortcut(event), let webViewController = contentViewController as? WebViewController {
            webViewController.toggleSidebar(nil)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        repositionControlButtons()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        repositionControlButtons()
    }

    /// `repositionControlButtons()` moves the close, miniaturize, and zoom buttons to align with Nextcloud's header bar, leaving them untouched while no header height has been reported yet, while they are not yet available, or while the window is in fullscreen.
    func repositionControlButtons() {
        guard styleMask.contains(.fullScreen) == false else {
            return
        }

        guard let headerHeight = NextcloudHeaderHeight.lastKnown() else {
            return
        }

        for (index, type) in Self.buttonTypes.enumerated() {
            guard let button = standardWindowButton(type), let superview = button.superview
            else {
                continue
            }

            let originInWindow = Self.buttonOriginInWindow(index: index, buttonHeight: button.bounds.height, windowHeight: frame.height, headerHeight: headerHeight)

            button.setFrameOrigin(superview.convert(originInWindow, from: nil))
        }
    }

    /// `windowButtonClearance(isFullScreen:)` is how far in from this window's leading edge page content must start to clear its own standard window buttons, measured from the button AppKit actually vends, or `nil` while AppKit vends none.
    func windowButtonClearance(isFullScreen: Bool) -> CGFloat? {
        guard let buttonWidth = standardWindowButton(.zoomButton)?.bounds.width else {
            return nil
        }

        return Self.windowButtonClearance(isFullScreen: isFullScreen, buttonWidth: buttonWidth)
    }

    /// `windowButtonClearance(isFullScreen:buttonWidth:)` is how far in from the leading edge page content must start to clear the standard window buttons, in points, and zero for a window in fullscreen.
    static func windowButtonClearance(isFullScreen: Bool, buttonWidth: CGFloat) -> CGFloat {
        guard isFullScreen == false else {
            return 0
        }

        return buttonLeadingEdge(index: buttonTypes.count - 1) + buttonWidth + trailingGap
    }

    /// `buttonOriginInWindow(index:buttonHeight:windowHeight:headerHeight:)` is where the window button at `index` belongs in window coordinates: laid out from the leading edge in the order the buttons are, and vertically centered in a header of `headerHeight` measured down from the top of a window of `windowHeight`.
    static func buttonOriginInWindow(index: Int, buttonHeight: CGFloat, windowHeight: CGFloat, headerHeight: CGFloat) -> NSPoint {
        let topInset = (headerHeight - buttonHeight) / 2

        return NSPoint(x: buttonLeadingEdge(index: index), y: windowHeight - topInset - buttonHeight)
    }

    /// `buttonLeadingEdge(index:)` is where the window button at `index` starts, measured from the window's leading edge.
    private static func buttonLeadingEdge(index: Int) -> CGFloat {
        leadingInset + CGFloat(index) * buttonSpacing
    }
}
