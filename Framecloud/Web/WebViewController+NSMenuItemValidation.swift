import AppKit

/// `WebViewController`'s conformance to `NSMenuItemValidation` keeps the "Show/Hide Sidebar" menu item in sync with the state of Nextcloud's sidebar that `WebViewController` tracks via its `sidebarToggleAvailable` and `sidebarToggleExpanded` properties.
extension WebViewController: NSMenuItemValidation {

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSidebar(_:)) {
            menuItem.title = sidebarToggleExpanded ? "Hide Sidebar" : "Show Sidebar"
            return sidebarToggleAvailable
        }

        return true
    }
}
