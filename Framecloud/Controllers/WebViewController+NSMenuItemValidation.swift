import AppKit

extension WebViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSidebar(_:)) {
            menuItem.title = sidebarToggleExpanded ? "Hide Sidebar" : "Show Sidebar"
            return sidebarToggleAvailable
        }

        return true
    }
}
