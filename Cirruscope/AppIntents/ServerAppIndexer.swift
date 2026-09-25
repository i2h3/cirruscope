// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppIntents
import Foundation
import os

/// `ServerAppIndexer` keeps Spotlight and Siri in step with the connected server's app list, donating each `ServerAppEntity` to the on-device Spotlight index and refreshing the App Shortcut parameters when the apps change.
///
/// It is a main-actor observer of `Notification.Name.serverAppsDidChange` — the same signal `AppDelegate` and `ServerAppsViewController` react to — so `AccountStore` itself never imports App Intents or Core Spotlight; donation is just one more subscriber to the store's existing write-then-notify contract. `AppDelegate.applicationDidFinishLaunching(_:)` calls `start()` once, which indexes the apps already persisted from a previous run and then keeps the index current on every change, including clearing it when `AccountStore.disconnect()` empties the account.
///
/// Indexing runs at most a handful of times per session, so each pass logs at `.notice` with the counts and app ids in the clear (`.public`), letting a log capture show exactly what was donated to or removed from Spotlight; failures log at `.error`.
@MainActor
final class ServerAppIndexer: NSObject {
    /// `shared` is the process-wide indexer, mirroring the `AccountStore.shared` / `NotificationMonitor.shared` conventions.
    static let shared = ServerAppIndexer()

    /// `logger` records indexing activity under the `ServerAppIndexer` category.
    private let logger = Logger(for: ServerAppIndexer.self)

    /// `index` donates the apps and remembers what it has donated.
    ///
    /// The bookkeeping of which identifiers are in the index, and the deletion of the ones that have gone, moved into `SpotlightIndex` when a second domain needed exactly the same thing. What stays here is what is this domain's alone: which notification to listen to, and the App Shortcut parameter refresh below.
    private let index = SpotlightIndex<ServerAppEntity>(label: "server apps")

    /// `hasStarted` records that `start()` has already run, so a second call registers no second observer.
    ///
    /// macOS calls `start()` once, from `applicationDidFinishLaunching(_:)`. iOS has no such moment: the nearest thing is the app becoming active, which happens again on every return to the foreground. Making the second call a no-op here is what lets that caller stay a single line rather than carrying a flag of its own.
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

    /// `serverAppsDidChange()` reindexes when `AccountStore` reports the app list or a shortcut changed, deferring to the next main-thread turn so it never runs reentrantly inside the mutation that posted the notification — matching `ServerAppsViewController`.
    @objc
    private func serverAppsDidChange() {
        logger.debug("Received serverAppsDidChange; scheduling a reindex")
        DispatchQueue.main.async { [weak self] in
            self?.reindex(isInitial: false)
        }
    }

    /// `reindex(isInitial:)` donates the current apps to Spotlight, deletes the ids the server no longer offers, and asks the App Intents system to refresh the App Shortcut parameter values.
    ///
    /// `isInitial` distinguishes the one-shot index from `start()` from a later change, for the log only. The parameter refresh runs on **every** pass, including the initial one: `updateAppShortcutParameters()` is what makes the system pull the current values from the entity queries, and without it Siri never learns the names and cannot bind a parameterized phrase such as "Open Notes in Cirruscope" — it silently falls back to merely launching the app. An earlier revision skipped the call unless the app id set had changed, which in practice meant never (the server's app list is stable across launches) and broke exactly that. The call is cheap and idempotent, so it is unconditional; if it fails because the app is not yet registered with the App Intents subsystem (`LNMetadataProviderErrorDomain` 9004, typical of a build run from a non-standard location), the system logs that itself.
    ///
    /// It is made here and nowhere else. There is one `AppShortcutsProvider` in the app, so one refresh brings every parameter's values up to date, this entity's and every other domain's alike — which is why `ConversationIndexer` deliberately does not make the same call.
    private func reindex(isInitial: Bool) {
        logger.notice("Reindexing server apps (\(isInitial ? "initial" : "on change", privacy: .public))")

        Task {
            await self.donateAll()
        }
    }

    /// `donateAll()` donates everything the account currently has, and waits for the donation to finish.
    ///
    /// Awaitable and not merely scheduled, because the system asks for this as well as the app doing it on its own: an `IndexedEntityQuery`'s reindex is a request Spotlight makes when it believes what it holds is stale, and answering it means having actually finished rather than having started.
    func donateAll() async {
        let entities = AccountStore.shared.serverApps.map(ServerAppEntity.init)
        await index.donate(entities)

        ServerAppShortcuts.updateAppShortcutParameters()
        logger.notice("Requested an App Shortcut parameter refresh; the system now pulls the current values from every entity query")
    }
}
