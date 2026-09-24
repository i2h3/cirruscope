// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `SameOriginURLComponentsTests` covers building the address of a path the app itself knows, which is a different question from resolving one the server named.
///
/// The suite exists because the difference is invisible on the instances most people test against and decisive on the rest. A server-named path already carries the instance's web root, so resolving it from the root is right; a path the app knows does not, so resolving it the same way silently moves it to the host's own root. On `https://cloud.example.com` the two agree exactly, which is why this shipped in the iOS account menu and in the first draft of the Talk conversation route before a subdirectory case caught it.
///
/// The case worth having is therefore the one asserting the two initializers *disagree*. Testing the new one alone would pass just as well if it were quietly changed back to the old behaviour.
struct SameOriginURLComponentsTests {
    @Test
    func `Components are appended to the server's own path, so a subdirectory install keeps its web root`() throws {
        let server = try #require(URL(string: "https://example.com/nextcloud"))
        let address = try #require(SameOriginURL(components: ["settings", "user"], relativeTo: server))

        #expect(address.url.absoluteString == "https://example.com/nextcloud/settings/user")
    }

    @Test
    func `Appending components differs from resolving the same path from the server root, on a subdirectory install`() throws {
        let server = try #require(URL(string: "https://example.com/nextcloud"))

        let appended = try #require(SameOriginURL(components: ["settings", "user"], relativeTo: server))
        let resolved = try #require(SameOriginURL(path: "/settings/user", relativeTo: server))

        // Both are on the right server, which is why the mistake was not caught by the origin proof: the resolved
        // one lands on a page of the host that has nothing to do with this account.
        #expect(appended.url.absoluteString == "https://example.com/nextcloud/settings/user")
        #expect(resolved.url.absoluteString == "https://example.com/settings/user")
        #expect(appended.url != resolved.url)
    }

    @Test
    func `On an instance at the host root the two agree, which is why the difference goes unnoticed`() throws {
        let server = try #require(URL(string: "https://cloud.example.com"))

        let appended = try #require(SameOriginURL(components: ["settings", "user"], relativeTo: server))
        let resolved = try #require(SameOriginURL(path: "/settings/user", relativeTo: server))

        #expect(appended.url == resolved.url)
    }

    @Test
    func `A single component is appended to the server address`() throws {
        let server = try #require(URL(string: "https://cloud.example.com"))
        let address = try #require(SameOriginURL(components: ["call"], relativeTo: server))

        #expect(address.url.absoluteString == "https://cloud.example.com/call")
    }

    @Test
    func `A non-default port is kept`() throws {
        let server = try #require(URL(string: "https://cloud.example.com:8443"))
        let address = try #require(SameOriginURL(components: ["apps", "notes"], relativeTo: server))

        #expect(address.url.absoluteString == "https://cloud.example.com:8443/apps/notes")
    }

    @Test
    func `A component is escaped as one path segment rather than being read as several`() throws {
        let server = try #require(URL(string: "https://cloud.example.com"))
        let address = try #require(SameOriginURL(components: ["apps", "a/b c"], relativeTo: server))

        // A slash inside a component is part of the name, not a separator: a collective called "a/b c" is one
        // segment. Interpolating the component into a string would have made it two and changed what is opened.
        #expect(address.url.absoluteString == "https://cloud.example.com/apps/a%2Fb%20c")
    }

    @Test
    func `No components at all is refused rather than opening the server's own root`() throws {
        let server = try #require(URL(string: "https://cloud.example.com"))

        #expect(SameOriginURL(components: [], relativeTo: server) == nil)
    }

    @Test
    func `An empty component is refused rather than producing a doubled separator`() throws {
        let server = try #require(URL(string: "https://cloud.example.com"))

        // A caller reaching here with an empty segment has built a path out of something it did not have, and the
        // address that would result is a real page that would open and look like an answer.
        #expect(SameOriginURL(components: ["call", ""], relativeTo: server) == nil)
        #expect(SameOriginURL(components: ["", "user"], relativeTo: server) == nil)
    }

    @Test
    func `A dot-segment component is refused, because it would climb out of the instance's web root`() throws {
        let server = try #require(URL(string: "https://example.com/nextcloud"))

        #expect(SameOriginURL(components: ["apps", "..", "..", "settings"], relativeTo: server) == nil)
        #expect(SameOriginURL(components: ["apps", "."], relativeTo: server) == nil)
        #expect(SameOriginURL(components: [".."], relativeTo: server) == nil)
    }

    @Test
    func `Refusing a dot segment is what stops a server-named path escaping its own installation`() throws {
        let server = try #require(URL(string: "https://example.com/nextcloud"))

        // What the refusal above prevents, measured rather than asserted from memory: appending escapes a slash
        // but passes a dot segment through, so the address a server would resolve leaves the web root while
        // staying on the same origin — which is why the origin proof alone does not catch it. The components
        // reaching this initializer are often the server's own values, so this is its path to name, not the app's.
        var escaped = server
        for component in ["apps", "..", "..", "settings"] {
            escaped = escaped.appending(component: component)
        }

        #expect(escaped.standardized.absoluteString == "https://example.com/settings")
    }

    @Test
    func `A component that merely contains a dot is not a dot segment and is kept`() throws {
        let server = try #require(URL(string: "https://cloud.example.com"))
        let address = try #require(SameOriginURL(components: ["apps", "notes", "Readme.md"], relativeTo: server))

        #expect(address.url.absoluteString == "https://cloud.example.com/apps/notes/Readme.md")
    }

    @Test
    func `A trailing slash on the server address does not double the separator`() throws {
        let server = try #require(URL(string: "https://example.com/nextcloud/"))
        let address = try #require(SameOriginURL(components: ["settings", "user"], relativeTo: server))

        #expect(address.url.absoluteString == "https://example.com/nextcloud/settings/user")
    }
}
