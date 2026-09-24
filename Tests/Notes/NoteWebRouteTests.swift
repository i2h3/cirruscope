// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `NoteWebRouteTests` pins where a note is opened.
///
/// The subdirectory case is the one that earns the suite. A note sits under its app's own prefix, which makes the path look self-describing and safe to write from the server root — and against an instance served from a subdirectory that is exactly how it opens a page on the wrong part of the host. The identical mistake was caught this way in the conversation route.
struct NoteWebRouteTests {
    @Test
    func `A note is addressed under the Notes app's own prefix`() throws {
        let server = try #require(URL(string: "https://cloud.example.com"))
        let route = try #require(NoteWebRoute.url(forID: 42, on: server))

        #expect(route.url.absoluteString == "https://cloud.example.com/apps/notes/note/42")
    }

    @Test
    func `A subdirectory install keeps its web root in front of the note route`() throws {
        let server = try #require(URL(string: "https://example.com/nextcloud"))
        let route = try #require(NoteWebRoute.url(forID: 42, on: server))

        #expect(route.url.absoluteString == "https://example.com/nextcloud/apps/notes/note/42")
    }

    @Test
    func `A non-default port is kept`() throws {
        let server = try #require(URL(string: "https://cloud.example.com:8443"))
        let route = try #require(NoteWebRoute.url(forID: 42, on: server))

        #expect(route.url.absoluteString == "https://cloud.example.com:8443/apps/notes/note/42")
    }

    @Test
    func `A negative identifier is refused rather than encoded into a request the server would answer with an error page`() throws {
        let server = try #require(URL(string: "https://cloud.example.com"))

        #expect(NoteWebRoute.url(forID: -1, on: server) == nil)
    }

    @Test
    func `A note route resolves back to Notes, so a window showing one knows which app it is in`() throws {
        let server = try #require(URL(string: "https://cloud.example.com"))
        let route = try #require(NoteWebRoute.url(forID: 42, on: server))

        // The path names its own owner, which is why — unlike a Talk conversation — this needs no entry in
        // `ServerAppPath`'s table of routes an app registers at the server's root.
        #expect(ServerAppPath.appID(of: route.url, on: server) == "notes")
    }
}
