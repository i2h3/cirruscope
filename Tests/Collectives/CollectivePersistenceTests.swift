// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `CollectivePersistenceTests` covers what `AccountStore` does with the collectives a refresh found and with the pages of each.
///
/// The cases that earn the suite are the ones about scope. Pages are fetched one collective at a time, so a write of the collectives alone must leave the pages already stored for them alone, and a write of one collective's pages must not touch another's. Both are easy to get wrong in a way that only shows up on an account with more than one collective, which is why the fixture has two.
@MainActor
@Suite(.serialized)
struct CollectivePersistenceTests {
    /// `harness` is this case's own store over a fresh in-memory container.
    private let harness = AccountStoreHarness()

    @Test
    func `A store with no account has no collectives and no pages`() {
        #expect(harness.store.collectives.isEmpty)
        #expect(harness.store.collectivePages.isEmpty)
    }

    @Test
    func `Persisting collectives for the first time creates the account and stores them alphabetically`() {
        harness.store.persist(collectives: CollectiveFixture.all)

        #expect(harness.store.collectives.map(\.id) == [1, 2])
    }

    @Test
    func `A refresh updates a collective in place rather than replacing it`() {
        harness.store.persist(collectives: [CollectiveFixture.cookbook])

        let renamed = CollectiveTransferObject(id: 1, name: "Recipes", slug: "recipes", emoji: "🍳")
        harness.store.persist(collectives: [renamed])

        #expect(harness.store.collectives.count == 1)
        #expect(harness.store.collective(forID: 1)?.name == "Recipes")
        #expect(harness.store.collective(forID: 1)?.slug == "recipes")
    }

    @Test
    func `A collective the server no longer lists is deleted, and its pages with it`() {
        harness.store.persist(collectives: CollectiveFixture.all)
        harness.store.persist(pages: CollectiveFixture.pages, inCollective: 1)
        #expect(harness.store.collectivePages.count == 3)

        harness.store.persist(collectives: [CollectiveFixture.handbook])

        #expect(harness.store.collectives.map(\.id) == [2])
        #expect(harness.store.collectivePages.isEmpty)
    }

    @Test
    func `Re-listing the collectives leaves the pages already stored for them alone`() {
        harness.store.persist(collectives: CollectiveFixture.all)
        harness.store.persist(pages: CollectiveFixture.pages, inCollective: 1)

        // The pages are fetched per collective, so a write of the collectives knows nothing about them. Matching by
        // identifier rather than replacing the list is what keeps this from emptying every collective on a refresh.
        harness.store.persist(collectives: CollectiveFixture.all)

        #expect(harness.store.collectivePages.count == 3)
    }

    @Test
    func `Writing one collective's pages does not touch another's`() {
        harness.store.persist(collectives: CollectiveFixture.all)
        harness.store.persist(pages: [CollectiveFixture.pancakes], inCollective: 1)

        let other = CollectivePageTransferObject(id: 20, collectiveID: 2, title: "Support", slug: "support", emoji: nil, fileName: "Support.md", filePath: "", isLandingPage: false, modification: Date(timeIntervalSince1970: 1_700_000_000))
        harness.store.persist(pages: [other], inCollective: 2)

        #expect(Set(harness.store.collectivePages.map(\.id)) == [11, 20])
    }

    @Test
    func `A page the server no longer lists is deleted from its collective`() {
        harness.store.persist(collectives: [CollectiveFixture.cookbook])
        harness.store.persist(pages: CollectiveFixture.pages, inCollective: 1)
        harness.store.persist(pages: [CollectiveFixture.pancakes], inCollective: 1)

        #expect(harness.store.collectivePages.map(\.id) == [11])
    }

    @Test
    func `Pages written for a collective the account does not have are ignored`() {
        harness.store.persist(pages: CollectiveFixture.pages, inCollective: 99)

        #expect(harness.store.collectivePages.isEmpty)
    }

    @Test
    func `Pages come back most recently changed first, across every collective`() {
        harness.store.persist(collectives: CollectiveFixture.all)
        harness.store.persist(pages: CollectiveFixture.pages, inCollective: 1)

        #expect(harness.store.collectivePages.map(\.id) == [11, 12, 10])
    }

    @Test
    func `A page is found by its identifier across every collective, and an unknown one finds nothing`() {
        harness.store.persist(collectives: CollectiveFixture.all)
        harness.store.persist(pages: CollectiveFixture.pages, inCollective: 1)

        #expect(harness.store.collectivePage(forID: 11)?.title == "Pancakes")
        #expect(harness.store.collectivePage(forID: 11)?.collectiveID == 1)
        #expect(harness.store.collectivePage(forID: 999) == nil)
    }

    @Test
    func `A collective without a slug round-trips as having none`() {
        harness.store.persist(collectives: CollectiveFixture.all)

        #expect(harness.store.collective(forID: 2)?.slug == nil)
        #expect(harness.store.collective(forID: 1)?.slug == "cookbook")
    }

    @Test
    func `Deleting the account takes its collectives and their pages with it`() {
        harness.store.persist(collectives: CollectiveFixture.all)
        harness.store.persist(pages: CollectiveFixture.pages, inCollective: 1)
        harness.store.deleteAccount()

        #expect(harness.store.collectives.isEmpty)
        #expect(harness.store.collectivePages.isEmpty)
    }

    @Test
    func `Every write announces the collectives changed, and reading announces nothing`() {
        harness.store.persist(collectives: CollectiveFixture.all)
        #expect(harness.announcements == [.collectivesDidChange])

        harness.store.persist(pages: CollectiveFixture.pages, inCollective: 1)
        #expect(harness.announcements == [.collectivesDidChange, .collectivesDidChange])

        _ = harness.store.collectivePages
        #expect(harness.announcements.count == 2)
    }

    @Test
    func `Dropping the collectives of a server without the app announces once, and again does nothing`() {
        harness.store.persist(collectives: CollectiveFixture.all)
        harness.store.deleteCollectives()

        #expect(harness.store.collectives.isEmpty)
        #expect(harness.announcements == [.collectivesDidChange, .collectivesDidChange])

        harness.store.deleteCollectives()
        #expect(harness.announcements.count == 2)
    }
}
