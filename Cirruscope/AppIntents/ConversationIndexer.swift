// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

/// `ConversationIndexer` keeps Spotlight and the Shortcuts app in step with the Talk conversations the connected account takes part in.
///
/// It is `ServerAppIndexer`'s counterpart, and the pair is what the shape of a domain's indexer looks like: observe the one notification the store posts for that domain, and hand the current snapshot to a `SpotlightIndex`. Everything that is the same between them — the bookkeeping of what has been donated, the deletion of what has not — is in that type rather than copied here.
///
/// `AccountStore` itself imports neither App Intents nor Core Spotlight, and does not need to: donation is one more subscriber to the store's existing write-then-announce contract, exactly as the menus are.
@MainActor
final class ConversationIndexer: NSObject {
    /// `shared` is the process-wide conversation indexer, mirroring the `AccountStore.shared` / `ServerAppIndexer.shared` conventions.
    static let shared = ConversationIndexer()

    /// `logger` records indexing activity under the `ConversationIndexer` category.
    private let logger = Logger(for: ConversationIndexer.self)

    /// `index` donates the conversations and remembers what it has donated.
    private let index = SpotlightIndex<ConversationEntity>(label: "conversations")

    /// `hasStarted` records that `start()` has already run, so a second call registers no second observer.
    private var hasStarted = false

    override private init() {
        super.init()
    }

    /// `start()` registers the change observer and performs the initial index over the conversations already persisted from a previous run.
    ///
    /// Calling it again does nothing, for the reason `ServerAppIndexer.start()` is likewise idempotent: iOS has no once-per-launch hook and calls it on every activation.
    func start() {
        guard hasStarted == false else {
            logger.debug("Already started; ignoring this call")
            return
        }

        hasStarted = true
        logger.notice("Starting the conversation indexer")
        NotificationCenter.default.addObserver(self, selector: #selector(conversationsDidChange), name: .conversationsDidChange, object: nil)

        // The artwork arrives separately from the data and later than it, so a donation made before the app
        // icons were on disk carries no picture. This is what donates again once they are.
        NotificationCenter.default.addObserver(self, selector: #selector(donatedArtworkDidChange), name: .donatedArtworkDidChange, object: nil)
        reindex()
    }

    /// `conversationsDidChange()` reindexes when `AccountStore` reports the conversations changed, deferring to the next main-thread turn so it never runs reentrantly inside the mutation that posted the notification.
    @objc
    private func conversationsDidChange() {
        logger.debug("Received conversationsDidChange; scheduling a reindex")
        DispatchQueue.main.async { [weak self] in
            self?.reindex()
        }
    }

    /// `donatedArtworkDidChange()` donates again once whatever this domain's artwork is drawn from has landed.
    @objc
    private func donatedArtworkDidChange() {
        logger.debug("Received donatedArtworkDidChange; scheduling a reindex so the artwork lands in the index")
        DispatchQueue.main.async { [weak self] in
            self?.reindex()
        }
    }

    /// `reindex()` donates the conversations the account currently has.
    ///
    /// It deliberately does not ask for the App Shortcut parameters to be refreshed. `ServerAppIndexer` does that, and there is one `AppShortcutsProvider` in the app, so one refresh brings every parameter's values up to date — including this entity's. Doing it from both would be two calls for one effect, on the path that runs whenever anything changes.
    private func reindex() {
        Task {
            await self.donateAll()
        }
    }

    /// `donateAll()` donates everything the account currently has, and waits for the donation to finish.
    ///
    /// Awaitable and not merely scheduled, because the system asks for this as well as the app doing it on its own: an `IndexedEntityQuery`'s reindex is a request Spotlight makes when it believes what it holds is stale, and answering it means having actually finished rather than having started.
    func donateAll() async {
        let entities = AccountStore.shared.conversations.map(ConversationEntity.init)
        logger.notice("Donating \(entities.count, privacy: .public) conversation(s)")
        await index.donate(entities)
    }
}
