// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

/// `ServerCollectivePage` is the SwiftData record for one page within a collective.
///
/// It is the persistent counterpart of the value-type `CollectivePageTransferObject`, and hangs off its collective rather than off the account directly: a page is only addressable through the collective containing it, so the relationship is the same shape as the address.
///
/// It holds no page text, and unlike a note that is not a decision this app had to make — the server's page listing is metadata only, and the Markdown lives in a file in the collective's folder that nothing here reads. What it does deliberately drop is who last edited the page, which the server reports on every one: that is a record of other people's activity, kept in an unencrypted file, for a feature that only finds pages and opens them.
@Model
final class ServerCollectivePage {
    /// `pageID` is the page's server-assigned identifier, which is the identifier of its file.
    ///
    /// Not named `id`, because SwiftData treats that name as the model's own identity and this is the server's.
    var pageID: Int

    /// `title` is the page's title, which for an ordinary page is its file name without the Markdown extension.
    var title: String

    /// `slug` is the url-safe form of `title` the server addresses the page by in a link, or `nil` on a server whose Collectives app predates slugs.
    var slug: String?

    /// `emoji` is the emoji the page is decorated with, or `nil` when it has none.
    var emoji: String?

    /// `fileName` is the name of the file backing the page, including its extension.
    var fileName: String

    /// `filePath` is the folder containing `fileName`, relative to the root of the collective, or an empty string for a page sitting directly in it.
    var filePath: String

    /// `isLandingPage` is whether this is the page at the root of its collective, which the collective's own address opens.
    var isLandingPage: Bool

    /// `modification` is when the page was last changed, which is the order these are listed in.
    var modification: Date

    /// `collective` is the collective this page belongs to; it is the inverse of `ServerCollective.pages`.
    var collective: ServerCollective?

    init(pageID: Int, title: String, slug: String? = nil, emoji: String? = nil, fileName: String, filePath: String, isLandingPage: Bool, modification: Date, collective: ServerCollective? = nil) {
        self.pageID = pageID
        self.title = title
        self.slug = slug
        self.emoji = emoji
        self.fileName = fileName
        self.filePath = filePath
        self.isLandingPage = isLandingPage
        self.modification = modification
        self.collective = collective
    }
}
