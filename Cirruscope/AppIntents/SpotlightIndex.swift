// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import CoreSpotlight
import Foundation
import os

/// `SpotlightIndex` donates one kind of entity to Spotlight and keeps track of what it has donated, so a shrinking list has its removed entries deleted rather than left behind.
///
/// It is the mechanism every domain's indexer shares, holding the one piece of state that is easy to get wrong: the set of identifiers currently in the index. Without it a list that loses an entry leaves a Spotlight result behind that opens nothing, and with a copy of it per domain the same bug is available once per domain.
///
/// The index it writes to is named rather than `CSSearchableIndex.default()`, which Apple documents as being for prototyping only. The name is historical and deliberately not corrected: every entity type shares `"ServerAppIndex"` because renaming it would orphan everything already donated on every Mac that has run this app, with no way left to delete it — and `deleteAppEntities(identifiedBy:ofType:)` is scoped by type anyway, so one index costs nothing.
///
/// It is not an observer of anything and knows nothing about when to run. That belongs to the per-domain indexer that owns one, because what a domain listens to is the one thing about it that is not shared.
@MainActor
final class SpotlightIndex<Entity: IndexedEntity> {
    /// `indexName` is the Core Spotlight index every entity type is donated to; see the note above on why it is named for the first of them.
    private static var indexName: String {
        "ServerAppIndex"
    }

    /// `logger` records donations under the `SpotlightIndex` category.
    private let logger = Logger(for: SpotlightIndex.self)

    /// `label` names the domain in every line this logs, so one category can carry several indexes without a capture becoming unreadable.
    private let label: StaticString

    /// `indexedIDs` is the set of identifiers currently donated, retained so a shrinking list can have its removed entries deleted.
    private var indexedIDs: Set<Entity.ID> = []

    /// `init(label:)` builds an index for one entity type, naming it for the log.
    init(label: StaticString) {
        self.label = label
    }

    /// `donate(_:)` puts `entities` into the index and removes whatever was donated before and is not among them.
    ///
    /// It replaces rather than merges: what it is given is the whole of what the account currently has, so anything previously donated and now absent is gone rather than merely unlisted. That is what makes a signed-out account's entries disappear — `AccountStore` empties the list and announces it, and this is called with nothing.
    func donate(_ entities: [Entity]) async {
        let currentIDs = Set(entities.map(\.id))
        let removedIDs = indexedIDs.subtracting(currentIDs)
        indexedIDs = currentIDs

        logger.notice("Reindexing \(self.label, privacy: .public): \(entities.count, privacy: .public) current, \(removedIDs.count, privacy: .public) to remove")

        // A fresh local value, not a stored one: `CSSearchableIndex` is created here so it stays outside the main
        // actor's isolation region and can be passed to these nonisolated async calls without tripping Swift's
        // sending diagnostic.
        let index = CSSearchableIndex(name: Self.indexName)

        do {
            if removedIDs.isEmpty == false {
                try await index.deleteAppEntities(identifiedBy: Array(removedIDs), ofType: Entity.self)
                logger.notice("Deleted \(removedIDs.count, privacy: .public) stale \(self.label, privacy: .public) entr(y/ies)")
            }

            try await index.indexAppEntities(entities)
            logger.notice("Donated \(entities.count, privacy: .public) \(self.label, privacy: .public) entit(y/ies)")
        } catch {
            logger.error("Could not update the Spotlight index for \(self.label, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
