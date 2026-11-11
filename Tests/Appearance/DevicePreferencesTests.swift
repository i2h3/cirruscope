// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import SwiftData
import Testing

/// `DevicePreferencesTests` covers the appearance settings as the store keeps them: on the device, apart from any account.
@MainActor
@Suite(.serialized, .exclusiveStoreAccess)
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
