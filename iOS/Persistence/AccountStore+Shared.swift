// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// This extension builds the iOS app's process-wide account store.
///
/// It is the counterpart of the macOS file of the same name, and differs in exactly one thing: nothing is passed for `isReservedShortcut`, so the store keeps its default answer that no shortcut is reserved. That is not a stub standing in for unfinished work — it is the truth. A reserved shortcut is one a server app cannot be given because one of Cirruscope's own menu items already holds it, and iOS never gives a server app a shortcut at all — the iPad's View menu lists them without any.
extension AccountStore {
    /// `shared` is the process-wide account store, over the app's on-disk container.
    ///
    /// It is the only instance production code builds, and the only one that must ever be built over `AppDatabase.container`: each instance memoizes the single `Account` and the single `DevicePreferences` separately, so two of them over one container would each believe a stale answer. Being a `static let` it is created lazily, the first time anything names it — at launch, when `Store.restored()` seeds the app list from it; the account itself is read back from the Keychain rather than from here.
    static let shared = AccountStore(container: AppDatabase.container)
}
