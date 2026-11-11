// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

extension SchemaV3 {
    /// `ServerCollective` is the v3 record for a collective the account is a member of exactly as it shipped in `1.2.0` and `1.2.1`.
    @Model
    final class ServerCollective {
        /// `collectiveID` is the collective's server-assigned identifier, which is what listing its pages takes.
        var collectiveID: Int

        /// `name` is the collective's human-readable name, which is also what its folder is called.
        var name: String

        /// `slug` is the url-safe form of `name` the server addresses the collective by in a link, or `nil` on a server whose Collectives app predates slugs.
        var slug: String?

        /// `emoji` is the emoji the collective is decorated with, or `nil` when it has none.
        var emoji: String?

        /// `account` is the account this collective belongs to; it is the inverse of `Account.collectives`.
        var account: Account?

        /// `pages` are the pages within this collective; deleting the collective cascades to them.
        @Relationship(deleteRule: .cascade, inverse: \ServerCollectivePage.collective)
        var pages: [ServerCollectivePage] = []

        init(collectiveID: Int, name: String, slug: String? = nil, emoji: String? = nil, account: Account? = nil) {
            self.collectiveID = collectiveID
            self.name = name
            self.slug = slug
            self.emoji = emoji
            self.account = account
        }
    }
}
