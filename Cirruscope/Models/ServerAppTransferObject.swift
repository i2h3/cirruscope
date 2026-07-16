// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ServerAppTransferObject` is a value-type snapshot of a Nextcloud server app the user can navigate to, used to populate the View and Dock menus and the Apps settings tab.
///
/// It is the immutable projection `AccountStore` returns from its `ServerApp` records, keeping just the fields the UI needs: the `id` used to detect which app a window shows, the `order` used to sort the menus, the `href` used to build the app's URL, and the `name` used as the menu label. It is `Sendable` so it can be passed freely between actors without exposing a managed `@Model` object.
struct ServerAppTransferObject: Codable, Identifiable, Sendable {
    /// `id` is the Nextcloud app identifier (e.g. `"files"`), matched against the `/apps/<id>/` path of a web view's URL to detect which app a window currently shows.
    let id: String

    /// `order` is the position the server assigns the app; the View and Dock menus list apps sorted ascending by this value.
    let order: Int

    /// `href` is the server-relative path of the app (e.g. `"/apps/files/"`), appended to the connected server address to form the URL a window loads.
    let href: String

    /// `name` is the localized display name of the app, used as its menu item label.
    let name: String

    init(id: String, order: Int, href: String, name: String) {
        self.id = id
        self.order = order
        self.href = href
        self.name = name
    }
}
