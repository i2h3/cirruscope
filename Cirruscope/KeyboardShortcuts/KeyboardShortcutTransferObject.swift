// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `KeyboardShortcutTransferObject` is a value-type snapshot of a user-assigned key equivalent for a server app, persisted by `AccountStore` as a `KeyboardShortcut`.
struct KeyboardShortcutTransferObject: Codable, Equatable, Sendable {
    /// `keyEquivalent` is the character that triggers the shortcut.
    let keyEquivalent: String

    /// `modifierFlags` is the raw value of the modifier flags required by the shortcut.
    let modifierFlags: UInt
}
