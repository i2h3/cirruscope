// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker

/// `ServerConnection`'s notes: fetching what the server has and recording the part of it this app keeps.
///
/// **A note's text is never downloaded at all.** The refresh asks for summaries, which the server sends without the content of any note, and maps them into a value type with no field for one, so nothing downstream can be made to carry it later by accident.
///
/// Every refresh still lists every note, asking for the changes since before any could have been made, because the store keeps no record of when it last asked; what it no longer costs is a download and a decode proportional to the size of the account's notes.
extension ServerConnection {
    /// `refreshNotes(using:)` fetches the notes the authenticated `server` has and persists their metadata, or clears what was stored when the server has no usable Notes app.
    ///
    /// Every other failure leaves the previous list in place. An unreachable server has told us nothing, and emptying a Spotlight index on a network blip would be reading silence as an answer.
    static func refreshNotes(using server: Server) async {
        let address = server.address
        let credentials = credentials(of: server)

        guard await isStillSignedIn(at: address, as: credentials) else {
            logger.notice("The account this refresh was begun for is no longer signed in; not asking for notes")
            return
        }

        do {
            // Changes since before the epoch are every note there is, each sent in full but for its text.
            let summaries = try await server.noteSummaries(changedSince: .distantPast).changed
            let stored = summaries.map { NoteTransferObject(id: $0.id, title: $0.title, category: $0.category, isFavorite: $0.isFavorite, isReadOnly: $0.isReadOnly, modification: $0.modification) }
            logger.notice("Fetched the summaries of \(stored.count, privacy: .public) note(s), none of them with its text")

            await record("the notes", fetchedFrom: address, as: credentials) {
                AccountStore.shared.persist(notes: stored)
            }
        } catch RainmakerError.appUnavailable {
            logger.notice("The notes endpoint was not served by the Notes app, so the app is absent or disabled; dropping anything stored for it")

            await record("the absence of the Notes app", fetchedFrom: address, as: credentials) {
                AccountStore.shared.deleteNotes()
            }
        } catch let RainmakerError.unsupportedAPIVersion(app, required, advertised) {
            logger.notice("The \(app, privacy: .public) app advertises API \(advertised, privacy: .public) but \(required, privacy: .public) is required; dropping anything stored for it")

            await record("the absence of a usable Notes app", fetchedFrom: address, as: credentials) {
                AccountStore.shared.deleteNotes()
            }
        } catch {
            logger.notice("Could not refresh the notes; keeping the previous list: \(error.localizedDescription, privacy: .public)")
        }
    }
}
