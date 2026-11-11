// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// This extension builds the macOS app's process-wide account store.
extension AccountStore {
    /// `shared` is the process-wide account store, over the app's on-disk container.
    static let shared = AccountStore(container: AppDatabase.container, isReservedShortcut: { AppDelegate.reservedShortcutName(for: $0) != nil })
}
