// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import SwiftData

/// `AppDatabase` owns the single, process-wide SwiftData `ModelContainer` backing Cirruscope's account store.
///
/// The container is configured with `groupContainer: .identifier(AppGroup.identifier)` so the store lives in the shared App Group container — under `Library/Application Support/`, disjoint from `AssetCache`'s `Library/Caches/` subtree — where a future app extension carrying the same entitlement can also open it. The store is local only (`cloudKitDatabase: .none`); secrets never go in it (they stay in `Keychain`).
///
/// `ModelContainer` is `Sendable`, so exposing it as a `static let` mirrors the existing `AppGroup` / `AssetCache.shared` singleton conventions. Access the main-actor context through `AccountStore`, which is the only type that touches it. Opening the store — including running `CirruscopeMigrationPlan` and any quarantine or container fallback — logs at `.notice`/`.error`/`.fault` so the whole startup path is reconstructable from a log capture in a release build.
enum AppDatabase {
    /// `logger` records store setup and recovery under the `AppDatabase` category.
    private static let logger = Logger(for: AppDatabase.self)

    /// `storeName` is the fixed configuration name that pins the store's filename, so every target — the app and any future extension — opens the very same file rather than a differently-named default.
    private static let storeName = "Cirruscope"

    /// `schema` is the app's current SwiftData schema.
    ///
    /// It is one definition rather than two because `AccountStore`'s unit tests build their own in-memory container from it (see `AccountStoreHarness`): a schema spelled out a second time on the test side would keep exercising whichever version it was written against once the app moves on. It names the newest versioned schema, `SchemaV3`; `CirruscopeMigrationPlan` migrates a store written by an older one up to it.
    static let schema = Schema(versionedSchema: SchemaV3.self)

    /// `container` is the shared model container, built on first access, opened with `CirruscopeMigrationPlan` so a store written by an earlier shipped schema is migrated forward in place.
    ///
    /// Three locations are tried in order. First the App Group container, which is where a properly signed build always ends up. If opening it fails — a genuinely corrupt file, or a migration that could not complete — the store files are moved aside to `.quarantine` siblings (never deleted) and it is tried once more: the store is largely reconstructible (apps are re-fetched from the server; only user shortcuts are authored locally), so recovering beats crash-looping on launch, and quarantining rather than deleting means a failed migration never destroys the user's shortcuts — the files stay on disk for recovery. If that fails too, the store is opened in the app's own container instead, because the likeliest remaining cause is not corruption at all but a build with no App Group entitlement to reach the shared container with — an ad-hoc build, which is what a fresh clone, a fork, and CI all produce, and which the sandbox then denies write access to that path. Only a failure there as well is unrecoverable.
    ///
    /// Falling back rather than trapping is what lets such a build actually run, and it is deliberately the *last* resort: an entitled build that lands there would silently be reading an empty store instead of the user's data, so the switch is logged at a level that persists to the system log.
    ///
    /// Being a `static let`, it is opened only once something actually asks for it, which is what lets the account store's tests run entirely on their own in-memory container: nothing in them reaches `AccountStore.shared`, so this store is never opened on their behalf — and it must stay that way, since the recovery path above moves the developer's real store files aside.
    static let container: ModelContainer = {
        let schema = Self.schema

        // Asked before a group-container `ModelConfiguration` is so much as constructed, because constructing one
        // an app is not entitled to reach does not fail — it traps. SwiftData resolves the container inside the
        // initializer and calls `fatalError` when the lookup is refused: "Unable to find App Group Container in
        // Entitlements", from `SwiftData/DataUtilities.swift`, with `containermanager` logging "client is not
        // entitled" immediately before it. There is no `try` to write and nothing to catch.
        // That is fatal at launch rather than merely inconvenient. This is a `static let` reached from
        // `Store.restored()` in `iOSApp.init()`, so an iOS build with no entitlements — every fresh clone, every
        // fork, every CI run — died before its first screen. It was measured on a simulator by installing such a
        // build and reading its log, after two earlier guesses at the trap's location proved wrong.
        // `AppGroup.containerURL` asks the same question of the same subsystem and answers `nil` instead of
        // trapping, which is the whole reason it exists.
        guard AppGroup.containerURL != nil else {
            logger.notice("This build has no App Group entitlement, so the shared container is unreachable; opening the store in the build's own container instead")
            return ownContainer(for: schema)
        }

        let sharedConfiguration = ModelConfiguration(
            storeName,
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .none
        )

        logger.notice("Opening SwiftData store \"\(storeName, privacy: .public)\" in App Group \(AppGroup.identifier, privacy: .public) with schema v\(SchemaV3.versionIdentifier.description, privacy: .public) and the migration plan")

        do {
            let container = try ModelContainer(for: schema, migrationPlan: CirruscopeMigrationPlan.self, configurations: sharedConfiguration)
            logger.notice("Opened the SwiftData store in the App Group container at \(sharedConfiguration.url.path, privacy: .public)")
            return container
        } catch {
            logger.error("Could not open the SwiftData store in the App Group container; quarantining it and retrying: \(error.localizedDescription, privacy: .public)")
        }

        quarantineStore(at: sharedConfiguration.url)

        do {
            let container = try ModelContainer(for: schema, migrationPlan: CirruscopeMigrationPlan.self, configurations: sharedConfiguration)
            logger.notice("Rebuilt the SwiftData store in the App Group container after quarantining the previous one")
            return container
        } catch {
            logger.error("Could not open the rebuilt SwiftData store in the App Group container; falling back to this build's own container: \(error.localizedDescription, privacy: .public)")
        }

        return ownContainer(for: schema)
    }()

    /// `ownContainer(for:)` opens the store in the container this build has to itself, which is where a build that cannot reach the App Group's keeps its data.
    ///
    /// Reached two ways, and they mean different things. A build with no App Group entitlement comes straight here, having never had a shared container to use; a build that has one comes here only after its shared store failed to open twice and was quarantined. Both end up with a store that works and is private to this build, which is what lets a fresh clone and a CI run launch at all — see "Building and Signing" in `AGENTS.md`.
    private static func ownContainer(for schema: Schema) -> ModelContainer {
        let configuration = ModelConfiguration(
            storeName,
            schema: schema,
            groupContainer: .none,
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(for: schema, migrationPlan: CirruscopeMigrationPlan.self, configurations: configuration)
            logger.notice("Opened the SwiftData store in this build's own container at \(configuration.url.path, privacy: .public); it is not reading the shared store")
            return container
        } catch {
            logger.fault("Could not open the SwiftData store in the App Group container or in this build's own container: \(error.localizedDescription, privacy: .public)")
            preconditionFailure("Could not open the SwiftData store in the App Group container or in this build's own container: \(error.localizedDescription)")
        }
    }

    /// `storeFileSuffixes` are the store file itself and the three sidecars SQLite may have written beside it, which have to be set aside together for either the quarantined copy or what replaces it to be readable.
    private static let storeFileSuffixes = ["", "-wal", "-shm", "-journal"]

    /// `quarantineStore(at:)` moves the SQLite store file and its `-wal`/`-shm`/`-journal` sidecars aside to `.quarantine` siblings, so a fresh container can be created in place of an unreadable one without destroying the user's data — which stays on disk, recoverable, rather than being deleted.
    ///
    /// A second quarantine never overwrites the first. The whole point of moving these files rather than deleting them is that the user's keyboard shortcuts are the one thing in the store nothing can re-fetch, and an earlier version of this method removed an existing `.quarantine` sibling before moving the live file onto it — so a store that failed to open twice destroyed the copy made the first time, which is the run most likely to have held good data. Later passes therefore land on `.quarantine-2`, `.quarantine-3`, and so on, chosen by `quarantineExtension(in:for:)`.
    ///
    /// Each move is logged (and each failure logged at `.error`, without aborting the rest) so a support log shows exactly which files were set aside and where.
    private static func quarantineStore(at storeURL: URL) {
        let directory = storeURL.deletingLastPathComponent()
        let name = storeURL.lastPathComponent
        let fileManager = FileManager.default
        let quarantineExtension = quarantineExtension(in: directory, for: name)

        logger.notice("Quarantining store \"\(name, privacy: .public)\" and its sidecars in \(directory.path, privacy: .public) as \"\(quarantineExtension, privacy: .public)\"")

        for suffix in storeFileSuffixes {
            let live = directory.appending(path: name + suffix)

            guard fileManager.fileExists(atPath: live.path) else {
                logger.debug("No \"\(name + suffix, privacy: .public)\" present; nothing to quarantine")
                continue
            }

            let quarantined = directory.appending(path: name + suffix + quarantineExtension)

            do {
                try fileManager.moveItem(at: live, to: quarantined)
                logger.notice("Quarantined \"\(name + suffix, privacy: .public)\" → \"\(quarantined.lastPathComponent, privacy: .public)\"")
            } catch {
                logger.error("Could not quarantine \"\(name + suffix, privacy: .public)\": \(error.localizedDescription, privacy: .public)")
            }
        }

        logger.notice("Quarantine pass complete")
    }

    /// `quarantineExtension(in:for:)` is the file extension this quarantine pass appends, being the first of `.quarantine`, `.quarantine-2`, `.quarantine-3`, … that no file of the store's name already carries.
    ///
    /// One extension is chosen for the whole pass rather than per file, so the store and its sidecars stay a matched set: a copy whose `-wal` came from a different failure is not a recoverable store. The plain `.quarantine` is kept for the first pass because it is the case that essentially always happens and the one the surrounding documentation names; the numbered ones exist so a second failure adds to the evidence instead of erasing it.
    /// The search is bounded. Ten quarantined copies of one store is not a state worth generating more of, and reusing the last extension at that point trades a theoretical loss of the tenth copy for a guarantee that this never becomes an unbounded loop on a directory the app cannot write to.
    private static func quarantineExtension(in directory: URL, for name: String) -> String {
        let fileManager = FileManager.default

        for generation in 1 ... 10 {
            let candidate = generation == 1 ? ".quarantine" : ".quarantine-\(generation)"

            let isTaken = storeFileSuffixes.contains { suffix in
                fileManager.fileExists(atPath: directory.appending(path: name + suffix + candidate).path)
            }

            guard isTaken else {
                return candidate
            }
        }

        logger.error("Ten quarantined copies of \"\(name, privacy: .public)\" already exist; reusing the last extension, which overwrites it")
        return ".quarantine-10"
    }
}
