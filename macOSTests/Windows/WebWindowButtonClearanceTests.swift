// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
@testable import Cirruscope
import Testing

/// `WebWindowButtonClearanceTests` covers `WebWindow.windowButtonClearance(isFullScreen:buttonWidth:)`, which decides how far in from the leading edge Nextcloud's header must start so the close, miniaturize, and zoom buttons do not overlap its own controls.
///
/// This is where issue #95 lived, and it is the same shape as issue #102 one axis over: the arithmetic was correct and was written out twice, once here and once as a hand-tuned `margin-left: 90px` in `macOS/Cirruscope.css` — a file with no way of noticing a change to the constants the buttons are laid out from, and no way of noticing native fullscreen either, where macOS moves those buttons into the auto-revealing title bar and the header needs no clearance at all. So the cases below assert the properties a second copy of a sum cannot hold: that fullscreen answers nothing, that whatever is answered leaves the last button behind it, and that the button's own width is a real input rather than decoration.
///
/// One literal survives that deduplication and cannot be removed — `Cirruscope.css` must declare a `:root` fallback, a `var()` reference to an unset custom property being invalid at computed-value time — so the last case measures a real AppKit window button and pins the function's answer for an ordinary window to exactly the number the stylesheet falls back to. That follows AGENTS.md → "When the code assumes something about a framework, test the framework": the width is asked of AppKit rather than restated here.
///
/// The rule takes a `Bool` rather than a style mask, unlike `WebWindowFrame.isRecordable(styleMask:)`, so none of this needs a window in fullscreen — which `WebWindowFrameTests` records is not something a test may ask for.
///
/// The suite is `@MainActor` because `WebWindow` inherits that isolation from `NSResponder`, its static members included.
@MainActor
struct WebWindowButtonClearanceTests {
    /// `buttonWidths` are the widths the case matrix covers: AppKit draws the standard window buttons at 14 points today, and the surrounding cases guard against the clearance quietly depending on that.
    ///
    /// It is `nonisolated` because Swift Testing evaluates an `@Test(arguments:)` expression outside the suite's own isolation, so a main-actor-isolated fixture is unreachable from there; a `let` of a `Sendable` type may say so without further ceremony.
    private nonisolated static let buttonWidths: [CGFloat] = [10, 14, 16, 20]

    /// `windowStyleMask` is the mask the storyboard's "Web Window" scene declares, which is what an ordinary web window is measured as.
    ///
    /// It is `nonisolated` for the same reason as `buttonWidths`.
    private nonisolated static let windowStyleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]

    /// `styleSheetFallbackClearance` is the `--cirruscope-window-button-clearance` value `macOS/Cirruscope.css` declares on `:root`, which is in force until Swift has run against a document.
    ///
    /// It is `nonisolated` for the same reason as `buttonWidths`.
    private nonisolated static let styleSheetFallbackClearance: CGFloat = 90

    @Test(arguments: buttonWidths)
    func `A window in full screen needs no clearance at all`(buttonWidth: CGFloat) {
        #expect(WebWindow.windowButtonClearance(isFullScreen: true, buttonWidth: buttonWidth) == 0)
    }

    @Test(arguments: buttonWidths)
    func `The clearance leaves the last window button behind it`(buttonWidth: CGFloat) {
        let clearance = WebWindow.windowButtonClearance(isFullScreen: false, buttonWidth: buttonWidth)

        // The zoom button is the last of the three, so where it ends is what the header has to start after. Asking
        // the placement for it rather than restating `leadingInset` and `buttonSpacing` is the point of the case:
        // moving the buttons without moving the clearance fails here, which is what a second copy of the sum could
        // never do. The header height is the placement's own input and does not reach the clearance at all.
        let lastButtonTrailingEdge = WebWindow.buttonOriginInWindow(index: 2, buttonHeight: 16, windowHeight: 800, headerHeight: 44).x + buttonWidth

        #expect(clearance > lastButtonTrailingEdge)
    }

    @Test(arguments: buttonWidths)
    func `A wider window button pushes the clearance out by exactly as much`(buttonWidth: CGFloat) {
        let clearance = WebWindow.windowButtonClearance(isFullScreen: false, buttonWidth: buttonWidth)
        let wider = WebWindow.windowButtonClearance(isFullScreen: false, buttonWidth: buttonWidth + 1)

        #expect(wider - clearance == 1)
    }

    @Test
    func `The clearance the stylesheet falls back to is the one a real window button produces`() throws {
        // AppKit vends a standard window button for a style mask without a window, which is the only way to measure
        // what it actually draws without opening one. Should this case fail, the number to correct is the :root
        // declaration of --cirruscope-window-button-clearance in macOS/Cirruscope.css, and the gap the function adds
        // past the button, so that the two still agree — not the assertion.
        let button = try #require(NSWindow.standardWindowButton(.zoomButton, for: Self.windowStyleMask))

        #expect(WebWindow.windowButtonClearance(isFullScreen: false, buttonWidth: button.bounds.width) == Self.styleSheetFallbackClearance)
    }
}
