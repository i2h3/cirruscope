// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import Observation
import os

/// `EntityOpening` is how an App Intent hands what the user picked to whichever app is running it.
///
/// The intent itself cannot do the opening. macOS opens a server app by asking `AppDelegate` to reuse or create a web window; iOS has one web view and loads a request into it. Neither of those can be named from a folder the other app also compiles, and an intent has nowhere to be handed a dependency either: the system instantiates it as a plain value through a synthesized `init()`, so there is no initializer to inject into and no environment to read from. This is the seam that closes that gap, and it is a small piece of shared state rather than a protocol because the project has no dependency-injection layer and wants none — the same reasoning `AccountStore`'s closure seams rest on.
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

    /// `pending` is a server app requested before anything could open it, held until something can.
    ///
    /// It is read and cleared by whatever installs a handler, and observed on iOS by the screen that owns the web view. It holds at most one: a second request before either is served replaces the first, which is what a user pressing Return twice in Spotlight means.
    private(set) var pending: ServerAppTransferObject?

    /// `openServerApp` is what the running app does with a chosen server app, or `nil` while nothing is ready to do anything.
    @ObservationIgnored
    private var openServerApp: (@MainActor (ServerAppTransferObject) -> Void)?

    private init() {}

    /// `install(_:)` records how this app opens a server app, and immediately serves anything that was requested before now.
    ///
    /// Draining here rather than leaving it to the caller is what keeps the cold-launch path from depending on every installer remembering to check.
    func install(_ open: @escaping @MainActor (ServerAppTransferObject) -> Void) {
        logger.notice("Installing the server-app opener")
        openServerApp = open

        guard let app = pending else {
            return
        }

        pending = nil
        logger.notice("Serving the request for \(app.id, privacy: .public) that arrived before an opener was installed")
        open(app)
    }

    /// `open(_:)` opens `app` now if this app can, and remembers it to be opened as soon as it can otherwise.
    func open(_ app: ServerAppTransferObject) {
        guard let openServerApp else {
            logger.notice("Nothing can open \(app.id, privacy: .public) yet; holding it until an opener is installed")
            pending = app
            return
        }

        logger.notice("Opening \(app.id, privacy: .public)")
        openServerApp(app)
    }

    /// `consumePending()` is the pending request, cleared, for a caller that watches `pending` rather than installing a handler.
    ///
    /// iOS uses this: the screen owning the web view can only load a request while it is on screen, so it observes the latch and takes what is there instead of registering a closure that would outlive it.
    func consumePending() -> ServerAppTransferObject? {
        guard let app = pending else {
            return nil
        }

        pending = nil
        logger.notice("A screen took the pending request for \(app.id, privacy: .public)")
        return app
    }
}
