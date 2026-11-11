// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `ServerAppTransferObject` is a value-type snapshot of a Nextcloud server app the user can navigate to, used to populate both apps' server-app menus and the Keyboard Shortcuts settings tab on macOS.
struct ServerAppTransferObject: Codable, Identifiable, Sendable {
    /// `id` is the Nextcloud app identifier (e.g. `"files"`), matched against the `/apps/<id>/` path of a web view's URL to detect which app a window currently shows.
    let id: String

    /// `order` is the position the server assigns the app in the web interface's own app menu, recorded as reported on every refresh but not what any of Cirruscope's lists are sorted by — see `AccountStore.serverApps` for the order they use instead and why.
    let order: Int

    /// `href` is where the server says the app lives (e.g. `"/apps/files/"`), resolved against the connected server address to form the URL a window loads.
    let href: String

    /// `name` is the localized display name of the app, used as its menu item label.
    let name: String
}
