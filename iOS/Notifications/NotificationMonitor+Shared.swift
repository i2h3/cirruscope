// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

///
/// This extension builds the iOS app's process-wide notification monitor.
///
/// It exists per platform because building the monitor means answering two questions differently on each: the badge is the home screen's, written through `AppIconBadge`, and nothing is ever posted while the monitor runs, since it runs only while the app is in front, where the Nextcloud web interface shows the same notifications already.
/// What arrives meanwhile is recorded as seen, so the background refresh does not announce it later either.
///
extension NotificationMonitor {
    ///
    /// `shared` is the process-wide monitor, retained for the app's lifetime so it can own the event stream while the app is in front.
    ///
    static let shared = NotificationMonitor(writeBadge: AppIconBadge.apply, mayPost: { false })
}
