// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `LocalStorageRetentionTests` measures that `Script.localStorageRetention`, installed the way both apps install it, keeps a page's own call clearing local storage from removing anything.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(5)))
struct LocalStorageRetentionTests {
    @Test
    func `Without the script a page clearing its local storage empties it`() async {
        let remaining = await LocalStorageClearProbe.remainingItemCount(installing: nil)

        #expect(remaining == 0)
    }

    @Test
    func `With the script a page clearing its local storage keeps every item`() async throws {
        let source = try #require(Script.localStorageRetention.source)
        let remaining = await LocalStorageClearProbe.remainingItemCount(installing: source)

        #expect(remaining == 1)
    }
}
