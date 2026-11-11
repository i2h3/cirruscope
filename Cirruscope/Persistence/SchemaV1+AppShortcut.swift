// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

extension SchemaV1 {
    /// `AppShortcut` is the v1 record for the keyboard shortcut a user assigns to a `ServerApp`; it is renamed to `KeyboardShortcut` in `SchemaV2`, and `CirruscopeMigrationPlan` copies each row across that rename.
    @Model
    final class AppShortcut {
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
