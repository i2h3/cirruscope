// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `NoteSortingTests` pins the single order every list of notes is shown in: favourites first, then most recently changed, then by title, then by identifier.
///
/// The last two exist to make the ordering total, and that is not pedantry here: the server stamps modification in whole seconds, so two notes saved in the same second are ordinary, and `sorted(by:)` promises no stability. An unstable order means the identifier behind a donated Spotlight row can move under the user between one refresh and the next.
struct NoteSortingTests {
    private func note(_ id: Int, _ title: String, favorite: Bool = false, at seconds: TimeInterval = 100) -> NoteTransferObject {
        NoteTransferObject(id: id, title: title, category: "", isFavorite: favorite, isReadOnly: false, modification: Date(timeIntervalSince1970: seconds))
    }

    @Test
    func `A favourite comes before a more recently changed note that is not one`() {
        let sorted = [note(1, "Recent", at: 900), note(2, "Pinned", favorite: true, at: 100)].sortedByPriority()

        #expect(sorted.map(\.id) == [2, 1])
    }

    @Test
    func `Among notes of equal standing, the most recently changed comes first`() {
        let sorted = [note(1, "Older", at: 100), note(2, "Newer", at: 200)].sortedByPriority()

        #expect(sorted.map(\.id) == [2, 1])
    }

    @Test
    func `Favourites are ordered among themselves by how recently they changed`() {
        let sorted = [note(1, "Older", favorite: true, at: 100), note(2, "Newer", favorite: true, at: 200)].sortedByPriority()

        #expect(sorted.map(\.id) == [2, 1])
    }

    @Test
    func `Notes changed in the same second are ordered by title`() {
        let sorted = [note(1, "Zebra"), note(2, "Alpha")].sortedByPriority()

        #expect(sorted.map(\.id) == [2, 1])
    }

    @Test
    func `Two notes sharing a second and a title are ordered by identifier`() {
        let sorted = [note(2, "Notes"), note(1, "Notes")].sortedByPriority()

        #expect(sorted.map(\.id) == [1, 2])
    }

    @Test
    func `The same notes come out in the same order whichever order they arrive in`() {
        let all = NoteFixture.all

        #expect(all.sortedByPriority().map(\.id) == all.reversed().sortedByPriority().map(\.id))
    }

    @Test
    func `The fixture corpus orders as the rule describes`() {
        // Favourite first despite being the oldest, then the two ordinary notes by recency.
        #expect(NoteFixture.all.sortedByPriority().map(\.id) == [3, 1, 2])
    }
}
