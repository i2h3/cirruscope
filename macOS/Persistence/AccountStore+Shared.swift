// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// This extension builds the macOS app's process-wide account store.
///
/// It exists per platform rather than in the shared file because constructing the store means answering what counts as a reserved shortcut, and that answer is `AppDelegate.reservedShortcutName(for:)` — AppKit, reading the live `NSApp.mainMenu`. Passing it here rather than assigning it to the store after the fact is deliberate: an instance that existed for even one turn of the main queue while answering "nothing is reserved" would apply a shortcut to a menu item that already has one, which is the exact condition the reserved-shortcut rule exists to prevent.
extension AccountStore {
    /// `shared` is the process-wide account store, over the app's on-disk container.
    ///
    /// It is the only instance production code builds, and the only one that must ever be built over `AppDatabase.container`: each instance memoizes the single `Account` separately, so two of them over one container would each believe a stale answer. Being a `static let` it is created lazily, which is what keeps the real store closed during a test run that never names it.
    static let shared = AccountStore(container: AppDatabase.container, isReservedShortcut: { AppDelegate.reservedShortcutName(for: $0) != nil })
}
