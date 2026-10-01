// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

extension SchemaV2_1 {
    /// `ServerApp` is the v2.1 record for a Nextcloud server app offered by an `Account`, identical to the v2 `ServerApp`: its `shortcut` relationship is what the stage into `SchemaV3` reads each shortcut's app identifier from before the relationship is dropped.
    ///
    /// It is a frozen copy; see `SchemaV2_1` for why this intermediate schema exists and why it never changes.
    @Model
    final class ServerApp {
        /// `appID` is the Nextcloud app identifier (e.g. `"files"`).
        var appID: String

        /// `order` is the position the server assigns the app.
        var order: Int

        /// `href` is the server-relative path of the app (e.g. `"/apps/files/"`).
        var href: String

        /// `name` is the localized display name of the app.
        var name: String

        /// `account` is the account this app belongs to; it is the inverse of `Account.apps`.
        var account: Account?

        /// `shortcut` is the user's keyboard shortcut for this app, if any; deleting the app cascades to it.
        @Relationship(deleteRule: .cascade, inverse: \KeyboardShortcut.app)
        var shortcut: KeyboardShortcut?

        init(appID: String, order: Int, href: String, name: String, account: Account? = nil) {
            self.appID = appID
            self.order = order
            self.href = href
            self.name = name
            self.account = account
        }
    }
}
