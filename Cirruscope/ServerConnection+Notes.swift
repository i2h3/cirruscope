// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import Rainmaker

/// `ServerConnection`'s notes: fetching what the server has and recording the part of it this app keeps.
///
/// **This is where a note's text is dropped**, and it is dropped in the same expression that maps the server's answer, so nothing downstream ever receives one. That placement is the whole safeguard: a value type with no field for it cannot be made to carry one later by accident, and the mapping is the only place a `Rainmaker.Note` exists at all.
///
/// The body is still fetched, and there is no way around that with this API: the endpoint returns every note in full unless a chunk size is requested, and Rainmaker deliberately does not request one. So the cost is a decode proportional to the account's notes, once per refresh, and what this avoids is that text being *retained* — in memory past the mapping, and on disk at all. Saying that plainly is better than implying the fetch is cheap.
extension ServerConnection {
    /// `refreshNotes(using:)` fetches the notes the authenticated `server` has and persists their metadata, or clears what was stored when the server has no usable Notes app.
    ///
    /// Availability is decided from the response rather than from the capability the server advertises, for the reasons recorded on `refreshConversations(using:)` and in `DECISIONS.md`. Notes adds a second way to be unusable and it is handled the same way: an app that is installed but older than the API this library speaks answers with an unsupported-version error, and an app this old is no more openable than an absent one, so what was stored for it goes too.
    ///
    /// Every other failure leaves the previous list in place. An unreachable server has told us nothing, and emptying a Spotlight index on a network blip would be reading silence as an answer.
    static func refreshNotes(using server: Server) async {
        do {
            let notes = try await server.notes()
            let stored = notes.map { NoteTransferObject(id: $0.id, title: $0.title, category: $0.category, isFavorite: $0.isFavorite, isReadOnly: $0.isReadOnly, modification: $0.modification) }
            logger.notice("Fetched \(stored.count, privacy: .public) note(s); their text was dropped at this boundary")
            await AccountStore.shared.persist(notes: stored)
        } catch RainmakerError.notFound {
            logger.notice("The notes endpoint answered 404, so the app is absent or disabled; dropping anything stored for it")
            await AccountStore.shared.deleteNotes()
        } catch let RainmakerError.unsupportedAPIVersion(app, required, advertised) {
            logger.notice("The \(app, privacy: .public) app advertises API \(advertised, privacy: .public) but \(required, privacy: .public) is required; dropping anything stored for it")
            await AccountStore.shared.deleteNotes()
        } catch {
            logger.notice("Could not refresh the notes; keeping the previous list: \(error.localizedDescription, privacy: .public)")
        }
    }
}
