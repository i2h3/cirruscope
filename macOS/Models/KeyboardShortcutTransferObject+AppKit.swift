// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit

/// This extension turns the flags a stored shortcut carries back into the AppKit type a menu item is assigned.
///
/// It is macOS's half of a value type the two apps share: the shortcut itself is plain data and lives in `Cirruscope/`, while `NSEvent.ModifierFlags` is AppKit and could not follow it there. iOS assigns no key equivalent to a server app, the iPad's View menu included, so it needs nothing from this file.
extension KeyboardShortcutTransferObject {
    /// `modifierMask` reconstructs the `NSEvent.ModifierFlags` from `modifierFlags` for assignment to `NSMenuItem.keyEquivalentModifierMask`.
    var modifierMask: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags)
    }
}
