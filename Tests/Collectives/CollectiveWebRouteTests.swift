// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `CollectiveWebRouteTests` pins where a collective and a page within it are opened.
///
/// These two were the only addresses in the app not read out of the owning app's own routing, and the cost of that showed up on a live server: both resolved, both opened a window, and neither showed what was asked for. The Collectives app declares a catch-all on the server and decides the rest in its Vue router, so what the suite is written against is that router — `'/:collectiveSlug-:collectiveId(\\d+)'` before `'/:collective'`, each with the children `':pageSlug-:pageId(\\d+)'` before `':page(.*)'`.
///
/// So the cases come in pairs: the slugged form, which is what a current server gives and what the app's own links carry, and the unslugged one, which the network library documents as what an instance whose Collectives app predates slugs answers with.
struct CollectiveWebRouteTests {
    @Test
    func `A collective is addressed by its slug and identifier together`() throws {
        let server = try #require(URL(string: "https://cloud.example.com"))
        let route = try #require(CollectiveWebRoute.url(for: CollectiveFixture.cookbook, on: server))

        #expect(route.url.absoluteString == "https://cloud.example.com/apps/collectives/cookbook-1")
    }

    /// The slug is `nil` on an instance whose Collectives app predates them, and the router's second pattern is what takes the name.
    @Test
    func `A collective with no slug is addressed by its name`() throws {
        let server = try #require(URL(string: "https://cloud.example.com"))
        let route = try #require(CollectiveWebRoute.url(for: CollectiveFixture.handbook, on: server))

        #expect(route.url.absoluteString == "https://cloud.example.com/apps/collectives/Nextcloud%20Handbook")
    }

    @Test
    func `A subdirectory install keeps its web root in front of a collective`() throws {
        let server = try #require(URL(string: "https://example.com/nextcloud"))
        let route = try #require(CollectiveWebRoute.url(for: CollectiveFixture.cookbook, on: server))

        #expect(route.url.absoluteString == "https://example.com/nextcloud/apps/collectives/cookbook-1")
    }

    @Test
    func `A collective with neither slug nor name is refused rather than opening the overview`() throws {
        let server = try #require(URL(string: "https://cloud.example.com"))
        let nameless = CollectiveTransferObject(id: 9, name: "", slug: nil, emoji: nil)

        #expect(CollectiveWebRoute.url(for: nameless, on: server) == nil)
    }

    @Test
    func `A page is addressed by its slug and identifier within its collective`() throws {
        let server = try #require(URL(string: "https://cloud.example.com"))
        let route = try #require(CollectivePageWebRoute.url(for: CollectiveFixture.pancakes, in: CollectiveFixture.cookbook, on: server))

        #expect(route.url.absoluteString == "https://cloud.example.com/apps/collectives/cookbook-1/pancakes-11")
    }

    /// A page with subpages is stored as a folder's `Readme.md`, which changes its *path* and nothing about its slug — so the slugged form is unaffected by the distinction the path form has to make.
    @Test
    func `A page that has subpages is addressed no differently`() throws {
        let server = try #require(URL(string: "https://cloud.example.com"))
        let route = try #require(CollectivePageWebRoute.url(for: CollectiveFixture.desserts, in: CollectiveFixture.cookbook, on: server))

        #expect(route.url.absoluteString == "https://cloud.example.com/apps/collectives/cookbook-1/desserts-12")
    }

    /// The page at the root of a collective is what opening the collective shows, and has no address of its own.
    @Test
    func `A collective's landing page is addressed by the collective itself`() throws {
        let server = try #require(URL(string: "https://cloud.example.com"))
        let route = try #require(CollectivePageWebRoute.url(for: CollectiveFixture.landingPage, in: CollectiveFixture.cookbook, on: server))

        #expect(route.url.absoluteString == "https://cloud.example.com/apps/collectives/cookbook-1")
    }

    /// The fallback branch, and the only one that still builds a path out of titles. It carries the file identifier because a path built from titles is the part that can be wrong.
    @Test
    func `A page with no slug is addressed by its path and carries its file identifier`() throws {
        let server = try #require(URL(string: "https://cloud.example.com"))
        let route = try #require(CollectivePageWebRoute.url(for: CollectiveFixture.unsluggedPage, in: CollectiveFixture.cookbook, on: server))

        #expect(route.url.absoluteString == "https://cloud.example.com/apps/collectives/cookbook-1/Recipes/Waffles?fileId=13")
    }

    @Test
    func `A subdirectory install keeps its web root in front of a page`() throws {
        let server = try #require(URL(string: "https://example.com/nextcloud"))
        let route = try #require(CollectivePageWebRoute.url(for: CollectiveFixture.pancakes, in: CollectiveFixture.cookbook, on: server))

        #expect(route.url.absoluteString == "https://example.com/nextcloud/apps/collectives/cookbook-1/pancakes-11")
    }

    /// A page in a collective that cannot be named cannot be addressed either, the collective's own segment being the front of every page's address.
    @Test
    func `A page in a nameless collective is refused`() throws {
        let server = try #require(URL(string: "https://cloud.example.com"))
        let nameless = CollectiveTransferObject(id: 9, name: "", slug: nil, emoji: nil)

        #expect(CollectivePageWebRoute.url(for: CollectiveFixture.pancakes, in: nameless, on: server) == nil)
    }
}
