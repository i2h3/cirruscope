// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// This extension builds the iOS app's process-wide account store.
///
/// It is the counterpart of the macOS file of the same name, and differs in exactly one thing: nothing is passed for `isReservedShortcut`, so the store keeps its default answer that no shortcut is reserved. That is not a stub standing in for unfinished work — it is the truth. A reserved shortcut is one of Cirruscope's own menu items already holding a key equivalent, and iOS has no menu bar for one to be held in.
extension AccountStore {
    /// `shared` is the process-wide account store, over the app's on-disk container.
    ///
    /// It is the only instance production code builds, and the only one that must ever be built over `AppDatabase.container`: each instance memoizes the single `Account` separately, so two of them over one container would each believe a stale answer. Being a `static let` it is created lazily, which is what keeps the real store closed until something asks for persisted data — sign-in and the web view both come up from the Keychain alone.
    static let shared = AccountStore(container: AppDatabase.container)
}
