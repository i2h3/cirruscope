// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `ConversationSortingTests` pins the single order every list of Talk conversations is shown in.
///
/// The server does not sort them at all, so whatever order they arrive in is an accident of the response, and the rule has to live somewhere that every surface shares. These cases also pin that the order is *total*: `sorted(by:)` promises no stability, and the server stamps activity in whole seconds, so ties are common rather than theoretical and two lists built from the same conversations must not be able to disagree.
struct ConversationSortingTests {
    private func conversation(_ id: String, _ name: String, _ secondsSinceEpoch: TimeInterval) -> ConversationTransferObject {
        ConversationTransferObject(id: id, name: name, kind: .group, lastActivity: Date(timeIntervalSince1970: secondsSinceEpoch), avatarVersion: "")
    }

    @Test
    func `The most recently active conversation comes first`() {
        let sorted = [conversation("a", "Older", 100), conversation("b", "Newer", 200)].sortedByActivity()

        #expect(sorted.map(\.id) == ["b", "a"])
    }

    @Test
    func `Conversations active at the same moment are ordered by name`() {
        let sorted = [conversation("a", "Zebra", 100), conversation("b", "Alpha", 100)].sortedByActivity()

        #expect(sorted.map(\.id) == ["b", "a"])
    }

    @Test
    func `Two conversations sharing a moment and a name are ordered by token`() {
        let sorted = [conversation("b", "Design", 100), conversation("a", "Design", 100)].sortedByActivity()

        #expect(sorted.map(\.id) == ["a", "b"])
    }

    @Test
    func `The same conversations come out in the same order whichever order they arrive in`() {
        let all = [conversation("a", "Design", 100), conversation("b", "Design", 100), conversation("c", "Build", 300)]

        #expect(all.sortedByActivity().map(\.id) == all.reversed().sortedByActivity().map(\.id))
    }

    @Test
    func `A name is collated the way a person reads it rather than by Unicode scalar`() {
        let sorted = [conversation("a", "design", 100), conversation("b", "Build", 100)].sortedByActivity()

        // `<` would file every lowercase name behind every uppercase one, so "design" would come after "Build"
        // only by accident of case rather than because of its letter.
        #expect(sorted.map(\.id) == ["b", "a"])
    }
}
