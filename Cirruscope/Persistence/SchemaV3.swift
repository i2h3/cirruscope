// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// `SchemaV3` is the versioned schema of Cirruscope's SwiftData store exactly as it shipped in the `1.2.0` and `1.2.1` App Store builds: `SchemaV2` with `TalkConversation`, `ServerNote`, `ServerCollective` and `ServerCollectivePage` added, and what the user sets up on the device moved out of the account into `KeyboardShortcut`, keyed by its app's identifier, and `DevicePreferences`.
///
/// That move is not inferable, which is why `CirruscopeMigrationPlan` reaches this schema through `SchemaV2_1`, writing what it moves into the store before anything is dropped.
///
/// It is frozen like `SchemaV1` and `SchemaV2`, and for the same reasons: its models are the nested copies in the `SchemaV3+<Model>.swift` files, byte-for-byte the live models at both tags, so the identity this schema claims is the identity the stores in the field carry. The freeze happened in the change that introduced `SchemaV4`, which is the one that now references the live models. Never edit these types or the version identifier; introduce changes in a new `SchemaV{n}` and a migration stage instead.
enum SchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(3, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Account.self, ServerApp.self, KeyboardShortcut.self, DevicePreferences.self, TalkConversation.self, ServerNote.self, ServerCollective.self, ServerCollectivePage.self]
    }
}
