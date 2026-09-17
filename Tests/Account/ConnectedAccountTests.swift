// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import SwiftData
import Testing

/// `ConnectedAccountTests` covers the lifecycle of the single `Account` record: connecting to a server, recording its version, and deleting the account again.
///
/// The case worth the suite is about the memoized `cachedAccount`, which every read in the store goes through: deleting the account has to clear it, or a later write lands on a deleted object and the old app list comes back with it. `deleteAccount()` is exercised rather than `disconnect()` because `disconnect()`'s other steps empty the real `AssetCache` and clear the real `Keychain`.
///
/// That the deletion also cascades to a keyboard shortcut is asserted by `macOSTests/Account/AccountDeletionCascadeTests`, which could not move here: assigning a shortcut needs a fixture built out of AppKit's own modifier flags. This suite runs against both app modules, which is what makes it the one that would notice an iOS-side difference in how the store or its container behaves.
@MainActor
@Suite(.serialized)
struct ConnectedAccountTests {
    /// `harness` is this case's own store over a fresh in-memory container.
    private let harness = AccountStoreHarness()

    /// `server` is the address these cases connect to.
    private let server = URL(string: "https://cloud.example.com")!

    /// `otherServer` is a second address, for the cases that reconnect.
    private let otherServer = URL(string: "https://other.example.com")!

    @Test
    func `A fresh store has no server address and no server version`() {
        #expect(harness.store.serverAddress == nil)
        #expect(harness.store.serverVersion == nil)
    }

    @Test
    func `Connecting records the server address`() {
        harness.store.connect(to: server)

        #expect(harness.store.serverAddress == server)
    }

    @Test
    func `Reconnecting replaces the server address`() {
        harness.store.connect(to: server)
        harness.store.connect(to: otherServer)

        #expect(harness.store.serverAddress == otherServer)
    }

    @Test
    func `Recording the server version creates the account when none exists yet`() {
        // `ServerConnection.validate(_:)` records the version before `connect(to:)` ever runs, so this write has to
        // be able to create the account rather than quietly doing nothing.
        harness.store.setServerVersion("31.0.2")

        #expect(harness.store.serverVersion == "31.0.2")
    }

    @Test
    func `Clearing the server version`() {
        harness.store.setServerVersion("31.0.2")
        harness.store.setServerVersion(nil)

        #expect(harness.store.serverVersion == nil)
    }

    @Test
    func `Neither connecting nor recording a version announces an app change`() {
        harness.store.connect(to: server)
        harness.store.setServerVersion("31.0.2")

        #expect(harness.notificationCount == 0)
    }

    @Test
    func `A connection after deletion does not resurrect the deleted account`() {
        harness.store.connect(to: server)
        harness.store.persist(serverApps: ServerAppFixture.all)
        harness.store.deleteAccount()

        harness.store.connect(to: otherServer)

        // A `cachedAccount` left pointing at the deleted record would take this write instead, and the old app list
        // would come back with it.
        #expect(harness.store.serverAddress == otherServer)
        #expect(harness.store.serverApps.isEmpty)
    }

    @Test
    func `A write is committed rather than left pending in the context`() throws {
        harness.store.connect(to: server)

        // Autosave is off, so every mutator saves explicitly; a second context on the same container sees only what
        // was actually committed.
        let separateContext = ModelContext(harness.container)
        let accounts = try separateContext.fetch(FetchDescriptor<Account>())

        #expect(accounts.count == 1)
        #expect(accounts.first?.serverAddress == server)
    }
}
