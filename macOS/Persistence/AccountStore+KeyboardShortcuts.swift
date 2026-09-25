// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `AccountStore`'s macOS half: the reads that decide which app a keystroke actually reaches.
///
/// They are here rather than with the rest of the store because each of them compares two shortcuts through `ShortcutMatching`, and that comparison is a measured statement about how AppKit matches key equivalents against a real `NSMenu` — AppKit, and so unusable from a folder the iOS app also compiles. The storage half of the same domain stayed behind: reading a stored shortcut out of a record and writing one back needs nothing but the record.
///
/// This is the split `Core/ServerConnection.swift` and `ServerConnection+AccountStore` already make, applied within one type rather than across two: what can be shared is, and what names a platform framework sits beside the platform that has it. iOS has no menu bar, so nothing there asks which app a keystroke reaches, and `isReservedShortcut` correspondingly answers that nothing is.
extension AccountStore {
    /// `appHolding(_:)` is the one app a keystroke matching `shortcut` actually reaches — the first entry in `storedShortcuts` carrying an equivalent shortcut — or `nil` when no app carries it at all.
    ///
    /// Answering both `shortcut(forAppID:)` and `nameOfApp(usingShortcut:otherThanAppID:)` from this same entry is what keeps the two from contradicting each other where a duplicate is stored: were the latter to consider every stored shortcut instead, an app whose duplicate the former suppresses would still be named as the occupant of a combination the settings tab shows as unassigned for it, and the app visibly holding that combination could not even re-record it.
    private func appHolding(_ shortcut: KeyboardShortcutTransferObject) -> (appID: String, name: String, shortcut: KeyboardShortcutTransferObject)? {
        storedShortcuts.first { ShortcutMatching.areEquivalent($0.shortcut, shortcut) }
    }

    /// `shortcut(forAppID:)` is the user's keyboard shortcut for the app with `appID`, or `nil` when none is assigned, the app is unknown, the stored shortcut collides with one of Cirruscope's own reserved shortcuts (see `AppDelegate.reservedShortcutName(for:)`), or another app already holds the same one (see `appHolding(_:)`).
    ///
    /// Both collisions can only come from data recorded before their respective checks existed, since `ShortcutRecorderView` now refuses to record either going forward; suppressing them here as well means such a shortcut is not applied to a menu item — and is shown as unassigned in the settings tab, so the user can see it is not in effect and record another — rather than being deleted behind the user's back.
    func shortcut(forAppID appID: String) -> KeyboardShortcutTransferObject? {
        guard let stored = currentAccount(createIfNeeded: false)?.apps.first(where: { $0.appID == appID })?.shortcut else {
            return nil
        }

        let shortcut = KeyboardShortcutTransferObject(keyEquivalent: stored.keyEquivalent, modifierFlags: stored.modifierFlags)

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
    ///
    /// `ServerAppsViewController` hands it to each row's `ShortcutRecorderView` as its `conflictingAppName`, so a combination another app already uses is rejected while recording — naming that app — instead of leaving two menu items to share one key equivalent, exactly as `AppDelegate.reservedShortcutName(for:)` does for Cirruscope's own fixed items. Excluding the app being edited is what lets a row re-record the shortcut it already displays without being told it conflicts with itself.
    func nameOfApp(usingShortcut shortcut: KeyboardShortcutTransferObject, otherThanAppID appID: String) -> String? {
        guard let holder = appHolding(shortcut) else {
            return nil
        }

        return holder.appID == appID ? nil : holder.name
    }
}
