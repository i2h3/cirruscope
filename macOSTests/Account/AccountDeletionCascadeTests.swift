// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `AccountDeletionCascadeTests` covers the one part of deleting an account that only macOS can assert: that the cascade reaches a keyboard shortcut.
///
/// The rest of the account lifecycle moved to `Tests/Account/ConnectedAccountTests`, which both app modules run. This case could not follow it, and the reason is worth naming because it looks like an arbitrary line: assigning a shortcut needs a `ShortcutFixture`, and that fixture is built out of `NSEvent.ModifierFlags` and the Private Use Area scalars AppKit reserves for function keys. The split follows what a case *needs*, not what it is about \u2014 the same rule `AGENTS.md` records for `ServerAddress`.
@MainActor
@Suite(.serialized)
struct AccountDeletionCascadeTests {
    /// `harness` is this case's own store over a fresh in-memory container.
    private let harness = AccountStoreHarness()

    /// `server` is the address this case connects to.
    private let server = URL(string: "https://cloud.example.com")!

    @Test
    func `Deleting the account removes its apps and their shortcuts`() {
        harness.store.connect(to: server)
        harness.store.persist(serverApps: ServerAppFixture.all)
        harness.store.setShortcut(ShortcutFixture.named("⌘1").shortcut, forAppID: "files")

        harness.store.deleteAccount()

        #expect(harness.store.serverAddress == nil)
        #expect(harness.store.serverApps.isEmpty)

        // Re-adding the app shows the cascade really removed the shortcut record, rather than it being unreachable
        // only because its app was gone.
        harness.store.persist(serverApps: [ServerAppFixture.files])
        #expect(harness.store.shortcut(forAppID: "files") == nil)
    }
}
