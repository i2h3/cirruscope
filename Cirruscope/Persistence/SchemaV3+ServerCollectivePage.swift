// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import SwiftData

extension SchemaV3 {
    /// `ServerCollectivePage` is the v3 record for a page within a collective exactly as it shipped in `1.2.0` and `1.2.1`.
    ///
    /// It is a frozen copy; see `SchemaV3` for why it never changes.
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
}
