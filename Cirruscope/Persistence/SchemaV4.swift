// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// `SchemaV4` is the current versioned schema of Cirruscope's SwiftData store, and the only one that references the app's live top-level `@Model` types.
///
/// **This is the one schema that may still change.** The rule the frozen schemas record is that the newest schema stays live until a build carrying it ships, and is frozen — into nested copies, like theirs — the moment it does, with a successor created in the same change. Until then, a new model or a new property belongs here.
enum SchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(4, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Account.self, ServerApp.self, KeyboardShortcut.self, DevicePreferences.self, TalkConversation.self, ServerNote.self, ServerCollective.self, ServerCollectivePage.self]
    }
}
