// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
@testable import Cirruscope
import Foundation
import Testing

/// `EntityIdentifierRoundTripTests` measures that App Intents' own identifier carries the entity's *type* as well as its identifier, and that two types sharing one identifier stay apart.
///
/// This is the assumption the Spotlight selection path rests on, and it is measured rather than restated because the app got it wrong once in exactly the way a restatement would not have caught: the identifier was read out of a selection and the type thrown away, so every donated item that was not a server app resolved to nothing and opened nothing. An identifier is unique within a type and not across them — `42` is a note and also a collective and also a page — so without the type there is no honest way to resolve one.
///
/// **What this deliberately does not test, having measured why it cannot:** the fallback that parses a raw Spotlight identifier through `EntityIdentifier(activityIdentifier:)`. There is no public way to produce such a string — `EntityIdentifier.description` answers `"NoteEntity/<redacted>"`, with the identifier withheld, and feeding that back returns `nil` — so the only source of a real one is an item Spotlight itself donated. That path is exercised on a device and logged at `.notice`; pretending to cover it here would be covering a string this app invented.
struct EntityIdentifierRoundTripTests {
    /// Each comparison of two metatypes is made into a `Bool` before an expectation sees it, because the macro rewrites the expression it is given and loses the static type of a member access on the way.
    @Test
    func `An identifier built for an entity type reports that type back`() {
        let isNote = EntityIdentifier(for: NoteEntity.self, identifier: 42).entityType == NoteEntity.self
        let isCollective = EntityIdentifier(for: CollectiveEntity.self, identifier: 42).entityType == CollectiveEntity.self
        let isPage = EntityIdentifier(for: CollectivePageEntity.self, identifier: 42).entityType == CollectivePageEntity.self
        let isServerApp = EntityIdentifier(for: ServerAppEntity.self, identifier: "notes").entityType == ServerAppEntity.self
        let isConversation = EntityIdentifier(for: ConversationEntity.self, identifier: "al1ce000").entityType == ConversationEntity.self

        #expect(isNote)
        #expect(isCollective)
        #expect(isPage)
        #expect(isServerApp)
        #expect(isConversation)
    }

    /// The one that pins the defect itself: three entity types sharing one identifier are three different identifiers, and anything reading only the identifier would see them as one.
    @Test
    func `Three types sharing one identifier do not collapse into one`() {
        let note = EntityIdentifier(for: NoteEntity.self, identifier: 42)
        let collective = EntityIdentifier(for: CollectiveEntity.self, identifier: 42)
        let page = EntityIdentifier(for: CollectivePageEntity.self, identifier: 42)

        #expect(note.identifier == collective.identifier)
        #expect(collective.identifier == page.identifier)

        #expect(note != collective)
        #expect(collective != page)
        #expect(note != page)
    }

    /// A numeric entity's identifier crosses as text, which is why the selection path parses it back rather than assuming it arrives as a number.
    @Test
    func `A numeric identifier is carried as its decimal text`() {
        #expect(EntityIdentifier(for: NoteEntity.self, identifier: 42).identifier == "42")
        #expect(EntityIdentifier(for: CollectivePageEntity.self, identifier: 0).identifier == "0")
    }
}
