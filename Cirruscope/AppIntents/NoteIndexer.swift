// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

/// `NoteIndexer` keeps Spotlight and the Shortcuts app in step with the connected account's notes.
@MainActor
final class NoteIndexer: NSObject {
    /// `shared` is the process-wide note indexer.
    static let shared = NoteIndexer()

    /// `logger` records indexing activity under the `NoteIndexer` category.
    private let logger = Logger(for: NoteIndexer.self)

    /// `index` donates the notes and remembers what it has donated.
    private let index = SpotlightIndex<NoteEntity>(label: "notes")

    /// `hasStarted` records that `start()` has already run, so a second call registers no second observer.
    private var hasStarted = false

    override private init() {
        super.init()
    }

    /// `start()` registers the change observer and performs the initial index over the notes already persisted from a previous run.
    ///
    /// Calling it again does nothing: iOS has no once-per-launch hook and calls it on every activation.
    func start() {
        guard hasStarted == false else {
            logger.debug("Already started; ignoring this call")
            return
        }

        hasStarted = true
        logger.notice("Starting the note indexer")
        NotificationCenter.default.addObserver(self, selector: #selector(notesDidChange), name: .notesDidChange, object: nil)

        // The artwork arrives separately from the data and later than it, so a donation made before the app
        // icons were on disk carries no picture. This is what donates again once they are.
        NotificationCenter.default.addObserver(self, selector: #selector(donatedArtworkDidChange), name: .donatedArtworkDidChange, object: nil)
        reindex()
    }

    /// `notesDidChange()` reindexes when `AccountStore` reports the notes changed, deferring to the next main-thread turn so it never runs reentrantly inside the mutation that posted the notification.
    @objc
    private func notesDidChange() {
        logger.debug("Received notesDidChange; scheduling a reindex")
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

    /// `reindex()` donates the notes the account currently has.
    private func reindex() {
        Task {
            await self.donateAll()
        }
    }

    /// `donateAll()` donates everything the account currently has, and waits for the donation to finish.
    func donateAll() async {
        let entities = AccountStore.shared.notes.map(NoteEntity.init)
        logger.notice("Donating \(entities.count, privacy: .public) note(s)")
        await index.donate(entities)
    }
}
