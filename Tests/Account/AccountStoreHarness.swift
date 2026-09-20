// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import SwiftData

/// `AccountStoreHarness` is one `AccountStore` under test, over a private in-memory SwiftData container and with stand-ins for the two things the store reaches outside itself for.
///
/// Every account suite holds one as a stored property, so Swift Testing's per-case instantiation gives each case a store nothing else can see: no case observes another's data, and none of them ever names `AccountStore.shared`, whose container lives in the shared App Group container and holds the developer's real account. The container is in-memory rather than a temporary file because nothing here tests file layout, and an in-memory store leaves no cleanup a failing case could skip.
///
/// The stand-ins are plain closures because that is how the store takes them. `isReservedShortcut` is what this harness claims Cirruscope's own menu items occupy, replacing a lookup that would otherwise answer from the app's real menu bar; `notificationCount` counts the change announcements the store made, replacing a post the app's real `AppDelegate` listens for throughout the run. The count says *that* a mutator announced, not *when*: the production post hops to the next main-thread turn and this one deliberately does not, so a case can assert it synchronously.
///
/// It lives here rather than beside the macOS suites because the store does: `Cirruscope/` is compiled into both apps, so a suite over it belongs in the folder both test targets list and runs against two SDKs rather than one. That is why the reserved-shortcut stand-in arrives as a closure instead of as a list of shortcuts this type compares itself — comparing them is `ShortcutMatching`, which is AppKit and stayed behind with the menu bar it describes. `macOSTests/Account/ReservedShortcuts.swift` builds the closure that does it.
@MainActor
final class AccountStoreHarness {
    /// `container` is the in-memory container `store` reads and writes.
    ///
    /// It is retained here as well as by `store` because a `ModelContainer` closes its store as soon as nothing references it, and it is not private so a case can open a second `ModelContext` on it and observe that a write was committed rather than left pending in the main context.
    let container: ModelContainer

    /// `isReservedShortcut` is what this harness reports as already occupied by one of Cirruscope's own fixed menu items.
    private let isReservedShortcut: @MainActor (KeyboardShortcutTransferObject) -> Bool

    /// `notificationCount` is how many times `store` has announced that something changed, whatever it was.
    ///
    /// A total rather than a tally per name, because what the suites assert is that a mutator announced *at all* and that a read announced nothing. `announcements` is there for a case that needs to know which domain.
    private(set) var notificationCount = 0

    /// `announcements` are the names `store` has announced, in order.
    private(set) var announcements: [Notification.Name] = []

    /// `store` is the store under test, over `container` and this harness's two stand-ins.
    ///
    /// It is `lazy` because its closures capture the harness, which they cannot do before every stored property is initialized, and the capture is `unowned` because the harness owns the store that owns them.
    private(set) lazy var store = AccountStore(container: container, isReservedShortcut: { [unowned self] shortcut in isReservedShortcut(shortcut) }, notifyChange: { [unowned self] name in countAnnouncement(name) })

    /// `init(isReservedShortcut:)` opens a fresh in-memory container over the app's current schema and answers `isReservedShortcut` when the store asks whether a combination is already spoken for.
    ///
    /// The default reserves nothing, which is what a suite that never touches shortcuts wants and what the store itself defaults to on a platform with no menu bar.
    /// Building the container is force-tried: an in-memory container over the very schema the app opens on every launch cannot fail for a reason a test should report as an expectation, so a throw here is a broken harness rather than a finding — the same call `KeyEquivalentProbe.keyDown(for:)`'s force-unwrap makes.
    init(isReservedShortcut: @escaping @MainActor (KeyboardShortcutTransferObject) -> Bool = { _ in false }) {
        container = try! ModelContainer(for: AppDatabase.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        self.isReservedShortcut = isReservedShortcut
    }

    /// `countAnnouncement(_:)` is what the store's `notifyChange` seam does here, in place of posting a notification the host app would act on.
    private func countAnnouncement(_ name: Notification.Name) {
        notificationCount += 1
        announcements.append(name)
    }
}
