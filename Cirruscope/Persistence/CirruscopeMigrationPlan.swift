// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import os
import SwiftData
import Synchronization

/// `CirruscopeMigrationPlan` carries Cirruscope's SwiftData store forward across every schema it has ever had: `SchemaV1` (the shipped `1.0.0` schema), `SchemaV2` (the shipped `1.1.0` one), `SchemaV2_1` (an intermediate step no build runs on), and `SchemaV3` (the current one), preserving the keyboard shortcuts and appearance settings users set up along the way.
///
/// Two of its moves are not inferable. The first renames the `AppShortcut` entity to `KeyboardShortcut`, and SwiftData has no entity-level `originalName`, so a lightweight migration would drop every row; that stage copies each row across the rename by value. The second moves the shortcuts and the appearance settings out of the account: a shortcut stops hanging off its `ServerApp` and is keyed by the app's identifier instead, which only the relationship being removed can tell it, and the appearance settings move from `Account` into a record of their own. That move goes through `SchemaV2_1`, which first adds the empty column and entity it needs, so that it can be written inside the store and saved before anything is dropped. `AppDatabase` passes this plan when opening the container, and a stage whose source version the store is already past is skipped, so a fresh install and a relaunch both run nothing.
///
/// Every stage addresses the models of the versions it operates on, never the app's live top-level types. That distinction is invisible while a frozen schema and the live models still agree and becomes silent data loss the moment they do not, which is exactly what freezing `SchemaV2` made possible: `didMigrate` below fetches `SchemaV2.ServerApp` and inserts a `SchemaV2.KeyboardShortcut`, because a `1.0.0` store arriving at the end of the first stage is a v2 store and nothing else.
///
/// Every step logs at `.notice` (and failures at `.error`) with the counts and app ids in the clear, because this migration runs once on a user's real data and is exactly the kind of thing whose logs must survive into a release build's persisted store — so that when something goes wrong, a `log show`/`log stream` capture reconstructs precisely what happened.
enum CirruscopeMigrationPlan: SchemaMigrationPlan {
    /// `logger` records migration activity under the `CirruscopeMigrationPlan` category.
    private static let logger = Logger(for: CirruscopeMigrationPlan.self)

    /// `schemas` lists every versioned schema this plan spans, oldest first.
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV2_1.self, SchemaV3.self]
    }

    /// `stages` are the migration stages applied in order: the `SchemaV1` to `SchemaV2` rename, then the two steps through `SchemaV2_1` that move what the user set up on the device out of the account.
    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV2_1, migrateV2_1toV3]
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

    /// `migrateV2toV2_1` carries a v2 store into `SchemaV2_1`, adding an empty `appID` column to the keyboard shortcuts and an empty `DevicePreferences` entity, both of which SwiftData infers.
    ///
    /// It is a stage of its own so that the next one has somewhere on disk to write what it moves, instead of a stash in memory.
    static let migrateV2toV2_1 = MigrationStage.lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV2_1.self)

    /// `migrateV2_1toV3` moves the keyboard shortcuts and the appearance settings out of the account, so that a sign-out, which deletes the account, no longer takes them with it.
    ///
    /// `willMigrate` does all of the work, inside the store and before the schema change: it copies each shortcut's app identifier off the `ServerApp` it hangs off into the shortcut's own `appID`, copies the appearance choices off the account into a `DevicePreferences`, and saves. The schema change that follows then only drops what has already been copied — the relationship between a shortcut and its app, and the account's two attributes — and makes `appID` required and unique, which every remaining row by then satisfies. Nothing the user set up is ever held only in memory, so a migration that is interrupted or fails, and the copy `AppDatabase` quarantines when one fails, still carry it.
    /// A shortcut whose app is missing cannot be keyed and is logged and deleted, as in the first stage. More than one shortcut for one app identifier cannot be written by a shipped build but is handled anyway, keeping the first and deleting the rest, because the identifier becomes unique. The `Account` and its `ServerApp` rows stay, because an upgrade must not sign anybody out. A `DevicePreferences` is written only if the user made either choice, so a choice never made stays one the defaults decide, and only if none exists yet, so a stage run again over a store it already wrote to changes nothing.
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
}
