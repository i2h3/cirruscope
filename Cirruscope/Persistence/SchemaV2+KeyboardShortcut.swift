// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

extension SchemaV2 {
    /// `KeyboardShortcut` is the v2 record for the keyboard shortcut a user assigns to a `ServerApp`; it is what the v1 `AppShortcut` record is renamed to, and `CirruscopeMigrationPlan` copies each row across that rename.
    @Model
    final class KeyboardShortcut {
        /// `keyEquivalent` is the character that triggers the shortcut.
        var keyEquivalent: String

        /// `modifierFlags` is the raw value of the `NSEvent.ModifierFlags` required by the shortcut.
        var modifierFlags: UInt

        /// `app` is the server app this shortcut belongs to; it is the inverse of `ServerApp.shortcut`.
        var app: ServerApp?

        init(keyEquivalent: String, modifierFlags: UInt, app: ServerApp? = nil) {
            self.keyEquivalent = keyEquivalent
            self.modifierFlags = modifierFlags
            self.app = app
        }
    }
}
