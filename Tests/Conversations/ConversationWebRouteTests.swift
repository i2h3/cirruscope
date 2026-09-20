// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `ConversationWebRouteTests` pins where a Talk conversation is opened, which is the one thing about this feature that cannot be recovered from a wrong answer.
///
/// A deep link that opens the wrong page is worse than one that opens nothing: the user sees a page load and has no reason to think the app misunderstood them. So the cases below cover the shapes of server address a real instance takes — a bare host, one installed in a subdirectory, one on a non-default port — rather than only the happy one, because the route is at the server's own root and a subdirectory install is exactly where a hand-built path goes wrong.
struct ConversationWebRouteTests {
    @Test
    func `A conversation is addressed at the server's own root rather than under Talk's app prefix`() throws {
        let server = try #require(URL(string: "https://cloud.example.com"))
        let route = try #require(ConversationWebRoute.url(forToken: "a1b2c3d4", on: server))

        #expect(route.url.absoluteString == "https://cloud.example.com/call/a1b2c3d4")
    }

    @Test
    func `A subdirectory install keeps its web root in front of the conversation route`() throws {
        let server = try #require(URL(string: "https://example.com/nextcloud"))
        let route = try #require(ConversationWebRoute.url(forToken: "a1b2c3d4", on: server))

        #expect(route.url.absoluteString == "https://example.com/nextcloud/call/a1b2c3d4")
    }

    @Test
    func `A non-default port is kept`() throws {
        let server = try #require(URL(string: "https://cloud.example.com:8443"))
        let route = try #require(ConversationWebRoute.url(forToken: "a1b2c3d4", on: server))

        #expect(route.url.absoluteString == "https://cloud.example.com:8443/call/a1b2c3d4")
    }

    @Test
    func `An empty token is refused rather than opening Talk's conversation list`() throws {
        let server = try #require(URL(string: "https://cloud.example.com"))

        #expect(ConversationWebRoute.url(forToken: "", on: server) == nil)
    }

    @Test
    func `A token is percent-encoded rather than pasted into the path`() throws {
        let server = try #require(URL(string: "https://cloud.example.com"))
        let route = try #require(ConversationWebRoute.url(forToken: "a b", on: server))

        #expect(route.url.absoluteString == "https://cloud.example.com/call/a%20b")
    }

    @Test
    func `A conversation route resolves back to Talk, so a window showing one knows which app it is in`() throws {
        let server = try #require(URL(string: "https://cloud.example.com"))
        let route = try #require(ConversationWebRoute.url(forToken: "a1b2c3d4", on: server))

        // The other half of the same fact: `ServerAppPath` maps the root route back to Talk's own path, which is
        // what titles the iPhone's navigation bar and what lets the Mac reuse the window already showing Talk.
        #expect(ServerAppPath.appID(of: route.url, on: server) == "spreed")
    }
}
