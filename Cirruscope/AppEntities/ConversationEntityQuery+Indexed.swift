// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import CoreSpotlight
import Foundation

/// `ConversationEntityQuery`'s conformance to `IndexedEntityQuery`, which is how the system asks this app to donate the account's Talk conversations again.
@available(macOS 27.0, iOS 27.0, *)
extension ConversationEntityQuery: IndexedEntityQuery {
    /// `reindexEntities(for:indexDescription:)` donates the account's Talk conversations again, which covers the ones named and every other one besides.
    nonisolated func reindexEntities(for _: [String], indexDescription _: CSSearchableIndexDescription) async throws {
        await ConversationIndexer.shared.donateAll()
    }

    /// `reindexAllEntities(indexDescription:)` donates the account's Talk conversations again.
    nonisolated func reindexAllEntities(indexDescription _: CSSearchableIndexDescription) async throws {
        await ConversationIndexer.shared.donateAll()
    }
}
