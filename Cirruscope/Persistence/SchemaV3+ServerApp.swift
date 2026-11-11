// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

extension SchemaV3 {
    /// `ServerApp` is the v3 record for a Nextcloud server app offered by an account exactly as it shipped in `1.2.0` and `1.2.1`.
    ///
    /// It is a frozen copy; see `SchemaV3` for why it never changes.
    @Model
    final class ServerApp {
        /// `appID` is the Nextcloud app identifier (e.g. `"files"`), used to match a web view's URL and to upsert this row across refreshes.
        var appID: String

        /// `order` is the position the server assigns the app in the web interface's own app menu, kept in step with the server on every refresh but not what any of Cirruscope's lists are sorted by — see `AccountStore.serverApps`.
        var order: Int

        /// `href` is the server-relative path of the app (e.g. `"/apps/files/"`), resolved against `Account.serverAddress` to form the URL a window loads.
        var href: String

        /// `name` is the localized display name of the app, used as its menu item label.
        var name: String

        /// `account` is the account this app belongs to; it is the inverse of `Account.apps`.
        var account: Account?

        init(appID: String, order: Int, href: String, name: String, account: Account? = nil) {
            self.appID = appID
            self.order = order
            self.href = href
            self.name = name
            self.account = account
        }
    }
}
