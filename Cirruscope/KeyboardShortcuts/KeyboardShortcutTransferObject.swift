// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `KeyboardShortcutTransferObject` is a value-type snapshot of a user-assigned key equivalent for a server app, persisted by `AccountStore` as a `KeyboardShortcut`.
///
/// It stores the key equivalent character and the raw value of the modifier flags; on macOS `ShortcutRecorderView` produces it and the menu builder applies it to a menu item. It is `Sendable` so it can cross actors without exposing a managed `@Model` object.
///
/// It is shared rather than macOS-only, and holds no AppKit type, because `AccountStore` is compiled into both apps and carries this in the seam it consults to decide whether a shortcut is already spoken for. Turning the stored flags back into an `NSEvent.ModifierFlags` is the one thing here that needs AppKit, and that lives in `KeyboardShortcutTransferObject+AppKit.swift` beside the code that assigns it to a menu item. iOS compiles the value and never builds one: there is no menu bar to assign a key equivalent to.
struct KeyboardShortcutTransferObject: Codable, Equatable, Sendable {
    /// `keyEquivalent` is the character that triggers the shortcut.
    let keyEquivalent: String

    /// `modifierFlags` is the raw value of the modifier flags required by the shortcut.
    let modifierFlags: UInt
}
