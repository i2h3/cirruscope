// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `ShortcutSurvivalTests` covers what happens to a keyboard shortcut when the server data around it changes: an app updated in place, an app the server stops offering, and the account itself being deleted at a sign-out.
@MainActor
@Suite(.serialized, .exclusiveStoreAccess)
struct ShortcutSurvivalTests {
    /// `harness` is this case's own store over a fresh in-memory container.
    private let harness = AccountStoreHarness()

    /// `server` is the address the cases connect to first.
    private let server = URL(string: "https://cloud.example.com")!

    /// `otherServer` is a second address, for the case that signs in somewhere else.
    private let otherServer = URL(string: "https://other.example.com")!

    @Test
    func `A shortcut survives an app-list refresh`() {
        harness.store.persist(serverApps: [ServerAppFixture.files, ServerAppFixture.photos])
        harness.store.setShortcut(ShortcutFixture.named("⌘1").shortcut, forAppID: "files")

        // Refreshing with the *renamed* app proves the update path ran, rather than the list happening to be identical.
        harness.store.persist(serverApps: [ServerAppFixture.renamedFiles, ServerAppFixture.photos])

        #expect(harness.store.shortcut(forAppID: "files") == ShortcutFixture.named("⌘1").shortcut)
    }

    @Test
    func `A shortcut outlives its app being pruned, reaches nothing meanwhile, and applies again when the app returns`() {
        harness.store.persist(serverApps: [ServerAppFixture.files, ServerAppFixture.photos])
        harness.store.setShortcut(ShortcutFixture.named("⌘1").shortcut, forAppID: "files")
        harness.store.persist(serverApps: [ServerAppFixture.photos])

        // While Files is not offered, its shortcut applies to nothing and occupies nothing.
        #expect(harness.store.shortcut(forAppID: "files") == nil)
        #expect(harness.store.nameOfApp(usingShortcut: ShortcutFixture.named("⌘1").shortcut, otherThanAppID: "photos") == nil)

        harness.store.persist(serverApps: [ServerAppFixture.files, ServerAppFixture.photos])
        #expect(harness.store.shortcut(forAppID: "files") == ShortcutFixture.named("⌘1").shortcut)
    }

    @Test
    func `A shortcut survives the account being deleted, and applies on whichever server offers the app next`() {
        harness.store.connect(to: server)
        harness.store.persist(serverApps: ServerAppFixture.all)
        harness.store.setShortcut(ShortcutFixture.named("⌘1").shortcut, forAppID: "files")

        harness.store.deleteAccount()

        #expect(harness.store.serverApps.isEmpty)
        #expect(harness.store.shortcut(forAppID: "files") == nil)

        harness.store.connect(to: otherServer)
        harness.store.persist(serverApps: [ServerAppFixture.files])

        #expect(harness.store.shortcut(forAppID: "files") == ShortcutFixture.named("⌘1").shortcut)
    }
}
