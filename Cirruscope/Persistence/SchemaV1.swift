// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// `SchemaV1` is the initial versioned schema of Cirruscope's SwiftData store.
///
/// Anchoring the schema to an explicit version from the first shipped build gives future schema changes a defined starting point: additive changes (new optional properties, new models) migrate automatically, and only a genuinely complex change later needs a `SchemaMigrationPlan` built on top of this version.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Account.self, ServerApp.self, AppShortcut.self]
    }
}
