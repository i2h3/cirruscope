// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit
@testable import Cirruscope

/// `KeyEquivalentProbe` answers what real AppKit does with a key equivalent: whether an `NSMenuItem` declaring one shortcut fires for the keystroke behind another.
@MainActor
final class KeyEquivalentProbe: NSObject {
    /// `didFire` is `true` once the menu item's action reached this probe, meaning AppKit considered the event a match for the item's key equivalent.
    private var didFire = false

    @objc
    private func fire(_: Any?) {
        didFire = true
    }

    /// `fires(keystroke:againstItemDeclaring:)` is `true` when a menu item declaring `item` is triggered by the keystroke a user pressing `keystroke` produces.
    static func fires(keystroke: KeyboardShortcutTransferObject, againstItemDeclaring item: KeyboardShortcutTransferObject) -> Bool {
        let probe = KeyEquivalentProbe()
        let menu = NSMenu()
        menu.autoenablesItems = false

        let menuItem = NSMenuItem(title: "Probe", action: #selector(fire(_:)), keyEquivalent: item.keyEquivalent)
        menuItem.keyEquivalentModifierMask = item.modifierMask
        menuItem.target = probe
        menuItem.isEnabled = true
        menu.addItem(menuItem)

        menu.performKeyEquivalent(with: keyDown(for: keystroke))
        return probe.didFire
    }

    /// `keyDown(for:)` synthesizes the key-down event AppKit would deliver for `shortcut`.
    private static func keyDown(for shortcut: KeyboardShortcutTransferObject) -> NSEvent {
        var flags = shortcut.modifierMask

        if ShortcutMatching.isFunctionRegionKey(shortcut.keyEquivalent) {
            flags.insert(.function)
        }

        // Force-unwrapped deliberately: these arguments are always a valid key-down event, and a `nil` here is a
        // broken probe rather than a test expectation worth reporting through.
        return NSEvent.keyEvent(with: .keyDown,
                                location: .zero,
                                modifierFlags: flags,
                                timestamp: 0,
                                windowNumber: 0,
                                context: nil,
                                characters: shortcut.keyEquivalent,
                                charactersIgnoringModifiers: shortcut.keyEquivalent,
                                isARepeat: false,
                                keyCode: 0)!
    }
}
