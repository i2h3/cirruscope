// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
import os

/// `WebWindowFrame` remembers how large the user last made a web window, so the next one opens at that size instead of the fixed one the storyboard declares.
enum WebWindowFrame {
    /// `logger` records this facility's activity under the `WebWindowFrame` category.
    private static let logger = Logger(for: WebWindowFrame.self)

    /// `defaultName` is the AppKit frame name every web window shares, and therefore the one remembered size they all open at.
    ///
    /// It is shared rather than per server app on purpose; see DECISIONS.md → "Why do all web windows share one remembered size?".
    static let defaultName = "WebWindow"

    /// `isRecordable(styleMask:)` reports whether a window carrying `styleMask` has a frame worth remembering, which is every state but fullscreen.
    static func isRecordable(styleMask: NSWindow.StyleMask) -> Bool {
        styleMask.contains(.fullScreen) == false
    }

    /// `record(_:name:)` remembers `window`'s frame under `name`, unless the window is in fullscreen.
    @MainActor
    static func record(_ window: NSWindow, name: String = defaultName) {
        guard isRecordable(styleMask: window.styleMask) else {
            logger.debug("Not recording the frame of a fullscreen web window")
            return
        }

        window.saveFrame(usingName: name)
        logger.debug("Recorded web window size \(Int(window.frame.width)) × \(Int(window.frame.height))")
    }

    /// `applySize(to:name:)` resizes `window` to the size remembered under `name`, leaving it exactly where it already is, and does nothing when no size has been remembered yet.
    @MainActor
    static func applySize(to window: NSWindow, name: String = defaultName) {
        let origin = window.frame.origin

        guard window.setFrameUsingName(name) else {
            logger.debug("No web window size remembered yet; leaving the new window at its storyboard size")
            return
        }

        window.setFrameOrigin(origin)
        logger.debug("Applied remembered web window size \(Int(window.frame.width)) × \(Int(window.frame.height))")
    }
}
