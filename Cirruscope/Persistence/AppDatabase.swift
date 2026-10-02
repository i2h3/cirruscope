// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import SwiftData

/// `AppDatabase` owns the single, process-wide SwiftData `ModelContainer` backing Cirruscope's account store.
///
/// The container is configured with `groupContainer: .identifier(AppGroup.identifier)` so the store lives in the shared App Group container — under `Library/Application Support/`, disjoint from `AssetCache`'s `Library/Caches/` subtree — where any extension carrying the same entitlement can also open it. The store is local only (`cloudKitDatabase: .none`); secrets never go in it (they stay in `Keychain`).
///
/// `ModelContainer` is `Sendable`, so exposing it as a `static let` mirrors the existing `AppGroup` / `AssetCache.shared` singleton conventions. Access the main-actor context through `AccountStore`, which is the only type that touches it. Opening the store — including running `CirruscopeMigrationPlan` and any quarantine — logs at `.notice`/`.error`/`.fault` so the whole startup path is reconstructable from a log capture in a release build.
enum AppDatabase {
    /// `logger` records store setup and recovery under the `AppDatabase` category.
    private static let logger = Logger(for: AppDatabase.self)

    /// `storeName` is the fixed configuration name that pins the store's filename, so every target that opens the store — both apps — opens the very same file rather than a differently-named default.
    private static let storeName = "Cirruscope"

    /// `schema` is the app's current SwiftData schema.
    ///
    /// It is one definition rather than two because `AccountStore`'s unit tests build their own in-memory container from it (see `AccountStoreHarness`): a schema spelled out a second time on the test side would keep exercising whichever version it was written against once the app moves on. It names the newest versioned schema, `SchemaV3`; `CirruscopeMigrationPlan` migrates a store written by an older one up to it.
    static let schema = Schema(versionedSchema: SchemaV3.self)

    /// `container` is the shared model container, built on first access, opened with `CirruscopeMigrationPlan` so a store written by an earlier shipped schema is migrated forward in place.
    ///
    /// It lives in the App Group container and nowhere else. If opening it fails — a genuinely corrupt file, or a migration that could not complete — the store files are moved aside to `.quarantine` siblings (never deleted) and it is tried once more: the store is largely reconstructible (what came from the server is fetched from it again; only the user's own choices — keyboard shortcuts and the appearance settings — are authored locally), so recovering beats crash-looping on launch, and quarantining rather than deleting means a store that will not open is set aside with whatever it still holds rather than destroyed — the files stay on disk for recovery.
    ///
    /// A failure after that is unrecoverable and traps. There is deliberately no store private to this build to open instead: one would be empty, so a build landing there would silently show the user none of their data, and a build that cannot reach the shared container is one whose signing was overridden — see AGENTS.md → Building and Signing.
    ///
    /// Being a `static let`, it is opened only once something actually asks for it, which is what lets the account store's tests run entirely on their own in-memory container: nothing in them reaches `AccountStore.shared`, so this store is never opened on their behalf — and it must stay that way, since the recovery path above moves the developer's real store files aside.
    static let container: ModelContainer = {
        let schema = Self.schema

        // Resolved before a group-container `ModelConfiguration` is so much as constructed, because constructing one
        // an app is not entitled to reach does not fail — it traps inside SwiftData, with "Unable to find App Group
        // Container in Entitlements" from `SwiftData/DataUtilities.swift` and nothing to catch. `AppGroup.containerURL`
        // traps first on iOS, with a message that names the cause; on macOS it resolves regardless, and the open
        // below fails instead.
        _ = AppGroup.containerURL

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
            logger.error("Could not open the SwiftData store in the App Group container; quarantining it and retrying: \(String(describing: error), privacy: .public)")
        }

        quarantineStore(at: sharedConfiguration.url)

        do {
            let container = try ModelContainer(for: schema, migrationPlan: CirruscopeMigrationPlan.self, configurations: sharedConfiguration)
            logger.notice("Rebuilt the SwiftData store in the App Group container after quarantining the previous one")
            return container
        } catch {
            logger.fault("Could not open the SwiftData store in the App Group container, even after quarantining it: \(String(describing: error), privacy: .public)")
            preconditionFailure("Could not open the SwiftData store in the App Group container, even after quarantining it: \(error.localizedDescription)")
        }
    }()

    /// `storeFileSuffixes` are the store file itself and the three sidecars SQLite may have written beside it, which have to be set aside together for either the quarantined copy or what replaces it to be readable.
    private static let storeFileSuffixes = ["", "-wal", "-shm", "-journal"]

    /// `quarantineStore(at:)` moves the SQLite store file and its `-wal`/`-shm`/`-journal` sidecars aside to `.quarantine` siblings, so a fresh container can be created in place of an unreadable one without destroying the user's data — which stays on disk, recoverable, rather than being deleted.
    ///
    /// A second quarantine never overwrites the first. The whole point of moving these files rather than deleting them is that the user's own choices — keyboard shortcuts and the appearance settings — are the one part of the store nothing can re-fetch, and an earlier version of this method removed an existing `.quarantine` sibling before moving the live file onto it — so a store that failed to open twice destroyed the copy made the first time, which is the run most likely to have held good data. Later passes therefore land on `.quarantine-2`, `.quarantine-3`, and so on, chosen by `quarantineExtension(in:for:)`.
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
