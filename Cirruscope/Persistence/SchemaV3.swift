// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// `SchemaV3` is the versioned schema of Cirruscope's SwiftData store exactly as it shipped in the `1.2.0` and `1.2.1` App Store builds: `SchemaV2` with `TalkConversation`, `ServerNote`, `ServerCollective` and `ServerCollectivePage` added, and what the user sets up on the device moved out of the account into `KeyboardShortcut`, keyed by its app's identifier, and `DevicePreferences`.
enum SchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(3, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Account.self, ServerApp.self, KeyboardShortcut.self, DevicePreferences.self, TalkConversation.self, ServerNote.self, ServerCollective.self, ServerCollectivePage.self]
    }
}
