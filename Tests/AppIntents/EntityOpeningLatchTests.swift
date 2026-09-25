// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `EntityOpeningLatchTests` covers the latch that keeps a request made before anything could serve it.
///
/// The latch is the whole reason this seam is not a bare closure, and the case it exists for is the one hardest to reach by hand: an intent or a Spotlight selection reaching the app during a cold launch, before any window or screen exists. A request dropped there looks exactly like the app launching and doing nothing, which is the shape a person reports as "Spotlight is broken".
///
/// Every case builds its own `EntityOpening` rather than using `shared`, into which the host app installs a real opener for the whole test run — the same hazard `AccountStore.shared` carries, answered the same way.
@MainActor
struct EntityOpeningLatchTests {
    /// `serverAddress` is the instance every address in this suite is on.
    private let serverAddress = URL(string: "https://cloud.example.com")

    /// `firstAddress` is one page to open.
    private let firstAddress = "/apps/notes/note/1"

    /// `secondAddress` is a different page, for the case where two requests arrive before either can be served.
    private let secondAddress = "/apps/notes/note/2"

    @Test
    func `A request made before an opener is installed is served once one is`() throws {
        let server = try #require(serverAddress)
        let target = try #require(SameOriginURL(path: firstAddress, relativeTo: server))
        let opening = EntityOpening()
        var served: [SameOriginURL] = []

        opening.open(.page(target))

        #expect(served.isEmpty, "Nothing can have been served while nothing was installed.")

        opening.install { request in
            guard case let .page(address) = request else {
                return
            }

            served.append(address)
        }

        #expect(served.map(\.url) == [target.url])
    }

    @Test
    func `A request made after an opener is installed is served immediately`() throws {
        let server = try #require(serverAddress)
        let target = try #require(SameOriginURL(path: firstAddress, relativeTo: server))
        let opening = EntityOpening()
        var served: [SameOriginURL] = []

        opening.install { request in
            guard case let .page(address) = request else {
                return
            }

            served.append(address)
        }

        opening.open(.page(target))

        #expect(served.map(\.url) == [target.url])
    }

    /// Two requests before an opener exists are one request, and the second is the one that counts: somebody pressing Return twice in Spotlight means the second thing they picked, not both.
    @Test
    func `A second pending request replaces the first rather than queueing behind it`() throws {
        let server = try #require(serverAddress)
        let first = try #require(SameOriginURL(path: firstAddress, relativeTo: server))
        let second = try #require(SameOriginURL(path: secondAddress, relativeTo: server))
        let opening = EntityOpening()
        var served: [SameOriginURL] = []

        opening.open(.page(first))
        opening.open(.page(second))

        opening.install { request in
            guard case let .page(address) = request else {
                return
            }

            served.append(address)
        }

        #expect(served.map(\.url) == [second.url])
    }

    /// Installing again with nothing waiting must not replay what was served before, or a screen reappearing would reopen the last thing somebody asked for.
    @Test
    func `Installing a second opener with nothing pending serves nothing`() throws {
        let server = try #require(serverAddress)
        let target = try #require(SameOriginURL(path: firstAddress, relativeTo: server))
        let opening = EntityOpening()
        var served: [SameOriginURL] = []

        opening.install { _ in }
        opening.open(.page(target))

        opening.install { request in
            guard case let .page(address) = request else {
                return
            }

            served.append(address)
        }

        #expect(served.isEmpty)
    }
}
