// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import CoreSpotlight
import Foundation

/// `CollectivePageEntityQuery`'s conformance to `IndexedEntityQuery`, which is how the system asks this app to donate the pages within the account's collectives again.
@available(macOS 27.0, iOS 27.0, *)
extension CollectivePageEntityQuery: IndexedEntityQuery {
    /// `reindexEntities(for:indexDescription:)` donates the pages within the account's collectives again, which covers the ones named and every other one besides.
    nonisolated func reindexEntities(for _: [Int], indexDescription _: CSSearchableIndexDescription) async throws {
        await CollectiveIndexer.shared.donatePages()
    }

    /// `reindexAllEntities(indexDescription:)` donates the pages within the account's collectives again.
    nonisolated func reindexAllEntities(indexDescription _: CSSearchableIndexDescription) async throws {
        await CollectiveIndexer.shared.donatePages()
    }
}
