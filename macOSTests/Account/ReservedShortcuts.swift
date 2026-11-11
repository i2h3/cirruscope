// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope

/// `ReservedShortcuts` builds the stand-in a macOS account suite hands `AccountStoreHarness` for the reserved-shortcut lookup.
enum ReservedShortcuts {
    /// `claiming(_:)` answers that a shortcut is reserved when one of `reserved` would be triggered by the same keystroke.
    static func claiming(_ reserved: [KeyboardShortcutTransferObject]) -> @MainActor (KeyboardShortcutTransferObject) -> Bool {
        { shortcut in
            reserved.contains { ShortcutMatching.areEquivalent($0, shortcut) }
        }
    }
}
