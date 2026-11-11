// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit

/// `AppDelegate`'s reserved-shortcut lookup tells `ShortcutRecorderView` and `AccountStore.shortcut(forAppID:)` whether a server app's recorded (or already-stored) shortcut collides with one of Cirruscope's own fixed menu items, since `AppDelegate` is the one that builds and owns the live menu bar those items live in.
extension AppDelegate {
    /// `reservedShortcutName(for:)` is the title of the first menu item anywhere in `NSApp.mainMenu`'s tree — other than a dynamically-inserted server app item — whose key equivalent `shortcut` collides with, or `nil` when it collides with none.
    static func reservedShortcutName(for shortcut: KeyboardShortcutTransferObject) -> String? {
        firstConflictingItem(in: NSApp.mainMenu, matching: shortcut)?.title
    }

    /// `firstConflictingItem(in:matching:)` recursively searches `menu` and its submenus for the first non-server-app item whose key equivalent `candidate` collides with, per `ShortcutMatching.areEquivalent(_:_:)`.
    private static func firstConflictingItem(in menu: NSMenu?, matching candidate: KeyboardShortcutTransferObject) -> NSMenuItem? {
        guard let menu else {
            return nil
        }

        for item in menu.items {
            if let hit = firstConflictingItem(in: item.submenu, matching: candidate) {
                return hit
            }

            guard item.action != #selector(performServerApp(_:)), item.keyEquivalent.isEmpty == false
            else {
                continue
            }

            let itemShortcut = KeyboardShortcutTransferObject(keyEquivalent: item.keyEquivalent, modifierFlags: item.keyEquivalentModifierMask.rawValue)

            if ShortcutMatching.areEquivalent(itemShortcut, candidate) {
                return item
            }
        }

        return nil
    }
}
