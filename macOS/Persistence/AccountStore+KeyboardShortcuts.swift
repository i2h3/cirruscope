// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `AccountStore`'s macOS half: the reads that decide which app a keystroke actually reaches.
extension AccountStore {
    /// `appHolding(_:)` is the one app a keystroke matching `shortcut` actually reaches — the first entry in `storedShortcuts` carrying an equivalent shortcut — or `nil` when no app carries it at all.
    private func appHolding(_ shortcut: KeyboardShortcutTransferObject) -> (appID: String, name: String, shortcut: KeyboardShortcutTransferObject)? {
        storedShortcuts.first { ShortcutMatching.areEquivalent($0.shortcut, shortcut) }
    }

    /// `shortcut(forAppID:)` is the keyboard shortcut that reaches the app with `appID`, or `nil` when none is recorded, the connected server does not offer the app, the recorded shortcut collides with one of Cirruscope's own reserved shortcuts (see `AppDelegate.reservedShortcutName(for:)`), or another offered app already holds the same one (see `appHolding(_:)`).
    func shortcut(forAppID appID: String) -> KeyboardShortcutTransferObject? {
        guard serverApp(forID: appID) != nil else {
            return nil
        }

        guard let shortcut = storedShortcut(forAppID: appID) else {
            return nil
        }

        guard isReservedShortcut(shortcut) == false else {
            return nil
        }

        // Honour a shortcut two apps share for the first of them only, so one keystroke never reaches two equally
        // enabled menu items, between which AppKit has no reliable, documented tie-break.
        guard appHolding(shortcut)?.appID == appID else {
            return nil
        }

        return shortcut
    }

    /// `nameOfApp(usingShortcut:otherThanAppID:)` is the name of the server app that the same keystroke as `shortcut` already reaches, or `nil` when that app is the one with `appID` itself or no app holds the combination.
    func nameOfApp(usingShortcut shortcut: KeyboardShortcutTransferObject, otherThanAppID appID: String) -> String? {
        guard let holder = appHolding(shortcut) else {
            return nil
        }

        return holder.appID == appID ? nil : holder.name
    }
}
