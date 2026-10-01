// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

extension SchemaV2_1 {
    /// `KeyboardShortcut` is the v2.1 record for a keyboard shortcut: the v2 record, still hanging off its `ServerApp`, with room for the identifier of the app it opens.
    ///
    /// It is a frozen copy; see `SchemaV2_1` for why this intermediate schema exists and why it never changes.
    @Model
    final class KeyboardShortcut {
        /// `appID` is the identifier of the app this shortcut opens, `nil` until the stage into `SchemaV3` copies it off `app`; optional and not unique, so adding it is a change SwiftData infers.
        var appID: String?

        /// `keyEquivalent` is the character that triggers the shortcut.
        var keyEquivalent: String

        /// `modifierFlags` is the raw value of the `NSEvent.ModifierFlags` required by the shortcut.
        var modifierFlags: UInt

        /// `app` is the server app this shortcut belongs to; it is the inverse of `ServerApp.shortcut`.
        var app: ServerApp?

        init(appID: String? = nil, keyEquivalent: String, modifierFlags: UInt, app: ServerApp? = nil) {
            self.appID = appID
            self.keyEquivalent = keyEquivalent
            self.modifierFlags = modifierFlags
            self.app = app
        }
    }
}
