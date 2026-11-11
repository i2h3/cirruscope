// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import SwiftData
import Testing

/// `StoreFileHarness` gives one test case a SwiftData store on disk, in a directory of its own, and removes it again when the case ends.
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
    func configuration(for schema: Schema) -> ModelConfiguration {
        ModelConfiguration(schema: schema, url: storeURL)
    }

    /// `seed(_:_:)` opens the store at `schema` with no migration plan, hands its context to `write`, saves, and closes it again.
    func seed(_ schema: Schema, _ write: (ModelContext) throws -> Void) throws {
        ExclusiveStoreAccess.recordIfNotHeld(opening: "StoreFileHarness")
        let container = try ModelContainer(for: schema, configurations: configuration(for: schema))
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try write(context)
        try context.save()
    }

    /// `open(_:migrationPlan:)` reopens the store at `schema` through `migrationPlan`, hands its context to `read`, and closes it again.
    func open<Result>(_ schema: Schema, migrationPlan: (any SchemaMigrationPlan.Type)?, _ read: (ModelContext) throws -> Result) throws -> Result {
        ExclusiveStoreAccess.recordIfNotHeld(opening: "StoreFileHarness")
        let container = try ModelContainer(for: schema, migrationPlan: migrationPlan, configurations: configuration(for: schema))
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return try read(context)
    }
}
