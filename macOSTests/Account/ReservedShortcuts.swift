// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope

/// `ReservedShortcuts` builds the stand-in a macOS account suite hands `AccountStoreHarness` for the reserved-shortcut lookup.
///
/// It exists on this side alone because the comparison it makes is `ShortcutMatching.areEquivalent(_:_:)`, which is a measured statement about how AppKit matches key equivalents and could not follow the harness into the folder both test targets compile. Stating it once here rather than in each suite is what keeps two suites from disagreeing about what "already reserved" means — the same reason the app has one `ShortcutMatching` rather than a comparison per caller.
enum ReservedShortcuts {
    /// `claiming(_:)` answers that a shortcut is reserved when one of `reserved` would be triggered by the same keystroke.
    ///
    /// Equivalence rather than equality, so that reserving ⌘Z also reserves ⇧⌘Z, exactly as `AppDelegate.reservedShortcutName(for:)` does against a real menu item.
    static func claiming(_ reserved: [KeyboardShortcutTransferObject]) -> @MainActor (KeyboardShortcutTransferObject) -> Bool {
        { shortcut in
            reserved.contains { ShortcutMatching.areEquivalent($0, shortcut) }
        }
    }
}
