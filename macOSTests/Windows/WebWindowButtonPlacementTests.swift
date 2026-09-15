// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
@testable import Cirruscope
import Testing

/// `WebWindowButtonPlacementTests` covers `WebWindow.buttonOriginInWindow(index:buttonHeight:windowHeight:headerHeight:)`, which decides where the close, miniaturize, and zoom buttons go inside Nextcloud's header bar.
///
/// This is where issue #102 lived, and the reason it is worth pinning: the arithmetic was correct throughout and was fed one wrong number — a compiled-in 50 points, Nextcloud server 34's header height, kept after server 35 changed it to 44. So the cases assert the property that made the wrong number visible rather than the coordinates it produced: a button's vertical center coincides with the header's, whatever the header's height and whatever the button's own. A version-shaped constant cannot satisfy that for two different heights, which is what makes it the right assertion for this regression.
///
/// The placement is exercised through this pure function rather than through `repositionControlButtons()`, which needs a live window and the standard buttons AppKit vends only to one. `leadingInset` and `buttonSpacing` stay private, so the horizontal case asserts that the three buttons are evenly spaced in the order they are laid out, rather than restating the two numbers it would then be measuring against themselves.
///
/// The suite is `@MainActor` because `WebWindow` inherits that isolation from `NSResponder`, its static members included.
@MainActor
struct WebWindowButtonPlacementTests {
    /// `buttonHeights` are the heights the case matrix covers: AppKit draws the standard window buttons at 16 points today, and the surrounding cases guard against the placement rule quietly depending on that.
    ///
    /// It is `nonisolated` because Swift Testing evaluates an `@Test(arguments:)` expression outside the suite's own isolation, so a main-actor-isolated fixture is unreachable from there; a `let` of a `Sendable` type may say so without further ceremony.
    private nonisolated static let buttonHeights: [CGFloat] = [12, 14, 16, 20]

    /// `headerHeights` are the header heights the case matrix covers: the two current servers declare — 50 points on Nextcloud 34, 44 on 35 — plus both ends of the range `NextcloudHeaderHeight` believes at all.
    ///
    /// It is `nonisolated` for the same reason as `buttonHeights`.
    private nonisolated static let headerHeights: [CGFloat] = [20, 44, 50, 120]

    @Test(arguments: buttonHeights, headerHeights)
    func `A window button is vertically centered in the header whatever either of them measures`(buttonHeight: CGFloat, headerHeight: CGFloat) {
        let windowHeight: CGFloat = 800
        let origin = WebWindow.buttonOriginInWindow(index: 0, buttonHeight: buttonHeight, windowHeight: windowHeight, headerHeight: headerHeight)

        // The window's coordinate system has its origin at the bottom, while the header is measured down from the
        // top, so the header's own center sits `headerHeight / 2` below the top edge.
        #expect(origin.y + buttonHeight / 2 == windowHeight - headerHeight / 2)
    }

    @Test(arguments: headerHeights)
    func `All three window buttons share one vertical position`(headerHeight: CGFloat) {
        let origins = (0 ..< 3).map { WebWindow.buttonOriginInWindow(index: $0, buttonHeight: 16, windowHeight: 800, headerHeight: headerHeight) }

        #expect(origins[1].y == origins[0].y)
        #expect(origins[2].y == origins[0].y)
    }

    @Test
    func `The three window buttons are evenly spaced in the order they are laid out`() {
        let origins = (0 ..< 3).map { WebWindow.buttonOriginInWindow(index: $0, buttonHeight: 16, windowHeight: 800, headerHeight: 44) }

        #expect(origins[0].x < origins[1].x)
        #expect(origins[1].x < origins[2].x)
        #expect(origins[1].x - origins[0].x == origins[2].x - origins[1].x)
    }

    @Test
    func `The placement does not depend on the header height for its horizontal position`() {
        let inShortHeader = WebWindow.buttonOriginInWindow(index: 2, buttonHeight: 16, windowHeight: 800, headerHeight: 44)
        let inTallHeader = WebWindow.buttonOriginInWindow(index: 2, buttonHeight: 16, windowHeight: 800, headerHeight: 50)

        #expect(inShortHeader.x == inTallHeader.x)
        #expect(inShortHeader.y != inTallHeader.y)
    }
}
