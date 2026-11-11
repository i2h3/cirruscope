// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import CoreSpotlight
import Foundation

/// `ServerAppEntityQuery`'s conformance to `IndexedEntityQuery`, which is how the system asks this app to donate the server's apps again.
@available(macOS 27.0, iOS 27.0, *)
extension ServerAppEntityQuery: IndexedEntityQuery {
    /// `reindexEntities(for:indexDescription:)` donates the server's apps again, which covers the ones named and every other one besides.
    nonisolated func reindexEntities(for _: [String], indexDescription _: CSSearchableIndexDescription) async throws {
        await ServerAppIndexer.shared.donateAll()
    }

    /// `reindexAllEntities(indexDescription:)` donates the server's apps again.
    nonisolated func reindexAllEntities(indexDescription _: CSSearchableIndexDescription) async throws {
        await ServerAppIndexer.shared.donateAll()
    }
}
