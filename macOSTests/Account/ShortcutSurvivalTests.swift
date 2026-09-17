// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `ShortcutSurvivalTests` covers what an app-list refresh does to a keyboard shortcut: it survives the app being updated in place, and is pruned with the app when the server stops offering it.
///
/// This is the half of `ServerAppUpsertTests` that could not move to `Tests/`, where both app modules run the rest. Upserting, pruning and ordering are all pure and platform-neutral; these two cases are not, because a shortcut only exists as a `ShortcutFixture` built from `NSEvent.ModifierFlags`. The rule matching by identifier exists to serve is exactly this one, so the cases stay wherever they can be written rather than being dropped.
@MainActor
@Suite(.serialized)
struct ShortcutSurvivalTests {
    /// `harness` is this case's own store over a fresh in-memory container.
    private let harness = AccountStoreHarness()

    @Test
    func `A shortcut survives an app-list refresh`() {
        harness.store.persist(serverApps: [ServerAppFixture.files, ServerAppFixture.photos])
        harness.store.setShortcut(ShortcutFixture.named("⌘1").shortcut, forAppID: "files")

        // Refreshing with the *renamed* app proves the update path ran, rather than the list happening to be identical.
        harness.store.persist(serverApps: [ServerAppFixture.renamedFiles, ServerAppFixture.photos])

        #expect(harness.store.shortcut(forAppID: "files") == ShortcutFixture.named("⌘1").shortcut)
    }

    @Test
    func `A shortcut is pruned with the app it belonged to`() {
        harness.store.persist(serverApps: [ServerAppFixture.files, ServerAppFixture.photos])
        harness.store.setShortcut(ShortcutFixture.named("⌘1").shortcut, forAppID: "files")
        harness.store.persist(serverApps: [ServerAppFixture.photos])

        // The combination is free again, which is what tells the shortcut apart from one merely unreachable because
        // its app is gone: the cascade delete really removed the record.
        #expect(harness.store.nameOfApp(usingShortcut: ShortcutFixture.named("⌘1").shortcut, otherThanAppID: "photos") == nil)

        harness.store.persist(serverApps: [ServerAppFixture.files, ServerAppFixture.photos])
        #expect(harness.store.shortcut(forAppID: "files") == nil)
    }
}
