// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import SwiftData

/// `AppDatabase` owns the single, process-wide SwiftData `ModelContainer` backing Cirruscope's account store.
///
/// The container is configured with `groupContainer: .identifier(AppGroup.identifier)` so the store lives in the shared App Group container — under `Library/Application Support/`, disjoint from `AssetCache`'s `Library/Caches/` subtree — where a future app extension carrying the same entitlement can also open it. The store is local only (`cloudKitDatabase: .none`); secrets never go in it (they stay in `Keychain`).
///
/// `ModelContainer` is `Sendable`, so exposing it as a `static let` mirrors the existing `AppGroup` / `AssetCache.shared` singleton conventions. Access the main-actor context through `AccountStore`, which is the only type that touches it. Opening the store — including running `CirruscopeMigrationPlan` and any quarantine fallback — logs at `.notice`/`.error`/`.fault` so the whole startup path is reconstructable from a log capture in a release build.
enum AppDatabase {
    /// `logger` records store setup and recovery under the `AppDatabase` category.
    private static let logger = Logger(for: AppDatabase.self)

    /// `storeName` is the fixed configuration name that pins the store's filename, so every target — the app and any future extension — opens the very same file rather than a differently-named default.
    private static let storeName = "Cirruscope"

    /// `container` is the shared model container, built on first access, opened with `CirruscopeMigrationPlan` so a store written by an earlier shipped schema is migrated forward in place.
    ///
    /// If opening the store fails — a genuinely corrupt file, or a migration that could not complete — the store files are moved aside to `.quarantine` siblings (never deleted) and the container is rebuilt once from an empty store, so a failure degrades to "shortcuts reset, apps re-fetched from the server" rather than destroying the user's data or crash-looping on launch; the quarantined files stay on disk for recovery. A second failure is treated as an unrecoverable provisioning problem.
    static let container: ModelContainer = {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let configuration = ModelConfiguration(
            storeName,
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .none
        )

        logger.notice("Opening SwiftData store \"\(storeName, privacy: .public)\" at \(configuration.url.path, privacy: .public) with schema v\(SchemaV2.versionIdentifier.description, privacy: .public) and the migration plan")

        do {
            let container = try ModelContainer(for: schema, migrationPlan: CirruscopeMigrationPlan.self, configurations: configuration)
            logger.notice("Opened the SwiftData store successfully")
            return container
        } catch {
            logger.error("Could not open the SwiftData store; quarantining it and starting fresh: \(error.localizedDescription, privacy: .public)")
            quarantineStore(at: configuration.url)

            do {
                let container = try ModelContainer(for: schema, migrationPlan: CirruscopeMigrationPlan.self, configurations: configuration)
                logger.notice("Rebuilt the SwiftData store from empty after quarantining the previous one")
                return container
            } catch {
                logger.fault("Could not open the SwiftData store even after quarantining it: \(error.localizedDescription, privacy: .public)")
                preconditionFailure("Could not open the SwiftData store even after quarantining it: \(error.localizedDescription)")
            }
        }
    }()

    /// `quarantineStore(at:)` moves the SQLite store file and its `-wal`/`-shm`/`-journal` sidecars aside to `.quarantine` siblings, so a fresh container can be created in place of an unreadable one without destroying the user's data — which stays on disk, recoverable, rather than being deleted.
    ///
    /// Each move is logged (and each failure logged at `.error`, without aborting the rest) so a support log shows exactly which files were set aside and where.
    private static func quarantineStore(at storeURL: URL) {
        let directory = storeURL.deletingLastPathComponent()
        let name = storeURL.lastPathComponent
        let fileManager = FileManager.default

        logger.notice("Quarantining store \"\(name, privacy: .public)\" and its sidecars in \(directory.path, privacy: .public)")

        for suffix in ["", "-wal", "-shm", "-journal"] {
            let live = directory.appending(path: name + suffix)

            guard fileManager.fileExists(atPath: live.path) else {
                logger.debug("No \"\(name + suffix, privacy: .public)\" present; nothing to quarantine")
                continue
            }

            let quarantined = directory.appending(path: name + suffix + ".quarantine")
            try? fileManager.removeItem(at: quarantined)

            do {
                try fileManager.moveItem(at: live, to: quarantined)
                logger.notice("Quarantined \"\(name + suffix, privacy: .public)\" → \"\(quarantined.lastPathComponent, privacy: .public)\"")
            } catch {
                logger.error("Could not quarantine \"\(name + suffix, privacy: .public)\": \(error.localizedDescription, privacy: .public)")
            }
        }

        logger.notice("Quarantine pass complete")
    }
}
