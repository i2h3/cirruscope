// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `ShortcutSurvivalTests` covers what happens to a keyboard shortcut when the server data around it changes: an app updated in place, an app the server stops offering, and the account itself being deleted at a sign-out.
///
/// A shortcut belongs to the device and is keyed by the app's identifier, so none of these may delete it. What they change is whether it reaches anything: a shortcut whose app the connected server does not offer applies to nothing, conflicts with nothing and is named as nobody's occupant, and applies again the moment a server offers the app.
/// The cases read the shortcut the way a menu does, through `shortcut(forAppID:)` and `nameOfApp(usingShortcut:otherThanAppID:)`, which are macOS's alone; that the records themselves outlive a deletion is also pinned on both modules by `Tests/Account/ConnectedAccountTests`.
@MainActor
@Suite(.serialized)
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
