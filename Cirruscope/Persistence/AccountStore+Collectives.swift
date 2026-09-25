// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import SwiftData

/// `AccountStore`'s collectives and the pages within them: reading them back as value snapshots, and writing what a refresh found.
///
/// The shape is every other domain's — upsert by the identity the server addresses the thing by, prune what it no longer lists, sort at the read, announce afterwards — with one departure worth naming. The pages of a collective are written per collective rather than all at once, because that is how the server answers: listing them takes a collective's identifier, so a refresh is one request per collective and each answer is the whole truth about one of them and says nothing about the others.
extension AccountStore {
    /// `collectives` are the connected account's collectives as value snapshots, alphabetically by name.
    var collectives: [CollectiveTransferObject] {
        guard let account = currentAccount(createIfNeeded: false) else {
            return []
        }

        return account.collectives
            .map { CollectiveTransferObject(id: $0.collectiveID, name: $0.name, slug: $0.slug, emoji: $0.emoji) }
            .sortedByName()
    }

    /// `collective(forID:)` is the connected account's collective with `id` as a value snapshot, or `nil` when it has no such collective.
    func collective(forID id: Int) -> CollectiveTransferObject? {
        guard let collective = currentAccount(createIfNeeded: false)?.collectives.first(where: { $0.collectiveID == id }) else {
            return nil
        }

        return CollectiveTransferObject(id: collective.collectiveID, name: collective.name, slug: collective.slug, emoji: collective.emoji)
    }

    /// `collectivePages` are every page of every collective the account has, most recently changed first.
    ///
    /// Flat rather than grouped, because what reads this is an index: Spotlight is donated one item per page and has no notion of a page belonging to anything. Each snapshot carries its collective's identifier, which is what the address of a page needs and what a caller uses to look the collective up when it has to build one.
    var collectivePages: [CollectivePageTransferObject] {
        guard let account = currentAccount(createIfNeeded: false) else {
            return []
        }

        return account.collectives
            .flatMap { collective in
                collective.pages.map { page in
                    CollectivePageTransferObject(id: page.pageID, collectiveID: collective.collectiveID, title: page.title, slug: page.slug, emoji: page.emoji, fileName: page.fileName, filePath: page.filePath, isLandingPage: page.isLandingPage, modification: page.modification)
                }
            }
            .sortedByModification()
    }

    /// `collectivePage(forID:)` is the page with `id` as a value snapshot, or `nil` when the account has no such page.
    ///
    /// Searched across every collective rather than within one, because a page identifier is the identifier of its file and unique on the server — a caller resolving a donated Spotlight item has the page's identifier and nothing else.
    func collectivePage(forID id: Int) -> CollectivePageTransferObject? {
        guard let account = currentAccount(createIfNeeded: false) else {
            return nil
        }

        for collective in account.collectives {
            guard let page = collective.pages.first(where: { $0.pageID == id }) else {
                continue
            }

            return CollectivePageTransferObject(id: page.pageID, collectiveID: collective.collectiveID, title: page.title, slug: page.slug, emoji: page.emoji, fileName: page.fileName, filePath: page.filePath, isLandingPage: page.isLandingPage, modification: page.modification)
        }

        return nil
    }

    /// `persist(collectives:)` upserts the account's collectives: existing rows are updated in place, new ones inserted, and ones the server no longer lists deleted — which cascades to their pages.
    ///
    /// Pages are deliberately untouched here. A collective's pages are fetched separately, one request per collective, so a write of the collectives alone knows nothing about them; matching by identifier rather than replacing the list is what lets the pages already stored for a collective survive a refresh that only re-listed the collectives.
    func persist(collectives: [CollectiveTransferObject]) {
        guard let account = currentAccount(createIfNeeded: true) else {
            return
        }

        let existingCollectives = account.collectives
        var existingByID: [Int: ServerCollective] = [:]
        for collective in existingCollectives {
            existingByID[collective.collectiveID] = collective
        }

        var incomingIDs: Set<Int> = []
        var inserted = 0
        var updated = 0
        var pruned = 0

        for collective in collectives where incomingIDs.contains(collective.id) == false {
            incomingIDs.insert(collective.id)

            if let existing = existingByID[collective.id] {
                existing.name = collective.name
                existing.slug = collective.slug
                existing.emoji = collective.emoji
                updated += 1
            } else {
                context.insert(ServerCollective(collectiveID: collective.id, name: collective.name, slug: collective.slug, emoji: collective.emoji, account: account))
                inserted += 1
            }
        }

        for collective in existingCollectives where incomingIDs.contains(collective.collectiveID) == false {
            context.delete(collective)
            pruned += 1
        }

        logger.notice("Persisting collectives: \(inserted, privacy: .public) inserted, \(updated, privacy: .public) updated, \(pruned, privacy: .public) pruned, \(incomingIDs.count, privacy: .public) stored")
        save()
        notifyChange(.collectivesDidChange)
    }

    /// `persist(pages:inCollective:)` upserts the pages of one collective, and does nothing when the account has no such collective.
    ///
    /// Scoped to one collective because that is the scope of the answer it is written from: the server lists pages per collective, so an answer says everything about one of them and nothing about the rest. Pruning within that scope only is what keeps a refresh of one collective from emptying another.
    func persist(pages: [CollectivePageTransferObject], inCollective collectiveID: Int) {
        guard let collective = currentAccount(createIfNeeded: false)?.collectives.first(where: { $0.collectiveID == collectiveID }) else {
            return
        }

        let existingPages = collective.pages
        var existingByID: [Int: ServerCollectivePage] = [:]
        for page in existingPages {
            existingByID[page.pageID] = page
        }

        var incomingIDs: Set<Int> = []
        var inserted = 0
        var updated = 0
        var pruned = 0

        for page in pages where incomingIDs.contains(page.id) == false {
            incomingIDs.insert(page.id)

            if let existing = existingByID[page.id] {
                existing.title = page.title
                existing.slug = page.slug
                existing.emoji = page.emoji
                existing.fileName = page.fileName
                existing.filePath = page.filePath
                existing.isLandingPage = page.isLandingPage
                existing.modification = page.modification
                updated += 1
            } else {
                context.insert(ServerCollectivePage(pageID: page.id, title: page.title, slug: page.slug, emoji: page.emoji, fileName: page.fileName, filePath: page.filePath, isLandingPage: page.isLandingPage, modification: page.modification, collective: collective))
                inserted += 1
            }
        }

        for page in existingPages where incomingIDs.contains(page.pageID) == false {
            context.delete(page)
            pruned += 1
        }

        logger.notice("Persisting the pages of collective \(collectiveID, privacy: .public): \(inserted, privacy: .public) inserted, \(updated, privacy: .public) updated, \(pruned, privacy: .public) pruned, \(incomingIDs.count, privacy: .public) stored")
        save()
        notifyChange(.collectivesDidChange)
    }

    /// `deleteCollectives()` removes every stored collective and, through them, every page, for a server whose Collectives app is absent.
    ///
    /// Announcing nothing when there was nothing to delete keeps an instance that has never had the app from having its Spotlight index rebuilt on every launch for a domain it does not have.
    func deleteCollectives() {
        guard let account = currentAccount(createIfNeeded: false) else {
            return
        }

        guard account.collectives.isEmpty == false else {
            return
        }

        logger.notice("Dropping every stored collective (\(account.collectives.count, privacy: .public)) and the pages within them")

        for collective in account.collectives {
            context.delete(collective)
        }

        save()
        notifyChange(.collectivesDidChange)
    }
}
