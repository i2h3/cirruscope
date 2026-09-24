// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `CollectiveSortingTests` pins the two orders this domain uses, and that they are deliberately different from each other.
///
/// Collectives are alphabetical and their pages are by recency, which looks inconsistent until the rule behind it is stated: the order follows what the list is for. A collective is a container somebody named; a page is a document. The suite asserts both so a later change cannot quietly make them agree.
struct CollectiveSortingTests {
    @Test
    func `Collectives are ordered alphabetically by name`() {
        #expect(CollectiveFixture.all.sortedByName().map(\.id) == [1, 2])
    }

    @Test
    func `A lowercase collective name is ordered by its letter rather than behind every uppercase one`() {
        let collectives = [
            CollectiveTransferObject(id: 1, name: "Zebra", slug: nil, emoji: nil),
            CollectiveTransferObject(id: 2, name: "apples", slug: nil, emoji: nil),
        ]

        #expect(collectives.sortedByName().map(\.id) == [2, 1])
    }

    @Test
    func `Two collectives sharing a name are ordered by identifier`() {
        let collectives = [
            CollectiveTransferObject(id: 2, name: "Team", slug: nil, emoji: nil),
            CollectiveTransferObject(id: 1, name: "Team", slug: nil, emoji: nil),
        ]

        #expect(collectives.sortedByName().map(\.id) == [1, 2])
    }

    @Test
    func `Pages are ordered by how recently they changed, not by name`() {
        #expect(CollectiveFixture.pages.sortedByModification().map(\.id) == [11, 12, 10])
    }

    @Test
    func `Pages changed in the same second are ordered by title, then by identifier`() {
        let moment = Date(timeIntervalSince1970: 1_700_000_000)
        let pages = [
            CollectivePageTransferObject(id: 2, collectiveID: 1, title: "Same", slug: nil, emoji: nil, fileName: "Same.md", filePath: "", isLandingPage: false, modification: moment),
            CollectivePageTransferObject(id: 1, collectiveID: 1, title: "Same", slug: nil, emoji: nil, fileName: "Same.md", filePath: "", isLandingPage: false, modification: moment),
        ]

        #expect(pages.sortedByModification().map(\.id) == [1, 2])
    }

    @Test
    func `The same pages come out in the same order whichever order they arrive in`() {
        #expect(CollectiveFixture.pages.sortedByModification().map(\.id) == CollectiveFixture.pages.reversed().sortedByModification().map(\.id))
    }
}
