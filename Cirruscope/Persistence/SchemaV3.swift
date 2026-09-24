// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// `SchemaV3` is the current versioned schema of Cirruscope's SwiftData store, and the only one that references the app's live top-level `@Model` types.
///
/// Unlike the frozen `SchemaV1` and `SchemaV2`, it always reflects the model definitions the rest of the app uses, so `AppDatabase` builds its container from it and every `FetchDescriptor` in the app resolves against models this schema registers. That is also why freezing a schema and introducing its successor is one change rather than two: the moment `SchemaV2` stopped naming the live types, something else had to, or the container would register models no fetch could reach.
///
/// It began identical in shape to `SchemaV2`, the version existing to give the freeze somewhere to hand off to rather than because anything about the store had changed, which is why `CirruscopeMigrationPlan` migrates across it with a lightweight stage. It has since gained `TalkConversation` and `ServerNote`, and that stage is still lightweight: adding an entity, and adding a relationship to it that defaults to empty, are changes SwiftData infers on its own.
///
/// **This is the one schema that may still change.** The rule the two frozen schemas above record is that the newest schema stays live until a build carrying it ships, and is frozen — into nested copies, like theirs — the moment it does, with a successor created in the same change. Until then, a new model or a new property belongs here.
enum SchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(3, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Account.self, ServerApp.self, KeyboardShortcut.self, TalkConversation.self, ServerNote.self]
    }
}
