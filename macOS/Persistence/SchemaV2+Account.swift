// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

extension SchemaV2 {
    /// `Account` is the v2 root record for the connected Nextcloud account: server address, cached branding and version, the appearance choices, and the apps it offers.
    ///
    /// It is a frozen copy of the `Account` model as it shipped in `1.1.0`; see `SchemaV2` for why the v2 models are nested here rather than reusing the live top-level types.
    @Model
    final class Account {
        /// `serverAddress` is the URL of the connected Nextcloud server, or `nil` while a sign-in is still in progress.
        var serverAddress: URL?

        /// `serverVersion` is the human-readable version string of the connected server.
        var serverVersion: String?

        /// `themeBackground` is the `background` value from the server's `Theming` capability: an image URL string or a hex color value.
        var themeBackground: String?

        /// `themeLogo` is the URL of the instance logo published in the server's `Theming` capability.
        var themeLogo: URL?

        /// `themeBackgroundPlain` is the `backgroundPlain` flag from the server's `Theming` capability.
        var themeBackgroundPlain: Bool?

        /// `translucentAppearance` is the user's choice to let the macOS window material show through the web view; `nil` means the user has not chosen.
        var translucentAppearance: Bool?

        /// `removeGaps` is the user's choice to expand Nextcloud's content to the window edges; `nil` means the user has not chosen.
        var removeGaps: Bool?

        /// `apps` are the Nextcloud server apps offered by this account's server; deleting the account cascades to them.
        @Relationship(deleteRule: .cascade, inverse: \ServerApp.account)
        var apps: [ServerApp] = []

        init(
            serverAddress: URL? = nil,
            serverVersion: String? = nil,
            themeBackground: String? = nil,
            themeLogo: URL? = nil,
            themeBackgroundPlain: Bool? = nil,
            translucentAppearance: Bool? = nil,
            removeGaps: Bool? = nil
        ) {
            self.serverAddress = serverAddress
            self.serverVersion = serverVersion
            self.themeBackground = themeBackground
            self.themeLogo = themeLogo
            self.themeBackgroundPlain = themeBackgroundPlain
            self.translucentAppearance = translucentAppearance
            self.removeGaps = removeGaps
        }
    }
}
