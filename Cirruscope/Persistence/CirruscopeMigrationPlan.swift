// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import SwiftData
import Synchronization

/// `CirruscopeMigrationPlan` carries Cirruscope's SwiftData store forward across every schema it has ever had: `SchemaV1` (the shipped `1.0.0` schema), `SchemaV2` (the shipped `1.1.0` one), and `SchemaV3` (the current one), preserving the keyboard shortcuts users set up before the `AppShortcut` → `KeyboardShortcut` rename.
///
/// That rename changes a store entity's name, which SwiftData cannot infer on its own — there is no entity-level `originalName`, so a lightweight migration would drop every `AppShortcut` row. The first stage is therefore a custom one that copies each row across the rename by value; the second has no work to do at all. `AppDatabase` passes this plan when opening the container, and a stage whose source version the store is already past is skipped, so a fresh install and a relaunch both run nothing.
///
/// Every stage addresses the models of the version it operates on, never the app's live top-level types. That distinction is invisible while a frozen schema and the live models still agree and becomes silent data loss the moment they do not, which is exactly what freezing `SchemaV2` made possible: `didMigrate` below fetches `SchemaV2.ServerApp` and inserts a `SchemaV2.KeyboardShortcut`, because a `1.0.0` store arriving at the end of the first stage is a v2 store and nothing else.
///
/// Every step logs at `.notice` (and failures at `.error`) with the counts and app ids in the clear, because this migration runs once on a user's real data and is exactly the kind of thing whose logs must survive into a release build's persisted store — so that when something goes wrong, a `log show`/`log stream` capture reconstructs precisely what happened.
enum CirruscopeMigrationPlan: SchemaMigrationPlan {
    /// `logger` records migration activity under the `CirruscopeMigrationPlan` category.
    private static let logger = Logger(for: CirruscopeMigrationPlan.self)

    /// `schemas` lists every versioned schema this plan spans, oldest first.
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self]
    }

    /// `stages` are the migration stages applied in order: the custom `SchemaV1` to `SchemaV2` rename, then the empty `SchemaV2` to `SchemaV3` step.
    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3]
    }

    /// `CapturedShortcut` is a value snapshot of one v1 `AppShortcut` — its key equivalent, modifier flags, and the `appID` of the server app it belongs to — carried from `willMigrate` to `didMigrate` across the schema change.
    private struct CapturedShortcut: Sendable {
        /// `appID` identifies the `ServerApp` this shortcut is re-linked to after the migration.
        let appID: String

        /// `keyEquivalent` is the character that triggers the shortcut.
        let keyEquivalent: String

        /// `modifierFlags` is the raw value of the `NSEvent.ModifierFlags` required by the shortcut.
        let modifierFlags: UInt
    }

    /// `captured` holds the shortcuts read in `willMigrate` until `didMigrate` recreates them; a `Mutex` because the migration stage's closures are `@Sendable`.
    private static let captured = Mutex<[CapturedShortcut]>([])

    /// `migrateV1toV2` renames the `AppShortcut` entity to `KeyboardShortcut` without losing data.
    ///
    /// `willMigrate` reads every v1 `AppShortcut` into `captured`, then deletes the v1 rows so the `ServerApp.shortcut` relationship — whose destination entity is being renamed — has nothing dangling for SwiftData to auto-migrate (leaving it in place crashes the migration). Once the schema change has applied, `didMigrate` recreates each shortcut as a `KeyboardShortcut` and re-links it to its `ServerApp` by `appID`. Both closures log each step and log-then-rethrow on failure, so a partial or failed migration is fully diagnosable from a log capture.
    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self,
        willMigrate: { context in
            logger.notice("willMigrate (v1→v2): reading v1 AppShortcut rows before the schema change")

            do {
                let shortcuts = try context.fetch(FetchDescriptor<SchemaV1.AppShortcut>())
                logger.notice("willMigrate: found \(shortcuts.count, privacy: .public) AppShortcut row(s) in the v1 store")

                var items: [CapturedShortcut] = []
                for shortcut in shortcuts {
                    guard let appID = shortcut.app?.appID else {
                        logger.error("willMigrate: an AppShortcut (key '\(shortcut.keyEquivalent, privacy: .public)', flags \(shortcut.modifierFlags, privacy: .public)) has no associated ServerApp; it cannot be re-linked and will be dropped")
                        continue
                    }

                    items.append(CapturedShortcut(appID: appID, keyEquivalent: shortcut.keyEquivalent, modifierFlags: shortcut.modifierFlags))
                    logger.notice("willMigrate: captured shortcut '\(shortcut.keyEquivalent, privacy: .public)' (flags \(shortcut.modifierFlags, privacy: .public)) for app '\(appID, privacy: .public)'")
                }

                captured.withLock { $0 = items }
                logger.notice("willMigrate: captured \(items.count, privacy: .public) shortcut(s); deleting the v1 rows before the schema change")

                for shortcut in shortcuts {
                    context.delete(shortcut)
                }

                try context.save()
                logger.notice("willMigrate: deleted \(shortcuts.count, privacy: .public) v1 row(s) and saved; ready for the schema change")
            } catch {
                logger.error("willMigrate failed: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        },
        didMigrate: { context in
            logger.notice("didMigrate (v1→v2): recreating KeyboardShortcut rows from the captured v1 shortcuts")

            let items = captured.withLock { stash -> [CapturedShortcut] in
                let snapshot = stash
                stash = []
                return snapshot
            }

            guard items.isEmpty == false else {
                logger.notice("didMigrate: no shortcuts were captured; nothing to recreate, migration complete")
                return
            }

            do {
                let apps = try context.fetch(FetchDescriptor<SchemaV2.ServerApp>())
                logger.notice("didMigrate: \(items.count, privacy: .public) shortcut(s) to recreate against \(apps.count, privacy: .public) server app(s)")

                var appsByID: [String: SchemaV2.ServerApp] = [:]
                for app in apps {
                    appsByID[app.appID] = app
                }

                var recreated = 0
                for item in items {
                    guard let app = appsByID[item.appID] else {
                        logger.error("didMigrate: no ServerApp with id '\(item.appID, privacy: .public)' found; shortcut '\(item.keyEquivalent, privacy: .public)' cannot be re-linked and is dropped")
                        continue
                    }

                    context.insert(SchemaV2.KeyboardShortcut(keyEquivalent: item.keyEquivalent, modifierFlags: item.modifierFlags, app: app))
                    recreated += 1
                    logger.notice("didMigrate: recreated shortcut '\(item.keyEquivalent, privacy: .public)' (flags \(item.modifierFlags, privacy: .public)) for app '\(item.appID, privacy: .public)'")
                }

                try context.save()
                logger.notice("didMigrate: recreated \(recreated, privacy: .public) of \(items.count, privacy: .public) shortcut(s) and saved; migration complete")
            } catch {
                logger.error("didMigrate failed: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }
    )

    /// `migrateV2toV3` carries a store from the schema `1.1.0` shipped to the current one, and has nothing to do.
    ///
    /// `SchemaV3` is shape-identical to `SchemaV2`: it exists so that freezing `SchemaV2` into nested model copies had a successor to hand the live types to, rather than because anything about the store changed. A lightweight stage is therefore both correct and a no-op, and it is declared rather than omitted because a plan whose `schemas` names a version its `stages` cannot reach is a plan with a hole in it.
    static let migrateV2toV3 = MigrationStage.lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self)
}
