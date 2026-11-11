// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import SwiftData

/// `AppDatabase` owns the single, process-wide SwiftData `ModelContainer` backing Cirruscope's account store.
enum AppDatabase {
    /// `logger` records store setup and recovery under the `AppDatabase` category.
    private static let logger = Logger(for: AppDatabase.self)

    /// `storeName` is the fixed configuration name that pins the store's filename, so every target that opens the store — both apps — opens the very same file rather than a differently-named default.
    private static let storeName = "Cirruscope"

    /// `schema` is the app's current SwiftData schema.
    static let schema = Schema(versionedSchema: SchemaV4.self)

    /// `container` is the shared model container, built on first access, opened with `CirruscopeMigrationPlan` so a store written by an earlier shipped schema is migrated forward in place.
    ///
    /// A failure after that is unrecoverable and traps. There is deliberately no store private to this build to open instead: one would be empty, so a build landing there would silently show the user none of their data, and a build that cannot reach the shared container is one whose signing was overridden — see AGENTS.md → Building and Signing.
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

        // Where every build without the App Group entitlement kept the store, `1.1.0` as the App Store shipped it
        // included. Only the URL is read; the configuration is never opened.
        let ownConfiguration = ModelConfiguration(
            storeName,
            schema: schema,
            groupContainer: .none,
            cloudKitDatabase: .none
        )

        importStore(from: ownConfiguration.url, into: sharedConfiguration.url)

        logger.notice("Opening SwiftData store \"\(storeName, privacy: .public)\" in App Group \(AppGroup.identifier, privacy: .public) with schema v\(SchemaV4.versionIdentifier.description, privacy: .public) and the migration plan")

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

    /// `importStore(from:into:)` moves the store at `ownStoreURL`, which a build without the App Group entitlement wrote into the app's own container, to `sharedStoreURL` in the App Group container, so the first entitled launch carries the user's data across instead of leaving it behind.
    static func importStore(from ownStoreURL: URL, into sharedStoreURL: URL) {
        let fileManager = FileManager.default
        let ownDirectory = ownStoreURL.deletingLastPathComponent()
        let ownName = ownStoreURL.lastPathComponent
        let sharedDirectory = sharedStoreURL.deletingLastPathComponent()
        let sharedName = sharedStoreURL.lastPathComponent

        guard fileManager.fileExists(atPath: ownStoreURL.path) else {
            logger.debug("No store in this build's own container; nothing to import")
            return
        }

        logger.notice("Found a store in this build's own container at \(ownStoreURL.path, privacy: .public), written by a build without the App Group entitlement; moving it into the App Group container")

        do {
            try fileManager.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("Could not create \(sharedDirectory.path, privacy: .public) to import the store into; leaving it in this build's own container: \(error.localizedDescription, privacy: .public)")
            return
        }

        let sharedFileExists = {
            storeFileSuffixes.contains { suffix in
                fileManager.fileExists(atPath: sharedDirectory.appending(path: sharedName + suffix).path)
            }
        }

        if sharedFileExists() {
            quarantineStore(at: sharedStoreURL)
        }

        guard sharedFileExists() == false else {
            logger.error("The store already in the App Group container could not be set aside; leaving the one in this build's own container to try again on the next launch")
            return
        }

        for suffix in storeFileSuffixes {
            let source = ownDirectory.appending(path: ownName + suffix)

            guard fileManager.fileExists(atPath: source.path) else {
                continue
            }

            let destination = sharedDirectory.appending(path: sharedName + suffix)

            do {
                try fileManager.moveItem(at: source, to: destination)
                logger.notice("Moved \"\(ownName + suffix, privacy: .public)\" into the App Group container")
            } catch {
                logger.error("Could not move \"\(ownName + suffix, privacy: .public)\" into the App Group container: \(error.localizedDescription, privacy: .public)")

                // The store file is the first to move, so failing on it leaves everything in place to be tried again.
                // A sidecar failing after it cannot be put right from here, and is what the error above records.
                guard suffix.isEmpty == false else {
                    return
                }
            }
        }

        logger.notice("Imported the store from this build's own container into the App Group container")
    }

    /// `storeFileSuffixes` are the store file itself and the three sidecars SQLite may have written beside it, which have to be set aside together for either the quarantined copy or what replaces it to be readable.
    private static let storeFileSuffixes = ["", "-wal", "-shm", "-journal"]

    /// `quarantineStore(at:)` moves the SQLite store file and its `-wal`/`-shm`/`-journal` sidecars aside to `.quarantine` siblings, so a fresh container can be created in place of an unreadable one without destroying the user's data — which stays on disk, recoverable, rather than being deleted.
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
