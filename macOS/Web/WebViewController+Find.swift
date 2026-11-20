// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit

/// `WebViewController`'s find actions forward to the auxiliary find bar window: the Edit menu's Find items target the first responder, so they land here while the web window is key and on `FindBarViewController` while the find panel is key.
extension WebViewController {
    /// `showFindBar(_:)` backs the Edit menu's "Find…" item while the web window is key.
    @IBAction
    func showFindBar(_: Any?) {
        findBarWindowController()?.findBarViewController?.showFindBar(nil)
    }

    /// `findNext(_:)` backs the Edit menu's "Find Next" item while the web window is key.
    @IBAction
    func findNext(_: Any?) {
        findBarWindowController()?.findBarViewController?.findNext(nil)
    }

    /// `findPrevious(_:)` backs the Edit menu's "Find Previous" item while the web window is key.
    @IBAction
    func findPrevious(_: Any?) {
        findBarWindowController()?.findBarViewController?.findPrevious(nil)
    }
}
