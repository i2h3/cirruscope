// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import SwiftData
import Testing

///
/// `StoreImportTests` pins `AppDatabase.importStore(from:into:)`, the one move that carries a store a build without the App Group entitlement wrote into the App Group container.
///
/// It exists because that store is where every `1.1.0` user's keyboard shortcuts and appearance choices live: the release the App Store shipped carried no App Group entitlement and kept its store in the app's own container, so an entitled build that opened only the App Group's would greet everybody updating with an empty one. Nothing reports that as an error, which is why it has to be asserted.
/// Two harnesses stand in for the two containers. Neither is the app's: naming `AppDatabase.container` from a test is forbidden, because its recovery path moves the developer's real store files aside, and this function moves files by design.
/// Like `StoreMigrationTests` it is not `@MainActor`, for the same reason: nothing here touches AppKit or `AccountStore`.
///
@Suite(.serialized)
struct StoreImportTests {
    /// `own` stands in for the app's own container, where a build without the App Group entitlement kept the store.
    let own = StoreFileHarness()

    /// `shared` stands in for the App Group container the store is moved into.
    let shared = StoreFileHarness()

    /// `write(_:to:)` creates a file at `url` holding `contents`, which the cases read back to tell whose file ended up where.
    private func write(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url)
    }

    /// `contents(of:)` is what `write(_:to:)` put at `url`, or `nil` when nothing is there.
    private func contents(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return String(decoding: data, as: UTF8.self)
    }

    /// `sibling(of:suffix:)` is the file beside `url` whose name carries `suffix`, the way SQLite names its sidecars and `AppDatabase` names a quarantined copy.
    private func sibling(of url: URL, suffix: String) -> URL {
        url.deletingLastPathComponent().appending(path: url.lastPathComponent + suffix)
    }

    ///
    /// A build that was always entitled has nothing in its own container, and the store already in the App Group container must then be left exactly as it is.
    ///
    @Test
    func `Nothing moves when the own container holds no store`() throws {
        try write("shared", to: shared.storeURL)

        AppDatabase.importStore(from: own.storeURL, into: shared.storeURL)

        #expect(contents(of: shared.storeURL) == "shared")
        #expect(FileManager.default.fileExists(atPath: sibling(of: shared.storeURL, suffix: ".quarantine").path) == false)
    }

    ///
    /// The store and its write-ahead log are one store between them, so both have to arrive, and the own container has to be left empty so that the next launch does not import again.
    ///
    @Test
    func `The store and its sidecars move into the App Group container`() throws {
        try write("own", to: own.storeURL)
        try write("own-wal", to: sibling(of: own.storeURL, suffix: "-wal"))
        try write("own-shm", to: sibling(of: own.storeURL, suffix: "-shm"))

        AppDatabase.importStore(from: own.storeURL, into: shared.storeURL)

        #expect(contents(of: shared.storeURL) == "own")
        #expect(contents(of: sibling(of: shared.storeURL, suffix: "-wal")) == "own-wal")
        #expect(contents(of: sibling(of: shared.storeURL, suffix: "-shm")) == "own-shm")
        #expect(FileManager.default.fileExists(atPath: own.storeURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: sibling(of: own.storeURL, suffix: "-wal").path) == false)
    }

    ///
    /// A Mac that ran an entitled build before this one already has a store in the App Group container. It is the less valuable of the two, since the user's own choices are in the other, but it is set aside rather than overwritten.
    ///
    @Test
    func `A store already in the App Group container is quarantined rather than overwritten`() throws {
        try write("own", to: own.storeURL)
        try write("shared", to: shared.storeURL)
        try write("shared-wal", to: sibling(of: shared.storeURL, suffix: "-wal"))

        AppDatabase.importStore(from: own.storeURL, into: shared.storeURL)

        #expect(contents(of: shared.storeURL) == "own")
        #expect(contents(of: sibling(of: shared.storeURL, suffix: ".quarantine")) == "shared")
        #expect(contents(of: sibling(of: shared.storeURL, suffix: "-wal.quarantine")) == "shared-wal")
    }

    ///
    /// A write-ahead log left behind in the App Group container without its store would otherwise be read as the imported store's own, which SQLite would apply to the wrong database.
    ///
    @Test
    func `A sidecar left alone in the App Group container is set aside before the store arrives`() throws {
        try write("own", to: own.storeURL)
        try write("stale-wal", to: sibling(of: shared.storeURL, suffix: "-wal"))

        AppDatabase.importStore(from: own.storeURL, into: shared.storeURL)

        #expect(contents(of: shared.storeURL) == "own")
        #expect(FileManager.default.fileExists(atPath: sibling(of: shared.storeURL, suffix: "-wal").path) == false)
        #expect(contents(of: sibling(of: shared.storeURL, suffix: "-wal.quarantine")) == "stale-wal")
    }

    ///
    /// The case that matters: a store written in the `1.1.0` shape in the own container, moved and then opened by the current build through the migration plan, still holds the account, its apps, the shortcuts and the appearance choices.
    ///
    @Test
    func `A store written by 1.1.0 in the own container keeps its data once imported and migrated`() throws {
        try own.seed(Schema(versionedSchema: SchemaV2.self)) { context in
            let account = SchemaV2.Account(serverAddress: URL(string: "https://cloud.example.com"), serverVersion: "34.0.0", translucentAppearance: true, removeGaps: true)
            context.insert(account)

            let files = SchemaV2.ServerApp(appID: "files", order: 0, href: "/apps/files/", name: "Files", account: account)
            context.insert(files)
            context.insert(SchemaV2.KeyboardShortcut(keyEquivalent: "1", modifierFlags: 1_048_576, app: files))
        }

        AppDatabase.importStore(from: own.storeURL, into: shared.storeURL)

        #expect(FileManager.default.fileExists(atPath: own.storeURL.path) == false)

        try shared.open(AppDatabase.schema, migrationPlan: CirruscopeMigrationPlan.self) { context in
            let accounts = try context.fetch(FetchDescriptor<Account>())
            #expect(accounts.count == 1)
            #expect(accounts.first?.serverAddress == URL(string: "https://cloud.example.com"))
            #expect(try context.fetch(FetchDescriptor<ServerApp>()).map(\.appID) == ["files"])

            let preferences = try context.fetch(FetchDescriptor<DevicePreferences>())
            #expect(preferences.first?.translucentAppearance == true)
            #expect(preferences.first?.removeGaps == true)

            let shortcuts = try context.fetch(FetchDescriptor<KeyboardShortcut>())
            #expect(shortcuts.map(\.appID) == ["files"])
            #expect(shortcuts.first?.keyEquivalent == "1")
        }
    }
}
