// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Testing

/// `AppShortcutAssignmentTests` covers the plain round trip through `AccountStore.setShortcut(_:forAppID:)` and `shortcut(forAppID:)`: recording, replacing, and clearing one app's keyboard shortcut.
///
/// `DuplicateShortcutSuppressionTests` covers which app a combination reaches when several could claim it; this suite covers the simpler contract underneath that, including the deliberate asymmetry that the store stores whatever it is given and leaves refusing an occupied combination to the recorder — visible here because a shortcut Cirruscope's own menu occupies is still stored, merely never applied.
/// The store likewise keeps a shortcut for an app the connected server does not offer: it is recorded against the identifier and announced, reaches nothing and occupies nothing while the app is missing, and applies once a refresh lists it. Clearing a shortcut that was never recorded is the one call to `setShortcut(_:forAppID:)` that announces nothing.
@MainActor
@Suite(.serialized)
struct AppShortcutAssignmentTests {
    /// `harness` is this case's own store over a fresh in-memory container.
    private let harness = AccountStoreHarness()

    /// `commandOne` is the combination these cases record, chosen because no menu item in `Main.storyboard` declares a digit.
    private let commandOne = ShortcutFixture.named("⌘1").shortcut

    @Test
    func `An app with no recorded shortcut has none`() {
        harness.store.persist(serverApps: [ServerAppFixture.files])

        #expect(harness.store.shortcut(forAppID: "files") == nil)
    }

    @Test
    func `A recorded shortcut is stored and read back`() {
        harness.store.persist(serverApps: [ServerAppFixture.files])
        harness.store.setShortcut(commandOne, forAppID: "files")

        #expect(harness.store.shortcut(forAppID: "files") == commandOne)
    }

    @Test
    func `Recording again replaces the stored shortcut`() {
        harness.store.persist(serverApps: [ServerAppFixture.files])
        harness.store.setShortcut(commandOne, forAppID: "files")
        harness.store.setShortcut(ShortcutFixture.named("F5").shortcut, forAppID: "files")

        #expect(harness.store.shortcut(forAppID: "files") == ShortcutFixture.named("F5").shortcut)

        // Asserted from the other side too, through the read that walks every stored shortcut rather than the one
        // fetching this app's, so the combination it replaced is shown to be free again rather than only no longer
        // read back for Files.
        #expect(harness.store.nameOfApp(usingShortcut: commandOne, otherThanAppID: "photos") == nil)
    }

    @Test
    func `Clearing a shortcut removes it`() {
        harness.store.persist(serverApps: [ServerAppFixture.files])
        harness.store.setShortcut(commandOne, forAppID: "files")
        harness.store.setShortcut(nil, forAppID: "files")

        #expect(harness.store.shortcut(forAppID: "files") == nil)
        #expect(harness.store.nameOfApp(usingShortcut: commandOne, otherThanAppID: "photos") == nil)
    }

    @Test
    func `A shortcut for an app the server does not offer is stored but reaches nothing until it does`() {
        harness.store.persist(serverApps: [ServerAppFixture.files])

        harness.store.setShortcut(commandOne, forAppID: "talk")

        // Recorded against the identifier, the shortcut belonging to the device rather than to this server…
        #expect(harness.store.storedShortcut(forAppID: "talk") == commandOne)
        #expect(harness.announcements.last == .keyboardShortcutsDidChange)

        // …but applied to nothing and occupying nothing while no app with that identifier is offered.
        #expect(harness.store.shortcut(forAppID: "talk") == nil)
        #expect(harness.store.nameOfApp(usingShortcut: commandOne, otherThanAppID: "files") == nil)

        harness.store.persist(serverApps: [ServerAppFixture.files, ServerAppFixture.talk])
        #expect(harness.store.shortcut(forAppID: "talk") == commandOne)
    }

    @Test
    func `Clearing a shortcut that was never recorded announces nothing`() {
        harness.store.persist(serverApps: [ServerAppFixture.files])
        let announcementsBefore = harness.notificationCount

        harness.store.setShortcut(nil, forAppID: "files")

        #expect(harness.notificationCount == announcementsBefore)
    }

    @Test
    func `A shortcut Cirruscope's own menu already uses is still stored`() {
        let reserving = AccountStoreHarness(isReservedShortcut: ReservedShortcuts.claiming([commandOne]))
        reserving.store.persist(serverApps: [ServerAppFixture.files, ServerAppFixture.photos])
        reserving.store.setShortcut(commandOne, forAppID: "files")

        // Not applied, because it would shadow one of Cirruscope's own menu items…
        #expect(reserving.store.shortcut(forAppID: "files") == nil)

        // …but stored all the same, which is the observable form of the store keeping what it was given and leaving
        // the refusal to `ShortcutRecorderView`, where the user can be told why.
        #expect(reserving.store.nameOfApp(usingShortcut: commandOne, otherThanAppID: "photos") == "Files")
    }
}
