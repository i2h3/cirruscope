// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import os

/// `ConversationEntityQuery` supplies `ConversationEntity` values to the App Intents system: it enumerates the Talk conversations the connected account takes part in, resolves tokens back to entities, and matches them by name.
@MainActor
struct ConversationEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    /// `logger` records query activity under the `ConversationEntityQuery` category.
    private static let logger = Logger(for: ConversationEntityQuery.self)

    /// `suggestionLimit` is how many conversations are offered without the user having typed anything.
    ///
    /// A bound rather than the whole list, because nothing bounds how many conversations an account takes part in and a picker offering hundreds is a picker nobody scrolls. The store returns them most recently active first, so the ones kept are the ones a person is most likely to mean.
    private static let suggestionLimit = 10

    /// `allEntities()` is every Talk conversation the connected account takes part in.
    func allEntities() async throws -> [ConversationEntity] {
        let entities = AccountStore.shared.conversations.map(ConversationEntity.init)
        Self.logger.notice("allEntities: returning \(entities.count, privacy: .public) conversation entities")
        return entities
    }

    /// `suggestedEntities()` is what Siri and the Shortcuts app offer without the user typing anything: the most recently active conversations.
    func suggestedEntities() async throws -> [ConversationEntity] {
        let entities = AccountStore.shared.conversations.prefix(Self.suggestionLimit).map(ConversationEntity.init)
        Self.logger.notice("suggestedEntities: returning \(entities.count, privacy: .public) of the most recently active conversations")
        return entities
    }

    /// `entities(for:)` resolves each requested token back to an entity, silently dropping the ones the account no longer takes part in.
    func entities(for identifiers: [ConversationEntity.ID]) async throws -> [ConversationEntity] {
        let entities = identifiers.compactMap { identifier in
            AccountStore.shared.conversation(forToken: identifier).map(ConversationEntity.init)
        }

        Self.logger.notice("entities(for:): resolved \(entities.count, privacy: .public) of \(identifiers.count, privacy: .public) requested token(s)")
        return entities
    }

    /// `entities(matching:)` is every conversation whose name contains `string`, case-insensitively.
    func entities(matching string: String) async throws -> [ConversationEntity] {
        let entities = AccountStore.shared
            .conversations
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(ConversationEntity.init)

        Self.logger.notice("entities(matching:): \(entities.count, privacy: .public) match(es)")
        return entities
    }
}
