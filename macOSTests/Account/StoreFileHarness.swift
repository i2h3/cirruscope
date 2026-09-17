// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import SwiftData

/// `StoreFileHarness` gives one test case a SwiftData store on disk, in a directory of its own, and removes it again when the case ends.
///
/// It exists because `AccountStoreHarness`' in-memory container cannot answer the question a migration asks. A migration is what happens when a store *written earlier* is *opened again*, and an in-memory container has no earlier: it is created at one schema and discarded, never reopened, so nothing about `CirruscopeMigrationPlan` can be exercised through it. These cases therefore need real files.
///
/// The directory is unique per instance, which is what keeps cases from colliding while Swift Testing runs them in parallel, and it is deliberately under `URL.temporaryDirectory` rather than anywhere the app itself would look. Naming `AppGroup.containerURL` or `AppDatabase.container` from a test is forbidden for a reason that applies with particular force here: `AppDatabase`'s recovery path *moves the developer's real store files aside*, so a migration test pointed at it would quarantine their actual account the first time it failed.
final class StoreFileHarness {
    /// `directory` is this harness' own directory, holding the store file and whatever sidecars SQLite writes beside it.
    let directory: URL

    /// `storeURL` is the store file itself, named as `AppDatabase` names the app's.
    var storeURL: URL {
        directory.appending(path: "Cirruscope.store")
    }

    /// `init()` creates the directory the store will live in.
    init() {
        directory = URL.temporaryDirectory.appending(path: "CirruscopeStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// `configuration(for:)` is a configuration over this harness' store file, carrying `schema`.
    ///
    /// The URL is given explicitly rather than through a `groupContainer`, so nothing about what this resolves to depends on which entitlements the test bundle's host happens to carry — which is the difference between a suite that means the same thing on a developer's provisioned Mac and on an ad-hoc CI runner.
    func configuration(for schema: Schema) -> ModelConfiguration {
        ModelConfiguration(schema: schema, url: storeURL)
    }

    /// `seed(_:_:)` opens the store at `schema` with no migration plan, hands its context to `write`, saves, and closes it again.
    ///
    /// Closing is the whole point and is why this takes a closure rather than vending a container: a `ModelContainer` keeps its store open for as long as anything references it, so a case that merely stopped using one would go on to reopen a file still held by the first. Everything the container owns is confined to this call, so the store is closed by the time it returns.
    func seed(_ schema: Schema, _ write: (ModelContext) throws -> Void) throws {
        let container = try ModelContainer(for: schema, configurations: configuration(for: schema))
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try write(context)
        try context.save()
    }

    /// `open(_:migrationPlan:)` reopens the store at `schema` through `migrationPlan`, hands its context to `read`, and closes it again.
    func open<Result>(_ schema: Schema, migrationPlan: (any SchemaMigrationPlan.Type)?, _ read: (ModelContext) throws -> Result) throws -> Result {
        let container = try ModelContainer(for: schema, migrationPlan: migrationPlan, configurations: configuration(for: schema))
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return try read(context)
    }
}
