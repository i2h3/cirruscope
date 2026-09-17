// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// `SchemaV2` is the versioned schema of Cirruscope's SwiftData store exactly as it shipped in the `1.1.0` App Store build: identical to `SchemaV1` except that the `AppShortcut` record is renamed to `KeyboardShortcut`, and `Account` gains the two appearance choices.
///
/// Like `SchemaV1` it is a frozen historical snapshot and must never change: its model definitions describe the store on disk for every user who installed `1.1.0`, so `CirruscopeMigrationPlan` can read that store and migrate it forward. Its models are frozen copies rather than the app's live top-level types for the same reason `SchemaV1`'s are — the live types are free to evolve, and a version whose definition moves with them describes no store at all. They are nested in this enum so their Swift type names (`SchemaV2.Account`, …) do not collide with the live ones while the entity names SwiftData records stay exactly what the shipped store contains. Each nested model lives in its own `SchemaV2+<Model>.swift` extension file.
///
/// The freeze happened after `1.1.0` shipped rather than before, which is why the version identifier is untouched: the models nested here are byte-for-byte the live models at that tag, so the identity this schema claims is the identity the stores in the field carry. Never edit these types or the version identifier; introduce changes in a new `SchemaV{n}` and a migration stage instead.
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Account.self, ServerApp.self, KeyboardShortcut.self]
    }
}
