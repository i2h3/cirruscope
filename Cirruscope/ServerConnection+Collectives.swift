// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker

/// `ServerConnection`'s collectives: fetching the collectives the account is a member of and the pages within each.
extension ServerConnection {
    /// `refreshCollectives(using:)` fetches the account's collectives and each one's pages, or clears what was stored when the server has no Collectives app.
    ///
    /// The pages are fetched one collective at a time and in sequence rather than together. A collective's page listing is the whole truth about that collective and says nothing about the others, so each answer is written on its own — which is also what keeps a failure part-way through from emptying the collectives that were already refreshed.
    static func refreshCollectives(using server: Server) async {
        let address = server.address
        let credentials = credentials(of: server)

        // Before the gate, which reads the store: a store a sign-out emptied offers no app at all, and the gate would
        // log that as the server lacking one.
        guard await isStillSignedIn(at: address, as: credentials) else {
            logger.notice("The account this refresh was begun for is no longer signed in; not asking for collectives")
            return
        }

        guard await AccountStore.shared.serverApp(forID: "collectives") != nil else {
            logger.notice("The server does not offer the collectives app; not asking for collectives")

            await record("the absence of the Collectives app", fetchedFrom: address, as: credentials) {
                AccountStore.shared.deleteCollectives()
            }

            return
        }

        let collectives: [Collective]

        do {
            collectives = try await server.collectives()
            let stored = collectives.map { CollectiveTransferObject(id: $0.id, name: $0.name, slug: $0.slug, emoji: $0.emoji) }
            logger.notice("Fetched \(stored.count, privacy: .public) collective(s)")

            let recorded = await record("the collectives", fetchedFrom: address, as: credentials) {
                AccountStore.shared.persist(collectives: stored)
            }

            guard recorded else {
                return
            }
        } catch RainmakerError.notFound {
            logger.notice("The collectives endpoint answered 404, so the app is absent or disabled; dropping anything stored for it")

            await record("the absence of the Collectives app", fetchedFrom: address, as: credentials) {
                AccountStore.shared.deleteCollectives()
            }

            return
        } catch {
            logger.notice("Could not refresh the collectives; keeping the previous list: \(error.localizedDescription, privacy: .public)")
            return
        }

        for collective in collectives {
            guard await refreshPages(ofCollective: collective.id, using: server) else {
                logger.notice("The account this refresh was begun for is no longer signed in; not asking for the pages of the remaining collectives")
                return
            }
        }
    }

    /// `refreshPages(ofCollective:using:)` fetches the pages of one collective and persists them.
    private static func refreshPages(ofCollective collectiveID: Int, using server: Server) async -> Bool {
        do {
            let pages = try await server.pages(inCollective: collectiveID)
            let stored = pages.map { CollectivePageTransferObject(id: $0.id, collectiveID: collectiveID, title: $0.title, slug: $0.slug, emoji: $0.emoji, fileName: $0.fileName, filePath: $0.filePath, isLandingPage: $0.isLandingPage, modification: $0.modification) }
            logger.notice("Fetched \(stored.count, privacy: .public) page(s) of collective \(collectiveID, privacy: .public)")

            return await record("the pages of a collective", fetchedFrom: server.address, as: credentials(of: server)) {
                AccountStore.shared.persist(pages: stored, inCollective: collectiveID)
            }
        } catch {
            logger.notice("Could not refresh the pages of collective \(collectiveID, privacy: .public); keeping the previous ones: \(error.localizedDescription, privacy: .public)")
            return true
        }
    }
}
