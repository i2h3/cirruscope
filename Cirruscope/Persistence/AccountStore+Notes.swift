// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import SwiftData

/// `AccountStore`'s notes: reading them back as value snapshots, and writing what a refresh found.
///
/// What it never holds is a note's text. The refresh never downloads it, so it is not a rule this file has to keep; the value type it takes has nowhere to put one.
extension AccountStore {
    /// `notes` are the connected account's notes as value snapshots, favourites first and then most recently changed.
    var notes: [NoteTransferObject] {
        guard let account = currentAccount(createIfNeeded: false) else {
            return []
        }

        return account.notes
            .map { NoteTransferObject(id: $0.noteID, title: $0.title, category: $0.category, isFavorite: $0.isFavorite, isReadOnly: $0.isReadOnly, modification: $0.modification) }
            .sortedByPriority()
    }

    /// `note(forID:)` is the connected account's note with `id` as a value snapshot, or `nil` when the account has no such note.
    func note(forID id: Int) -> NoteTransferObject? {
        guard let note = currentAccount(createIfNeeded: false)?.notes.first(where: { $0.noteID == id }) else {
            return nil
        }

        return NoteTransferObject(id: note.noteID, title: note.title, category: note.category, isFavorite: note.isFavorite, isReadOnly: note.isReadOnly, modification: note.modification)
    }

    /// `persist(notes:)` upserts the account's notes: existing rows are updated in place, new ones inserted, and ones the server no longer lists deleted.
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
        var inserted = 0
        var updated = 0
        var pruned = 0

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
                updated += 1
            } else {
                context.insert(ServerNote(noteID: note.id, title: note.title, category: note.category, isFavorite: note.isFavorite, isReadOnly: note.isReadOnly, modification: note.modification, account: account))
                inserted += 1
            }
        }

        for note in existingNotes where incomingIDs.contains(note.noteID) == false {
            context.delete(note)
            pruned += 1
        }

        logger.notice("Persisting notes: \(inserted, privacy: .public) inserted, \(updated, privacy: .public) updated, \(pruned, privacy: .public) pruned, \(incomingIDs.count, privacy: .public) stored")
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

        logger.notice("Dropping every stored note (\(account.notes.count, privacy: .public))")

        for note in account.notes {
            context.delete(note)
        }

        save()
        notifyChange(.notesDidChange)
    }
}
