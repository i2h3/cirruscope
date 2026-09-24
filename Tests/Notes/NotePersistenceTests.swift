// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `NotePersistenceTests` covers what `AccountStore` does with the notes a refresh found: the upsert, the pruning, the order they come back in, and that a write announces itself while a read does not.
///
/// One case here is not like the others and is the reason the suite matters beyond symmetry: the store has nowhere to put a note's text, and a case asserts that the type it is written with has no such field. That is a weaker assertion than it sounds only if the value type is never changed — which is exactly when someone would add one.
@MainActor
@Suite(.serialized)
struct NotePersistenceTests {
    /// `harness` is this case's own store over a fresh in-memory container.
    private let harness = AccountStoreHarness()

    @Test
    func `A store with no account has no notes`() {
        #expect(harness.store.notes.isEmpty)
    }

    @Test
    func `Persisting notes for the first time creates the account and stores them`() {
        harness.store.persist(notes: NoteFixture.all)

        #expect(harness.store.notes.count == 3)
    }

    @Test
    func `Notes are returned favourites first and then most recently changed, whatever order the server sent them in`() {
        harness.store.persist(notes: NoteFixture.all)

        #expect(harness.store.notes.map(\.id) == [3, 1, 2])
    }

    @Test
    func `A refresh updates a note in place rather than replacing it`() {
        harness.store.persist(notes: [NoteFixture.groceries])

        let edited = NoteTransferObject(id: NoteFixture.groceries.id, title: "Groceries and errands", category: "Errands", isFavorite: true, isReadOnly: false, modification: Date(timeIntervalSince1970: 1_700_009_000))
        harness.store.persist(notes: [edited])

        #expect(harness.store.notes.count == 1)
        #expect(harness.store.notes.first?.title == "Groceries and errands")
        #expect(harness.store.notes.first?.category == "Errands")
        #expect(harness.store.notes.first?.isFavorite == true)
    }

    @Test
    func `A refresh deletes a note the server no longer lists`() {
        harness.store.persist(notes: NoteFixture.all)
        harness.store.persist(notes: [NoteFixture.groceries])

        #expect(harness.store.notes.map(\.id) == [1])
    }

    @Test
    func `Persisting an empty list deletes every note`() {
        harness.store.persist(notes: NoteFixture.all)
        harness.store.persist(notes: [])

        #expect(harness.store.notes.isEmpty)
    }

    @Test
    func `The same note listed twice is stored once`() {
        harness.store.persist(notes: [NoteFixture.groceries, NoteFixture.groceries])

        #expect(harness.store.notes.count == 1)
    }

    @Test
    func `A note is found by its identifier, and an unknown identifier finds nothing`() {
        harness.store.persist(notes: NoteFixture.all)

        #expect(harness.store.note(forID: 2)?.title == "Pancakes")
        #expect(harness.store.note(forID: 999) == nil)
    }

    @Test
    func `A note with no category round-trips as having none rather than as having a missing one`() {
        harness.store.persist(notes: [NoteFixture.pinned])

        // The server sends an empty string rather than nothing, and there is no third state for a `nil` to mean,
        // so the value type stores what the server said rather than inventing an optional.
        #expect(harness.store.note(forID: 3)?.category == "")
    }

    @Test
    func `Deleting the account takes its notes with it`() {
        harness.store.persist(notes: NoteFixture.all)
        harness.store.deleteAccount()

        #expect(harness.store.notes.isEmpty)
    }

    @Test
    func `Every write announces the notes changed, and reading announces nothing`() {
        harness.store.persist(notes: NoteFixture.all)
        #expect(harness.announcements == [.notesDidChange])

        _ = harness.store.notes
        #expect(harness.announcements == [.notesDidChange])
    }

    @Test
    func `Dropping the notes of a server without a usable Notes app announces once, and again does nothing`() {
        harness.store.persist(notes: NoteFixture.all)
        harness.store.deleteNotes()

        #expect(harness.store.notes.isEmpty)
        #expect(harness.announcements == [.notesDidChange, .notesDidChange])

        // Nothing to delete is not a change: an instance that has never had the Notes app would otherwise have its
        // Spotlight index rebuilt on every launch for a domain it does not have.
        harness.store.deleteNotes()
        #expect(harness.announcements.count == 2)
    }

    @Test
    func `Nothing the store is written with can carry a note's text`() throws {
        // The safeguard against a note's body reaching an unencrypted store is that the value type the store is
        // written with has no field for one — not a rule somebody has to remember at each call site. This asserts
        // the shape rather than a behaviour, which is the point: it fails the moment the shape changes, which is
        // the moment the decision in DECISIONS.md would be getting reversed by accident.
        let encoded = try JSONEncoder().encode(NoteFixture.groceries)
        let fields = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(Set(fields.keys) == ["id", "title", "category", "isFavorite", "isReadOnly", "modification"])
    }
}
