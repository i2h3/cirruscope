// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// `SchemaV2_1` is an intermediate versioned schema that no build ever runs on: `SchemaV2` with an optional `appID` on `KeyboardShortcut` and a `DevicePreferences` entity added, both changes SwiftData infers.
enum SchemaV2_1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 1, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Account.self, ServerApp.self, KeyboardShortcut.self, DevicePreferences.self]
    }
}
