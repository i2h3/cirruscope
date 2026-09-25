// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
@testable import Cirruscope
import Foundation
import Testing

/// `EntityIdentifierRoundTripTests` pins the two facts the Spotlight selection path reads a donated identifier with.
///
/// The path was broken once in a way no restatement would have caught — the identifier was read out of a selection and the type thrown away, so every donated item that was not a server app opened nothing — and it was then broken a second time by the obvious repair. `EntityIdentifier(activityIdentifier:)` looks like a parser and is a round trip into the system's App Intents index, which answers about whichever copy of this app Launch Services calls canonical; on a development machine that is an older archive, and every type it does not list is refused. So the app reads the string itself, and what it reads it with is pinned here.
///
/// The first fact is the spelling. The parser matches `String(describing:)` of each entity metatype against the type name a selection carries, so those two have to agree — a Spotlight result seen in the field carried `CollectivePageEntity/4012700`.
/// The second is why the type is needed at all: an identifier is unique within a type and not across them.
struct EntityIdentifierRoundTripTests {
    /// The names are asserted as literals rather than derived, which is the point: a literal is what a donated identifier carries, and this is what fails if a type is ever renamed without the donated items being migrated.
    @Test
    func `Each entity type is spelled the way a donated identifier spells it`() {
        #expect(String(describing: ServerAppEntity.self) == "ServerAppEntity")
        #expect(String(describing: ConversationEntity.self) == "ConversationEntity")
        #expect(String(describing: NoteEntity.self) == "NoteEntity")
        #expect(String(describing: CollectiveEntity.self) == "CollectiveEntity")
        #expect(String(describing: CollectivePageEntity.self) == "CollectivePageEntity")
    }

    /// The one that pins the original defect: three entity types sharing one identifier are three different things, and anything reading only the identifier would see them as one.
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

    /// A numeric entity's identifier crosses as text, which is why the selection path reads it back rather than assuming it arrives as a number.
    @Test
    func `A numeric identifier is carried as its decimal text`() {
        #expect(EntityIdentifier(for: NoteEntity.self, identifier: 42).identifier == "42")
        #expect(EntityIdentifier(for: CollectivePageEntity.self, identifier: 0).identifier == "0")
    }
}
