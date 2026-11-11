// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
@testable import Cirruscope
import Foundation
import Testing

/// `EntityIdentifierRoundTripTests` pins the two facts the Spotlight selection path reads a donated identifier with.
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
