// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `EntityOpeningPrecedenceTests` covers which of several installed openers serves a request, and what installing reports back.
///
/// An iPad runs one opener per window, and the failure this rule exists to prevent is invisible from the window the user is looking at: a Spotlight result loaded into a window that was closed, or that is behind the one in front. Only the ordering decides that, so it is pinned here rather than left to a hand check with two windows open.
///
/// Every case builds its own `EntityOpening` rather than using `shared`, into which the host app installs a real opener for the whole test run — the same hazard `AccountStore.shared` carries, answered the same way. Owners are plain objects, since only their identity is ever compared.
@MainActor
struct EntityOpeningPrecedenceTests {
    /// `serverAddress` is the instance every address in this suite is on.
    private let serverAddress = URL(string: "https://cloud.example.com")

    /// `address` is the page every case asks to open.
    private let address = "/apps/notes/note/1"

    /// `firstWindow` stands for the window that installed its opener first.
    private let firstWindow = NSObject()

    /// `secondWindow` stands for a window that installed its opener after it.
    private let secondWindow = NSObject()

    @Test
    func `The opener installed last serves a request`() throws {
        let server = try #require(serverAddress)
        let target = try #require(SameOriginURL(path: address, relativeTo: server))
        let opening = EntityOpening()
        var served: [String] = []

        opening.install(for: firstWindow) { _ in served.append("first") }
        opening.install(for: secondWindow) { _ in served.append("second") }
        opening.open(.page(target))

        #expect(served == ["second"])
    }

    /// A window coming back to the front installs again, and must then be the one asked rather than holding a second place in the list.
    @Test
    func `Installing again for an owner brings its opener back to the front`() throws {
        let server = try #require(serverAddress)
        let target = try #require(SameOriginURL(path: address, relativeTo: server))
        let opening = EntityOpening()
        var served: [String] = []

        opening.install(for: firstWindow) { _ in served.append("first") }
        opening.install(for: secondWindow) { _ in served.append("second") }
        opening.install(for: firstWindow) { _ in served.append("first again") }
        opening.open(.page(target))

        #expect(served == ["first again"])
    }

    /// Closing the window in front hands requests to the one in front before it, rather than to the closed window or to nothing.
    @Test
    func `Removing the opener in front hands requests to the one installed before it`() throws {
        let server = try #require(serverAddress)
        let target = try #require(SameOriginURL(path: address, relativeTo: server))
        let opening = EntityOpening()
        var served: [String] = []

        opening.install(for: firstWindow) { _ in served.append("first") }
        opening.install(for: secondWindow) { _ in served.append("second") }
        opening.uninstall(for: secondWindow)
        opening.open(.page(target))

        #expect(served == ["first"])
    }

    @Test
    func `Removing an opener behind the one in front leaves the one in front serving`() throws {
        let server = try #require(serverAddress)
        let target = try #require(SameOriginURL(path: address, relativeTo: server))
        let opening = EntityOpening()
        var served: [String] = []

        opening.install(for: firstWindow) { _ in served.append("first") }
        opening.install(for: secondWindow) { _ in served.append("second") }
        opening.uninstall(for: firstWindow)
        opening.open(.page(target))

        #expect(served == ["second"])
    }

    /// With every window closed the app is still running, and a request arriving then belongs to the next window rather than to none.
    @Test
    func `With every opener removed a request is held for the next one installed`() throws {
        let server = try #require(serverAddress)
        let target = try #require(SameOriginURL(path: address, relativeTo: server))
        let opening = EntityOpening()
        var served: [String] = []

        opening.install(for: firstWindow) { _ in served.append("first") }
        opening.uninstall(for: firstWindow)
        opening.open(.page(target))

        #expect(served.isEmpty, "A removed opener must not be asked.")

        opening.install(for: secondWindow) { _ in served.append("second") }

        #expect(served == ["second"])
    }

    /// The answer is what lets a screen load a request waiting from a cold launch in place of its own front page, so a wrong one either loads the front page over it or leaves the screen empty.
    @Test
    func `Installing reports whether it served a request that was waiting`() throws {
        let server = try #require(serverAddress)
        let target = try #require(SameOriginURL(path: address, relativeTo: server))
        let opening = EntityOpening()
        var served: [String] = []

        #expect(opening.install(for: firstWindow) { _ in served.append("first") } == false, "Nothing was waiting.")

        opening.uninstall(for: firstWindow)
        opening.open(.page(target))

        #expect(opening.install(for: secondWindow) { _ in served.append("second") }, "A request was waiting and was served.")
        #expect(opening.install(for: secondWindow) { _ in served.append("second again") } == false, "A served request must not be served again.")
        #expect(served == ["second"])
    }
}
