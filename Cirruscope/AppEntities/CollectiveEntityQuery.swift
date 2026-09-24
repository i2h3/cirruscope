// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import os

/// `CollectiveEntityQuery` supplies `CollectiveEntity` values to the App Intents system: it enumerates the collectives the account is a member of, resolves identifiers back to entities, and matches them by name.
///
/// It offers every collective as a suggestion rather than a bounded handful, where the note and conversation queries bound theirs. That is not an oversight: a collective is a thing a team sets up deliberately and an account belongs to a few of them, the way it has a few server apps — the list is short by its nature, and truncating it would hide one for no gain.
@MainActor
struct CollectiveEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    /// `logger` records query activity under the `CollectiveEntityQuery` category.
    private static let logger = Logger(for: CollectiveEntityQuery.self)

    /// `allEntities()` is every collective the connected account is a member of.
    func allEntities() async throws -> [CollectiveEntity] {
        let entities = AccountStore.shared.collectives.map(CollectiveEntity.init)
        Self.logger.notice("allEntities: returning \(entities.count, privacy: .public) collective entities")
        return entities
    }

    /// `suggestedEntities()` is what Siri and the Shortcuts app offer without the user typing anything; the whole list is short enough to offer in full.
    func suggestedEntities() async throws -> [CollectiveEntity] {
        try await allEntities()
    }

    /// `entities(for:)` resolves each requested identifier back to an entity, silently dropping collectives the account has left.
    func entities(for identifiers: [CollectiveEntity.ID]) async throws -> [CollectiveEntity] {
        let entities = identifiers.compactMap { identifier in
            AccountStore.shared.collective(forID: identifier).map(CollectiveEntity.init)
        }

        Self.logger.notice("entities(for:): resolved \(entities.count, privacy: .public) of \(identifiers.count, privacy: .public) requested identifier(s)")
        return entities
    }

    /// `entities(matching:)` is every collective whose name contains `string`, case-insensitively.
    ///
    /// Matched against the name rather than the display name, so that a search for a collective's words is not defeated by the emoji the display name puts in front of them.
    func entities(matching string: String) async throws -> [CollectiveEntity] {
        let entities = AccountStore.shared
            .collectives
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(CollectiveEntity.init)

        Self.logger.notice("entities(matching:): \(entities.count, privacy: .public) match(es)")
        return entities
    }
}
