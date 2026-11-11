// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// `SchemaV2` is the versioned schema of Cirruscope's SwiftData store exactly as it shipped in the `1.1.0` App Store build: identical to `SchemaV1` except that the `AppShortcut` record is renamed to `KeyboardShortcut`, and `Account` gains the two appearance choices.
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Account.self, ServerApp.self, KeyboardShortcut.self]
    }
}
