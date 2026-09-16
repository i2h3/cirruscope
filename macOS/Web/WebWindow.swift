// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit

/// `WebWindow` is the window of the storyboard "Web Window" scene that hosts `WebViewController`.
///
/// It keeps the standard close, miniaturize, and zoom buttons aligned with Nextcloud's own header bar, which is Cirruscope's title bar: the window hides its own (`titlebarAppearsTransparent`, `titleVisibility`, and `fullSizeContentView` are all set in the storyboard) and the web view reaches the top edge underneath. AppKit returns those buttons to their default position on every layout pass, so `WebWindow` repositions them again at the end of the same pass — synchronously, so they are never displayed at the default position and do not visibly jump.
///
/// How tall that bar is, is the server's to decide and `NextcloudHeaderHeight`'s to remember; it is deliberately no longer a constant here, which is what placed the buttons too low on Nextcloud server 35 (issue #102). While no height has ever been reported the buttons are left exactly where AppKit puts them.
///
/// How far *in* the page must start to clear those buttons is this window's own to decide, and `windowButtonClearance(isFullScreen:buttonWidth:)` answers it from the very constants they are laid out from. The stylesheet used to state that sum a second time as a hand-tuned margin, in a file with no way of noticing either a change to those constants or the window's fullscreen state, which is the excess inset issue #95 arrived as.
class WebWindow: NSWindow {
    /// `leadingInset` is the distance from the window's leading edge to the first window button.
    ///
    /// It is read by `buttonLeadingEdge(index:)`, and so reaches both the placement of the buttons themselves and the clearance the page keeps from them.
    private static let leadingInset: CGFloat = 20

    /// `buttonSpacing` is the horizontal distance between the leading edges of adjacent window buttons.
    ///
    /// It is read by `buttonLeadingEdge(index:)`, and so reaches both the placement of the buttons themselves and the clearance the page keeps from them.
    private static let buttonSpacing: CGFloat = 23

    /// `trailingGap` is the distance the page's own content keeps past the trailing edge of the last window button.
    ///
    /// It is what turns the buttons' own extent into a clearance a header can be laid out against, rather than a boundary the two share exactly.
    private static let trailingGap: CGFloat = 10

    /// `buttonTypes` are the standard window buttons this window places, in the order they are laid out from the leading edge.
    ///
    /// `repositionControlButtons()` iterates it to place them and `windowButtonClearance(isFullScreen:buttonWidth:)` counts it to find the last one, so neither can disagree with the other about how many there are.
    private static let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

    /// `restorableStateURLKey` is the coder key under which the displayed page URL is stored for window restoration.
    ///
    /// `encodeRestorableState(with:)` writes it; `AppDelegate.restoreWindow(withIdentifier:state:completionHandler:)` reads it back.
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
    ///
    /// `-[NSWindow performKeyEquivalent:]`'s default implementation asks the content view hierarchy — which includes the web view — before it ever falls back to the menu bar, and a `WKWebView` can itself claim a command-key event by forwarding it to the loaded page's JavaScript, which may call `preventDefault()` for its own purposes. Nextcloud Talk does exactly that for ⌃⌘S (issue #59): its own keyboard handling — almost certainly a `event.ctrlKey || event.metaKey` check meant to unify Mac and Windows/Linux shortcuts under one condition, which also fires when *both* are held together on Mac — swallows the event and triggers an unrelated, broken "export" download instead ("undefined.html"), and the "Show/Hide Sidebar" menu item, despite being enabled, never even gets asked. Intercepting the shortcut here, ahead of the content view hierarchy, guarantees Cirruscope's own action always wins regardless of what any loaded page's script does with the keystroke.
    ///
    /// This covers the shortcut only while this window is the one AppKit offers the event to, which it is not while the page is in element fullscreen: the key window then belongs to WebKit rather than to the app. `macOSScript.sidebarShortcut` claims the keystroke from inside the page for that case, and both halves agree on which keystroke it is — this one through `WebViewController.isSidebarToggleShortcut(_:)`, the script through the same modifier set spelled out in JavaScript.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if WebViewController.isSidebarToggleShortcut(event),
           let webViewController = contentViewController as? WebViewController
        {
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
    ///
    /// In fullscreen macOS relocates the window buttons into the auto-revealing title bar; the custom placement is skipped there so the buttons stay reachable in that title bar (including the green button used to leave fullscreen) instead of being pulled into the hidden content area. `windowButtonClearance(isFullScreen:buttonWidth:)` answers zero for the same state and for the same reason, which is how the page stops reserving room for buttons that are no longer in its header.
    /// Stepping aside while `NextcloudHeaderHeight` knows no height is what keeps a guess about one server release out of the code: AppKit's own placement is then left in force, which is the state a fresh install's very first window is shown in until its first page load reports (see `NextcloudHeaderHeight` for why that shift is accepted).
    /// Besides the two layout hooks above, `WebWindowController` calls it when a page reports a header height different from the one recorded, and again once the window has left fullscreen: neither change triggers a layout pass of its own, so a window already on screen would otherwise keep its old placement until it was next resized. Hence not `private`.
    func repositionControlButtons() {
        guard styleMask.contains(.fullScreen) == false else {
            return
        }

        guard let headerHeight = NextcloudHeaderHeight.lastKnown() else {
            return
        }

        for (index, type) in Self.buttonTypes.enumerated() {
            guard let button = standardWindowButton(type),
                  let superview = button.superview
            else {
                continue
            }

            let originInWindow = Self.buttonOriginInWindow(index: index, buttonHeight: button.bounds.height, windowHeight: frame.height, headerHeight: headerHeight)

            button.setFrameOrigin(superview.convert(originInWindow, from: nil))
        }
    }

    /// `windowButtonClearance(isFullScreen:)` is how far in from this window's leading edge page content must start to clear its own standard window buttons, measured from the button AppKit actually vends, or `nil` while AppKit vends none.
    ///
    /// `nil` is published as nothing at all rather than as a guess, which leaves the stylesheet's own fallback in force — see `WebViewController.appearanceAttributeScript(windowIsFullScreen:)`, which is the only caller.
    /// The zoom button is measured rather than the close button because all three are the same size and it is the one the clearance actually has to clear.
    func windowButtonClearance(isFullScreen: Bool) -> CGFloat? {
        guard let buttonWidth = standardWindowButton(.zoomButton)?.bounds.width else {
            return nil
        }

        return Self.windowButtonClearance(isFullScreen: isFullScreen, buttonWidth: buttonWidth)
    }

    /// `windowButtonClearance(isFullScreen:buttonWidth:)` is how far in from the leading edge page content must start to clear the standard window buttons, in points, and zero for a window in fullscreen.
    ///
    /// It is the horizontal counterpart of `buttonOriginInWindow(index:buttonHeight:windowHeight:headerHeight:)` and is derived from it rather than stated alongside it: the last button's leading edge comes from `buttonLeadingEdge(index:)`, so a change to where the buttons go moves what the page keeps clear of them in the same edit. `macOS/Cirruscope.css` used to state the sum a second time as a hand-tuned margin, which is the duplication issue #95 arrived as.
    /// Fullscreen answers zero because macOS relocates the buttons into the auto-revealing title bar there, exactly as `repositionControlButtons()` steps aside for. The page cannot decide that itself: CSS's `:fullscreen` is the Fullscreen API's pseudo-class, about an element the page put in the top layer, and says nothing about the window the page is in.
    /// It takes a `Bool` rather than a `NSWindow.StyleMask` — unlike `WebWindowFrame.isRecordable(styleMask:)`, which it otherwise resembles — because the callers that matter most are the two `NSWindowDelegate` hooks that know where a window is heading before AppKit has finished taking it there, and the instant AppKit flips that bit is undocumented. A caller that states the destination cannot be wrong about it.
    /// The clearance does not depend on the header's height; that is `buttonOriginInWindow(index:buttonHeight:windowHeight:headerHeight:)`'s input alone, and the two axes are independent.
    static func windowButtonClearance(isFullScreen: Bool, buttonWidth: CGFloat) -> CGFloat {
        guard isFullScreen == false else {
            return 0
        }

        return buttonLeadingEdge(index: buttonTypes.count - 1) + buttonWidth + trailingGap
    }

    /// `buttonOriginInWindow(index:buttonHeight:windowHeight:headerHeight:)` is where the window button at `index` belongs in window coordinates: laid out from the leading edge in the order the buttons are, and vertically centered in a header of `headerHeight` measured down from the top of a window of `windowHeight`.
    ///
    /// It is a pure function of its four inputs so the arithmetic can be exercised directly — `repositionControlButtons()` needs a live window and the standard buttons AppKit only vends to one — and that arithmetic is exactly where issue #102 lived: it was correct throughout and fed one wrong number. `WebWindowFrame.isRecordable(styleMask:)` is split out from its own caller for the same reason.
    /// Its horizontal half is `buttonLeadingEdge(index:)` and is shared with `windowButtonClearance(isFullScreen:buttonWidth:)`, so the placement and the clearance cannot drift apart.
    /// Nextcloud's header is `position: absolute; top: 0`, so measuring down from the window's top edge is the same as measuring down from the header's: the web view reaches that edge underneath the hidden title bar.
    static func buttonOriginInWindow(index: Int, buttonHeight: CGFloat, windowHeight: CGFloat, headerHeight: CGFloat) -> NSPoint {
        let topInset = (headerHeight - buttonHeight) / 2

        return NSPoint(x: buttonLeadingEdge(index: index), y: windowHeight - topInset - buttonHeight)
    }

    /// `buttonLeadingEdge(index:)` is where the window button at `index` starts, measured from the window's leading edge.
    ///
    /// It is the one expression in the app that answers that, read by `buttonOriginInWindow(index:buttonHeight:windowHeight:headerHeight:)` for the button it places and by `windowButtonClearance(isFullScreen:buttonWidth:)` for the last button the page has to clear.
    private static func buttonLeadingEdge(index: Int) -> CGFloat {
        leadingInset + CGFloat(index) * buttonSpacing
    }
}
