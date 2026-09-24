// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// `AccountStore`'s notes: reading them back as value snapshots, and writing what a refresh found.
///
/// The shape is `AccountStore+Conversations`' exactly — upsert by the identity the server addresses the thing by, prune what it no longer lists, sort at the read, announce afterwards — which is the shape every domain on this store is meant to have. A domain that needs to depart from it should say why next to the departure.
///
/// What it never holds is a note's text. That is dropped where the server's answer is mapped, so it is not a rule this file has to keep; the value type it takes has nowhere to put one.
extension AccountStore {
    /// `notes` are the connected account's notes as value snapshots, favourites first and then most recently changed.
    ///
    /// Sorted here rather than by each caller, as every other domain's read is: SwiftData does not preserve the order of a to-many relationship, so something has to impose one, and imposing it once is what keeps two surfaces from disagreeing. The comparison is `sortedByPriority()`, where the argument for that order rather than an alphabetical one is written down.
    var notes: [NoteTransferObject] {
        guard let account = currentAccount(createIfNeeded: false) else {
            return []
        }

        return account.notes
            .map { NoteTransferObject(id: $0.noteID, title: $0.title, category: $0.category, isFavorite: $0.isFavorite, isReadOnly: $0.isReadOnly, modification: $0.modification) }
            .sortedByPriority()
    }

    /// `note(forID:)` is the connected account's note with `id` as a value snapshot, or `nil` when the account has no such note.
    ///
    /// The single-note counterpart of `notes`, for the App Intents layer: a query resolving a donated or saved identifier, and an intent re-resolving the one it was handed rather than trusting it. A donated Spotlight item outlives the list it came from, and a note is a thing people delete.
    func note(forID id: Int) -> NoteTransferObject? {
        guard let note = currentAccount(createIfNeeded: false)?.notes.first(where: { $0.noteID == id }) else {
            return nil
        }

        return NoteTransferObject(id: note.noteID, title: note.title, category: note.category, isFavorite: note.isFavorite, isReadOnly: note.isReadOnly, modification: note.modification)
    }

    /// `persist(notes:)` upserts the account's notes: existing rows are updated in place, new ones inserted, and ones the server no longer lists deleted.
    ///
    /// Matching by identifier rather than replacing the list is what keeps a note the same record across a refresh, so the Spotlight item donated for it is left alone rather than deleted and re-added on every launch.
    /// It takes this app's own value type rather than the network library's model, as every writer on this store does: neither test target links Rainmaker, so a signature naming `Rainmaker.Note` would make the write side untestable.
    func persist(notes: [NoteTransferObject]) {
        guard let account = currentAccount(createIfNeeded: true) else {
            return
        }

        let existingNotes = account.notes
        var existingByID: [Int: ServerNote] = [:]
        for note in existingNotes {
            existingByID[note.noteID] = note
        }

        var incomingIDs: Set<Int> = []

        // An identifier already seen in this list is skipped rather than inserted twice, matching every other
        // domain: two rows sharing one identity would leave the read's ordering with a tie it cannot break.
        for note in notes where incomingIDs.contains(note.id) == false {
            incomingIDs.insert(note.id)

            if let existing = existingByID[note.id] {
                existing.title = note.title
                existing.category = note.category
                existing.isFavorite = note.isFavorite
                existing.isReadOnly = note.isReadOnly
                existing.modification = note.modification
            } else {
                context.insert(ServerNote(noteID: note.id, title: note.title, category: note.category, isFavorite: note.isFavorite, isReadOnly: note.isReadOnly, modification: note.modification, account: account))
            }
        }

        for note in existingNotes where incomingIDs.contains(note.noteID) == false {
            context.delete(note)
        }

        save()
        notifyChange(.notesDidChange)
    }

    /// `deleteNotes()` removes every stored note, for a server whose Notes app is absent or too old to talk to.
    ///
    /// Announcing nothing when there was nothing to delete is deliberate: an instance that has never had the Notes app would otherwise have its Spotlight index rebuilt on every launch for a domain it does not have.
    func deleteNotes() {
        guard let account = currentAccount(createIfNeeded: false) else {
            return
        }

        guard account.notes.isEmpty == false else {
            return
        }

        for note in account.notes {
            context.delete(note)
        }

        save()
        notifyChange(.notesDidChange)
    }
}
