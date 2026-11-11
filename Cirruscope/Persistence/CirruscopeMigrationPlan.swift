// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import SwiftData
import Synchronization

/// `CirruscopeMigrationPlan` carries Cirruscope's SwiftData store forward across every schema it has ever had: `SchemaV1` (the shipped `1.0.0` schema), `SchemaV2` (the shipped `1.1.0` one), `SchemaV2_1` (an intermediate step no build runs on), `SchemaV3` (the shipped `1.2.0` and `1.2.1` one), and `SchemaV4` (the current one), preserving the keyboard shortcuts and appearance settings users set up along the way.
enum CirruscopeMigrationPlan: SchemaMigrationPlan {
    /// `logger` records migration activity under the `CirruscopeMigrationPlan` category.
    private static let logger = Logger(for: CirruscopeMigrationPlan.self)

    /// `schemas` lists every versioned schema this plan spans, oldest first.
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV2_1.self, SchemaV3.self, SchemaV4.self]
    }

    /// `stages` are the migration stages applied in order: the `SchemaV1` to `SchemaV2` rename, the two steps through `SchemaV2_1` that move what the user set up on the device out of the account, and the addition of the account's identity.
    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV2_1, migrateV2_1toV3, migrateV3toV4]
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

    /// `migrateV2toV2_1` carries a v2 store into `SchemaV2_1`, adding an empty `appID` column to the keyboard shortcuts and an empty `DevicePreferences` entity, both of which SwiftData infers.
    ///
    /// It is a stage of its own so that the next one has somewhere on disk to write what it moves, instead of a stash in memory.
    static let migrateV2toV2_1 = MigrationStage.lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV2_1.self)

    /// `migrateV2_1toV3` moves the keyboard shortcuts and the appearance settings out of the account, so that a sign-out, which deletes the account, no longer takes them with it.
    static let migrateV2_1toV3 = MigrationStage.custom(
        fromVersion: SchemaV2_1.self,
        toVersion: SchemaV3.self,
        willMigrate: { context in
            logger.notice("willMigrate (v2.1→v3): keying the shortcuts by app identifier and moving the appearance choices off the account, inside the store")

            do {
                let shortcuts = try context.fetch(FetchDescriptor<SchemaV2_1.KeyboardShortcut>())
                logger.notice("willMigrate: found \(shortcuts.count, privacy: .public) KeyboardShortcut row(s)")

                var seenAppIDs: Set<String> = []
                var keyed = 0

                for shortcut in shortcuts {
                    guard let appID = shortcut.appID ?? shortcut.app?.appID else {
                        logger.error("willMigrate: a KeyboardShortcut (key '\(shortcut.keyEquivalent, privacy: .public)', flags \(shortcut.modifierFlags, privacy: .public)) has no associated ServerApp; it cannot be keyed and is deleted")
                        context.delete(shortcut)
                        continue
                    }

                    guard seenAppIDs.insert(appID).inserted else {
                        logger.error("willMigrate: a second shortcut '\(shortcut.keyEquivalent, privacy: .public)' (flags \(shortcut.modifierFlags, privacy: .public)) for app '\(appID, privacy: .public)' is deleted; the first one is kept")
                        context.delete(shortcut)
                        continue
                    }

                    shortcut.appID = appID
                    keyed += 1
                    logger.notice("willMigrate: keyed shortcut '\(shortcut.keyEquivalent, privacy: .public)' (flags \(shortcut.modifierFlags, privacy: .public)) to app '\(appID, privacy: .public)'")
                }

                if try context.fetchCount(FetchDescriptor<SchemaV2_1.DevicePreferences>()) == 0 {
                    let accounts = try context.fetch(FetchDescriptor<SchemaV2_1.Account>())

                    // A shipped build keeps at most one account, but a store can hold an address-less one created by an
                    // appearance toggle before signing in; the first account carrying a choice is the one that has it.
                    let translucentAppearance = accounts.lazy.compactMap(\.translucentAppearance).first
                    let removeGaps = accounts.lazy.compactMap(\.removeGaps).first

                    if translucentAppearance != nil || removeGaps != nil {
                        context.insert(SchemaV2_1.DevicePreferences(translucentAppearance: translucentAppearance, removeGaps: removeGaps))
                        logger.notice("willMigrate: recorded the appearance choices off \(accounts.count, privacy: .public) account(s) as device preferences: translucency \(translucentAppearance.map(String.init(describing:)) ?? "not chosen", privacy: .public), remove gaps \(removeGaps.map(String.init(describing:)) ?? "not chosen", privacy: .public)")
                    } else {
                        logger.notice("willMigrate: no appearance choice was ever made; the defaults keep applying")
                    }
                } else {
                    logger.notice("willMigrate: device preferences already exist; leaving them as they are")
                }

                try context.save()
                logger.notice("willMigrate: keyed \(keyed, privacy: .public) of \(shortcuts.count, privacy: .public) shortcut(s) and saved; ready for the schema change")
            } catch {
                logger.error("willMigrate (v2.1→v3) failed: \(String(describing: error), privacy: .public)")
                throw error
            }
        },
        didMigrate: { _ in
            logger.notice("didMigrate (v2.1→v3): the shortcuts are keyed by app identifier and the appearance choices are device preferences; migration complete")
        }
    )

    /// `migrateV3toV4` carries a v3 store into `SchemaV4`, adding the account's user identifier and display name, both optional and therefore inferred by SwiftData.
    ///
    /// Nothing is written: an account that arrives without its identity is asked for it on its next refresh, exactly like one that has just signed in.
    static let migrateV3toV4 = MigrationStage.lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self)
}
