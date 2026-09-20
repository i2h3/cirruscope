// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import Observation
import os

/// `EntityOpening` is how an App Intent hands what the user picked to whichever app is running it.
///
/// The intent itself cannot do the opening. macOS opens a server app by asking `AppDelegate` to reuse or create a web window; iOS has one web view and loads a request into it.
///
/// There are two ways to open something and not one, because a server app and a page within one are different requests. Opening an app means "show me Talk", and on macOS the right answer is to bring the window already showing Talk forward rather than to open a second one. Opening a conversation means "show me *this* conversation", and reusing a window without loading anything into it would bring a window forward showing a different conversation — which looks like the app ignored what was asked for. So an app is opened by identity and a page by address. Neither of those can be named from a folder the other app also compiles, and an intent has nowhere to be handed a dependency either: the system instantiates it as a plain value through a synthesized `init()`, so there is no initializer to inject into and no environment to read from. This is the seam that closes that gap, and it is a small piece of shared state rather than a protocol because the project has no dependency-injection layer and wants none — the same reasoning `AccountStore`'s closure seams rest on.
///
/// It carries a latch as well as a handler, and that is the part worth explaining. An intent run from Spotlight or Siri while the app is not running brings the app forward, which means `perform()` can reach this type before any window or view exists to open anything. A bare closure would then be `nil` and the request would be dropped — the user would watch the app launch and do nothing, which is exactly the failure that reads as "Spotlight is broken". So a request made before a handler is installed is remembered instead, and whatever installs the handler drains it.
///
/// It is `@Observable` so the iOS side can consume the latch by watching it from a view rather than polling; macOS installs a handler in `applicationDidFinishLaunching(_:)` and never reads `pending` at all.
@Observable
@MainActor
final class EntityOpening {
    /// `shared` is the process-wide seam, mirroring the `AccountStore.shared` / `ServerAppIndexer.shared` conventions.
    static let shared = EntityOpening()

    /// `logger` records what was requested and whether anything was there to take it, under the `EntityOpening` category.
    @ObservationIgnored
    private let logger = Logger(for: EntityOpening.self)

    /// `Request` is one thing the user asked to open.
    enum Request: Sendable {
        /// `serverApp` is a whole Nextcloud app, opened by identity so a window already showing it can be reused.
        case serverApp(ServerAppTransferObject)

        /// `page` is one address on the connected server, opened by loading it.
        case page(SameOriginURL)
    }

    /// `pending` is a request made before anything could serve it, held until something can.
    ///
    /// It is read and cleared by whatever installs the handlers, and observed on iOS by the screen that owns the web view. It holds at most one: a second request before either is served replaces the first, which is what a user pressing Return twice in Spotlight means.
    private(set) var pending: Request?

    /// `handle` is what the running app does with a request, or `nil` while nothing is ready to do anything.
    @ObservationIgnored
    private var handle: (@MainActor (Request) -> Void)?

    private init() {}

    /// `install(_:)` records how this app serves a request, and immediately serves anything asked for before now.
    ///
    /// Draining here rather than leaving it to the caller is what keeps the cold-launch path from depending on every installer remembering to check.
    func install(_ handle: @escaping @MainActor (Request) -> Void) {
        logger.notice("Installing the entity opener")
        self.handle = handle

        guard let request = pending else {
            return
        }

        pending = nil
        logger.notice("Serving a request that arrived before an opener was installed")
        handle(request)
    }

    /// `open(_:)` serves `request` now if this app can, and remembers it to be served as soon as it can otherwise.
    func open(_ request: Request) {
        guard let handle else {
            logger.notice("Nothing can serve this request yet; holding it until an opener is installed")
            pending = request
            return
        }

        handle(request)
    }
}
