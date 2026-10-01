// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// `SchemaV2_1` is an intermediate versioned schema that no build ever runs on: `SchemaV2` with an optional `appID` on `KeyboardShortcut` and a `DevicePreferences` entity added, both changes SwiftData infers.
///
/// It exists so that moving the keyboard shortcuts and the appearance choices out of the account never holds them only in memory. `CirruscopeMigrationPlan` first carries a v2 store here, which adds the empty column and the empty entity on disk; the stage into `SchemaV3` then writes each shortcut's app identifier into that column and the appearance choices into that entity and saves, all before the schema change that drops the relationship and the account's attributes. A store that fails or is interrupted anywhere along the way is left with the user's choices still in it, rather than in a process that is gone.
///
/// Its models are nested copies for the reason `SchemaV2`'s are, and it is frozen from the start, since stores in the field pass through it: never edit these types or the version identifier.
enum SchemaV2_1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 1, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Account.self, ServerApp.self, KeyboardShortcut.self, DevicePreferences.self]
    }
}
