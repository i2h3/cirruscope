// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import os

/// `NoteEntityQuery` supplies `NoteEntity` values to the App Intents system: it enumerates the connected account's notes, resolves identifiers back to entities, and matches them by title.
@MainActor
struct NoteEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    /// `logger` records query activity under the `NoteEntityQuery` category.
    private static let logger = Logger(for: NoteEntityQuery.self)

    /// `suggestionLimit` is how many notes are offered without the user having typed anything.
    private static let suggestionLimit = 10

    /// `allEntities()` is every note the connected account has.
    func allEntities() async throws -> [NoteEntity] {
        let entities = AccountStore.shared.notes.map(NoteEntity.init)
        Self.logger.notice("allEntities: returning \(entities.count, privacy: .public) note entities")
        return entities
    }

    /// `suggestedEntities()` is what Siri and the Shortcuts app offer without the user typing anything: the favourites, then the most recently changed.
    func suggestedEntities() async throws -> [NoteEntity] {
        let entities = AccountStore.shared.notes.prefix(Self.suggestionLimit).map(NoteEntity.init)
        Self.logger.notice("suggestedEntities: returning \(entities.count, privacy: .public) of the account's notes")
        return entities
    }

    /// `entities(for:)` resolves each requested identifier back to an entity, silently dropping notes the account no longer has.
    func entities(for identifiers: [NoteEntity.ID]) async throws -> [NoteEntity] {
        let entities = identifiers.compactMap { identifier in
            AccountStore.shared.note(forID: identifier).map(NoteEntity.init)
        }

        Self.logger.notice("entities(for:): resolved \(entities.count, privacy: .public) of \(identifiers.count, privacy: .public) requested identifier(s)")
        return entities
    }

    /// `entities(matching:)` is every note whose title or category contains `string`, case-insensitively.
    func entities(matching string: String) async throws -> [NoteEntity] {
        let entities = AccountStore.shared
            .notes
            .filter { $0.title.localizedCaseInsensitiveContains(string) || $0.category.localizedCaseInsensitiveContains(string) }
            .map(NoteEntity.init)

        Self.logger.notice("entities(matching:): \(entities.count, privacy: .public) match(es)")
        return entities
    }
}
