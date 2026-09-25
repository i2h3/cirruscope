// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// `ServerCollective` is the SwiftData record for one collective the connected account is a member of, persisted so Spotlight and the Shortcuts app can be offered them without the server having been asked first.
///
/// It is the persistent counterpart of the value-type `CollectiveTransferObject`; `AccountStore` maps between the two so nothing outside the store ever holds a managed object. It is named for the server rather than for the thing, as `ServerApp` and `ServerNote` are, because Rainmaker exports a public `Collective` that a record of the same name would shadow.
///
/// Its pages hang off it with a cascade, so the chain from the account reaches them in one step: deleting the account deletes its collectives, and deleting a collective deletes the pages inside it. That matters because a page's title is something a person wrote and a collective's membership is shared with other people — neither should outlive the account that was allowed to see it.
@Model
final class ServerCollective {
    /// `collectiveID` is the collective's server-assigned identifier, which is what listing its pages takes.
    ///
    /// Not named `id`, because SwiftData treats that name as the model's own identity and this is the server's.
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
