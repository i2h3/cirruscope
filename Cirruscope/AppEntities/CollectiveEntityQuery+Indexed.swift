// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import CoreSpotlight
import Foundation

/// `CollectiveEntityQuery`'s conformance to `IndexedEntityQuery`, which is how the system asks this app to donate the account's collectives again.
@available(macOS 27.0, iOS 27.0, *)
extension CollectiveEntityQuery: IndexedEntityQuery {
    /// `reindexEntities(for:indexDescription:)` donates the account's collectives again, which covers the ones named and every other one besides.
    nonisolated func reindexEntities(for _: [Int], indexDescription _: CSSearchableIndexDescription) async throws {
        await CollectiveIndexer.shared.donateCollectives()
    }

    /// `reindexAllEntities(indexDescription:)` donates the account's collectives again.
    nonisolated func reindexAllEntities(indexDescription _: CSSearchableIndexDescription) async throws {
        await CollectiveIndexer.shared.donateCollectives()
    }
}
