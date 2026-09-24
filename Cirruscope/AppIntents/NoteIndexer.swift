// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

/// `NoteIndexer` keeps Spotlight and the Shortcuts app in step with the connected account's notes.
///
/// It is the third of these and differs from `ConversationIndexer` only in which notification it observes and which read it donates, which is the point: everything that is the same — the bookkeeping of what has been donated, the deletion of what has not — lives in `SpotlightIndex`.
///
/// As there, it does not ask for the App Shortcut parameters to be refreshed. `ServerAppIndexer` makes that call, and there is one `AppShortcutsProvider` in the app, so one refresh brings every entity query's values up to date.
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
            return
        }

        hasStarted = true
        logger.notice("Starting the note indexer")
        NotificationCenter.default.addObserver(self, selector: #selector(notesDidChange), name: .notesDidChange, object: nil)
        reindex()
    }

    /// `notesDidChange()` reindexes when `AccountStore` reports the notes changed, deferring to the next main-thread turn so it never runs reentrantly inside the mutation that posted the notification.
    @objc
    private func notesDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.reindex()
        }
    }

    /// `reindex()` donates the notes the account currently has.
    private func reindex() {
        let entities = AccountStore.shared.notes.map(NoteEntity.init)

        Task {
            await index.donate(entities)
        }
    }
}
