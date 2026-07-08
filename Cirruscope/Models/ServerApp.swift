import Foundation
import Rainmaker

/// `ServerApp` is a Nextcloud server app the user can navigate to, persisted in `Settings.serverApps` so it can populate the View and Dock menus and the Apps settings tab.
///
/// It is the storable projection of `Rainmaker.NavigationItem` (which is decode-only), keeping just the fields Cirruscope needs: the `id` used to detect which app a window shows, the `order` used to sort the menus, the `href` used to build the app's URL, and the `name` used as the menu label.
struct ServerApp: Codable, Identifiable {

    /// `id` is the Nextcloud app identifier (e.g. `"files"`), matched against the `/apps/<id>/` path of a web view's URL to detect which app a window currently shows.
    let id: String

    /// `order` is the position the server assigns the app; the View and Dock menus list apps sorted ascending by this value.
    let order: Int

    /// `href` is the server-relative path of the app (e.g. `"/apps/files/"`), appended to `Settings.serverAddress` to form the URL a window loads.
    let href: String

    /// `name` is the localized display name of the app, used as its menu item label.
    let name: String

    /// `init(_:)` projects a `Rainmaker.NavigationItem` into the subset of fields Cirruscope persists.
    init(_ item: NavigationItem) {
        id = item.id
        order = item.order
        href = item.href
        name = item.name
    }
}
