// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import SwiftData
import Testing

/// `DevicePreferencesTests` covers the appearance settings as the store keeps them: on the device, apart from any account.
///
/// The suite exists because the settings used to live on the account, so every sign-out reset them and flipping a switch before signing in created an account with no address.
/// The second of those is pinned here by the case that looks for an account through a context of its own; the first by the deletion case in `ConnectedAccountTests`.
/// The read-back and unset cases are baselines that held under the old design too, and the announcement case observes the store's own seam rather than a web view in the host app reacting to it.
/// It runs against both app modules, the store being shared, though only the Mac app shows the settings today.
@MainActor
@Suite(.serialized)
struct DevicePreferencesTests {
    /// `harness` is this case's own store over a fresh in-memory container.
    private let harness = AccountStoreHarness()

    @Test
    func `Nothing chosen reads as nil, so the callers' defaults apply`() {
        #expect(harness.store.translucentAppearance == nil)
        #expect(harness.store.removeGaps == nil)
    }

    @Test
    func `A choice reads back without anybody being signed in`() {
        harness.store.setTranslucentAppearance(true)
        harness.store.setRemoveGaps(false)

        #expect(harness.store.translucentAppearance == true)
        #expect(harness.store.removeGaps == false)
        #expect(harness.store.serverAddress == nil)
    }

    @Test
    func `A choice creates no account`() throws {
        harness.store.setTranslucentAppearance(true)
        harness.store.setRemoveGaps(true)

        let separateContext = ModelContext(harness.container)
        #expect(try separateContext.fetch(FetchDescriptor<Account>()).isEmpty)
        #expect(try separateContext.fetch(FetchDescriptor<DevicePreferences>()).count == 1)
    }

    @Test
    func `Each choice is announced so open web views re-apply it`() {
        harness.store.setTranslucentAppearance(true)
        harness.store.setRemoveGaps(false)

        #expect(harness.announcements == [.appearanceSettingsDidChange, .appearanceSettingsDidChange])
    }
}
