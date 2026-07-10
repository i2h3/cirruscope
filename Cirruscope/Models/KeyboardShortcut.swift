// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit

/// `KeyboardShortcut` is a user-assigned key equivalent for a `ServerApp`, persisted in `Settings.appShortcuts` and applied to the app's menu items.
///
/// It stores the key equivalent character and the raw value of the `NSEvent.ModifierFlags` so it round-trips through `UserDefaults` as JSON; `ShortcutRecorderView` produces it and the menu builder applies it to `NSMenuItem.keyEquivalent` and `keyEquivalentModifierMask`.
struct KeyboardShortcut: Codable, Equatable {
    /// `keyEquivalent` is the character that triggers the shortcut, as assigned to `NSMenuItem.keyEquivalent`.
    let keyEquivalent: String

    /// `modifierFlags` is the raw value of the `NSEvent.ModifierFlags` required by the shortcut, assigned (via `modifierMask`) to `NSMenuItem.keyEquivalentModifierMask`.
    let modifierFlags: UInt

    /// `modifierMask` reconstructs the `NSEvent.ModifierFlags` from `modifierFlags` for assignment to a menu item.
    var modifierMask: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags)
    }
}
