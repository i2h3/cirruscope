// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
@testable import Cirruscope
import CoreSpotlight
import Foundation
import Testing

/// `SpotlightSelectionTests` covers reading a tapped Spotlight result back into something the app can open.
///
/// It exists because this is where the feature was broken: the selection was resolved by identifier alone, so only a server app ever came back and every note, conversation, collective and page the app had donated activated nothing. A person searching for a page of their collective watched Cirruscope come forward and sit there.
///
/// The activities are built the way Spotlight delivers one: a `CSSearchableItemActionType` whose `userInfo` carries `CSSearchableItemActivityIdentifier` as `<EntityTypeName>/<identifier>`. That shape is not invented here — it is what a result carried in the field, and what a probe confirmed is the only thing that arrives. `NSUserActivity.appEntityIdentifier` is deliberately not used by these cases or by the code they cover: it is held out of band, so assigning it leaves `userInfo` empty and it answers `nil` for an activity that crossed from Spotlight.
@MainActor
struct SpotlightSelectionTests {
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

    /// `selection(of:_:)` is the activity the system delivers when somebody taps a donated result of `entityType` named `identifier`.
    private func selection(of entityType: any AppEntity.Type, _ identifier: String) -> NSUserActivity {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: "\(String(describing: entityType))/\(identifier)"]

        return activity
    }

    /// `openedAddress(_:)` is the address a request opens, or `nil` when there is none or it opens an app instead.
    private func openedAddress(_ request: EntityOpening.Request?) -> String? {
        guard case let .page(address) = request else {
            return nil
        }

        return address.url.absoluteString
    }

    @Test
    func `A selected note resolves to the address that opens it`() throws {
        let store = try seededStore()
        let activity = selection(of: NoteEntity.self, String(NoteFixture.groceries.id))

        #expect(openedAddress(SpotlightSelection.request(from: activity, in: store)) == "https://cloud.example.com/apps/notes/note/1")
    }

    @Test
    func `A selected conversation resolves to the address that opens it`() throws {
        let store = try seededStore()
        let activity = selection(of: ConversationEntity.self, ConversationFixture.alice.id)

        #expect(openedAddress(SpotlightSelection.request(from: activity, in: store)) == "https://cloud.example.com/call/al1ce000")
    }

    @Test
    func `A selected collective resolves to the address that opens it`() throws {
        let store = try seededStore()
        let activity = selection(of: CollectiveEntity.self, String(CollectiveFixture.cookbook.id))

        #expect(openedAddress(SpotlightSelection.request(from: activity, in: store)) == "https://cloud.example.com/apps/collectives/cookbook-1")
    }

    /// The one from the report: a page of a collective, found by searching for its title, tapped, and opening nothing.
    @Test
    func `A selected collective page resolves to the address that opens it`() throws {
        let store = try seededStore()
        let activity = selection(of: CollectivePageEntity.self, String(CollectiveFixture.pancakes.id))

        #expect(openedAddress(SpotlightSelection.request(from: activity, in: store)) == "https://cloud.example.com/apps/collectives/cookbook-1/pancakes-11")
    }

    /// A server app is the one selection that opens by identity, so a window already showing it is reused rather than a second one opened.
    @Test
    func `A selected server app resolves to the app itself rather than to an address`() throws {
        let store = try seededStore()
        let activity = selection(of: ServerAppEntity.self, "files")

        guard case let .serverApp(app) = SpotlightSelection.request(from: activity, in: store) else {
            Issue.record("A selected server app must resolve to the app, not to a page.")
            return
        }

        #expect(app.id == "files")
    }

    /// Both platforms receive every kind of continuation through one entry point, so "is this even mine?" is part of the question being asked.
    @Test
    func `An activity of another type is not treated as a selection`() throws {
        let store = try seededStore()
        let activity = NSUserActivity(activityType: "de.i2h3.cirruscope.something-else")
        activity.userInfo = [CSSearchableItemActivityIdentifier: "NoteEntity/\(NoteFixture.groceries.id)"]

        #expect(SpotlightSelection.request(from: activity, in: store) == nil)
    }

    @Test
    func `A selection carrying no entity identifier at all opens nothing`() throws {
        let store = try seededStore()
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)

        #expect(SpotlightSelection.request(from: activity, in: store) == nil)
    }

    /// A donated item outlives the list it came from. Spotlight may still be showing a note the account deleted, and the honest answer to a tap on one is to leave the app where it is.
    @Test
    func `A selection naming something the account no longer has opens nothing`() throws {
        let store = try seededStore()
        let activity = selection(of: NoteEntity.self, "9999")

        #expect(SpotlightSelection.request(from: activity, in: store) == nil)
    }
}
