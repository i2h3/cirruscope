// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker

/// `ServerConnection`'s collectives: fetching the collectives the account is a member of and the pages within each.
///
/// This is the one domain that is gated before it asks anything, and the reason is arithmetic rather than principle. Talk and Notes are decided from the response because the gate would save a single request; here the server lists pages *per collective*, so a refresh is one request for the collectives plus one for each of them — and on an instance without the app, every one of those is wasted. The gate is free besides: Collectives advertises no capability at all, so the network library's own documentation points at the navigation entry with the identifier `collectives`, which this app already fetches and stores a moment earlier.
///
/// A `404` is still handled, because the gate is a prediction made from a list that can be a refresh behind. What it means differs from the gate, though, and only one of them clears what was stored: the gate says "do not ask", while a `404` says the app is gone.
extension ServerConnection {
    /// `refreshCollectives(using:)` fetches the account's collectives and each one's pages, or clears what was stored when the server has no Collectives app.
    ///
    /// The pages are fetched one collective at a time and in sequence rather than together. A collective's page listing is the whole truth about that collective and says nothing about the others, so each answer is written on its own — which is also what keeps a failure part-way through from emptying the collectives that were already refreshed.
    static func refreshCollectives(using server: Server) async {
        guard await AccountStore.shared.serverApp(forID: "collectives") != nil else {
            logger.notice("The server does not offer the collectives app; not asking for collectives")
            await AccountStore.shared.deleteCollectives()
            return
        }

        let collectives: [Collective]

        do {
            collectives = try await server.collectives()
            let stored = collectives.map { CollectiveTransferObject(id: $0.id, name: $0.name, slug: $0.slug, emoji: $0.emoji) }
            logger.notice("Fetched \(stored.count, privacy: .public) collective(s)")
            await AccountStore.shared.persist(collectives: stored)
        } catch RainmakerError.notFound {
            logger.notice("The collectives endpoint answered 404, so the app is absent or disabled; dropping anything stored for it")
            await AccountStore.shared.deleteCollectives()
            return
        } catch {
            logger.notice("Could not refresh the collectives; keeping the previous list: \(error.localizedDescription)")
            return
        }

        for collective in collectives {
            await refreshPages(ofCollective: collective.id, using: server)
        }
    }

    /// `refreshPages(ofCollective:using:)` fetches the pages of one collective and persists them.
    ///
    /// A failure here leaves that collective's stored pages alone and does not abort the collectives after it: one collective being unreadable — deleted between the listing and this request, or refused for this account — says nothing about the rest, and treating it as though it did would empty an index because of one row.
    private static func refreshPages(ofCollective collectiveID: Int, using server: Server) async {
        do {
            let pages = try await server.pages(inCollective: collectiveID)
            let stored = pages.map { CollectivePageTransferObject(id: $0.id, collectiveID: collectiveID, title: $0.title, slug: $0.slug, emoji: $0.emoji, fileName: $0.fileName, filePath: $0.filePath, isLandingPage: $0.isLandingPage, modification: $0.modification) }
            logger.notice("Fetched \(stored.count, privacy: .public) page(s) of collective \(collectiveID, privacy: .public)")
            await AccountStore.shared.persist(pages: stored, inCollective: collectiveID)
        } catch {
            logger.notice("Could not refresh the pages of collective \(collectiveID, privacy: .public); keeping the previous ones: \(error.localizedDescription)")
        }
    }
}
