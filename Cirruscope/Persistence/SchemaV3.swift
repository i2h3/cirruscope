// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// `SchemaV3` is the current versioned schema of Cirruscope's SwiftData store, and the only one that references the app's live top-level `@Model` types.
///
/// Unlike the frozen `SchemaV1` and `SchemaV2`, it always reflects the model definitions the rest of the app uses, so `AppDatabase` builds its container from it and every `FetchDescriptor` in the app resolves against models this schema registers. That is also why freezing a schema and introducing its successor is one change rather than two: the moment `SchemaV2` stopped naming the live types, something else had to, or the container would register models no fetch could reach.
///
/// It began identical in shape to `SchemaV2`, the version existing to give the freeze somewhere to hand off to rather than because anything about the store had changed. It has since gained `TalkConversation`, `ServerNote`, `ServerCollective` and `ServerCollectivePage`, which SwiftData infers on its own, and it has moved what the user sets up on the device out of the account: `KeyboardShortcut` is keyed by its app's identifier instead of hanging off a `ServerApp`, and the appearance settings moved from `Account` into `DevicePreferences`. That move is not inferable, which is why `CirruscopeMigrationPlan` reaches this schema through `SchemaV2_1`, writing what it moves into the store before anything is dropped.
///
/// **This is the one schema that may still change.** The rule the frozen schemas record is that the newest schema stays live until a build carrying it ships, and is frozen — into nested copies, like theirs — the moment it does, with a successor created in the same change. Until then, a new model or a new property belongs here.
///
/// Changing it in place has a cost on a developer's own machine: staged migration matches a store by its model's checksum, not by the version identifier, so a store an earlier shape of this schema wrote matches no schema in the plan, and `AppDatabase` quarantines it and starts empty. Test with `CIRRUSCOPE_BASE_BUNDLE_IDENTIFIER=de.i2h3.cirruscope.citest` to keep a real store out of it.
enum SchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(3, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Account.self, ServerApp.self, KeyboardShortcut.self, DevicePreferences.self, TalkConversation.self, ServerNote.self, ServerCollective.self, ServerCollectivePage.self]
    }
}
