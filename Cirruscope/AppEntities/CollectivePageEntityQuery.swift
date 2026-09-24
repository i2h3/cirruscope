// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import os

/// `CollectivePageEntityQuery` supplies `CollectivePageEntity` values to the App Intents system: it enumerates every page of every collective, resolves identifiers back to entities, and matches them by title.
///
/// Every page has to be paired with the name of the collective containing it, which the store does not carry on a page snapshot — a page knows its collective's identifier and no more. So each of these builds the identifier-to-name map once and reads it per page, rather than looking a collective up for each: an account with a handful of collectives and a few hundred pages would otherwise do a linear search per row.
@MainActor
struct CollectivePageEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    /// `logger` records query activity under the `CollectivePageEntityQuery` category.
    private static let logger = Logger(for: CollectivePageEntityQuery.self)

    /// `suggestionLimit` is how many pages are offered without the user having typed anything.
    ///
    /// Bounded where the collectives are not, because nothing bounds how many pages a collective holds. The store returns them most recently changed first, so the ones kept are the ones somebody was working on.
    private static let suggestionLimit = 10

    /// `entities(_:)` pairs each page with the name of its collective, which is what the entity's subtitle is.
    ///
    /// A page whose collective is not in the store is dropped rather than shown with an empty subtitle: it is a page nothing could address either, the collective's own segment being the front of a page's address.
    private func entities(_ pages: [CollectivePageTransferObject]) -> [CollectivePageEntity] {
        var namesByID: [Int: String] = [:]
        for collective in AccountStore.shared.collectives {
            namesByID[collective.id] = collective.name
        }

        return pages.compactMap { page in
            guard let name = namesByID[page.collectiveID] else {
                return nil
            }

            return CollectivePageEntity(page, inCollective: name)
        }
    }

    /// `allEntities()` is every page of every collective the account is a member of.
    func allEntities() async throws -> [CollectivePageEntity] {
        let entities = entities(AccountStore.shared.collectivePages)
        Self.logger.notice("allEntities: returning \(entities.count, privacy: .public) collective page entities")
        return entities
    }

    /// `suggestedEntities()` is what Siri and the Shortcuts app offer without the user typing anything: the most recently changed pages.
    func suggestedEntities() async throws -> [CollectivePageEntity] {
        let entities = entities(Array(AccountStore.shared.collectivePages.prefix(Self.suggestionLimit)))
        Self.logger.notice("suggestedEntities: returning \(entities.count, privacy: .public) of the most recently changed pages")
        return entities
    }

    /// `entities(for:)` resolves each requested identifier back to an entity, silently dropping pages that are gone.
    func entities(for identifiers: [CollectivePageEntity.ID]) async throws -> [CollectivePageEntity] {
        let pages = identifiers.compactMap { AccountStore.shared.collectivePage(forID: $0) }
        let entities = entities(pages)
        Self.logger.notice("entities(for:): resolved \(entities.count, privacy: .public) of \(identifiers.count, privacy: .public) requested identifier(s)")
        return entities
    }

    /// `entities(matching:)` is every page whose title contains `string`, case-insensitively.
    func entities(matching string: String) async throws -> [CollectivePageEntity] {
        let pages = AccountStore.shared.collectivePages.filter { $0.title.localizedCaseInsensitiveContains(string) }
        let entities = entities(pages)
        Self.logger.notice("entities(matching:): \(entities.count, privacy: .public) match(es)")
        return entities
    }
}
