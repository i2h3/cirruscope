// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

/// `EntityOpening` is how an App Intent, a Spotlight result or a tapped server notification hands what the user picked to whichever app is running it.
///
/// It holds more than one handler because an iPad has more than one window, each with a web view of its own and each able to close while the app runs on. macOS installs one handler for the whole process and never removes it; an iOS window installs its own whenever it comes to the front and removes it whenever it goes to the background or away, so the one serving a request is the window most recently in front, and closing that window hands requests to the one in front before it rather than to a web view nobody can see any more.
@MainActor
final class EntityOpening {
    /// `shared` is the process-wide seam, mirroring the `AccountStore.shared` / `ServerAppIndexer.shared` conventions.
    static let shared = EntityOpening()

    /// `logger` records what was requested and whether anything was there to take it, under the `EntityOpening` category.
    private let logger = Logger(for: EntityOpening.self)

    /// `Request` is one thing the user asked to open.
    enum Request: Sendable {
        /// `serverApp` is a whole Nextcloud app, opened by identity so a window already showing it can be reused.
        case serverApp(ServerAppTransferObject)

        /// `page` is one address on the connected server, opened by loading it.
        case page(SameOriginURL)
    }

    /// `pending` is a request made before anything could serve it, held until something can.
    private(set) var pending: Request?

    /// `handlers` is every way the running app can currently serve a request, the one installed most recently last, each with the object that installed it.
    ///
    /// The last is the one that serves. A handler installed without an owner stands for the whole process, as macOS's does; one installed with an owner is removed again by it, which is what lets an iPad window that closes stop being asked to open anything.
    private var handlers: [(owner: ObjectIdentifier?, handle: @MainActor (Request) -> Void)] = []

    /// `init()` builds an opener, which production does exactly once as `shared`.
    init() {}

    /// `install(for:_:)` makes `handle` the way this app serves a request, and immediately serves with it anything asked for before now, answering whether it did.
    ///
    /// Installing again for an owner already holding a handler replaces that handler and brings it to the front rather than adding a second, so a window can reinstall every time it comes forward. Without an owner the same holds for the one process-wide handler.
    /// Draining here rather than leaving it to the caller is what keeps the cold-launch path from depending on every installer remembering to check; the answer is for the one caller that has to choose between what was asked for and a page of its own, a screen deciding what its first document is.
    @discardableResult
    func install(for owner: AnyObject? = nil, _ handle: @escaping @MainActor (Request) -> Void) -> Bool {
        let identity = owner.map(ObjectIdentifier.init)

        handlers.removeAll { $0.owner == identity }
        handlers.append((owner: identity, handle: handle))
        logger.notice("Installed an entity opener; \(self.handlers.count, privacy: .public) installed in all")

        guard let request = pending else {
            return false
        }

        pending = nil
        logger.notice("Serving a request that arrived before an opener was installed")
        handle(request)

        return true
    }

    /// `uninstall(for:)` removes the handler `owner` installed, if it installed one, so a request goes to the handler installed before it instead.
    func uninstall(for owner: AnyObject) {
        let identity = ObjectIdentifier(owner)
        let countBefore = handlers.count

        handlers.removeAll { $0.owner == identity }

        guard handlers.count != countBefore else {
            logger.debug("Asked to remove an entity opener that was not installed")
            return
        }

        logger.notice("Removed an entity opener; \(self.handlers.count, privacy: .public) still installed")
    }

    /// `discardPending()` forgets a request no handler has served yet, which every sign-out does.
    ///
    /// What was asked for belonged to the account signed in when it was asked, and serving it after a sign-out would open it for whoever signs in next: on the same server the address still passes every origin check, and a tapped notification or a donated entity of one account would open in another's session.
    /// The handlers are left alone, since they belong to the windows and the process rather than to the account.
    func discardPending() {
        guard pending != nil else {
            return
        }

        pending = nil
        logger.notice("Discarded a request no opener had served yet, the account it was made for having signed out")
    }

    /// `open(_:)` serves `request` now if this app can, and remembers it to be served as soon as it can otherwise.
    func open(_ request: Request) {
        guard let handle = handlers.last?.handle else {
            logger.notice("Nothing can serve this request yet; holding it until an opener is installed")
            pending = request
            return
        }

        logger.notice("Serving a request with the opener installed most recently; \(self.handlers.count, privacy: .public) installed in all")
        handle(request)
    }
}
