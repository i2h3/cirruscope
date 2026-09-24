// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `CollectiveWebRouteTests` pins the address that opens a collective and the one that opens a page within it.
///
/// These are the app's least certain routes: the Collectives app is installed on no instance available here, so unlike Talk's and Notes' they were derived rather than read out of the app's own routing. What the suite can still do is pin the parts that do not depend on that — that the web root of a subdirectory install is kept, that a collective without a slug falls back to its name rather than producing a path with a hole in it, and that the page-path rule handles the three file shapes the server actually produces. If the shape turns out to be wrong, these are the cases that will need changing, and they are deliberately written so that is a small edit rather than a rewrite.
struct CollectiveWebRouteTests {
    private let server = URL(string: "https://cloud.example.com")!

    @Test
    func `A collective is addressed by its slug`() throws {
        let route = try #require(CollectiveWebRoute.url(forSlug: "cookbook", name: "Cookbook", on: server))

        #expect(route.url.absoluteString == "https://cloud.example.com/apps/collectives/cookbook")
    }

    @Test
    func `A collective on a server without slugs is addressed by its name, percent-encoded`() throws {
        let route = try #require(CollectiveWebRoute.url(forSlug: nil, name: "Nextcloud Handbook", on: server))

        #expect(route.url.absoluteString == "https://cloud.example.com/apps/collectives/Nextcloud%20Handbook")
    }

    @Test
    func `A subdirectory install keeps its web root in front of the collective route`() throws {
        let subdirectory = try #require(URL(string: "https://example.com/nextcloud"))
        let route = try #require(CollectiveWebRoute.url(forSlug: "cookbook", name: "Cookbook", on: subdirectory))

        #expect(route.url.absoluteString == "https://example.com/nextcloud/apps/collectives/cookbook")
    }

    @Test
    func `A collective with neither a slug nor a name is refused rather than opening the list of every collective`() {
        #expect(CollectiveWebRoute.url(forSlug: nil, name: "", on: server) == nil)
        #expect(CollectiveWebRoute.url(forSlug: "", name: "", on: server) == nil)
    }

    @Test
    func `A collective route resolves back to Collectives, so a window showing one knows which app it is in`() throws {
        let route = try #require(CollectiveWebRoute.url(forSlug: "cookbook", name: "Cookbook", on: server))

        #expect(ServerAppPath.appID(of: route.url, on: server) == "collectives")
    }

    @Test
    func `A page sitting directly in a collective is addressed by its file name without the extension`() {
        #expect(CollectivePageWebRoute.pathComponents(forFileName: "Pancakes.md", filePath: "") == ["Pancakes"])
    }

    @Test
    func `A page inside a folder is addressed by the folder and then the file`() {
        #expect(CollectivePageWebRoute.pathComponents(forFileName: "Pancakes.md", filePath: "Recipes") == ["Recipes", "Pancakes"])
    }

    @Test
    func `A page with subpages is addressed by its folder alone, its file being that folder's index`() {
        // The server stores such a page as `Readme.md` inside a folder named after the page, so appending the file
        // name would repeat the page's own title in the path.
        #expect(CollectivePageWebRoute.pathComponents(forFileName: "Readme.md", filePath: "Desserts") == ["Desserts"])
    }

    @Test
    func `A nested page keeps its whole ancestor chain`() {
        #expect(CollectivePageWebRoute.pathComponents(forFileName: "Portal.md", filePath: "Support/How to") == ["Support", "How to", "Portal"])
    }

    @Test
    func `The page at the root of a collective is opened by the collective's own address`() throws {
        let route = try #require(CollectivePageWebRoute.url(collectiveSlug: "cookbook", collectiveName: "Cookbook", page: CollectiveFixture.landingPage, on: server))

        // Not a fallback: there is no separate address for the page a collective shows when it is opened.
        #expect(route.url.absoluteString == "https://cloud.example.com/apps/collectives/cookbook")
    }

    @Test
    func `An ordinary page carries its path and its file identifier`() throws {
        let route = try #require(CollectivePageWebRoute.url(collectiveSlug: "cookbook", collectiveName: "Cookbook", page: CollectiveFixture.pancakes, on: server))

        // The identifier is what the server can resolve the page from even where the path segments are not what it
        // expects, which is the hedge against this route's shape being the one thing here not read from the app's
        // own routing.
        #expect(route.url.absoluteString == "https://cloud.example.com/apps/collectives/cookbook/Recipes/Pancakes?fileId=11")
    }

    @Test
    func `A subdirectory install keeps its web root in front of a page's address too`() throws {
        let subdirectory = try #require(URL(string: "https://example.com/nextcloud"))
        let route = try #require(CollectivePageWebRoute.url(collectiveSlug: "cookbook", collectiveName: "Cookbook", page: CollectiveFixture.pancakes, on: subdirectory))

        // The collective route has had this case since it was written; the page route did not, and it is the more
        // restructured of the two — it builds the collective's segments and the page's together and appends the
        // file identifier afterwards. On a host-root server that branch is indistinguishable from the broken one.
        #expect(route.url.absoluteString == "https://example.com/nextcloud/apps/collectives/cookbook/Recipes/Pancakes?fileId=11")
    }

    @Test
    func `The landing page of a collective on a subdirectory install opens that collective`() throws {
        let subdirectory = try #require(URL(string: "https://example.com/nextcloud"))
        let route = try #require(CollectivePageWebRoute.url(collectiveSlug: "cookbook", collectiveName: "Cookbook", page: CollectiveFixture.landingPage, on: subdirectory))

        #expect(route.url.absoluteString == "https://example.com/nextcloud/apps/collectives/cookbook")
    }

    @Test
    func `A page of a collective with no slug is addressed under that collective's name`() throws {
        let route = try #require(CollectivePageWebRoute.url(collectiveSlug: nil, collectiveName: "Nextcloud Handbook", page: CollectiveFixture.pancakes, on: server))

        #expect(route.url.absoluteString == "https://cloud.example.com/apps/collectives/Nextcloud%20Handbook/Recipes/Pancakes?fileId=11")
    }

    @Test
    func `A page whose collective cannot be addressed is refused rather than opened somewhere arbitrary`() {
        #expect(CollectivePageWebRoute.url(collectiveSlug: nil, collectiveName: "", page: CollectiveFixture.pancakes, on: server) == nil)
    }
}
