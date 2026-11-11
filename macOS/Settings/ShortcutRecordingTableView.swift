// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit

/// `ShortcutRecordingTableView` is the "Keyboard Shortcuts" settings table's `NSTableView`, overridden only so its `ShortcutRecorderView` cells can become first responder from a plain click.
class ShortcutRecordingTableView: NSTableView {
    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        if responder is ShortcutRecorderView {
            return true
        }

        return super.validateProposedFirstResponder(responder, for: event)
    }
}
