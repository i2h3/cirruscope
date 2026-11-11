// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import AppKit

/// `WebViewController`'s conformance to `NSMenuItemValidation` keeps the "Show/Hide Sidebar" menu item in sync with the state of Nextcloud's sidebar that `WebViewController` tracks via its `sidebarToggleAvailable` and `sidebarToggleExpanded` properties.
extension WebViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSidebar(_:)) {
            menuItem.title = sidebarToggleExpanded
                ? String(localized: "Hide Sidebar", comment: "Title of the \"Show/Hide Sidebar\" menu item while Nextcloud's sidebar is currently shown.")
                : String(localized: "Show Sidebar", comment: "Title of the \"Show/Hide Sidebar\" menu item while Nextcloud's sidebar is currently hidden.")
            return sidebarToggleAvailable
        }

        return true
    }
}
