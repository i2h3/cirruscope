// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

/// `CollectiveIndexer` keeps Spotlight and the Shortcuts app in step with the account's collectives and the pages within them.
///
/// It is the only one of these that donates two entity types, and it does because the two change together: a page is reached through its collective, so `AccountStore` announces both under one name and nothing observes one without observing the other. Two indexers over one notification would be two passes for one refresh.
///
/// As with the others, it does not ask for the App Shortcut parameters to be refreshed — `ServerAppIndexer` makes that call, and one refresh brings every entity query's values up to date.
@MainActor
final class CollectiveIndexer: NSObject {
    /// `shared` is the process-wide collective indexer.
    static let shared = CollectiveIndexer()

    /// `logger` records indexing activity under the `CollectiveIndexer` category.
    private let logger = Logger(for: CollectiveIndexer.self)

    /// `collectiveIndex` donates the collectives and remembers what it has donated.
    private let collectiveIndex = SpotlightIndex<CollectiveEntity>(label: "collectives")

    /// `pageIndex` donates the pages and remembers what it has donated.
    ///
    /// Its own index rather than a shared one, because the bookkeeping is per entity type: what has been donated for one says nothing about the other, and deleting stale entries is scoped by type anyway.
    private let pageIndex = SpotlightIndex<CollectivePageEntity>(label: "collective pages")

    /// `hasStarted` records that `start()` has already run, so a second call registers no second observer.
    private var hasStarted = false

    override private init() {
        super.init()
    }

    /// `start()` registers the change observer and performs the initial index over what was already persisted from a previous run.
    func start() {
        guard hasStarted == false else {
            return
        }

        hasStarted = true
        logger.notice("Starting the collective indexer")
        NotificationCenter.default.addObserver(self, selector: #selector(collectivesDidChange), name: .collectivesDidChange, object: nil)
        reindex()
    }

    /// `collectivesDidChange()` reindexes when `AccountStore` reports the collectives or their pages changed, deferring to the next main-thread turn so it never runs reentrantly inside the mutation that posted the notification.
    @objc
    private func collectivesDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.reindex()
        }
    }

    /// `reindex()` donates the collectives and the pages the account currently has.
    ///
    /// The pages are built through their own query rather than from the store directly, because a page entity needs the name of the collective containing it and that pairing is the query's job — restating it here would be a second place for the two to disagree about what a page is called.
    private func reindex() {
        let collectives = AccountStore.shared.collectives.map(CollectiveEntity.init)

        Task {
            await collectiveIndex.donate(collectives)

            let pages = try? await CollectivePageEntity.defaultQuery.allEntities()
            await pageIndex.donate(pages ?? [])
        }
    }
}
