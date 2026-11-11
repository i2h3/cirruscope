// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import CoreSpotlight
import Foundation

/// `NoteEntityQuery`'s conformance to `IndexedEntityQuery`, which is how the system asks this app to donate the account's notes again.
@available(macOS 27.0, iOS 27.0, *)
extension NoteEntityQuery: IndexedEntityQuery {
    /// `reindexEntities(for:indexDescription:)` donates the account's notes again, which covers the ones named and every other one besides.
    nonisolated func reindexEntities(for _: [Int], indexDescription _: CSSearchableIndexDescription) async throws {
        await NoteIndexer.shared.donateAll()
    }

    /// `reindexAllEntities(indexDescription:)` donates the account's notes again.
    nonisolated func reindexAllEntities(indexDescription _: CSSearchableIndexDescription) async throws {
        await NoteIndexer.shared.donateAll()
    }
}
