// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `EntityActivationTests` covers what each kind of donated entity resolves to, and what happens when it cannot resolve.
///
/// This is the layer the Spotlight tap and the Shortcuts action now share, and sharing it is the point: before it existed the resolution lived inside the intents alone, so the Spotlight side had none of it and opened nothing for four of the five types. A case per type is therefore not repetition — it is the assertion that all five are served.
///
/// Every case reads a store of its own through `AccountStoreHarness`, and none names `AccountStore.shared`, whose container holds the developer's real account.
@MainActor
struct EntityActivationTests {
    /// `harness` is this case's own store.
    private let harness = AccountStoreHarness()

    /// `serverAddress` is the instance the seeded account is signed in to.
    private let serverAddress = URL(string: "https://cloud.example.com")

    /// `seededStore()` is a store holding one account with every domain populated from the shared fixtures.
    private func seededStore() throws -> AccountStore {
        let server = try #require(serverAddress)
        let store = harness.store

        store.connect(to: server)
        store.persist(serverApps: ServerAppFixture.all)
        store.persist(conversations: ConversationFixture.all)
        store.persist(notes: NoteFixture.all)
        store.persist(collectives: CollectiveFixture.all)
        store.persist(pages: CollectiveFixture.pages, inCollective: CollectiveFixture.cookbook.id)

        return store
    }

    /// `openedAddress(_:)` is the address an outcome opens, or `nil` when it opens nothing or opens an app rather than a page.
    private func openedAddress(_ outcome: EntityActivation.Outcome) -> String? {
        guard case let .open(request) = outcome else {
            return nil
        }

        guard case let .page(address) = request else {
            return nil
        }

        return address.url.absoluteString
    }

    @Test
    func `A server app resolves to itself, by identity rather than by address`() throws {
        let store = try seededStore()
        let outcome = EntityActivation.outcome(forServerAppID: "files", in: store)

        guard case let .open(request) = outcome else {
            Issue.record("A server app the account has must resolve to something openable.")
            return
        }

        guard case let .serverApp(app) = request else {
            Issue.record("A server app opens by identity, so that a window already showing it can be reused.")
            return
        }

        #expect(app.id == "files")
    }

    @Test
    func `A conversation resolves to its address at the server's own root`() throws {
        let store = try seededStore()
        let outcome = EntityActivation.outcome(forConversationToken: ConversationFixture.alice.id, in: store)

        #expect(openedAddress(outcome) == "https://cloud.example.com/call/al1ce000")
    }

    @Test
    func `A note resolves to its address under the Notes app`() throws {
        let store = try seededStore()
        let outcome = EntityActivation.outcome(forNoteID: NoteFixture.groceries.id, in: store)

        #expect(openedAddress(outcome) == "https://cloud.example.com/apps/notes/note/1")
    }

    @Test
    func `A collective resolves to its address, addressed by its slug`() throws {
        let store = try seededStore()
        let outcome = EntityActivation.outcome(forCollectiveID: CollectiveFixture.cookbook.id, in: store)

        #expect(openedAddress(outcome) == "https://cloud.example.com/apps/collectives/cookbook-1")
    }

    @Test
    func `A page resolves to its address within its collective, carrying its file identifier`() throws {
        let store = try seededStore()
        let outcome = EntityActivation.outcome(forCollectivePageID: CollectiveFixture.pancakes.id, in: store)

        #expect(openedAddress(outcome) == "https://cloud.example.com/apps/collectives/cookbook-1/pancakes-11")
    }

    /// The page at the root of a collective has no address of its own, and its collective's is the right answer rather than a fallback.
    @Test
    func `A collective's landing page resolves to the collective itself`() throws {
        let store = try seededStore()
        let outcome = EntityActivation.outcome(forCollectivePageID: CollectiveFixture.landingPage.id, in: store)

        #expect(openedAddress(outcome) == "https://cloud.example.com/apps/collectives/cookbook-1")
    }

    /// A donated item outlives the list it came from, so every type has to survive being asked for something the account no longer has.
    @Test
    func `An entity the account no longer has is reported missing rather than opened`() throws {
        let store = try seededStore()

        #expect(isMissing(EntityActivation.outcome(forServerAppID: "gone", in: store)))
        #expect(isMissing(EntityActivation.outcome(forConversationToken: "n0suchtk", in: store)))
        #expect(isMissing(EntityActivation.outcome(forNoteID: 9999, in: store)))
        #expect(isMissing(EntityActivation.outcome(forCollectiveID: 9999, in: store)))
        #expect(isMissing(EntityActivation.outcome(forCollectivePageID: 9999, in: store)))
    }

    /// An account that was signed out between the donation and the tap has nothing to resolve against, and that is a different answer from the entity being gone: nothing the user picks instead would help.
    @Test
    func `With no server configured nothing is addressable`() throws {
        let store = try seededStore()
        store.deleteAccount()

        #expect(isMissing(EntityActivation.outcome(forNoteID: NoteFixture.groceries.id, in: store)))
    }

    /// `isMissing(_:)` reports whether an outcome is the one that asks for a different value.
    private func isMissing(_ outcome: EntityActivation.Outcome) -> Bool {
        guard case .missing = outcome else {
            return false
        }

        return true
    }
}
