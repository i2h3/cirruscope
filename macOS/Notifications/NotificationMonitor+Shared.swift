// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit

///
/// This extension builds the macOS app's process-wide notification monitor.
///
/// It exists per platform because building the monitor means answering two questions only AppKit can: the badge is the Dock tile's, and new notifications are posted only while no web window is open, since an open window shows the Nextcloud web interface, which raises its own notifications through the page's notification bridge and would otherwise announce each one twice.
///
extension NotificationMonitor {
    ///
    /// `shared` is the process-wide monitor, retained for the app's lifetime so it can own the long-lived event stream.
    ///
    static let shared = NotificationMonitor(writeBadge: { DockBadge.apply($0) }, mayPost: { (NSApp.delegate as? AppDelegate)?.hasOpenWebWindow == false })
}
