// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit

/// `ShortcutMatching` is the single definition of when two key equivalents mean the same keystroke to AppKit, so every conflict check in the app agrees on it.
enum ShortcutMatching {
    /// `areEquivalent(_:_:)` is `true` when AppKit's key-equivalent matching cannot tell `one` and `other` apart, so a single keystroke would trigger both.
    static func areEquivalent(_ one: KeyboardShortcutTransferObject, _ other: KeyboardShortcutTransferObject) -> Bool {
        one.keyEquivalent == other.keyEquivalent && matchedModifiers(of: one) == matchedModifiers(of: other)
    }

    /// `matchedModifiers(of:)` is the part of `shortcut`'s modifier mask that AppKit actually matches an event against: its mask as-is for a function-region key, and its mask without Shift for every other key equivalent.
    private static func matchedModifiers(of shortcut: KeyboardShortcutTransferObject) -> NSEvent.ModifierFlags {
        isFunctionRegionKey(shortcut.keyEquivalent) ? shortcut.modifierMask : shortcut.modifierMask.subtracting(.shift)
    }

    /// `isFunctionRegionKey(_:)` is `true` when `keyEquivalent` is one of the function-region keys, which AppKit represents as a single scalar from the Unicode Private Use Area block `NSUpArrowFunctionKey` (U+F700) onwards rather than as a typable character.
    static func isFunctionRegionKey(_ keyEquivalent: String) -> Bool {
        guard keyEquivalent.unicodeScalars.count == 1 else {
            return false
        }

        guard let scalar = keyEquivalent.unicodeScalars.first else {
            return false
        }

        return (0xF700 ... 0xF8FF).contains(scalar.value)
    }
}
