// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit

/// This extension turns the flags a stored shortcut carries back into the AppKit type a menu item is assigned.
extension KeyboardShortcutTransferObject {
    /// `modifierMask` reconstructs the `NSEvent.ModifierFlags` from `modifierFlags` for assignment to `NSMenuItem.keyEquivalentModifierMask`.
    var modifierMask: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags)
    }
}
