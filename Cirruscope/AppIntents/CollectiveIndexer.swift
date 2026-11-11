// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os

/// `CollectiveIndexer` keeps Spotlight and the Shortcuts app in step with the account's collectives and the pages within them.
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
            logger.debug("Already started; ignoring this call")
            return
        }

        hasStarted = true
        logger.notice("Starting the collective indexer")
        NotificationCenter.default.addObserver(self, selector: #selector(collectivesDidChange), name: .collectivesDidChange, object: nil)

        // The artwork arrives separately from the data and later than it, so a donation made before the app
        // icons were on disk carries no picture. This is what donates again once they are.
        NotificationCenter.default.addObserver(self, selector: #selector(donatedArtworkDidChange), name: .donatedArtworkDidChange, object: nil)
        reindex()
    }

    /// `collectivesDidChange()` reindexes when `AccountStore` reports the collectives or their pages changed, deferring to the next main-thread turn so it never runs reentrantly inside the mutation that posted the notification.
    @objc
    private func collectivesDidChange() {
        logger.debug("Received collectivesDidChange; scheduling a reindex")
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

    /// `reindex()` donates the collectives and the pages the account currently has.
    ///
    /// The pages are built through their own query rather than from the store directly, because a page entity needs the name of the collective containing it and that pairing is the query's job — restating it here would be a second place for the two to disagree about what a page is called.
    private func reindex() {
        Task {
            await self.donateAll()
        }
    }

    /// `donateAll()` donates everything the account currently has, and waits for the donation to finish.
    func donateAll() async {
        await donateCollectives()
        await donatePages()
    }

    /// `donateCollectives()` donates the collectives the account currently has.
    func donateCollectives() async {
        let collectives = AccountStore.shared.collectives.map(CollectiveEntity.init)
        logger.notice("Donating \(collectives.count, privacy: .public) collective(s)")
        await collectiveIndex.donate(collectives)
    }

    /// `donatePages()` donates the pages of every collective the account currently has.
    ///
    /// A query that cannot enumerate them donates none, which removes whatever is still in the index. That is the honest answer rather than the cautious one: leaving them would keep results that open pages this app can no longer describe.
    func donatePages() async {
        guard let pages = try? await CollectivePageEntity.defaultQuery.allEntities() else {
            logger.error("The collective page query could not enumerate the pages; donating none, which removes any still in the index")
            await pageIndex.donate([])
            return
        }

        logger.notice("Donating \(pages.count, privacy: .public) collective page(s)")
        await pageIndex.donate(pages)
    }
}
