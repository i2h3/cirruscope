// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import SwiftData
import Testing

/// `StoreMigrationTests` covers `CirruscopeMigrationPlan` end to end: a store written by each schema Cirruscope has ever shipped is reopened at the current one, and everything the user authored has to still be there.
///
/// This suite exists because nothing tested the migration at all, and the migration is the one piece of this app that can destroy data a user cannot get back. Server apps, theming and the server version are all re-fetched on the next launch; a keyboard shortcut is authored locally and exists nowhere else. `AppDatabase` compounds that: when the store cannot be opened it quarantines the files and rebuilds an empty one, so a migration that throws does not surface as an error the user sees but as an app that has forgotten them.
///
/// Each case seeds a store through the *frozen* models of the version it is pretending to be — `SchemaV1.Account` and friends, never the live top-level types — because addressing the live types is precisely the mistake these cases are here to catch. That is not hypothetical: `migrateV1toV2`'s `didMigrate` addressed the live `ServerApp` and `KeyboardShortcut` until `SchemaV2` was frozen, which was correct only for as long as the live models happened to agree with the shipped v2 ones.
///
/// Two attributes here are load-bearing rather than tidiness, and both were measured rather than assumed after this suite hung the whole test run indefinitely while every one of its cases passed alone in under three seconds.
///
/// It is `.serialized` because Swift Testing runs a suite's cases in parallel by default, and a migration is not a pure function of the store it opens: `CirruscopeMigrationPlan` carries its captured shortcuts through process-wide state between `willMigrate` and `didMigrate`, so two of them in flight at once are two writers of one stash.
///
/// It is deliberately **not** `@MainActor`, which the other suites in this folder are. Nothing here touches AppKit or `AccountStore`; it builds its own containers and contexts, and those have no main-actor requirement. Annotating it anyway meant a synchronous migration ran *on* the main actor while the rest of the run's main-actor suites waited behind it, which is a deadlock rather than a slowdown — the run stopped with `StoreMigrationTests` announced, no case result after it, and the host app idle in its run loop.
@Suite(.serialized)
struct StoreMigrationTests {
    /// `harness` gives each case its own store on disk; see `StoreFileHarness` for why an in-memory one cannot answer this question.
    let harness = StoreFileHarness()

    // The `1.0.0` case below is disabled, and the reason is worth stating in full because it is the most valuable
    // case in this suite and its absence is a real gap rather than a tidied-away nuisance.
    //
    // It passes reliably as the only suite in a run and fails reliably as soon as any other suite runs beside it —
    // including one touching no SwiftData at all, which is what rules out contention over the app's schema as the
    // cause. The failure is not an expectation: the host process aborts on an uncaught Objective-C exception from
    // `-[NSStagedMigrationManager _findCurrentMigrationStageFromModelChecksum:]`, taking whatever else was in
    // flight down with it, and Swift cannot catch that to report it as a finding. What the exception says is that
    // the store's recorded model checksum matched no stage in the plan, which points at the store this case writes
    // a moment earlier not being settled by the time it is reopened: a `ModelContainer` has no explicit close, so
    // the seeding container is released rather than closed, and under concurrent execution that release is not
    // prompt.
    //
    // None of this reaches the app. `AppDatabase` builds every container the app ever opens, always through
    // `CirruscopeMigrationPlan`, and it is the first and only SwiftData container in that process — the ordering
    // this case cannot reproduce under load is exactly the ordering production always has.
    //
    // The fix is a store fixture written by a real `1.0.0` build and committed, rather than one synthesized here:
    // it removes the seeding step this case dies in, and tests something stronger besides — a store the shipped
    // app actually wrote. Until then the `1.0.0` path is covered by the manual check in the plan, and the two
    // cases that remain still pin the shipped `1.1.0` shape and the current one.

    @Test(.disabled("Seeding a 1.0.0-shaped store and migrating it in one process survives no concurrent test execution; see the note above."))
    func `A store written by 1.0.0 keeps its account, apps and shortcuts when it is opened by the current build`() throws {
        try harness.seed(Schema(versionedSchema: SchemaV1.self)) { context in
            let account = SchemaV1.Account(serverAddress: URL(string: "https://cloud.example.com"), serverVersion: "34.0.0")
            context.insert(account)

            let files = SchemaV1.ServerApp(appID: "files", order: 0, href: "/apps/files/", name: "Files", account: account)
            let notes = SchemaV1.ServerApp(appID: "notes", order: 1, href: "/apps/notes/", name: "Notes", account: account)
            context.insert(files)
            context.insert(notes)

            context.insert(SchemaV1.AppShortcut(keyEquivalent: "1", modifierFlags: 1_048_576, app: files))
            context.insert(SchemaV1.AppShortcut(keyEquivalent: "2", modifierFlags: 1_179_648, app: notes))
        }

        let shortcuts = try harness.open(AppDatabase.schema, migrationPlan: CirruscopeMigrationPlan.self) { context in
            let accounts = try context.fetch(FetchDescriptor<Account>())
            #expect(accounts.count == 1)
            #expect(accounts.first?.serverAddress == URL(string: "https://cloud.example.com"))
            #expect(accounts.first?.serverVersion == "34.0.0")

            let apps = try context.fetch(FetchDescriptor<ServerApp>())
            #expect(apps.map(\.appID).sorted() == ["files", "notes"])

            // Keyed by app identifier rather than compared as a list, because the shortcut that matters is the one
            // still attached to the app the user assigned it to. A migration that recreated both rows but crossed
            // their links would satisfy any assertion made over the shortcuts alone.
            return Dictionary(uniqueKeysWithValues: apps.compactMap { app in
                app.shortcut.map { (app.appID, ($0.keyEquivalent, $0.modifierFlags)) }
            })
        }

        #expect(shortcuts["files"]?.0 == "1")
        #expect(shortcuts["files"]?.1 == 1_048_576)
        #expect(shortcuts["notes"]?.0 == "2")
        #expect(shortcuts["notes"]?.1 == 1_179_648)
    }

    @Test
    func `A store written by 1.1.0 keeps its account, apps, appearance choices and shortcuts when it is opened by the current build`() throws {
        try harness.seed(Schema(versionedSchema: SchemaV2.self)) { context in
            let account = SchemaV2.Account(serverAddress: URL(string: "https://cloud.example.com"), serverVersion: "34.0.0", translucentAppearance: true, removeGaps: false)
            context.insert(account)

            let files = SchemaV2.ServerApp(appID: "files", order: 0, href: "/apps/files/", name: "Files", account: account)
            context.insert(files)
            context.insert(SchemaV2.KeyboardShortcut(keyEquivalent: "1", modifierFlags: 1_048_576, app: files))
        }

        try harness.open(AppDatabase.schema, migrationPlan: CirruscopeMigrationPlan.self) { context in
            let accounts = try context.fetch(FetchDescriptor<Account>())
            #expect(accounts.count == 1)
            #expect(accounts.first?.serverAddress == URL(string: "https://cloud.example.com"))

            // The two appearance choices are the only attributes version 2 added, so they are what distinguishes a
            // migration that carried the v2 store forward from one that read it as a v1 store and dropped them.
            #expect(accounts.first?.translucentAppearance == true)
            #expect(accounts.first?.removeGaps == false)

            let apps = try context.fetch(FetchDescriptor<ServerApp>())
            #expect(apps.count == 1)
            #expect(apps.first?.shortcut?.keyEquivalent == "1")
            #expect(apps.first?.shortcut?.modifierFlags == 1_048_576)
        }
    }

    @Test
    func `A store created by the current build carries the current schema version`() throws {
        try harness.seed(AppDatabase.schema) { context in
            context.insert(Account(serverAddress: URL(string: "https://cloud.example.com")))
        }

        try harness.open(AppDatabase.schema, migrationPlan: CirruscopeMigrationPlan.self) { context in
            let accounts = try context.fetch(FetchDescriptor<Account>())
            #expect(accounts.count == 1)
        }

        // Pins what `AppDatabase` actually hands the container, so the day a new schema is introduced without the
        // app being pointed at it, this fails rather than the app quietly continuing to write the older shape.
        #expect(AppDatabase.schema.version == SchemaV3.versionIdentifier)
    }
}
