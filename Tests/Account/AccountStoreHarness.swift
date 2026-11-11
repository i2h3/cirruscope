// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import SwiftData
import Testing

/// `AccountStoreHarness` is one `AccountStore` under test, over a private in-memory SwiftData container and with stand-ins for the two things the store reaches outside itself for.
@MainActor
final class AccountStoreHarness {
    /// `container` is the in-memory container `store` reads and writes.
    let container: ModelContainer

    /// `isReservedShortcut` is what this harness reports as already occupied by one of Cirruscope's own fixed menu items.
    private let isReservedShortcut: @MainActor (KeyboardShortcutTransferObject) -> Bool

    /// `notificationCount` is how many times `store` has announced that something changed, whatever it was.
    private(set) var notificationCount = 0

    /// `announcements` are the names `store` has announced, in order.
    private(set) var announcements: [Notification.Name] = []

    /// `store` is the store under test, over `container` and this harness's two stand-ins.
    private(set) lazy var store = AccountStore(container: container, isReservedShortcut: { [unowned self] shortcut in isReservedShortcut(shortcut) }, notifyChange: { [unowned self] name in countAnnouncement(name) })

    /// `init(isReservedShortcut:)` opens a fresh in-memory container over the app's current schema and answers `isReservedShortcut` when the store asks whether a combination is already spoken for.
    init(isReservedShortcut: @escaping @MainActor (KeyboardShortcutTransferObject) -> Bool = { _ in false }) {
        ExclusiveStoreAccess.recordIfNotHeld(opening: "AccountStoreHarness")
        container = try! ModelContainer(for: AppDatabase.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        self.isReservedShortcut = isReservedShortcut
    }

    /// `countAnnouncement(_:)` is what the store's `notifyChange` seam does here, in place of posting a notification the host app would act on.
    private func countAnnouncement(_ name: Notification.Name) {
        notificationCount += 1
        announcements.append(name)
    }
}
