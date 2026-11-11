// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

extension SchemaV3 {
    /// `KeyboardShortcut` is the v3 record for a keyboard shortcut keyed by its app's identifier exactly as it shipped in `1.2.0` and `1.2.1`.
    ///
    /// It is a frozen copy; see `SchemaV3` for why it never changes.
    @Model
    final class KeyboardShortcut {
        /// `appID` is the Nextcloud app identifier (e.g. `"files"`) this shortcut opens, unique among the shortcuts so there is at most one per app.
        ///
        /// It carries a default value only so the schema change that made it required has one to infer; every record is created with an identifier, and the migration fills the identifier into every row it keeps before that change applies.
        @Attribute(.unique)
        var appID: String = ""

        /// `keyEquivalent` is the character that triggers the shortcut, as assigned to `NSMenuItem.keyEquivalent`.
        var keyEquivalent: String

        /// `modifierFlags` is the raw value of the `NSEvent.ModifierFlags` required by the shortcut.
        var modifierFlags: UInt

        init(appID: String, keyEquivalent: String, modifierFlags: UInt) {
            self.appID = appID
            self.keyEquivalent = keyEquivalent
            self.modifierFlags = modifierFlags
        }
    }
}
