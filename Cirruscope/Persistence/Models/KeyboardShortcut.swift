// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// `KeyboardShortcut` is the SwiftData record for the keyboard shortcut a user assigns to a Nextcloud server app on this device, keyed by that app's identifier.
///
/// It is the persistent counterpart of the value-type `KeyboardShortcutTransferObject` DTO; `AccountStore` maps between them. It belongs to the device rather than to an account or a server: it has no relationship to either, so a sign-out, an app-list refresh pruning the app, or signing in to a different server leaves it in place, and it applies again whenever the connected server offers an app with this identifier.
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
