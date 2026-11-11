// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

/// `ConversationIndexer` keeps Spotlight and the Shortcuts app in step with the Talk conversations the connected account takes part in.
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
    private func reindex() {
        Task {
            await self.donateAll()
        }
    }

    /// `donateAll()` donates everything the account currently has, and waits for the donation to finish.
    func donateAll() async {
        let entities = AccountStore.shared.conversations.map(ConversationEntity.init)
        logger.notice("Donating \(entities.count, privacy: .public) conversation(s)")
        await index.donate(entities)
    }
}
