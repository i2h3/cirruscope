// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// This extension builds the iOS app's process-wide notification monitor.
extension NotificationMonitor {
    /// `shared` is the process-wide monitor, retained for the app's lifetime so it can own the event stream while the app is in front.
    static let shared = NotificationMonitor(writeBadge: AppIconBadge.apply, mayPost: { false })
}
