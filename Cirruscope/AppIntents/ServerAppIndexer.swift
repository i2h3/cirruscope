// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import Foundation
import os

/// `ServerAppIndexer` keeps Spotlight and Siri in step with the connected server's app list, donating each `ServerAppEntity` to the on-device Spotlight index and refreshing the App Shortcut parameters when the apps change.
@MainActor
final class ServerAppIndexer: NSObject {
    /// `shared` is the process-wide indexer, mirroring the `AccountStore.shared` / `NotificationMonitor.shared` conventions.
    static let shared = ServerAppIndexer()

    /// `logger` records indexing activity under the `ServerAppIndexer` category.
    private let logger = Logger(for: ServerAppIndexer.self)

    /// `index` donates the apps and remembers what it has donated.
    private let index = SpotlightIndex<ServerAppEntity>(label: "server apps")

    /// `hasStarted` records that `start()` has already run, so a second call registers no second observer.
    private var hasStarted = false

    /// `start()` registers the change observer and performs the initial index over the apps already persisted from a previous run.
    ///
    /// Calling it again does nothing.
    func start() {
        guard hasStarted == false else {
            logger.debug("The server app indexer is already started; ignoring this call")
            return
        }

        hasStarted = true
        logger.notice("Starting server app indexer; registering for change notifications and performing the initial index")
        NotificationCenter.default.addObserver(self, selector: #selector(serverAppsDidChange), name: .serverAppsDidChange, object: nil)
        reindex(isInitial: true)
    }

    /// `serverAppsDidChange()` reindexes when `AccountStore` reports that the app list or the account's server address changed, or `ServerConnection` that the apps' icons have landed, deferring to the next main-thread turn so it never runs reentrantly inside the mutation that posted the notification — matching `ServerAppsViewController`.
    @objc
    private func serverAppsDidChange() {
        logger.debug("Received serverAppsDidChange; scheduling a reindex")
        DispatchQueue.main.async { [weak self] in
            self?.reindex(isInitial: false)
        }
    }

    /// `reindex(isInitial:)` donates the current apps to Spotlight, deletes the ids the server no longer offers, and asks the App Intents system to refresh the App Shortcut parameter values.
    private func reindex(isInitial: Bool) {
        logger.notice("Reindexing server apps (\(isInitial ? "initial" : "on change", privacy: .public))")

        Task {
            await self.donateAll()
        }
    }

    /// `donateAll()` donates everything the account currently has, and waits for the donation to finish.
    func donateAll() async {
        let entities = AccountStore.shared.serverApps.map(ServerAppEntity.init)
        logger.notice("Donating \(entities.count, privacy: .public) server app(s)")
        await index.donate(entities)

        ServerAppShortcuts.updateAppShortcutParameters()
        logger.notice("Requested an App Shortcut parameter refresh; the system now pulls the current values from every entity query")
    }
}
