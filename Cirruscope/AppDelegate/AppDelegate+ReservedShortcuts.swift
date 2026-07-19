// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit

/// `AppDelegate`'s reserved-shortcut lookup tells `ShortcutRecorderView` and `AccountStore.shortcut(forAppID:)` whether a server app's recorded (or already-stored) shortcut collides with one of Cirruscope's own fixed menu items, since `AppDelegate` is the one that builds and owns the live menu bar those items live in.
extension AppDelegate {
    /// `reservedShortcutName(for:)` is the title of the first menu item anywhere in `NSApp.mainMenu`'s tree — other than a dynamically-inserted server app item — whose key equivalent `shortcut` collides with, or `nil` when it collides with none.
    ///
    /// A server app's shortcut can never shadow one of Cirruscope's own fixed menu items this way — including ones in a completely different menu than the View menu's server app section, since AppKit resolves a key equivalent against the whole menu bar, not just one submenu, and there is no reliable, documented tie-break for two enabled items that share one. Reading the live menu, rather than a hand-maintained duplicate of `Main.storyboard`'s shortcuts, means this can never drift out of sync with it, and reports the item's actual (already-localized) title for free.
    ///
    /// Dynamic server app items are recognized by their action, `performServerApp(_:)`, and skipped: otherwise an already-assigned server app shortcut would collide with its own menu item (or, once two apps briefly share a shortcut mid-edit, with each other) instead of only with Cirruscope's fixed ones.
    static func reservedShortcutName(for shortcut: AppShortcutTransferObject) -> String? {
        firstConflictingItem(in: NSApp.mainMenu, matching: normalized(shortcut))?.title
    }

    /// `firstConflictingItem(in:matching:)` recursively searches `menu` and its submenus for the first non-server-app item whose normalized key equivalent (see `normalized(_:)`) equals `candidate`, which the caller has already normalized the same way.
    private static func firstConflictingItem(in menu: NSMenu?, matching candidate: AppShortcutTransferObject) -> NSMenuItem? {
        guard let menu else {
            return nil
        }

        for item in menu.items {
            if let hit = firstConflictingItem(in: item.submenu, matching: candidate) {
                return hit
            }

            guard item.action != #selector(performServerApp(_:)),
                  item.keyEquivalent.isEmpty == false
            else {
                continue
            }

            let itemShortcut = AppShortcutTransferObject(keyEquivalent: item.keyEquivalent, modifierFlags: item.keyEquivalentModifierMask.rawValue)

            if normalized(itemShortcut) == candidate {
                return item
            }
        }

        return nil
    }

    /// `normalized(_:)` strips Shift from `shortcut`'s modifiers, but deliberately leaves its key equivalent's case untouched.
    ///
    /// Confirmed directly against real `NSMenu`/`NSMenuItem` matching: an explicit `.shift` bit in `keyEquivalentModifierMask` plays no part in whether an event matches — AppKit derives Shift entirely from the key equivalent character itself (an uppercase letter, or whichever character Shift actually produces), so it must be stripped here for comparison purposes. But that also means case is the *only* signal distinguishing e.g. "Redo" (keyEquivalent `"Z"`, `.command` only) from "Undo" (`"z"`, `.command`) — lowercasing away that distinction, as an earlier version of this method did, collapsed the two into one, so recording ⇧⌘Z incorrectly reported a conflict with "Undo" instead of "Redo". `ShortcutRecorderView.handle(...)` correspondingly records the character exactly as `charactersIgnoringModifiers` produced it (never lowercased), so both sides of this comparison preserve case the same way.
    private static func normalized(_ shortcut: AppShortcutTransferObject) -> AppShortcutTransferObject {
        AppShortcutTransferObject(keyEquivalent: shortcut.keyEquivalent, modifierFlags: shortcut.modifierMask.subtracting(.shift).rawValue)
    }
}
